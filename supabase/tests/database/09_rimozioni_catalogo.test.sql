-- Rimozione di Copie ed Edizioni (ADR-0007, #177): atomiche, con i
-- collegamenti che le FK di ADR-0004 non eliminano a cascata, e limitate
-- dalle RLS alla Collezione dell'utente.
begin;
\ir helpers.psql
select plan(8);

select tests.create_user('rimuove@example.com') as utente \gset
select tests.create_user('estraneo@example.com') as estraneo \gset
select tests.collection_of(:'utente') as col \gset

select tests.authenticate_as(:'utente');
insert into public.opere (id, collection_id, title) values (900001, :'col', 'Watchmen');
insert into public.edizioni (id, collection_id, opera_id) values (900001, :'col', 900001);
insert into public.copie (id, collection_id, edizione_id, status)
values (900001, :'col', 900001, 'posseduta'), (900002, :'col', 900001, 'venduta');
insert into public.valore_stimato (collection_id, copia_id, status) values (:'col', 900001, 'inCorso');
insert into public.creator (id, collection_id, name) values (900001, :'col', 'Alan Moore');
insert into public.comic_creator (collection_id, edizione_id, creator_id, ruolo)
values (:'col', 900001, 900001, 'sceneggiatore');
insert into public.character (id, collection_id, name) values (900001, :'col', 'Rorschach');
insert into public.comic_character (collection_id, edizione_id, character_id) values (:'col', 900001, 900001);
insert into public.tag (id, collection_id, name) values (900001, :'col', 'capolavoro');
insert into public.edizione_tag (collection_id, edizione_id, tag_id) values (:'col', 900001, 900001);
insert into public.edizione_genere (collection_id, edizione_id, genere) values (:'col', 900001, 'supereroi');

select tests.authenticate_as(:'estraneo');
select throws_ok($$ select public.rimuovi_copia(900001) $$, 'P0002', null,
  'un estraneo non vede la Copia: rimuovi_copia fallisce');
select lives_ok($$ select public.elimina_edizione(900001) $$,
  'elimina_edizione di un estraneo non è un errore...');

select tests.authenticate_as(:'utente');
select is((select count(*)::int from public.copie where edizione_id = 900001), 2,
  '... e non elimina nulla');

select is(public.rimuovi_copia(900001), false,
  'rimuovi_copia con altre Copie restituisce false');
select is((select count(*)::int from public.valore_stimato), 0,
  'il Valore stimato della Copia rimossa è eliminato');

select is(public.rimuovi_copia(900002), true,
  'rimuovi_copia sull''ultima Copia restituisce true');
select is((select count(*)::int from public.edizioni where id = 900001), 0,
  '... ed elimina l''Edizione');
select is(
  (select count(*)::int from (
    select 1 from public.comic_creator union all
    select 1 from public.comic_character union all
    select 1 from public.edizione_tag union all
    select 1 from public.edizione_genere) t),
  0, '... con Autori, Personaggi, Tag e Generi');

select * from finish();
rollback;
