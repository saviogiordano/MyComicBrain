# Schema Postgres + RLS per collezioni condivise e ruoli (§17.2/§17.3)

ADR-0003 fissa l'architettura (nessun backend custom, autorizzazione via RLS, RPC/Edge Function `SECURITY DEFINER` per ciò che RLS da sola non esprime) ma non lo schema. Questo documento registra lo schema Postgres e le policy RLS che implementano §17.2 (collezioni condivise, ruoli Proprietario/Editor/Visualizzatore, inviti) e §17.3 (isolamento e permessi per-operazione, sopravvivenza della collezione alla rimozione di un collaboratore), coerenti con l'audit di autore/timestamp di §27. Si basa sulla ricerca sui pattern RLS ([#153](https://github.com/saviogiordano/MyComicBrain/issues/153), `docs/research/supabase-rls-role-sharing.md`) e sul mapping profilo↔account di [#151](https://github.com/saviogiordano/MyComicBrain/issues/151). Decisioni prese in sessione di grilling sul ticket [#154](https://github.com/saviogiordano/MyComicBrain/issues/154).

Decisione, in sintesi:

- **Catalogo per-collezione, non condiviso fra collezioni**: `opere`/`edizioni`/`serie`/`creator`/`personaggi`/`tag` restano scoped a una singola Collezione (righe duplicate fra collezioni diverse), esattamente come oggi lo schema locale (drift) è implicitamente scoped a un solo utente. Nessun catalogo globale deduplicato — nessun requisito lo chiede, e introdurrebbe un problema di dedup/moderazione cross-utente fuori scope.
- **Una Collezione per account**, creata automaticamente alla registrazione. Lo schema non impedisce tecnicamente N collezioni per proprietario (nessun vincolo UNIQUE su `owner`), ma non esiste alcun flusso applicativo per crearne/gestirne più di una.
- **Tabella di giunzione `collection_members`** con `role` — pattern raccomandato dalla ricerca #153, ricorsione delle policy evitata con funzioni `SECURITY DEFINER` in schema `private` (non esposto via API).
- **Inviti** in una tabella separata `collection_invites` (non una riga di `collection_members` con stato `pending`), perché un invito via codice/link condivisibile non ha ancora uno `user_id` finché non viene accettato. Nessuna verifica di corrispondenza email all'accettazione: il token è l'unica barriera.
- **`profiles`** materializza il concetto di Profilo già deciso su [#151](https://github.com/saviogiordano/MyComicBrain/issues/151) (un account Supabase = un Profilo), con una riga che **sopravvive** alla cancellazione dell'account (anonimizzata, non cancellata) — è la base per un audit trail sempre risolvibile anche dopo che un collaboratore ha eliminato il proprio account.
- **Cancellazione del Proprietario bloccata** (trigger su `auth.users`, non solo controllo applicativo) finché non trasferisce la proprietà o rimuove tutti i collaboratori.

## Schema

### Profilo (audit tombstone)

```sql
create table public.profiles (
  id uuid primary key,
  display_name text not null,
  deleted_at timestamptz,
  created_at timestamptz not null default now()
);

-- Deliberatamente NESSUNA foreign key verso auth.users(id): un vincolo con
-- on delete cascade cancellerebbe la riga insieme all'account, vanificando
-- lo scopo di tombstone. La riga sopravvive sempre; alla cancellazione
-- dell'account viene solo anonimizzata (display_name sostituito, deleted_at
-- valorizzato) da un Edge Function/RPC eseguito PRIMA di auth.admin.deleteUser.

create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', new.email));
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

alter table public.profiles enable row level security;

create policy "authenticated read profiles" on public.profiles
for select to authenticated
using (true);

create policy "user updates own profile" on public.profiles
for update to authenticated
using ( id = (select auth.uid()) )
with check ( id = (select auth.uid()) );
-- Nessuna policy insert/delete lato client: la riga nasce solo dal trigger
-- sopra e non viene mai cancellata.
```

Ogni colonna `created_by` delle tabelle di dominio (sotto) referenzia `profiles(id)`, **non** `auth.users(id)` direttamente — proprio perché `profiles` sopravvive alla cancellazione dell'account, `created_by` non richiede `on delete set null`: resta sempre risolvibile, anche a un nome anonimizzato.

### Collezione, appartenenza, ruoli

```sql
create type public.collection_role as enum ('owner', 'editor', 'viewer');

create table public.collections (
  id uuid primary key default gen_random_uuid(),
  name text not null default 'La mia collezione',
  created_at timestamptz not null default now()
);

create table public.collection_members (
  collection_id uuid not null references public.collections (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role public.collection_role not null,
  created_at timestamptz not null default now(),
  primary key (collection_id, user_id)
);

create index collection_members_user_id_idx
  on public.collection_members using btree (user_id);

-- Un solo Proprietario per Collezione (mai co-proprietà, deciso su #154).
create unique index collection_members_one_owner_idx
  on public.collection_members (collection_id)
  where role = 'owner';
```

Funzioni `SECURITY DEFINER` in schema `private` (non esposto via API), che rompono la ricorsione fra `collections`/`collection_members` e vengono richiamate da tutte le policy delle tabelle di dominio (pattern da #153):

```sql
create schema if not exists private;

create function private.member_role(target_collection_id uuid)
returns public.collection_role
language sql security definer set search_path = '' stable
as $$
  select role from public.collection_members
  where collection_id = target_collection_id
    and user_id = (select auth.uid())
$$;

create function private.visible_collection_ids()
returns setof uuid
language sql security definer set search_path = '' stable
as $$
  select collection_id from public.collection_members
  where user_id = (select auth.uid())
$$;

create function private.editable_collection_ids()
returns setof uuid
language sql security definer set search_path = '' stable
as $$
  select collection_id from public.collection_members
  where user_id = (select auth.uid()) and role in ('owner', 'editor')
$$;

revoke execute on function private.member_role(uuid) from public;
revoke execute on function private.visible_collection_ids() from public;
revoke execute on function private.editable_collection_ids() from public;
grant usage on schema private to authenticated;
grant execute on function private.member_role(uuid) to authenticated;
grant execute on function private.visible_collection_ids() to authenticated;
grant execute on function private.editable_collection_ids() to authenticated;
```

RLS su `collections` e `collection_members`:

```sql
alter table public.collections enable row level security;

create policy "members read their collection" on public.collections
for select to authenticated
using ( id in (select private.visible_collection_ids()) );

create policy "owner updates their collection" on public.collections
for update to authenticated
using ( private.member_role(id) = 'owner' )
with check ( private.member_role(id) = 'owner' );

create policy "owner deletes their collection" on public.collections
for delete to authenticated
using ( private.member_role(id) = 'owner' );
-- Nessuna policy insert diretta: la creazione avviene via RPC
-- create_own_collection() chiamata al signup, che inserisce
-- atomicamente la riga collections + la riga owner in collection_members.

alter table public.collection_members enable row level security;

create policy "members read membership of their collections" on public.collection_members
for select to authenticated
using ( collection_id in (select private.visible_collection_ids()) );

create policy "owner manages membership" on public.collection_members
for all to authenticated
using ( private.member_role(collection_id) = 'owner' )
with check ( private.member_role(collection_id) = 'owner' );

create policy "member leaves autonomously" on public.collection_members
for delete to authenticated
using ( user_id = (select auth.uid()) and role <> 'owner' );
```

Cancellazione account del Proprietario bloccata finché ci sono altri collaboratori (§17.3 copre solo il caso collaboratore; per il Proprietario serve un trasferimento esplicito o la rimozione di tutti i collaboratori — vedi RPC `transfer_collection_ownership` sotto):

```sql
create function private.prevent_orphaned_collection_owner()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if exists (
    select 1
    from public.collection_members owner_row
    where owner_row.user_id = old.id
      and owner_row.role = 'owner'
      and exists (
        select 1 from public.collection_members other
        where other.collection_id = owner_row.collection_id
          and other.user_id <> old.id
      )
  ) then
    raise exception 'Trasferisci la proprietà della collezione o rimuovi i collaboratori prima di eliminare l''account.';
  end if;
  return old;
end;
$$;

create trigger on_auth_user_deleted_check_ownership
before delete on auth.users
for each row execute function private.prevent_orphaned_collection_owner();
```

```sql
create function public.transfer_collection_ownership(target_collection_id uuid, new_owner_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if private.member_role(target_collection_id) <> 'owner' then
    raise exception 'Solo il Proprietario può trasferire la proprietà.';
  end if;
  update public.collection_members set role = 'editor'
    where collection_id = target_collection_id and user_id = (select auth.uid());
  update public.collection_members set role = 'owner'
    where collection_id = target_collection_id and user_id = new_owner_id;
end;
$$;
```

### Inviti

```sql
create type public.invite_status as enum ('pending', 'accepted', 'declined', 'revoked', 'expired');

create table public.collection_invites (
  id uuid primary key default gen_random_uuid(),
  collection_id uuid not null references public.collections (id) on delete cascade,
  token uuid not null default gen_random_uuid(),
  role public.collection_role not null check (role <> 'owner'),
  email text,
  invited_by uuid references public.profiles (id),
  status public.invite_status not null default 'pending',
  expires_at timestamptz not null default (now() + interval '7 days'),
  created_at timestamptz not null default now()
);

create unique index collection_invites_token_idx on public.collection_invites (token);

alter table public.collection_invites enable row level security;

create policy "owner manages invites" on public.collection_invites
for all to authenticated
using ( private.member_role(collection_id) = 'owner' )
with check ( private.member_role(collection_id) = 'owner' );
-- Nessuna policy select per l'invitato: l'accettazione passa sempre dalla
-- RPC sotto (token opaco via link/codice), mai da una lettura diretta della
-- tabella — RLS da sola non può esporre una riga a chi non è ancora membro.
```

```sql
create function public.accept_collection_invite(invite_token uuid)
returns public.collection_role
language plpgsql security definer set search_path = ''
as $$
declare
  v_invite public.collection_invites;
begin
  select * into v_invite from public.collection_invites
  where token = invite_token and status = 'pending' and expires_at > now();

  if not found then
    raise exception 'Invito non valido o scaduto';
  end if;

  insert into public.collection_members (collection_id, user_id, role)
  values (v_invite.collection_id, (select auth.uid()), v_invite.role);

  update public.collection_invites set status = 'accepted' where id = v_invite.id;

  return v_invite.role;
end;
$$;

revoke execute on function public.accept_collection_invite(uuid) from public;
grant execute on function public.accept_collection_invite(uuid) to authenticated;
```

### Tabelle di dominio (`opere`, `edizioni`, `copie`, `serie`, `creator`, `personaggi`, `tag`, tabelle di giunzione)

Ogni tabella di dominio (l'equivalente Postgres di `Opere`/`Edizioni`/`Copie`/`SerieTable`/`Creator`/`Character`/`TagTable` e delle tabelle di giunzione `ComicCreator`/`EdizioneTag`/`ComicCharacter`/`EdizioneGenere` di `app/lib/core/data/database.dart`) guadagna, oltre alle colonne esistenti:

```sql
alter table public.<tabella>
  add column collection_id uuid not null references public.collections (id) on delete cascade,
  add column created_by uuid references public.profiles (id);

create index <tabella>_collection_id_idx on public.<tabella> (collection_id);
```

Gli `id` restano `bigint`/interi autoincrementanti come nello schema locale attuale (nessuna ragione per passare a `uuid` sulle tabelle di dominio — solo le tabelle nuove di questa decisione, che attraversano un confine di sicurezza multiutente, usano `uuid`).

Le stesse quattro policy si applicano identiche a ogni tabella di dominio, parametrizzate solo dal nome tabella:

```sql
alter table public.<tabella> enable row level security;

create policy "collection members read" on public.<tabella>
for select to authenticated
using ( collection_id in (select private.visible_collection_ids()) );

create policy "owner and editor insert" on public.<tabella>
for insert to authenticated
with check ( collection_id in (select private.editable_collection_ids()) );

create policy "owner and editor update" on public.<tabella>
for update to authenticated
using ( collection_id in (select private.editable_collection_ids()) )
with check ( collection_id in (select private.editable_collection_ids()) );

create policy "owner and editor delete" on public.<tabella>
for delete to authenticated
using ( collection_id in (select private.editable_collection_ids()) );
```

Questo implementa direttamente §17.3 ("ogni operazione... deve verificare il ruolo"): il Visualizzatore passa solo la policy di lettura, Editor e Proprietario passano anche le tre di scrittura, nessuno passa quelle di un'altra collezione.

### Scansioni e Conversazioni: sempre private, mai condivise

`scansioni`, `analisi_copertina`, `identificazione`, `candidati`, `conversazioni`, `messaggi` restano **private all'account che le ha create**, anche dentro una Collezione condivisa — non hanno le quattro policy sopra, ma una sola coppia lettura/scrittura su `user_id`:

```sql
alter table public.scansioni
  add column user_id uuid not null references auth.users (id) on delete cascade,
  add column collection_id uuid references public.collections (id) on delete set null;
-- collection_id è informativo (quale Collezione riceverà la Copia se lo
-- Scansione viene confermata): non entra in nessuna policy, l'accesso è
-- interamente governato da user_id. La successiva creazione della Copia in
-- una Collezione condivisa è comunque vincolata dalle policy insert di
-- `copie` sopra (l'utente deve essere owner/editor di quella collezione).

alter table public.scansioni enable row level security;

create policy "creator reads own scansioni" on public.scansioni
for select to authenticated
using ( user_id = (select auth.uid()) );

create policy "creator writes own scansioni" on public.scansioni
for all to authenticated
using ( user_id = (select auth.uid()) )
with check ( user_id = (select auth.uid()) );
```

Stesso pattern (colonna `user_id`, due policy identiche) per `analisi_copertina`/`identificazione`/`candidati` (via `scansioni.user_id`, o duplicando `user_id` direttamente per evitare join — coerente con la raccomandazione di performance di #153 di preferire una colonna diretta filtrata a un join) e per `conversazioni`/`messaggi`.

### Audit trail (§27)

Tabella di log generica via trigger, come già fissato da ADR-0003:

```sql
create table public.audit_log (
  id bigint generated always as identity primary key,
  collection_id uuid references public.collections (id) on delete cascade,
  table_name text not null,
  row_id bigint not null,
  action text not null check (action in ('insert', 'update', 'delete')),
  actor_id uuid references public.profiles (id),
  changed_at timestamptz not null default now(),
  diff jsonb
);

create index audit_log_collection_id_idx on public.audit_log (collection_id);

create function private.log_change()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.audit_log (collection_id, table_name, row_id, action, actor_id, diff)
  values (
    coalesce(new.collection_id, old.collection_id),
    tg_table_name,
    coalesce(new.id, old.id),
    lower(tg_op),
    (select auth.uid()),
    case tg_op
      when 'DELETE' then to_jsonb(old)
      when 'INSERT' then to_jsonb(new)
      else jsonb_build_object('old', to_jsonb(old), 'new', to_jsonb(new))
    end
  );
  return coalesce(new, old);
end;
$$;

-- Applicato a ogni tabella di dominio con collection_id, es.:
create trigger audit_copie
after insert or update or delete on public.copie
for each row execute function private.log_change();
```

`audit_log` non ha policy di scrittura client-side (solo il trigger, `SECURITY DEFINER`, vi scrive); lettura riservata al Proprietario della Collezione:

```sql
alter table public.audit_log enable row level security;

create policy "owner reads audit log" on public.audit_log
for select to authenticated
using ( private.member_role(collection_id) = 'owner' );
```

## Considered Options

- **Catalogo `opere`/`edizioni` condiviso e deduplicato fra tutte le collezioni dell'app** (invece che duplicato per collezione) — scartata: nessun requisito lo chiede, e introdurrebbe un problema di dedup/matching/moderazione cross-utente completamente nuovo (chi decide se due edizioni di utenti diversi sono "la stessa riga"?) che il Candidato/matching engine esistente non è progettato per risolvere — quel motore fa matching contro database esterni (ComicVine), non fra collezioni di utenti diversi.
- **Trasferimento automatico della proprietà** alla cancellazione dell'account del Proprietario (es. al collaboratore più anziano) — scartata a favore del blocco esplicito: un passaggio di proprietà "a sorpresa" è meno prevedibile per l'utente e più difficile da implementare in modo sicuro con RLS pura (richiederebbe comunque un trigger `SECURITY DEFINER` equivalente, ma con una scelta arbitraria di "chi" invece di un errore chiaro).
- **Stato `pending` su una riga di `collection_members`** invece di una tabella `collection_invites` separata — scartata: un invito via codice/link condivisibile non ha uno `user_id` valido finché non viene accettato, e `collection_members.user_id` è `not null` (chiave primaria composita); servirebbe renderlo nullable e complicare tutte le policy di membership per gestire un caso che riguarda solo gli inviti.
- **Verifica di corrispondenza email** fra l'invito e l'account che accetta — scartata: il codice/link condivisibile non ha per natura un'email associata, quindi la verifica si applicherebbe solo a un canale dei due; il token stesso (uuid casuale, con scadenza) è già la barriera di sicurezza.

## Consequences

- §22 di `docs/requisiti.md` va aggiornato per riflettere questo schema al posto del vecchio stub `Collection { id, user_id, name }`.
- La migrazione dati da drift/sqlite (fog "Not yet specified" della mappa [#149](https://github.com/saviogiordano/MyComicBrain/issues/149)) deve creare la Collezione di ogni utente esistente e popolare `collection_id`/`created_by` su ogni riga migrata — probabilmente il prossimo ticket della mappa.
- Ogni nuova tabella di dominio futura che rappresenta dati posseduti dall'utente (non lavoro-in-corso come Scansioni) deve seguire lo stesso pattern (`collection_id` + le quattro policy) per restare coerente — non serve riaprire questa decisione per tabelle nuove dello stesso tipo.
- Se in futuro emergesse un requisito di collezioni multiple per proprietario, lo schema non richiede una migrazione strutturale (nessun vincolo che lo impedisca) — solo nuova UI/flussi applicativi, non nuove tabelle.
