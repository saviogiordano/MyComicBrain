-- Policy dei bucket Storage `covers` e `scansioni` (ADR-0007).
begin;
\ir helpers.psql
select plan(9);

select tests.create_user('owner@example.com') as owner \gset
select tests.create_user('viewer@example.com') as viewer \gset
select tests.create_user('estraneo@example.com') as estraneo \gset
select tests.collection_of(:'owner') as col \gset

insert into public.collection_members (collection_id, user_id, role) values (:'col', :'viewer', 'viewer');

select results_eq(
  $$ select id, public from storage.buckets where id in ('covers', 'scansioni') order by id $$,
  $$ values ('covers'::text, false), ('scansioni'::text, false) $$,
  'i due bucket esistono e sono privati');

select tests.authenticate_as(:'owner');
select lives_ok(
  format($$ insert into storage.objects (bucket_id, name) values ('covers', %L) $$, :'col' || '/a.jpg'),
  'il Proprietario carica una cover nella propria Collezione');
select throws_ok(
  format($$ insert into storage.objects (bucket_id, name) values ('covers', %L) $$, gen_random_uuid() || '/a.jpg'),
  '42501', null,
  'nessuno carica cover nella cartella di un''altra Collezione');
select lives_ok(
  format($$ insert into storage.objects (bucket_id, name) values ('scansioni', %L) $$, :'owner' || '/s.jpg'),
  'l''utente carica una Scansione nella propria cartella');
select throws_ok(
  format($$ insert into storage.objects (bucket_id, name) values ('scansioni', %L) $$, :'viewer' || '/s.jpg'),
  '42501', null,
  'nessuno carica Scansioni nella cartella di un altro utente');
reset role;

select tests.authenticate_as(:'viewer');
select results_eq($$ select count(*)::int from storage.objects where bucket_id = 'covers' $$, $$ values (1) $$,
  'il Visualizzatore legge le cover della Collezione');
select throws_ok(
  format($$ insert into storage.objects (bucket_id, name) values ('covers', %L) $$, :'col' || '/b.jpg'),
  '42501', null,
  'il Visualizzatore non carica cover');
select is_empty($$ select 1 from storage.objects where bucket_id = 'scansioni' $$,
  'un collaboratore non vede le Scansioni altrui');
reset role;

select tests.authenticate_as(:'estraneo');
select is_empty($$ select 1 from storage.objects $$,
  'un estraneo non vede nulla');
reset role;

select * from finish();
rollback;
