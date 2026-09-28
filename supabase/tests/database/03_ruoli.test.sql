-- Ruoli Proprietario/Editor/Visualizzatore su una tabella di dominio (§17.2).
begin;
\ir helpers.psql
select plan(12);

select tests.create_user('owner@example.com') as owner \gset
select tests.create_user('editor@example.com') as editor \gset
select tests.create_user('viewer@example.com') as viewer \gset
select tests.collection_of(:'owner') as col \gset

insert into public.collection_members (collection_id, user_id, role) values
  (:'col', :'editor', 'editor'),
  (:'col', :'viewer', 'viewer');
insert into public.opere (id, collection_id, title) values (101, :'col', 'Martin Mystère');
insert into public.edizioni (id, collection_id, opera_id, issue_number) values (101, :'col', 101, 1);
insert into public.copie (id, collection_id, edizione_id, status) values (101, :'col', 101, 'posseduta');

-- Visualizzatore: legge, non scrive.
select tests.authenticate_as(:'viewer');
select results_eq($$ select id from public.copie $$, $$ values (101::bigint) $$,
  'il Visualizzatore legge le Copie della Collezione');
select throws_ok(
  format($$ insert into public.copie (collection_id, edizione_id, status) values (%L, 101, 'posseduta') $$, :'col'),
  '42501', null, 'il Visualizzatore non inserisce Copie');
select is(tests.affected($$ update public.copie set notes = 'x' $$), 0,
  'il Visualizzatore non modifica Copie');
select is(tests.affected($$ delete from public.copie $$), 0,
  'il Visualizzatore non cancella Copie');
reset role;

-- Editor: legge e scrive.
select tests.authenticate_as(:'editor');
select lives_ok(
  format($$ insert into public.copie (id, collection_id, edizione_id, status) values (102, %L, 101, 'prestata') $$, :'col'),
  'l''Editor inserisce Copie');
select is(tests.affected($$ update public.copie set notes = 'riletto' where id = 101 $$), 1,
  'l''Editor modifica Copie');
select is(tests.affected($$ delete from public.copie where id = 102 $$), 1,
  'l''Editor cancella Copie');
select is((select created_by from public.opere where id = 101), null::uuid,
  'righe inserite come postgres non hanno autore');
select throws_ok(
  format($$ insert into public.collection_members (collection_id, user_id, role) values (%L, %L, 'editor') $$, :'col', :'editor'),
  '42501', null, 'l''Editor non gestisce l''appartenenza');
reset role;

-- Proprietario: scrive e gestisce i membri, ma non promuove un secondo
-- Proprietario.
select tests.authenticate_as(:'owner');
select is(tests.affected(format($$ update public.collection_members set role = 'editor' where user_id = %L $$, :'viewer')), 1,
  'il Proprietario cambia il ruolo di un membro');
select throws_ok(
  format($$ update public.collection_members set role = 'owner' where user_id = %L $$, :'editor'),
  '42501', null, 'il Proprietario non nomina un secondo Proprietario');
select is(tests.affected(format($$ delete from public.collection_members where user_id = %L $$, :'owner')), 0,
  'il Proprietario non rimuove sé stesso');
reset role;

select * from finish();
rollback;
