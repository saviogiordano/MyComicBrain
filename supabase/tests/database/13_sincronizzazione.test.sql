-- Lato server della Sincronizzazione (ADR-0008, #206): `applica_modifiche`
-- (ultima modifica fatta vince campo per campo, l'eliminazione prevale anche
-- a cascata, idempotenza per id operazione) e `cambiamenti_da` (pull a pagine
-- limitato all'orizzonte sicuro delle transazioni).
begin;
\ir helpers.psql
select plan(47);

-- Un timestamp HLC nel formato di ADR-0008: millisecondi, contatore, device.
create function tests.hlc(ms bigint, contatore int default 0)
returns text
language sql immutable
as $$ select lpad(ms::text, 13, '0') || '-' || lpad(contatore::text, 4, '0') || '-device-a' $$;

-- Un'operazione di scrittura con lo stesso timestamp per tutti i campi.
create function tests.scrivi(op bigint, tabella text, riga uuid, valori jsonb, ms bigint)
returns jsonb
language sql immutable
as $$
  select jsonb_build_object(
    'id', tests.id(op), 'tabella', tabella, 'riga', riga, 'valori', valori,
    'hlc', (select coalesce(jsonb_object_agg(k, tests.hlc(ms)), '{}') from jsonb_object_keys(valori) k))
$$;

create function tests.elimina(op bigint, tabella text, riga uuid)
returns jsonb
language sql immutable
as $$ select jsonb_build_object('id', tests.id(op), 'tabella', tabella, 'riga', riga, 'elimina', true) $$;

create function tests.applica(variadic ops jsonb[])
returns jsonb
language sql
as $$ select public.applica_modifiche(to_jsonb(ops)) $$;

-- Le righe eliminate restituite da `applica_modifiche`, come "tabella/id".
create function tests.eliminate(risultato jsonb)
returns text[]
language sql immutable
as $$
  select coalesce(array_agg((e->>'tabella') || '/' || (e->>'id') order by 1), '{}')
  from jsonb_array_elements(risultato->'eliminate') e
$$;

grant execute on all functions in schema tests to authenticated;

select tests.create_user('sincronizza@example.com') as utente \gset
select tests.create_user('estraneo@example.com') as estraneo \gset
select tests.collection_of(:'utente') as col \gset

-- Scrittura e conflitti campo per campo -------------------------------------------

select tests.authenticate_as(:'utente');

select is(
  tests.applica(
    tests.scrivi(1, 'opere', tests.id(1), '{"title": "Watchmen"}', 100),
    tests.scrivi(2, 'edizioni', tests.id(1), jsonb_build_object('opera_id', tests.id(1), 'issue_number_label', '1'), 100),
    tests.scrivi(3, 'copie', tests.id(1), jsonb_build_object('edizione_id', tests.id(1), 'status', 'posseduta', 'notes', 'a'), 100)),
  '{"eliminate": [], "rifiutate": []}'::jsonb,
  'una Opera, un''Edizione e una Copia nuove si creano senza scarti');
select is((select collection_id from public.copie where id = tests.id(1)), :'col'::uuid,
  'senza collection_id esplicito la riga va nella Collezione dell''utente');
select is((select hlc_campi->>'notes' from public.copie where id = tests.id(1)), tests.hlc(100),
  'la riga tiene il timestamp di ogni campo scritto');

select tests.applica(tests.scrivi(4, 'copie', tests.id(1), '{"notes": "vecchia"}', 50));
select is((select notes from public.copie where id = tests.id(1)), 'a',
  'una modifica fatta prima non sovrascrive una più recente, anche se arriva dopo');

select tests.applica(tests.scrivi(5, 'copie', tests.id(1), '{"notes": "nuova"}', 200));
select is((select notes from public.copie where id = tests.id(1)), 'nuova',
  'una modifica fatta dopo sovrascrive');

select tests.applica(tests.scrivi(6, 'copie', tests.id(1), '{"status": "venduta", "notes": "intermedia"}', 150));
select results_eq(
  $$ select status, notes from public.copie where id = tests.id(1) $$,
  $$ values ('venduta', 'nuova') $$,
  'i campi si confrontano uno per uno: vince status (150 > 100), non notes (150 < 200)');

select tests.applica(
  jsonb_build_object('id', tests.id(7), 'tabella', 'copie', 'riga', tests.id(1),
    'valori', '{"notes": "stesso istante"}'::jsonb, 'hlc', jsonb_build_object('notes', tests.hlc(200, 1))));
select is((select notes from public.copie where id = tests.id(1)), 'stesso istante',
  'a parità di millisecondi decide il contatore dell''HLC');

-- Idempotenza: la stessa operazione si applica una volta sola.
select tests.applica(tests.scrivi(8, 'copie', tests.id(1), '{"location": "scaffale"}', 300));
reset role;
update public.copie set location = 'altrove', hlc_campi = hlc_campi - 'location' where id = tests.id(1);
select tests.authenticate_as(:'utente');
select tests.applica(tests.scrivi(8, 'copie', tests.id(1), '{"location": "scaffale"}', 300));
select is((select location from public.copie where id = tests.id(1)), 'altrove',
  'un''operazione già applicata (stesso id) non si riapplica');

select tests.applica(tests.scrivi(9, 'copie', tests.id(1), '{"seller": null}', 400));
select is((select hlc_campi ? 'seller' from public.copie where id = tests.id(1)), true,
  'anche un campo messo a null tiene il suo timestamp');

-- Operazioni non valide, da un client che non passa versione_app (prima dei
-- rifiuti per operazione, #227): la transazione si annulla per intero.
select throws_ok(
  $$ select tests.applica(
       tests.scrivi(10, 'copie', tests.id(1), '{"notes": "valida"}', 500),
       jsonb_build_object('id', tests.id(11), 'tabella', 'copie', 'riga', tests.id(1),
         'valori', '{"notes": "x"}'::jsonb, 'hlc', '{"notes": "ieri"}'::jsonb)) $$,
  '22023', null, 'un timestamp HLC malformato è rifiutato');
select is((select notes from public.copie where id = tests.id(1)), 'stesso istante',
  '... e niente del lotto resta applicato');
select throws_ok(
  $$ select tests.applica(tests.scrivi(12, 'conversazione', tests.id(1), '{}', 500)) $$,
  '22023', null, 'una tabella non replicata è rifiutata');
select throws_ok(
  $$ select tests.applica(tests.scrivi(13, 'copie', tests.id(1), '{"hlc_campi": {}}', 500)) $$,
  '22023', null, 'una colonna gestita dal server è rifiutata');
select throws_ok(
  $$ select tests.applica(tests.scrivi(14, 'copie', tests.id(1), '{"inesistente": 1}', 500)) $$,
  '22023', null, 'una colonna inesistente è rifiutata');
select throws_ok(
  $$ select tests.applica(jsonb_build_object('id', tests.id(15), 'tabella', 'copie', 'riga', tests.id(1),
       'valori', '{"notes": "senza hlc"}'::jsonb)) $$,
  '22023', null, 'un campo senza timestamp è rifiutato');

-- Le RLS restano l'unica barriera.
select tests.authenticate_as(:'estraneo');
select throws_ok(
  format($$ select tests.applica(jsonb_build_object('id', tests.id(16), 'tabella', 'opere',
       'riga', tests.id(99), 'collection_id', %L::uuid,
       'valori', '{"title": "intrusa"}'::jsonb, 'hlc', jsonb_build_object('title', tests.hlc(500)))) $$, :'col'),
  '42501', null, 'un estraneo non scrive nella Collezione di un altro');
select throws_ok(
  $$ select tests.applica(tests.elimina(17, 'copie', tests.id(1))) $$,
  '42501', null, 'né elimina le sue righe');
select tests.authenticate_as(:'utente');
select is((select count(*)::int from public.copie where id = tests.id(1)), 1, '... che restano dove sono');

select throws_ok(
  $$ select tests.applica(tests.scrivi(18, 'copie', tests.id(50), jsonb_build_object('edizione_id', tests.id(77), 'status', 'posseduta'), 500)) $$,
  '23503', null, 'un riferimento a una riga mai esistita resta un errore');

-- L'eliminazione prevale ----------------------------------------------------------

select tests.applica(
  tests.scrivi(20, 'valore_stimato', tests.id(1), jsonb_build_object('copia_id', tests.id(1), 'status', 'inCorso'), 100),
  tests.scrivi(21, 'creator', tests.id(1), '{"name": "Alan Moore"}', 100),
  tests.scrivi(22, 'comic_creator', tests.id(1), jsonb_build_object('edizione_id', tests.id(1), 'creator_id', tests.id(1), 'ruolo', 'sceneggiatore'), 100),
  tests.scrivi(23, 'edizione_genere', tests.id(1), jsonb_build_object('edizione_id', tests.id(1), 'genere', 'supereroi'), 100));

select is(tests.eliminate(tests.applica(tests.elimina(24, 'edizioni', tests.id(1)))), '{}'::text[],
  'eliminare un''Edizione non scarta nulla');
select is(
  (select count(*)::int from (
    select 1 from public.edizioni where id = tests.id(1) union all
    select 1 from public.copie where id = tests.id(1) union all
    select 1 from public.valore_stimato where id = tests.id(1) union all
    select 1 from public.comic_creator where id = tests.id(1) union all
    select 1 from public.edizione_genere where id = tests.id(1)) t),
  0, '... e la elimina a cascata con Copie, Valore stimato e collegamenti');
select is((select count(*)::int from public.creator where id = tests.id(1)), 1,
  '... ma non l''Autore, che non dipende dall''Edizione');
select results_eq(
  $$ select tabella from public.eliminazioni where riga = tests.id(1) order by tabella $$,
  $$ values ('comic_creator'), ('copie'), ('edizione_genere'), ('edizioni'), ('valore_stimato') $$,
  'ogni riga eliminata, anche a cascata, va nel registro delle eliminazioni');

select is(
  tests.eliminate(tests.applica(tests.scrivi(25, 'edizioni', tests.id(1), '{"issue_number_label": "2"}', 900))),
  array['edizioni/' || tests.id(1)],
  'una modifica a una riga eliminata, anche più recente, è ignorata e restituita come eliminata');
select is((select count(*)::int from public.edizioni where id = tests.id(1)), 0,
  '... e la riga non risorge');

select is(
  tests.eliminate(tests.applica(
    tests.scrivi(26, 'copie', tests.id(2), jsonb_build_object('edizione_id', tests.id(1), 'status', 'posseduta'), 900),
    tests.scrivi(27, 'valore_stimato', tests.id(2), jsonb_build_object('copia_id', tests.id(2), 'status', 'inCorso'), 900))),
  array['copie/' || tests.id(2), 'valore_stimato/' || tests.id(2)],
  'una Copia aggiunta offline sotto un''Edizione eliminata altrove è scartata, con i suoi figli');
select is((select count(*)::int from public.eliminazioni where riga = tests.id(2)), 2,
  '... e le righe scartate vanno nel registro');

select tests.applica(
  tests.scrivi(28, 'serie', tests.id(1), '{"name": "Batman"}', 100),
  tests.scrivi(29, 'edizioni', tests.id(2), jsonb_build_object('opera_id', tests.id(1), 'serie_id', tests.id(1)), 100),
  tests.elimina(30, 'serie', tests.id(1)));
select is((select serie_id from public.edizioni where id = tests.id(2)), null,
  'eliminare una Serie toglie la Serie dalle sue Edizioni, senza eliminarle');
select is(
  tests.eliminate(tests.applica(
    tests.scrivi(31, 'edizioni', tests.id(3), jsonb_build_object('opera_id', tests.id(1), 'serie_id', tests.id(1)), 900))),
  '{}'::text[],
  'un''Edizione nuova che punta a una Serie eliminata non è scartata...');
select is((select serie_id from public.edizioni where id = tests.id(3)), null, '... perde solo la Serie');

select tests.applica(tests.elimina(32, 'tag', tests.id(5)));
select is((select count(*)::int from public.eliminazioni where tabella = 'tag' and riga = tests.id(5)), 1,
  'eliminare una riga mai arrivata al server la registra comunque...');
select is(
  tests.eliminate(tests.applica(tests.scrivi(33, 'tag', tests.id(5), '{"name": "tardivo"}', 900))),
  array['tag/' || tests.id(5)], '... così le operazioni successive su quell''id sono ignorate');

select tests.authenticate_as(:'estraneo');
select is((select count(*)::int from public.eliminazioni), 0,
  'un estraneo non vede le eliminazioni di un''altra Collezione');

-- Pull: cambiamenti_da ------------------------------------------------------------

select tests.authenticate_as(:'utente');
select is(jsonb_array_length(public.cambiamenti_da(null)->'cambiamenti'), 0,
  'le righe di una transazione ancora aperta non escono: stanno oltre l''orizzonte sicuro');

-- Da qui l'orizzonte lo decide il test, come se le transazioni facessero commit.
reset role;
select pg_current_xact_id()::text::bigint as x \gset
create or replace function private.orizzonte_sincronizzazione()
returns xid8 language sql stable
as $$ select current_setting('tests.orizzonte')::xid8 $$;
select set_config('tests.orizzonte', (:x + 1)::text, true);
select tests.authenticate_as(:'utente');

select public.cambiamenti_da(null) as primo \gset
select is(
  jsonb_array_length(:'primo'::jsonb->'cambiamenti'),
  (select (select count(*) from public.opere) + (select count(*) from public.serie)
        + (select count(*) from public.edizioni) + (select count(*) from public.copie)
        + (select count(*) from public.creator))::int,
  'il primo download (cursore nullo) restituisce tutte le righe visibili...');
select is(
  (select count(*)::int from jsonb_array_elements(:'primo'::jsonb->'cambiamenti') c where c->'riga' = 'null'),
  0, '... senza le eliminazioni, che a una Replica nuova non servono');
select is((:'primo'::jsonb->>'cursore'), (:x + 1)::text,
  '... e dà come cursore l''orizzonte, a lotto finito');
select is((:'primo'::jsonb->'altre')::boolean, false, '... senza altre pagine');
select is(
  (select c->'riga'->>'title' from jsonb_array_elements(:'primo'::jsonb->'cambiamenti') c
   where c->>'tabella' = 'opere' and c->>'id' = tests.id(1)::text),
  'Watchmen', 'ogni riga arriva per intero');

-- Una transazione con un id più alto, che fa commit dopo.
reset role;
set local session_replication_role = replica;
update public.opere set title = 'Watchmen (Absolute)', xid_modifica = (:x + 5)::text::xid8 where id = tests.id(1);
update public.eliminazioni set xid_modifica = (:x + 6)::text::xid8 where tabella = 'tag' and riga = tests.id(5);
set local session_replication_role = origin;
select set_config('tests.orizzonte', (:x + 5)::text, true);
select tests.authenticate_as(:'utente');

select public.cambiamenti_da((:x + 1)::text) as attesa \gset
select is(jsonb_array_length(:'attesa'::jsonb->'cambiamenti'), 0,
  'una transazione non ancora sotto l''orizzonte non esce...');

reset role;
select set_config('tests.orizzonte', (:x + 10)::text, true);
select tests.authenticate_as(:'utente');
select results_eq(
  format($$ select c->>'tabella', c->>'id', c->'riga'->>'title'
            from jsonb_array_elements(public.cambiamenti_da(%L)->'cambiamenti') c $$, :'attesa'::jsonb->>'cursore'),
  format($$ values ('opere', %L, 'Watchmen (Absolute)'), ('tag', %L, null) $$, tests.id(1), tests.id(5)),
  '... ma esce dopo, dal cursore restituito, con le eliminazioni');

-- A pagine: nessuna riga persa né ripetuta.
reset role;
create function tests.scarica_a_pagine(limite int)
returns table (pagine int, righe text[])
language plpgsql
as $$
declare
  v_cursore text;
  v_pagina jsonb;
begin
  pagine := 0;
  righe := '{}';
  loop
    v_pagina := public.cambiamenti_da(v_cursore, limite);
    pagine := pagine + 1;
    righe := righe || array(select (c->>'tabella') || '/' || (c->>'id') from jsonb_array_elements(v_pagina->'cambiamenti') c);
    v_cursore := v_pagina->>'cursore';
    exit when not (v_pagina->'altre')::boolean;
  end loop;
  return next;
end;
$$;
grant execute on function tests.scarica_a_pagine(int) to authenticated;
select tests.authenticate_as(:'utente');

select results_eq(
  $$ select pagine, (select array_agg(r order by r) from unnest(righe) r) from tests.scarica_a_pagine(2) $$,
  $$ select (jsonb_array_length(public.cambiamenti_da(null)->'cambiamenti') + 1) / 2,
            (select array_agg((c->>'tabella') || '/' || (c->>'id') order by 1)
             from jsonb_array_elements(public.cambiamenti_da(null)->'cambiamenti') c) $$,
  'a pagine di 2 righe arrivano le stesse righe del lotto unico, una volta sola');

-- Un'eliminazione arrivata mentre il primo download è a metà.
select public.cambiamenti_da(null, 2) as pagina \gset
select ok((:'pagina'::jsonb->>'cursore') like ('primo:' || (:x + 10) || ':%'),
  'le pagine del primo download ricordano l''orizzonte da cui è partito');
select tests.applica(tests.elimina(40, 'creator', tests.id(1)));
reset role;
set local session_replication_role = replica;
update public.eliminazioni set xid_modifica = (:x + 12)::text::xid8 where tabella = 'creator' and riga = tests.id(1);
set local session_replication_role = origin;
select set_config('tests.orizzonte', (:x + 20)::text, true);
select tests.authenticate_as(:'utente');

select public.cambiamenti_da(:'pagina'::jsonb->>'cursore', 1000) as resto \gset
select is(:'resto'::jsonb->>'cursore', (:x + 10)::text,
  'a download finito il cursore è l''orizzonte di partenza...');
select is(
  (select count(*)::int from jsonb_array_elements(:'resto'::jsonb->'cambiamenti') c where c->'riga' = 'null'),
  0, '... il download non porta eliminazioni...');
select ok(
  public.cambiamenti_da(:'resto'::jsonb->>'cursore')->'cambiamenti'
    @> jsonb_build_array(jsonb_build_object('tabella', 'creator', 'id', tests.id(1), 'riga', null)),
  '... e il pull successivo porta quella avvenuta durante il download');

select tests.authenticate_as(:'estraneo');
select is(jsonb_array_length(public.cambiamenti_da(null)->'cambiamenti'), 0,
  'un estraneo non riceve le righe di un''altra Collezione');

select * from finish();
rollback;
