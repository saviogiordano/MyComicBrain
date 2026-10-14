-- Importazione della Modalità locale (ADR-0005, ADR-0007, #173): gli id
-- drift si rimappano, tutto finisce nella Collezione dell'utente, un nuovo
-- tentativo con lo stesso import_id non duplica, un errore non lascia
-- righe a metà.
begin;
\ir helpers.psql
select plan(21);

select tests.create_user('importa@example.com') as utente \gset
select tests.create_user('altro@example.com') as altro \gset
select tests.collection_of(:'utente') as col \gset

-- Id drift volutamente bassi e sovrapposti fra tabelle: non devono
-- comparire tali e quali in Postgres.
\set payload '{"opere":[{"id":1,"title":"Dylan Dog","created_at":"2026-01-02T10:00:00Z"}],"serie":[{"id":1,"name":"Dylan Dog","total_issues":400,"cover_image":"COL/serie.jpg"}],"edizioni":[{"id":1,"opera_id":1,"serie_id":1,"issue_number":1,"issue_number_label":"1","cover_image":"COL/cover-1.jpg","created_at":"2026-01-02T10:00:00Z","format":"bonellide"},{"id":2,"opera_id":1,"serie_id":null,"issue_number_label":"2","created_at":"2026-01-03T10:00:00Z"}],"copie":[{"id":1,"edizione_id":1,"status":"posseduta","reading_status":"letto","purchase_price":3.5,"purchase_price_currency":"eur","created_at":"2026-01-02T10:00:00Z","updated_at":"2026-01-02T10:00:00Z","scansione_id":99,"for_sale":true},{"id":2,"edizione_id":2,"status":"posseduta","created_at":"2026-01-03T10:00:00Z","updated_at":"2026-01-03T10:00:00Z"}],"valore_stimato":[{"id":1,"copia_id":1,"status":"completata","value":12.5,"created_at":"2026-01-04T10:00:00Z"}],"creator":[{"id":1,"name":"Tiziano Sclavi"}],"comic_creator":[{"id":1,"edizione_id":1,"creator_id":1,"ruolo":"sceneggiatore"}],"tag":[{"id":1,"name":"horror"}],"edizione_tag":[{"id":1,"edizione_id":1,"tag_id":1}],"character":[{"id":1,"name":"Groucho"}],"comic_character":[{"id":1,"edizione_id":1,"character_id":1}],"edizione_genere":[{"id":1,"edizione_id":1,"genere":"horror"}],"scansioni":[{"id":5,"image":"UID/scan-5.jpg","created_at":"2026-01-05T10:00:00Z"}],"analisi_copertina":[{"id":1,"scansione_id":5,"title":"Martin Mystère","characters":["Martin","Java"],"status":"completata","created_at":"2026-01-05T10:00:00Z"}],"identificazione":[{"id":1,"scansione_id":5,"status":"completata","created_at":"2026-01-05T10:00:00Z"}],"candidati":[{"id":1,"identificazione_id":1,"source":"interno","edizione_id":2,"punteggio":80,"scelto":false},{"id":2,"identificazione_id":1,"source":"esterno","edizione_id":null,"cover_image_url":"https://example.com/c.jpg","punteggio":40}]}'

-- Un'importazione precedente da un altro device: la Collezione è già
-- popolata e l'importazione la unisce senza deduplicare.
select tests.authenticate_as(:'utente');
insert into public.opere (id, collection_id, title) values (tests.id(1), :'col', 'Già nell''account');
insert into public.edizioni (id, collection_id, opera_id) values (tests.id(1), :'col', tests.id(1));
insert into public.copie (collection_id, edizione_id, status) values (:'col', tests.id(1), 'posseduta');

select is(
  public.importa_modalita_locale(:'payload'::jsonb, '00000000-0000-4000-8000-000000000001'),
  '{"copie_importate": 2, "scansioni_importate": 1, "copie_collezione": 3}'::jsonb,
  'restituisce le Copie importate, le Scansioni e il totale della Collezione');

select results_eq(
  $$ select count(*)::int from public.edizioni where issue_number_label in ('1', '2') $$,
  $$ values (2) $$, 'le Edizioni sono importate');
select is(
  (select o.title from public.edizioni e join public.opere o on o.id = e.opera_id
   where e.issue_number_label = '1'),
  'Dylan Dog', 'l''Edizione punta alla nuova Opera, non all''id drift');
select is(
  (select s.name from public.edizioni e join public.serie s on s.id = e.serie_id
   where e.issue_number_label = '1'),
  'Dylan Dog', '... e alla nuova Serie');
select is(
  (select count(*)::int from public.copie c join public.edizioni e on e.id = c.edizione_id
   where e.issue_number_label = '1' and c.for_sale and c.reading_status = 'letto'),
  1, 'la Copia conserva i suoi campi e punta alla nuova Edizione');
select is(
  (select c.scansione_id from public.copie c join public.edizioni e on e.id = c.edizione_id
   where e.issue_number_label = '1'),
  null, 'una Scansione assente dal payload (già risolta) diventa null');
select is(
  (select v.value from public.valore_stimato v join public.copie c on c.id = v.copia_id
   join public.edizioni e on e.id = c.edizione_id where e.issue_number_label = '1'),
  12.5::double precision, 'il Valore stimato segue la sua Copia');
select is(
  (select cr.name || '/' || cc.ruolo from public.comic_creator cc
   join public.creator cr on cr.id = cc.creator_id),
  'Tiziano Sclavi/sceneggiatore', 'Creator e ruoli sono rimappati');
select is(
  (select count(*)::int from public.edizione_tag et join public.tag t on t.id = et.tag_id
   join public.comic_character ch on ch.edizione_id = et.edizione_id
   join public.edizione_genere g on g.edizione_id = et.edizione_id),
  1, 'Tag, Personaggi e Generi sono rimappati');
select is(
  (select array_agg(distinct collection_id) from (
     select collection_id from public.opere union all
     select collection_id from public.edizioni union all
     select collection_id from public.copie) t),
  array[:'col'::uuid], 'tutte le righe stanno nella Collezione dell''utente');
select is(
  (select count(*)::int from public.copie where created_by = :'utente'),
  3, 'created_by è l''utente che importa');

select is(
  (select a.characters from public.analisi_copertina a
   join public.scansioni s on s.id = a.scansione_id where s.image = 'UID/scan-5.jpg'),
  array['Martin', 'Java'], 'l''Analisi Copertina segue la sua Scansione, liste comprese');
select is(
  (select e.issue_number_label from public.candidati c
   join public.identificazione i on i.id = c.identificazione_id
   join public.edizioni e on e.id = c.edizione_id),
  '2', 'un Candidato interno punta alla nuova Edizione');

-- Drift con chiavi uuid (ADR-0008): gli id che sono già uuid si conservano,
-- e i collegamenti seguono l'ordine del payload.
select is(
  public.importa_modalita_locale(
    '{"opere":[{"id":"0190b000-0000-7000-8000-0000000000a1","title":"Zagor"}],
      "edizioni":[{"id":"0190b000-0000-7000-8000-0000000000b1","opera_id":"0190b000-0000-7000-8000-0000000000a1","issue_number_label":"Z1"}],
      "creator":[{"id":"0190b000-0000-7000-8000-0000000000c1","name":"Guido Nolitta"},
                 {"id":"0190b000-0000-7000-8000-0000000000c2","name":"Gallieno Ferri"},
                 {"id":"0190b000-0000-7000-8000-0000000000c3","name":"Bonelli"}],
      "comic_creator":[{"id":3,"edizione_id":"0190b000-0000-7000-8000-0000000000b1","creator_id":"0190b000-0000-7000-8000-0000000000c3","ruolo":"altro"},
                       {"id":1,"edizione_id":"0190b000-0000-7000-8000-0000000000b1","creator_id":"0190b000-0000-7000-8000-0000000000c1","ruolo":"sceneggiatore"},
                       {"id":2,"edizione_id":"0190b000-0000-7000-8000-0000000000b1","creator_id":"0190b000-0000-7000-8000-0000000000c2","ruolo":"disegnatore"}]}',
    '00000000-0000-4000-8000-000000000003') ->> 'copie_importate',
  '0', 'un payload con id uuid viene importato');
