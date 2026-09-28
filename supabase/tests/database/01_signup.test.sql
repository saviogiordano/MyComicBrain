-- Signup: Profilo e Collezione nascono con l'utente (ADR-0004, "una
-- Collezione per account").
begin;
\ir helpers.psql
select plan(8);

select tests.create_user('anna@example.com') as anna \gset

select results_eq(
  format($$ select display_name from public.profiles where id = %L $$, :'anna'),
  $$ values ('anna@example.com') $$,
  'il Profilo nasce con l''email come nome visualizzato'
);

select results_eq(
  format($$ select role from public.collection_members where user_id = %L $$, :'anna'),
  $$ values ('owner'::public.collection_role) $$,
  'il nuovo utente è Proprietario di esattamente una Collezione'
);

select isnt(tests.collection_of(:'anna'), null, 'la Collezione esiste');

select tests.authenticate_as(:'anna');

select is(
  public.create_own_collection(),
  tests.collection_of(:'anna'),
  'create_own_collection è idempotente: restituisce la Collezione esistente'
);

select results_eq(
  $$ select count(*)::int from public.collections $$,
  $$ values (1) $$,
  'l''utente vede solo la propria Collezione'
);

select throws_ok(
  $$ insert into public.collections (name) values ('Seconda') $$,
  '42501',
  null,
  'nessun insert diretto su collections'
);

select throws_ok(
  $$ insert into public.profiles (id, display_name) values (gen_random_uuid(), 'x') $$,
  '42501',
  null,
  'nessun insert diretto su profiles'
);

reset role;

-- Utente registrato prima della migrazione (o Collezione persa): la RPC la
-- ricrea.
delete from public.collection_members where user_id = :'anna';
select tests.authenticate_as(:'anna');
select isnt(public.create_own_collection(), null, 'create_own_collection ricrea la Collezione mancante');
reset role;

select * from finish();
rollback;
