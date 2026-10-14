-- Chiavi uuid sulle tabelle replicate (ADR-0008, #203): id generati dal
-- device, oppure uuid v7 di default (ordinati nel tempo, così `order by id`
-- resta l'ordine di creazione).
begin;
\ir helpers.psql
select plan(25);

select col_type_is('public', t, 'id', 'uuid', t || '.id è uuid')
from unnest(array[
  'opere', 'serie', 'edizioni', 'copie', 'creator', 'comic_creator', 'tag',
  'edizione_tag', 'character', 'comic_character', 'edizione_genere',
  'valore_stimato', 'scansioni', 'analisi_copertina', 'identificazione',
  'candidati'
]) as t;

select col_type_is('public', 'edizioni', 'opera_id', 'uuid', 'le chiavi esterne sono uuid');
select col_type_is('public', 'copie', 'scansione_id', 'uuid', '... anche verso le Scansioni');
select col_type_is('public', 'candidati', 'edizione_id', 'uuid', '... e dai Candidati alle Edizioni');
select col_type_is('public', 'messaggio', 'edizione_ids', 'uuid[]',
  'i Messaggi riferiscono Edizioni per uuid');
select col_type_is('public', 'audit_log', 'row_id', 'uuid', 'l''audit riferisce righe per uuid');
select col_type_is('public', 'conversazione', 'id', 'bigint',
  'la Conversazione, non replicata, resta a bigint');

select tests.create_user('uuid@example.com') as utente \gset
select tests.collection_of(:'utente') as col \gset
select tests.authenticate_as(:'utente');

insert into public.opere (id, collection_id, title)
values ('0190a000-0000-7000-8000-000000000001', :'col', 'Dal device');
select is((select title from public.opere where id = '0190a000-0000-7000-8000-000000000001'),
  'Dal device', 'un id generato dal device viene accettato');

insert into public.opere (collection_id, title) values (:'col', 'Prima');
select pg_sleep(0.002);
insert into public.opere (collection_id, title) values (:'col', 'Seconda');
select is(
  (select substr(id::text, 15, 1) from public.opere where title = 'Prima'), '7',
  'senza id, il database genera un uuid v7');
select results_eq(
  $$ select title from public.opere
     where title in ('Prima', 'Seconda') order by id $$,
  $$ values ('Prima'), ('Seconda') $$,
  'gli uuid generati seguono l''ordine di creazione');

select * from finish();
rollback;
