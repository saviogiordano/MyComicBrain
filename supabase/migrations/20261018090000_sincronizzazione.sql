-- Lato server della Sincronizzazione (ADR-0008, #206).
--
-- Ogni tabella replicata tiene, per ogni riga, il timestamp HLC di ogni
-- campo (`hlc_campi`) e l'id della transazione che l'ha scritta per ultima
-- (`xid_modifica`). Le eliminazioni vanno in un registro, che le propaga e le
-- fa prevalere. Due RPC SECURITY INVOKER, quindi soggette alle RLS:
-- `applica_modifiche(ops)` per il push e `cambiamenti_da(cursore)` per il pull.

-- Tabelle replicate --------------------------------------------------------------

-- `collezione`: righe di una Collezione (RLS per membership); `utente`: righe
-- private di chi le ha create (Scansioni e derivati, ADR-0004).
create table private.tabelle_replicate (
  tabella text primary key,
  ambito text not null check (ambito in ('collezione', 'utente'))
);

insert into private.tabelle_replicate (tabella, ambito) values
  ('opere', 'collezione'), ('serie', 'collezione'), ('edizioni', 'collezione'),
  ('copie', 'collezione'), ('creator', 'collezione'), ('comic_creator', 'collezione'),
  ('tag', 'collezione'), ('edizione_tag', 'collezione'), ('character', 'collezione'),
  ('comic_character', 'collezione'), ('edizione_genere', 'collezione'),
  ('valore_stimato', 'collezione'),
  ('scansioni', 'utente'), ('analisi_copertina', 'utente'),
  ('identificazione', 'utente'), ('candidati', 'utente');

grant usage on schema private to authenticated;
grant select on private.tabelle_replicate to authenticated;

-- L'eliminazione prevale a cascata: le chiavi esterne fra tabelle replicate
-- che non avevano un'azione (le rimozioni a cascata le facevano le RPC di
-- ADR-0007) eliminano i figli; una Serie eliminata lascia le sue Edizioni
-- senza Serie. Così il comportamento è lo stesso da qualunque strada arrivi
-- l'eliminazione, e ogni riga eliminata passa dal trigger del registro.
do $$
declare
  fk record;
begin
  for fk in
    select c.conname, c.conrelid::regclass as tabella, pg_get_constraintdef(c.oid) as def,
           figlia.relname = 'edizioni' and padre.relname = 'serie' as verso_serie
    from pg_constraint c
    join pg_class figlia on figlia.oid = c.conrelid
    join pg_class padre on padre.oid = c.confrelid
    where c.contype = 'f' and c.confdeltype = 'a'
      and c.connamespace = 'public'::regnamespace
      and figlia.relname in (select tabella from private.tabelle_replicate)
      and padre.relname in (select tabella from private.tabelle_replicate)
  loop
    execute format('alter table %s drop constraint %I', fk.tabella, fk.conname);
    execute format('alter table %s add constraint %I %s %s', fk.tabella, fk.conname, fk.def,
      case when fk.verso_serie then 'on delete set null (serie_id)' else 'on delete cascade' end);
  end loop;
end;
$$;

-- I riferimenti fra tabelle replicate, una riga per colonna che punta all'id
-- di un'altra tabella replicata, con l'azione all'eliminazione del padre
-- (`c` cascade, `n` set null).
create view private.riferimenti_replicati
with (security_invoker = true)
as
-- Nomi da `pg_class`, non da `regclass::text`, che dipende dal search_path di
-- chi legge.
select tabella_figlia.relname::text as tabella,
       figlia.attname::text as colonna,
       tabella_padre.relname::text as tabella_padre,
       c.confdeltype::text as azione
from pg_constraint c
join pg_class tabella_figlia on tabella_figlia.oid = c.conrelid
join pg_class tabella_padre on tabella_padre.oid = c.confrelid
cross join lateral unnest(c.conkey, c.confkey) as k(colonna_figlia, colonna_padre)
join pg_attribute figlia on figlia.attrelid = c.conrelid and figlia.attnum = k.colonna_figlia
join pg_attribute padre on padre.attrelid = c.confrelid and padre.attnum = k.colonna_padre
where c.contype = 'f'
  and c.connamespace = 'public'::regnamespace
  and padre.attname = 'id'
  and tabella_figlia.relname in (select tabella from private.tabelle_replicate)
  and tabella_padre.relname in (select tabella from private.tabelle_replicate);

grant select on private.riferimenti_replicati to authenticated;

