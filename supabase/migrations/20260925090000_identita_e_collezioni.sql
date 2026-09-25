-- Identità, Collezioni, appartenenza e inviti (ADR-0004).
--
-- Scostamenti da ADR-0004 (riportati nella sezione "Implementazione" dell'ADR):
-- - le funzioni trigger stanno in `private`, non in `public`: non devono
--   comparire fra le RPC esposte da PostgREST;
-- - la Collezione viene creata dal trigger di signup, nella stessa
--   transazione dell'utente; `create_own_collection()` resta come RPC
--   idempotente di recupero;
-- - i controlli di ruolo nelle RPC usano `is distinct from`: con `<>` un
--   non-membro (member_role = null) supererebbe il controllo;
-- - la cancellazione dell'account anonimizza il Profilo ed elimina le
--   Collezioni di cui l'utente è unico membro nello stesso trigger che
--   blocca il Proprietario con collaboratori.

create schema if not exists private;
grant usage on schema private to authenticated;

-- Profilo (audit tombstone) ---------------------------------------------------

create table public.profiles (
  id uuid primary key,
  display_name text not null,
  deleted_at timestamptz,
  created_at timestamptz not null default now()
);
-- Deliberatamente nessuna FK verso auth.users: la riga sopravvive alla
-- cancellazione dell'account (anonimizzata), così created_by/actor_id
-- restano sempre risolvibili.

alter table public.profiles enable row level security;

create policy "authenticated read profiles" on public.profiles
for select to authenticated
using (true);

create policy "user updates own profile" on public.profiles
for update to authenticated
using ( id = (select auth.uid()) )
with check ( id = (select auth.uid()) );

-- Collezione, appartenenza, ruoli ---------------------------------------------

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

-- Un solo Proprietario per Collezione.
create unique index collection_members_one_owner_idx
  on public.collection_members (collection_id)
  where role = 'owner';

-- Funzioni SECURITY DEFINER usate da tutte le policy: rompono la ricorsione
-- fra collections e collection_members.

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
grant execute on function private.member_role(uuid) to authenticated;
grant execute on function private.visible_collection_ids() to authenticated;
grant execute on function private.editable_collection_ids() to authenticated;

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
-- Nessuna policy insert: le Collezioni nascono dal trigger di signup o da
-- create_own_collection().

alter table public.collection_members enable row level security;

create policy "members read membership of their collections" on public.collection_members
for select to authenticated
using ( collection_id in (select private.visible_collection_ids()) );

-- Il Proprietario gestisce gli altri membri, non la propria riga, e non può
-- nominare un altro Proprietario: la proprietà passa solo da
-- transfer_collection_ownership(), che mantiene sempre esattamente un owner.
create policy "owner manages membership" on public.collection_members
for all to authenticated
using (
  private.member_role(collection_id) = 'owner'
  and user_id <> (select auth.uid())
)
with check (
  private.member_role(collection_id) = 'owner'
  and user_id <> (select auth.uid())
  and role <> 'owner'
);

create policy "member leaves autonomously" on public.collection_members
for delete to authenticated
using ( user_id = (select auth.uid()) and role <> 'owner' );

-- Creazione della Collezione ---------------------------------------------------

create function private.create_collection_for(target_user_id uuid)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_collection_id uuid;
begin
  insert into public.collections default values
  returning id into v_collection_id;

  insert into public.collection_members (collection_id, user_id, role)
  values (v_collection_id, target_user_id, 'owner');

  return v_collection_id;
end;
$$;

revoke execute on function private.create_collection_for(uuid) from public;

-- Idempotente: restituisce la Collezione posseduta dal chiamante, creandola
-- solo se manca (utenti registrati prima di questa migrazione, o riga
-- rimossa a mano).
create function public.create_own_collection()
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_collection_id uuid;
begin
  if v_user_id is null then
    raise exception 'Autenticazione richiesta';
  end if;

  select collection_id into v_collection_id
  from public.collection_members
  where user_id = v_user_id and role = 'owner'
  order by created_at
  limit 1;

  if v_collection_id is null then
    v_collection_id := private.create_collection_for(v_user_id);
  end if;

  return v_collection_id;
end;
$$;

revoke execute on function public.create_own_collection() from public, anon;
grant execute on function public.create_own_collection() to authenticated;

-- Signup: Profilo + Collezione ---------------------------------------------------

create function private.handle_new_user()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'display_name', new.email, 'Utente')
  );

  perform private.create_collection_for(new.id);

  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function private.handle_new_user();

