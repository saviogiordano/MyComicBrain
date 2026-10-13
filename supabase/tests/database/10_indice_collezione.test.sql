-- Indice della Collezione (ADR-0007, #193): solo le Edizioni possedute,
-- con i collegamenti aggregati, e mai le Edizioni di un'altra Collezione.
begin;
\ir helpers.psql
select plan(5);

select tests.create_user('indice@example.com') as utente \gset
select tests.create_user('estraneo-indice@example.com') as estraneo \gset
select tests.collection_of(:'utente') as col \gset

select tests.authenticate_as(:'utente');
insert into public.opere (id, collection_id, title) values (910001, :'col', 'Watchmen'), (910002, :'col', 'Venduto');
insert into public.edizioni (id, collection_id, opera_id) values (910001, :'col', 910001), (910002, :'col', 910002);
insert into public.copie (collection_id, edizione_id, status, location)
values (:'col', 910001, 'posseduta', 'Scaffale A'), (:'col', 910001, 'venduta', 'Scatola'),
       (:'col', 910002, 'venduta', null);
insert into public.creator (id, collection_id, name) values (910001, :'col', 'Alan Moore');
insert into public.comic_creator (collection_id, edizione_id, creator_id, ruolo)
values (:'col', 910001, 910001, 'sceneggiatore');
insert into public.edizione_genere (collection_id, edizione_id, genere) values (:'col', 910001, 'supereroi');

select is(jsonb_array_length(public.indice_collezione(:'col')), 1,
  'solo le Edizioni con una Copia posseduta o prestata');
select is(public.indice_collezione(:'col') -> 0 ->> 'titolo', 'Watchmen',
  'il titolo viene dall''Opera');
select is(public.indice_collezione(:'col') -> 0 -> 'autori', '["Alan Moore"]'::jsonb,
  'gli Autori sono aggregati');
select is(public.indice_collezione(:'col') -> 0 -> 'copie' -> 0 ->> 'location', 'Scaffale A',
  'gli assi vengono solo dalle Copie possedute');

select tests.authenticate_as(:'estraneo');
select is(public.indice_collezione(:'col'), '[]'::jsonb,
  'un estraneo non vede l''indice di un''altra Collezione');

select * from finish();
rollback;
