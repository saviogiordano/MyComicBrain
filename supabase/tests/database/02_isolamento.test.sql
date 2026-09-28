-- Isolamento fra due account (§17.3): nessuno vede o tocca la Collezione
-- dell'altro, nemmeno per riferimento.
begin;
\ir helpers.psql
select plan(10);

select tests.create_user('anna@example.com') as anna \gset
select tests.create_user('bruno@example.com') as bruno \gset
select tests.collection_of(:'anna') as anna_col \gset
select tests.collection_of(:'bruno') as bruno_col \gset

insert into public.opere (id, collection_id, title) values (101, :'anna_col', 'Dylan Dog');
insert into public.edizioni (id, collection_id, opera_id, issue_number) values (101, :'anna_col', 101, 1);
insert into public.copie (id, collection_id, edizione_id, status) values (101, :'anna_col', 101, 'posseduta');
insert into public.opere (id, collection_id, title) values (102, :'bruno_col', 'Tex');

select tests.authenticate_as(:'bruno');

select is_empty(format($$ select 1 from public.edizioni where collection_id = %L $$, :'anna_col'),
  'Bruno non vede le Edizioni di Anna');
select is_empty($$ select 1 from public.copie $$,
  'Bruno non vede le Copie di Anna');
select results_eq($$ select title from public.opere $$, $$ values ('Tex') $$,
  'Bruno vede solo le proprie Opere');
select is_empty(format($$ select 1 from public.collections where id = %L $$, :'anna_col'),
  'Bruno non vede la Collezione di Anna');
select is_empty(format($$ select 1 from public.collection_members where user_id = %L $$, :'anna'),
  'Bruno non vede l''appartenenza di Anna');

select throws_ok(
  format($$ insert into public.opere (collection_id, title) values (%L, 'Intruso') $$, :'anna_col'),
  '42501', null,
  'Bruno non può inserire nella Collezione di Anna'
);

select is(tests.affected($$ update public.copie set notes = 'x' where id = 101 $$), 0,
  'Bruno non può modificare le Copie di Anna');
select is(tests.affected($$ delete from public.opere where id = 101 $$), 0,
  'Bruno non può cancellare le Opere di Anna');

-- FK composita: una riga di Bruno non può puntare a una riga di Anna,
-- anche conoscendone l'id.
select throws_ok(
  format($$ insert into public.edizioni (collection_id, opera_id) values (%L, 101) $$, :'bruno_col'),
  '23503', null,
  'un''Edizione di Bruno non può riferire un''Opera di Anna'
);

reset role;

select results_eq($$ select notes from public.copie where id = 101 $$, $$ values (null::text) $$,
  'la Copia di Anna è intatta');

select * from finish();
rollback;