select is(
  (select o.title from public.edizioni e join public.opere o on o.id = e.opera_id
   where e.id = '0190b000-0000-7000-8000-0000000000b1'),
  'Zagor', '... conservando gli uuid del device');
select results_eq(
  $$ select cr.name from public.comic_creator cc join public.creator cr on cr.id = cc.creator_id
     where cc.edizione_id = '0190b000-0000-7000-8000-0000000000b1' order by cc.id $$,
  $$ values ('Bonelli'), ('Guido Nolitta'), ('Gallieno Ferri') $$,
  '... e l''ordine del payload per gli id da rimappare');

-- Nuovo tentativo dopo una risposta persa: stesso esito, nessuna riga in più.
select is(
  public.importa_modalita_locale(:'payload'::jsonb, '00000000-0000-4000-8000-000000000001'),
  '{"copie_importate": 2, "scansioni_importate": 1, "copie_collezione": 3}'::jsonb,
  'lo stesso import_id restituisce l''esito già salvato');
select results_eq($$ select count(*)::int from public.copie $$, $$ values (3) $$,
  '... senza duplicare le Copie');

-- Un errore a metà (genere fuori dal check) annulla tutto, compresa la riga
-- in importazioni: il tentativo successivo con lo stesso id riparte da zero.
select throws_ok(
  $$ select public.importa_modalita_locale(
       '{"opere":[{"id":1,"title":"Rotta","created_at":"2026-01-01T00:00:00Z"}],
         "edizioni":[{"id":1,"opera_id":1,"created_at":"2026-01-01T00:00:00Z"}],
         "edizione_genere":[{"id":1,"edizione_id":1,"genere":"inesistente"}]}',
       '00000000-0000-4000-8000-000000000002') $$,
  '23514', null, 'un payload non valido fa fallire l''importazione');
select results_eq(
  $$ select (select count(*)::int from public.opere where title = 'Rotta'),
            (select count(*)::int from public.importazioni
             where id = '00000000-0000-4000-8000-000000000002') $$,
  $$ values (0, 0) $$, '... senza lasciare righe a metà');
reset role;

-- Un import_id di un altro utente non rivela né ripete nulla.
select tests.authenticate_as(:'altro');
select throws_ok(
  $$ select public.importa_modalita_locale('{}', '00000000-0000-4000-8000-000000000001') $$,
  '42501', null, 'l''import_id di un altro utente è rifiutato');
reset role;

select * from finish();
rollback;
