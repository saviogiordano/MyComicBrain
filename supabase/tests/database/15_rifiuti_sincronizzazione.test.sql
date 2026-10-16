-- Modifiche rifiutate (ADR-0008, #227): con `versione_app` un'operazione
-- non valida è rifiutata da sola, le altre del lotto si applicano, e il
-- rifiuto finisce in `rifiuti_sincronizzazione`.
begin;
\ir helpers.psql
select plan(16);

create function tests.hlc(ms bigint)
returns text
language sql immutable
as $$ select lpad(ms::text, 13, '0') || '-0000-device-a' $$;

create function tests.scrivi(op bigint, tabella text, riga uuid, valori jsonb, ms bigint)
returns jsonb
language sql immutable
as $$
  select jsonb_build_object(
    'id', tests.id(op), 'tabella', tabella, 'riga', riga, 'valori', valori,
    'hlc', (select coalesce(jsonb_object_agg(k, tests.hlc(ms)), '{}') from jsonb_object_keys(valori) k))
$$;

create function tests.applica(variadic ops jsonb[])
returns jsonb
language sql
as $$ select public.applica_modifiche(to_jsonb(ops), '1.4.0+12') $$;

-- Le operazioni rifiutate, come "id/codice".
create function tests.rifiutate(risultato jsonb)
returns text[]
language sql immutable
as $$
  select coalesce(array_agg((r->>'id') || '/' || (r->>'codice') order by r->>'id'), '{}')
  from jsonb_array_elements(risultato->'rifiutate') r
$$;

grant execute on all functions in schema tests to authenticated;

select tests.create_user('rifiuti@example.com') as utente \gset
select tests.create_user('altro@example.com') as altro \gset
select tests.collection_of(:'altro') as col_altro \gset

select tests.authenticate_as(:'utente');

-- Un lotto con un'operazione non valida in mezzo.
select tests.applica(
  tests.scrivi(1, 'opere', tests.id(1), '{"title": "Saga"}', 100),
  tests.scrivi(2, 'opere', tests.id(2), '{"inesistente": 1}', 100),
  tests.scrivi(3, 'edizioni', tests.id(1), jsonb_build_object('opera_id', tests.id(1)), 100)) as esito \gset

select is(tests.rifiutate(:'esito'), array[tests.id(2) || '/22023'],
  'l''operazione non valida è restituita in rifiutate, con il codice');
select ok((:'esito'::jsonb->'rifiutate'->0->>'messaggio') like '%inesistente%',
  '... e il messaggio dell''errore');
select is((select count(*)::int from public.opere where id in (tests.id(1), tests.id(2))), 1,
  'le altre operazioni del lotto sono applicate...');
select is((select count(*)::int from public.edizioni where id = tests.id(1)), 1,
  '... anche quelle dopo il rifiuto');
select results_eq(
  $$ select operazione, tabella, riga, codice, versione_app, user_id
     from public.rifiuti_sincronizzazione $$,
  format($$ values (%L::uuid, 'opere', %L::uuid, '22023', '1.4.0+12', %L::uuid) $$,
    tests.id(2), tests.id(2), :'utente'),
  'il rifiuto è registrato con operazione, riga, codice e versione dell''app');

-- Un figlio di una creazione rifiutata cade per chiave esterna.
select is(
  tests.rifiutate(tests.applica(
    tests.scrivi(4, 'opere', tests.id(3), '{"title": "Paper Girls", "hlc_campi": {}}', 100),
    tests.scrivi(5, 'edizioni', tests.id(3), jsonb_build_object('opera_id', tests.id(3)), 100))),
  array[tests.id(4) || '/22023', tests.id(5) || '/23503'],
  'il figlio di una creazione rifiutata è rifiutato anche lui');

-- Idempotenza: un'operazione rifiutata non risulta applicata.
select is((select count(*)::int from public.operazioni_sincronizzate where id in (tests.id(2), tests.id(4), tests.id(5))), 0,
  'le operazioni rifiutate non finiscono in operazioni_sincronizzate...');
select is(
  tests.rifiutate(tests.applica(
    tests.scrivi(4, 'opere', tests.id(3), '{"title": "Paper Girls"}', 100),
    tests.scrivi(5, 'edizioni', tests.id(3), jsonb_build_object('opera_id', tests.id(3)), 100))),
  '{}'::text[],
  '... quindi un nuovo tentativo con lo stesso id, corretto, passa');
select is((select count(*)::int from public.edizioni where id = tests.id(3)), 1,
  '... e si applica');
select is(
  tests.rifiutate(tests.applica(tests.scrivi(1, 'opere', tests.id(1), '{"inesistente": 1}', 200))),
  '{}'::text[],
  'un''operazione già applicata non si rivaluta, quindi non si rifiuta');

-- Un rifiuto RLS: scrivere nella Collezione di un altro.
select is(
  tests.rifiutate(tests.applica(
    jsonb_build_object('id', tests.id(6), 'tabella', 'opere', 'riga', tests.id(99),
      'collection_id', :'col_altro'::uuid,
      'valori', '{"title": "intrusa"}'::jsonb, 'hlc', jsonb_build_object('title', tests.hlc(100))))),
  array[tests.id(6) || '/42501'],
  'una scrittura che le RLS non ammettono è rifiutata');

-- Un'operazione malformata, senza id valido, è rifiutata e registrata.
select is(
  (tests.applica(jsonb_build_object('id', 'nonuno', 'tabella', 'opere', 'riga', tests.id(7)))->'rifiutate'->0->>'codice'),
  '22P02',
  'un''operazione con un id non valido è rifiutata');
select is(
  (select count(*)::int from public.rifiuti_sincronizzazione where operazione is null and riga = tests.id(7)), 1,
  '... e registrata senza id');

-- Il client registra un upload rifiutato; ognuno vede solo i propri rifiuti.
insert into public.rifiuti_sincronizzazione (file, codice, messaggio, versione_app)
values ('copertine/abc.jpg', '413', 'Payload too large', '1.4.0+12');
select tests.authenticate_as(:'altro');
select is((select count(*)::int from public.rifiuti_sincronizzazione), 0,
  'un altro utente non vede i rifiuti altrui');
select throws_ok(
  format($$ insert into public.rifiuti_sincronizzazione (user_id, file, codice, messaggio)
     values (%L, 'x', '400', 'x') $$, :'utente'),
  '42501', null, 'né ne scrive a nome di altri');

-- Senza sessione.
reset role;
select set_config('request.jwt.claims', '{}', true);
select throws_ok(
  $$ select public.applica_modifiche('[]', '1.4.0+12') $$,
  '28000', null, 'senza sessione la chiamata fallisce con 28000, non come un rifiuto RLS');

select * from finish();
rollback;
