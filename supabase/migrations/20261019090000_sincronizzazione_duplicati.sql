-- Duplicati di chiave naturale nella Sincronizzazione (ADR-0008, #208).
--
-- Due device offline possono creare con id diversi la stessa riga che un
-- vincolo unique vuole sola: lo stesso collegamento di un'Edizione
-- (`comic_creator`, `edizione_tag`, `comic_character`, `edizione_genere`) o
-- il Valore stimato della stessa Copia. Prima l'errore di unicità annullava
-- tutto il lotto e il device restava bloccato. Ora vince la riga già sul
-- server: l'inserimento del device si scarta come un'eliminazione (registro
-- `eliminazioni`, `eliminate` nella risposta), il device toglie la sua riga e
-- col pull riceve quella del server.

create or replace function public.applica_modifiche(ops jsonb)
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
      begin
        execute format(
          'insert into public.%I (id, %s hlc_campi%s) select $1, %s $3%s from jsonb_populate_record(null::public.%I, $2) r',
          v_tabella,
          (select coalesce(string_agg(format('%I, ', k), ''), '') from jsonb_object_keys(v_valori) k),
          case when v_ambito = 'collezione' or v_tabella = 'scansioni' then ', collection_id' else '' end,
          (select coalesce(string_agg(format('r.%I, ', k), ''), '') from jsonb_object_keys(v_valori) k),
          case when v_ambito = 'collezione' or v_tabella = 'scansioni' then ', $4' else '' end,
          v_tabella)
          using v_riga, v_valori, v_hlc, v_collection_id;
      exception when unique_violation then
        -- La stessa chiave naturale di una riga già sul server: lo stesso
        -- collegamento (Autore, Tag, Personaggio, Genere di un'Edizione) o il
        -- Valore stimato della stessa Copia, creati da due device. Vince la
        -- riga del server; quella del device si scarta come eliminata.
        perform private.registra_scarto(v_tabella, v_riga, v_collection_id);
        v_eliminate := v_eliminate || jsonb_build_object('tabella', v_tabella, 'id', v_riga);
      end;
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
