-- Conferma di un Candidato (ADR-0007, #196): atomica e limitata dalle RLS
-- alla Collezione dell'utente.
begin;
\ir helpers.psql
select plan(9);

select tests.create_user('conferma@example.com') as utente \gset
select tests.create_user('estraneo@example.com') as estraneo \gset
select tests.collection_of(:'utente') as col \gset

select tests.authenticate_as(:'utente');
insert into public.scansioni (id, collection_id, image)
values (900001, :'col', 'u/1.jpg'), (900002, :'col', 'u/2.jpg');
insert into public.identificazione (id, scansione_id, status)
values (900001, 900001, 'completata'), (900002, 900002, 'completata');
insert into public.candidati (id, identificazione_id, source, punteggio)
values (900001, 900001, 'esterno', 80), (900002, 900002, 'interno', 90);
insert into public.serie (id, collection_id, name) values (900001, :'col', 'Batman');

select is(
  public.conferma_candidato(:'col', 900001, 900001, null, null,
    '{"title": "Batman 1", "series_name": " BATMAN ", "issue_number": 1,
      "issue_number_label": "1", "cover_image": "c/1.jpg"}'::jsonb,
    'fine', 5.3, 'eur') is not null,
  true, 'un Candidato esterno viene confermato');
select is((select serie_id from public.edizioni e join public.opere o on o.id = e.opera_id
           where o.title = 'Batman 1'), 900001::bigint,
  '... riusando la Serie con lo stesso nome');
select is((select scelto from public.candidati where id = 900001), true,
  '... marcando il Candidato scelto');
select is((select scansione_id from public.copie c join public.edizioni e on e.id = c.edizione_id
           where e.cover_image = 'c/1.jpg'), 900001::bigint,
  '... e collegando la Copia alla Scansione');

select tests.authenticate_as(:'estraneo');
select throws_ok(
  format($$ select public.conferma_candidato(%L, 900002, 900002, null, null,
    '{"title": "Intruso"}'::jsonb, 'fine', null, null) $$, :'col'),
  '42501', null, 'un estraneo non può confermare nella Collezione altrui');

select tests.authenticate_as(:'utente');
select is((select count(*)::int from public.opere where title = 'Intruso'), 0,
  '... e non lascia righe a metà');
select throws_ok(
  format($$ select public.conferma_candidato(%L, 900002, 900002, null, null,
    '{"title": "Rotto"}'::jsonb, 'condizione-inesistente', null, null) $$, :'col'),
  '23514', null, 'un errore sulla Copia annulla la conferma...');
select is((select count(*)::int from public.opere where title = 'Rotto'), 0,
  '... compresa l''Opera già inserita');
select is((select scelto from public.candidati where id = 900002), false,
  '... e la marcatura del Candidato');

select * from finish();
rollback;