-- Colonne di servizio ------------------------------------------------------------

create function private.segna_modifica()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.xid_modifica := pg_current_xact_id();
  return new;
end;
$$;

do $$
declare
  t text;
begin
  for t in select tabella from private.tabelle_replicate loop
    execute format($f$
      alter table public.%1$I
        add column hlc_campi jsonb not null default '{}',
        add column xid_modifica xid8 not null default pg_current_xact_id()
    $f$, t);
    execute format('create index %I on public.%I (xid_modifica)', t || '_xid_modifica_idx', t);
    execute format($f$
      create trigger segna_modifica before insert or update on public.%I
      for each row execute function private.segna_modifica()
    $f$, t);
  end loop;
end;
$$;

-- Registro delle eliminazioni ----------------------------------------------------

create table public.eliminazioni (
  tabella text not null references private.tabelle_replicate (tabella),
  riga uuid not null,
  -- Valorizzata per le tabelle `collezione`, `user_id` per quelle `utente`.
  collection_id uuid references public.collections (id) on delete cascade,
  user_id uuid references auth.users (id) on delete cascade,
  xid_modifica xid8 not null default pg_current_xact_id(),
  eliminata_il timestamptz not null default now(),
  primary key (tabella, riga),
  check ((collection_id is null) <> (user_id is null))
);

create index eliminazioni_collection_id_idx on public.eliminazioni (collection_id, xid_modifica);
create index eliminazioni_user_id_idx on public.eliminazioni (user_id, xid_modifica);
create index eliminazioni_xid_modifica_idx on public.eliminazioni (xid_modifica);

alter table public.eliminazioni enable row level security;

-- Solo lettura: il registro lo scrivono il trigger e `applica_modifiche`.
create policy "members read deletions" on public.eliminazioni
for select to authenticated
using (
  collection_id in (select private.visible_collection_ids())
  or user_id = (select auth.uid())
);

