-- Audit trail (§27): ogni scrittura sulle tabelle di dominio lascia una
-- riga in audit_log, leggibile solo dal Proprietario.
begin;
\ir helpers.psql
select plan(5);

select tests.create_user('owner@example.com') as owner \gset
select tests.create_user('editor@example.com') as editor \gset
select tests.collection_of(:'owner') as col \gset

insert into public.collection_members (collection_id, user_id, role) values (:'col', :'editor', 'editor');

select tests.authenticate_as(:'editor');
insert into public.opere (id, collection_id, title) values (101, :'col', 'Nathan Never');
update public.opere set title = 'Nathan Never Gigante' where id = 101;
delete from public.opere where id = 101;

select is_empty($$ select 1 from public.audit_log $$,
  'l''Editor non legge l''audit log');
select throws_ok(
  format($$ insert into public.audit_log (collection_id, table_name, row_id, action) values (%L, 'opere', 1, 'insert') $$, :'col'),
  '42501', null,
  'nessuno scrive l''audit log a mano');
reset role;

select tests.authenticate_as(:'owner');
select results_eq(
  $$ select action, actor_id::text from public.audit_log where table_name = 'opere' and row_id = 101 order by id $$,
  format($$ values ('insert', %1$L), ('update', %1$L), ('delete', %1$L) $$, :'editor'),
  'il Proprietario vede insert/update/delete con l''autore');
select results_eq(
  $$ select diff -> 'new' ->> 'title' from public.audit_log where action = 'update' and row_id = 101 $$,
  $$ values ('Nathan Never Gigante') $$,
  'l''update registra il valore nuovo');
select is(
  (select created_by from public.audit_log a
   cross join lateral jsonb_to_record(a.diff) as r(created_by uuid)
   where a.action = 'insert' and a.row_id = 101),
  :'editor'::uuid,
  'created_by prende il default auth.uid()');
reset role;

select * from finish();
rollback;
