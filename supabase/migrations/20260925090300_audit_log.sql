-- Audit trail (§27, ADR-0004): log generico via trigger su ogni tabella di
-- dominio della Collezione. Scansioni e Conversazione (private) non sono
-- tracciate.

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
create index audit_log_actor_id_idx on public.audit_log (actor_id);

create function private.log_change()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  -- Cancellazione a cascata dell'intera Collezione (eliminata dal
  -- Proprietario o con il suo account): la riga di log violerebbe la FK
  -- verso una Collezione che non esiste più, e verrebbe comunque cancellata.
  if tg_op = 'DELETE' and not exists (
    select 1 from public.collections where id = old.collection_id
  ) then
    return old;
  end if;

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

do $$
declare
  t text;
begin
  foreach t in array array[
    'opere', 'serie', 'edizioni', 'copie', 'creator', 'comic_creator', 'tag',
    'edizione_tag', 'character', 'comic_character', 'edizione_genere',
    'valore_stimato'
  ] loop
    execute format(
      'create trigger %I after insert or update or delete on public.%I '
      'for each row execute function private.log_change()',
      'audit_' || t, t
    );
  end loop;
end;
$$;

alter table public.audit_log enable row level security;

create policy "owner reads audit log" on public.audit_log
for select to authenticated
using ( private.member_role(collection_id) = 'owner' );
-- Nessuna policy di scrittura: scrive solo il trigger (SECURITY DEFINER).