-- Ogni riga eliminata, comprese le cascate. Non registra le righe che se ne
-- vanno con la loro Collezione o il loro utente (eliminazione dell'account):
-- non c'è più nessuno a cui propagarle.
create function private.registra_eliminazione()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_riga jsonb := to_jsonb(old);
  v_collection_id uuid;
  v_user_id uuid;
begin
  if tg_argv[0] = 'collezione' then
    v_collection_id := (v_riga->>'collection_id')::uuid;
    if not exists (select 1 from public.collections where id = v_collection_id) then
      return old;
    end if;
  else
    v_user_id := (v_riga->>'user_id')::uuid;
    if not exists (select 1 from auth.users where id = v_user_id) then
      return old;
    end if;
  end if;
  insert into public.eliminazioni (tabella, riga, collection_id, user_id)
  values (tg_table_name, old.id, v_collection_id, v_user_id)
  on conflict (tabella, riga) do nothing;
  return old;
end;
$$;

do $$
declare
  t record;
begin
  for t in select tabella, ambito from private.tabelle_replicate loop
    execute format($f$
      create trigger registra_eliminazione after delete on public.%I
      for each row execute function private.registra_eliminazione(%L)
    $f$, t.tabella, t.ambito);
  end loop;
end;
$$;

-- Registra l'eliminazione di una riga che sul server non c'è: mai arrivata
-- (creata ed eliminata offline) o scartata perché figlia di una riga
-- eliminata. Rifiuta una riga che esiste ma l'utente non può eliminare.
create function private.registra_scarto(p_tabella text, p_riga uuid, p_collection_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ambito text;
  v_esiste boolean;
begin
  select ambito into v_ambito from private.tabelle_replicate where tabella = p_tabella;
  execute format('select exists (select 1 from public.%I where id = $1)', p_tabella)
    into v_esiste using p_riga;
  if v_esiste then
    raise exception 'Riga % di % non eliminabile', p_riga, p_tabella using errcode = '42501';
  end if;
  if v_ambito = 'collezione' then
    if p_collection_id is null
       or p_collection_id not in (select private.editable_collection_ids()) then
      raise exception 'Collezione % non modificabile', p_collection_id using errcode = '42501';
    end if;
    insert into public.eliminazioni (tabella, riga, collection_id)
    values (p_tabella, p_riga, p_collection_id)
    on conflict (tabella, riga) do nothing;
  else
    insert into public.eliminazioni (tabella, riga, user_id)
    values (p_tabella, p_riga, (select auth.uid()))
    on conflict (tabella, riga) do nothing;
  end if;
end;
$$;

revoke execute on function private.registra_scarto(text, uuid, uuid) from public;
grant execute on function private.registra_scarto(text, uuid, uuid) to authenticated;

-- Operazioni già applicate -------------------------------------------------------

create table public.operazioni_sincronizzate (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  id uuid not null,
  applicata_il timestamptz not null default now(),
  primary key (user_id, id)
);

alter table public.operazioni_sincronizzate enable row level security;

create policy "user reads own operations" on public.operazioni_sincronizzate
for select to authenticated
using ( user_id = (select auth.uid()) );

create policy "user records own operations" on public.operazioni_sincronizzate
for insert to authenticated
with check ( user_id = (select auth.uid()) );

-- Push: applica_modifiche --------------------------------------------------------

-- Un timestamp HLC (ADR-0008): millisecondi dall'epoch su 13 cifre, contatore
-- su 4 cifre, id del device. Con larghezze fisse l'ordine dei testi (collation
-- C) è l'ordine nel tempo.
create function private.hlc_valido(hlc text)
returns boolean
language sql
immutable
as $$ select hlc ~ '^[0-9]{13}-[0-9]{4}-[0-9A-Za-z-]{1,64}$' $$;

-- Applica in una transazione le operazioni del registro delle Modifiche in
-- sospeso di un device, nell'ordine dato. Ogni operazione:
--
--   {"id": uuid, "tabella": text, "riga": uuid,
--    "valori": {colonna: valore}, "hlc": {colonna: hlc},
--    "collection_id": uuid (facoltativo)}            -- scrittura
--   {"id": uuid, "tabella": text, "riga": uuid, "elimina": true}
--
-- Una scrittura crea la riga se non c'è, altrimenti aggiorna solo i campi con
-- un timestamp più recente di quello salvato. Un'operazione già applicata
-- (stesso id, stesso utente) si salta. Un'operazione su una riga eliminata, o
-- figlia di una riga eliminata, si scarta: la riga torna in `eliminate`, che il
-- device toglie dalla Replica. Un riferimento a una Serie eliminata diventa
-- null. Un'operazione non valida o vietata dalle RLS annulla tutto il lotto.
create function public.applica_modifiche(ops jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  op jsonb;
  v_n integer;
  v_tabella text;
  v_ambito text;
  v_riga uuid;
  v_collection_id uuid;
  v_valori jsonb;
  v_hlc jsonb;
  v_campo text;
  v_esistente jsonb;
  v_da_scrivere text[];
  v_rif record;
  v_padre uuid;
  v_scartata boolean;
  v_eliminate jsonb := '[]';
begin
  if (select auth.uid()) is null then
    raise exception 'Autenticazione richiesta' using errcode = '42501';
  end if;
  if jsonb_typeof(ops) is distinct from 'array' then
    raise exception 'ops deve essere un array' using errcode = '22023';
  end if;

  for op in select value from jsonb_array_elements(ops) loop
    insert into public.operazioni_sincronizzate (id) values ((op->>'id')::uuid)
    on conflict do nothing;
    get diagnostics v_n = row_count;
    continue when v_n = 0;

    v_tabella := op->>'tabella';
    v_riga := (op->>'riga')::uuid;
    select ambito into v_ambito from private.tabelle_replicate where tabella = v_tabella;
    if v_ambito is null or v_riga is null then
      raise exception 'Operazione non valida: %', op using errcode = '22023';
    end if;
    v_collection_id := coalesce(
      (op->>'collection_id')::uuid,
      (select collection_id from public.collection_members
       where user_id = (select auth.uid()) and role = 'owner'));

    -- L'eliminazione prevale: nessuna operazione dopo.
    if exists (select 1 from public.eliminazioni
               where tabella = v_tabella and riga = v_riga) then
      v_eliminate := v_eliminate || jsonb_build_object('tabella', v_tabella, 'id', v_riga);
      continue;
    end if;

    if coalesce((op->>'elimina')::boolean, false) then
      execute format('delete from public.%I where id = $1', v_tabella) using v_riga;
      get diagnostics v_n = row_count;
      if v_n = 0 then
        perform private.registra_scarto(v_tabella, v_riga, v_collection_id);
      end if;
      continue;
    end if;

    v_valori := coalesce(op->'valori', '{}');
    v_hlc := coalesce(op->'hlc', '{}');
    if jsonb_typeof(v_valori) <> 'object' or jsonb_typeof(v_hlc) <> 'object' then
      raise exception 'Operazione non valida: %', op using errcode = '22023';
    end if;
    for v_campo in select jsonb_object_keys(v_valori) loop
      if v_campo in ('id', 'collection_id', 'user_id', 'created_by', 'hlc_campi', 'xid_modifica')
         or not exists (
           select 1 from pg_attribute
           where attrelid = ('public.' || quote_ident(v_tabella))::regclass
             and attname = v_campo and attnum > 0 and not attisdropped) then
        raise exception 'Colonna % di % non scrivibile', v_campo, v_tabella using errcode = '22023';
      end if;
      if not coalesce(private.hlc_valido(v_hlc->>v_campo), false) then
        raise exception 'Timestamp HLC non valido per %.%: %', v_tabella, v_campo, v_hlc->v_campo
          using errcode = '22023';
      end if;
    end loop;
    v_hlc := (select coalesce(jsonb_object_agg(k, v_hlc->k), '{}') from jsonb_object_keys(v_valori) k);

    execute format('select to_jsonb(t) from public.%I t where id = $1 for update', v_tabella)
      into v_esistente using v_riga;

    -- Figlia di una riga eliminata: scartata, o staccata se il riferimento
    -- è facoltativo (Serie di un'Edizione, Scansione di una Copia, ...).
    v_scartata := false;
    for v_rif in
      select colonna, tabella_padre, azione from private.riferimenti_replicati
      where tabella = v_tabella
    loop
      v_padre := case when v_valori ? v_rif.colonna then v_valori->>v_rif.colonna
                      else v_esistente->>v_rif.colonna end;
      continue when v_padre is null or not exists (
        select 1 from public.eliminazioni
        where tabella = v_rif.tabella_padre and riga = v_padre);
      if v_rif.azione = 'n' then
        v_valori := jsonb_set(v_valori, array[v_rif.colonna], 'null');
      else
        v_scartata := true;
        exit;
      end if;
    end loop;
    if v_scartata then
      if v_esistente is null then
        perform private.registra_scarto(v_tabella, v_riga, v_collection_id);
      else
        execute format('delete from public.%I where id = $1', v_tabella) using v_riga;
      end if;
      v_eliminate := v_eliminate || jsonb_build_object('tabella', v_tabella, 'id', v_riga);
      continue;
    end if;

    if v_esistente is null then
      execute format(
        'insert into public.%I (id, %s hlc_campi%s) select $1, %s $3%s from jsonb_populate_record(null::public.%I, $2) r',
        v_tabella,
        (select coalesce(string_agg(format('%I, ', k), ''), '') from jsonb_object_keys(v_valori) k),
        case when v_ambito = 'collezione' or v_tabella = 'scansioni' then ', collection_id' else '' end,
        (select coalesce(string_agg(format('r.%I, ', k), ''), '') from jsonb_object_keys(v_valori) k),
        case when v_ambito = 'collezione' or v_tabella = 'scansioni' then ', $4' else '' end,
        v_tabella)
        using v_riga, v_valori, v_hlc, v_collection_id;
    else
      -- Ultima modifica fatta vince, campo per campo.
      select array_agg(k) into v_da_scrivere
      from jsonb_object_keys(v_valori) k
      where (v_hlc->>k) collate "C"
            > coalesce(v_esistente->'hlc_campi'->>k, '') collate "C";
      continue when v_da_scrivere is null;
      execute format(
        'update public.%I t set %s, hlc_campi = t.hlc_campi || $3 from jsonb_populate_record(null::public.%I, $2) r where t.id = $1',
        v_tabella,
        (select string_agg(format('%I = r.%I', k, k), ', ') from unnest(v_da_scrivere) k),
        v_tabella)
        using v_riga, v_valori,
          (select jsonb_object_agg(k, v_hlc->k) from unnest(v_da_scrivere) k);
    end if;
  end loop;

  return jsonb_build_object('eliminate', v_eliminate);
end;
$$;

revoke execute on function public.applica_modifiche(jsonb) from public, anon;
grant execute on function public.applica_modifiche(jsonb) to authenticated;

-- Pull: cambiamenti_da -----------------------------------------------------------

-- Sotto questo id di transazione ogni transazione è finita: una riga scritta
-- da una transazione più vecchia ma con commit tardivo non può comparire
-- dopo che il cursore l'ha superata.
create function private.orizzonte_sincronizzazione()
returns xid8
language sql
stable
as $$ select pg_snapshot_xmin(pg_current_snapshot()) $$;

grant execute on function private.orizzonte_sincronizzazione() to authenticated;

-- Le righe cambiate e le eliminazioni visibili all'utente dopo [cursore], a
-- pagine di [limite], in un solo jsonb (niente tetto `max_rows`):
--
--   {"cambiamenti": [{"tabella", "id", "riga": {...} | null}],
--    "cursore": text, "altre": boolean}
--
-- `riga` null è un'eliminazione. Ordine: per transazione, poi tabella e id;
-- un figlio può arrivare prima del suo padre. Il cursore è opaco: si ripassa
-- quello restituito finché `altre` è true, poi lo si conserva per il prossimo
-- pull.
--
-- Il primo download (cursore nullo) non porta le eliminazioni, che a una
-- Replica nuova non servono, nemmeno nelle pagine successive: i loro cursori
-- ricordano l'orizzonte della prima pagina, che è anche il cursore finale.
-- Così il pull successivo riparte da lì e porta ciò che è cambiato o è stato
-- eliminato mentre il download era in corso (qualche riga arriva due volte).
create function public.cambiamenti_da(cursore text default null, limite integer default 1000)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_orizzonte xid8 := private.orizzonte_sincronizzazione();
  v_parti text[];
  v_primo boolean := cursore is null or cursore like 'primo:%';
  v_inizio xid8;
  v_xid xid8 := '0';
  v_tabella text := '';
  v_id uuid := '00000000-0000-0000-0000-000000000000';
  v_sql text;
  v_pagina jsonb;
  v_altre boolean;
  v_ultima jsonb;
begin
  if limite is null or limite < 1 then
    raise exception 'limite deve essere positivo' using errcode = '22023';
  end if;
  -- [primo:<inizio>:]<xid>[:<tabella>:<id>]
  if cursore is not null then
    v_parti := regexp_match(cursore,
      '^(?:primo:([0-9]+):)?([0-9]+)(?::([a-z_]+):([0-9a-f-]{36}))?$');
    if v_parti is null then
      raise exception 'Cursore non valido: %', cursore using errcode = '22023';
    end if;
    v_inizio := v_parti[1]::xid8;
    v_xid := v_parti[2]::xid8;
    v_tabella := coalesce(v_parti[3], '');
    v_id := coalesce(v_parti[4]::uuid, v_id);
  end if;
  v_inizio := coalesce(v_inizio, v_orizzonte);

  select string_agg(format(
    'select %L::text as tabella, t.id, t.xid_modifica as xid, to_jsonb(t) - %L as riga
     from public.%I t where t.xid_modifica >= $1 and t.xid_modifica < $2',
    tabella, 'xid_modifica', tabella), ' union all ')
  into v_sql
  from private.tabelle_replicate;
  if not v_primo then
    v_sql := v_sql || ' union all select e.tabella, e.riga, e.xid_modifica, null
      from public.eliminazioni e where e.xid_modifica >= $1 and e.xid_modifica < $2';
  end if;

  execute format(
    'select coalesce(jsonb_agg(jsonb_build_object(%L, p.tabella, %L, p.id, %L, p.riga, %L, p.xid::text)
                               order by p.xid, p.tabella collate "C", p.id), %L)
     from (select * from (%s) u
           where (u.xid, u.tabella collate "C", u.id) > ($1, $3 collate "C", $4)
           order by u.xid, u.tabella collate "C", u.id
           limit $5) p',
    'tabella', 'id', 'riga', 'xid', '[]', v_sql)
    into v_pagina using v_xid, v_orizzonte, v_tabella, v_id, limite + 1;

  v_altre := jsonb_array_length(v_pagina) > limite;
  if v_altre then
    v_pagina := v_pagina - limite;
    v_ultima := v_pagina->(limite - 1);
  end if;

  return jsonb_build_object(
    'cambiamenti', (select coalesce(jsonb_agg(c - 'xid' order by n), '[]')
                    from jsonb_array_elements(v_pagina) with ordinality as e(c, n)),
    'cursore', case
                 when v_altre then
                   case when v_primo then 'primo:' || v_inizio::text || ':' else '' end
                   || (v_ultima->>'xid') || ':' || (v_ultima->>'tabella') || ':' || (v_ultima->>'id')
                 when v_primo then v_inizio::text
                 else v_orizzonte::text end,
    'altre', v_altre);
end;
$$;

revoke execute on function public.cambiamenti_da(text, integer) from public, anon;
grant execute on function public.cambiamenti_da(text, integer) to authenticated;
