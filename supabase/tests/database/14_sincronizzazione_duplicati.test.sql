-- Duplicati di chiave naturale nella Sincronizzazione (ADR-0008, #208): lo
-- stesso collegamento o Valore stimato creato con id diversi da due device
-- non blocca il lotto; vince la riga già sul server.
begin;
\ir helpers.psql
select plan(7);

create function tests.hlc(ms bigint)
returns text
language sql immutable
as $$ select lpad(ms::text, 13, '0') || '-0000-device-b' $$;

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
as $$ select public.applica_modifiche(to_jsonb(ops)) $$;

grant execute on all functions in schema tests to authenticated;

select tests.create_user('duplicati@example.com') as utente \gset

select tests.authenticate_as(:'utente');

-- Il device A ha già caricato un'Edizione con un Tag e il Valore stimato
-- della sua Copia.
select tests.applica(
  tests.scrivi(1, 'opere', tests.id(1), '{"title": "Sandman"}', 100),
  tests.scrivi(2, 'edizioni', tests.id(1), jsonb_build_object('opera_id', tests.id(1)), 100),
  tests.scrivi(3, 'copie', tests.id(1), jsonb_build_object('edizione_id', tests.id(1), 'status', 'posseduta'), 100),
  tests.scrivi(4, 'tag', tests.id(1), '{"name": "horror"}', 100),
  tests.scrivi(5, 'edizione_tag', tests.id(1), jsonb_build_object('edizione_id', tests.id(1), 'tag_id', tests.id(1)), 100),
  tests.scrivi(6, 'valore_stimato', tests.id(1), jsonb_build_object('copia_id', tests.id(1), 'status', 'completata', 'value', 10), 100));

-- Il device B, offline, ha messo lo stesso Tag sulla stessa Edizione e
-- stimato la stessa Copia, con id suoi, e ha aggiunto una Nota.
select tests.applica(
  tests.scrivi(10, 'edizione_tag', tests.id(2), jsonb_build_object('edizione_id', tests.id(1), 'tag_id', tests.id(1)), 200),
  tests.scrivi(11, 'valore_stimato', tests.id(2), jsonb_build_object('copia_id', tests.id(1), 'status', 'completata', 'value', 12), 200),
  tests.scrivi(12, 'copie', tests.id(1), '{"notes": "da B"}', 200)) as esito \gset

select is(
  (select array_agg((e->>'tabella') || '/' || (e->>'id') order by 1)
   from jsonb_array_elements(:'esito'::jsonb->'eliminate') e),
  array['edizione_tag/' || tests.id(2), 'valore_stimato/' || tests.id(2)],
  'i duplicati del device sono restituiti come eliminati, senza annullare il lotto');
select is((select notes from public.copie where id = tests.id(1)), 'da B',
  '... e le altre operazioni del lotto sono applicate');
select is((select count(*)::int from public.edizione_tag where edizione_id = tests.id(1)), 1,
  'resta un solo collegamento...');
select is((select id from public.edizione_tag where edizione_id = tests.id(1)), tests.id(1),
  '... quello già sul server');
select is((select value from public.valore_stimato where copia_id = tests.id(1)), 10::double precision,
  'vince anche il Valore stimato già sul server');
select is((select count(*)::int from public.eliminazioni where riga = tests.id(2)), 2,
  'i duplicati scartati vanno nel registro delle eliminazioni...');
select is(
  (select array_agg(e->>'tabella' order by 1)
   from jsonb_array_elements(tests.applica(
     tests.scrivi(13, 'valore_stimato', tests.id(2), '{"value": 99}', 300))->'eliminate') e),
  array['valore_stimato'],
  '... così le operazioni successive del device su quel duplicato sono ignorate');

select * from finish();
rollback;