-- Cancellazione dell'account ---------------------------------------------------

create function private.handle_deleted_user()
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

  -- Collezioni di cui l'utente è l'unico membro: senza di lui resterebbero
  -- orfane e irraggiungibili (App Store 5.1.1(v): i dati vanno eliminati).
  delete from public.collections c
  where exists (
    select 1 from public.collection_members m
    where m.collection_id = c.id and m.user_id = old.id and m.role = 'owner'
  );

  update public.profiles
  set display_name = 'Utente eliminato', deleted_at = now()
  where id = old.id;

  return old;
end;
$$;

create trigger on_auth_user_deleted
before delete on auth.users
for each row execute function private.handle_deleted_user();

-- Trasferimento di proprietà ---------------------------------------------------

create function public.transfer_collection_ownership(target_collection_id uuid, new_owner_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if private.member_role(target_collection_id) is distinct from 'owner' then
    raise exception 'Solo il Proprietario può trasferire la proprietà.';
  end if;

  if new_owner_id = (select auth.uid()) or not exists (
    select 1 from public.collection_members
    where collection_id = target_collection_id and user_id = new_owner_id
  ) then
    raise exception 'Il nuovo Proprietario deve essere un altro membro della collezione.';
  end if;

  update public.collection_members set role = 'editor'
    where collection_id = target_collection_id and user_id = (select auth.uid());
  update public.collection_members set role = 'owner'
    where collection_id = target_collection_id and user_id = new_owner_id;
end;
$$;

revoke execute on function public.transfer_collection_ownership(uuid, uuid) from public, anon;
grant execute on function public.transfer_collection_ownership(uuid, uuid) to authenticated;

-- Inviti -------------------------------------------------------------------------

create type public.invite_status as enum ('pending', 'accepted', 'declined', 'revoked', 'expired');

create table public.collection_invites (
  id uuid primary key default gen_random_uuid(),
  collection_id uuid not null references public.collections (id) on delete cascade,
  token uuid not null default gen_random_uuid(),
  role public.collection_role not null check (role <> 'owner'),
  email text,
  invited_by uuid default auth.uid() references public.profiles (id),
  status public.invite_status not null default 'pending',
  expires_at timestamptz not null default (now() + interval '7 days'),
  created_at timestamptz not null default now()
);

create unique index collection_invites_token_idx on public.collection_invites (token);
create index collection_invites_collection_id_idx on public.collection_invites (collection_id);

alter table public.collection_invites enable row level security;

create policy "owner manages invites" on public.collection_invites
for all to authenticated
using ( private.member_role(collection_id) = 'owner' )
with check ( private.member_role(collection_id) = 'owner' );

create function public.accept_collection_invite(invite_token uuid)
returns public.collection_role
language plpgsql security definer set search_path = ''
as $$
declare
  v_invite public.collection_invites;
begin
  if (select auth.uid()) is null then
    raise exception 'Autenticazione richiesta';
  end if;

  select * into v_invite from public.collection_invites
  where token = invite_token and status = 'pending' and expires_at > now()
  for update;

  if not found then
    raise exception 'Invito non valido o scaduto';
  end if;

  insert into public.collection_members (collection_id, user_id, role)
  values (v_invite.collection_id, (select auth.uid()), v_invite.role);

  update public.collection_invites set status = 'accepted' where id = v_invite.id;

  return v_invite.role;
end;
$$;

revoke execute on function public.accept_collection_invite(uuid) from public, anon;
grant execute on function public.accept_collection_invite(uuid) to authenticated;
