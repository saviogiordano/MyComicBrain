-- Chiavi uuid sulle tabelle replicate (ADR-0008, #203): le righe create
-- offline nascono sul device, quindi gli id non possono più venire da una
-- sequence. Le tabelle della Replica locale passano da `bigint identity` a
-- `uuid`, convertite sul posto conservando i dati.
--
-- uuid v7 (ordinati nel tempo), perché `order by id` decide ancora l'ordine
-- di creazione (Autori, Tag, Scansioni, …). Le righe esistenti ricevono un
-- uuid v7 deterministico ricavato da tabella e vecchio id, con istante
-- 2020-09-13 + id millisecondi: tutte prima delle righe nuove e nello
-- stesso ordine di prima, e ogni chiave esterna si converte con la stessa
-- funzione senza join.
--
-- Conversazione e Messaggi non sono replicati e restano a bigint;
-- `messaggio.edizione_ids` e `audit_log.row_id` riferiscono righe
-- replicate e passano a uuid.

-- uuid v7 da un istante in millisecondi e un seme: `rand_a` e `rand_b`
-- vengono dall'md5 del seme, quindi stesso input, stesso uuid.
create function private.uuid_v7_da(ms bigint, seme text)
returns uuid
language sql
immutable
strict
set search_path = ''
as $$
  select (
    lpad(to_hex(ms), 12, '0') || '7' || substr(h, 1, 3)
    || substr('89ab', get_byte(decode(substr(h, 4, 2), 'hex'), 0) % 4 + 1, 1)
    || substr(h, 6, 15)
  )::uuid
  from (select md5(seme) as h) as hash
$$;

-- uuid v7 nuovo, default delle chiavi: millisecondi dell'orologio e, in
-- `rand_a`, la frazione di millisecondo (come `uuidv7()` di Postgres 18),
-- così anche le righe dello stesso millisecondo seguono l'ordine di
-- creazione.
create function private.uuid_v7()
returns uuid
language sql
volatile
set search_path = ''
as $$
  select (
    lpad(to_hex(us / 1000), 12, '0') || '7'
    || lpad(to_hex((us % 1000) * 4096 / 1000), 3, '0')
    || substr('89ab', get_byte(decode(substr(h, 1, 2), 'hex'), 0) % 4 + 1, 1)
    || substr(h, 3, 15)
  )::uuid
  from (
    select floor(extract(epoch from clock_timestamp()) * 1000000)::bigint as us,
           md5(gen_random_uuid()::text) as h
  ) as adesso
$$;

grant execute on function private.uuid_v7() to authenticated, anon;

-- Il vecchio id bigint di una riga, convertito: usato solo qui.
create function private.uuid_da_id(tabella text, id bigint)
returns uuid
language sql
immutable
strict
set search_path = ''
as $$
  select private.uuid_v7_da(1600000000000 + id, tabella || ':' || id)
$$;

create function private.uuid_da_ids(tabella text, ids bigint[])
returns uuid[]
language sql
immutable
strict
set search_path = ''
as $$
  select coalesce(array_agg(private.uuid_da_id(tabella, x) order by n), '{}')
  from unnest(ids) with ordinality as u (x, n)
$$;

-- Conversione ---------------------------------------------------------------

do $$
declare
  tabelle text[] := array[
    'opere', 'serie', 'edizioni', 'copie', 'creator', 'comic_creator', 'tag',
    'edizione_tag', 'character', 'comic_character', 'edizione_genere',
    'valore_stimato', 'scansioni', 'analisi_copertina', 'identificazione',
    'candidati'
  ];
  -- tabella -> { colonna FK: tabella riferita }
  chiavi_esterne jsonb := '{
    "edizioni": {"opera_id": "opere", "serie_id": "serie"},
    "copie": {"edizione_id": "edizioni", "scansione_id": "scansioni"},
    "comic_creator": {"edizione_id": "edizioni", "creator_id": "creator"},
    "edizione_tag": {"edizione_id": "edizioni", "tag_id": "tag"},
    "comic_character": {"edizione_id": "edizioni", "character_id": "character"},
    "edizione_genere": {"edizione_id": "edizioni"},
    "valore_stimato": {"copia_id": "copie"},
    "analisi_copertina": {"scansione_id": "scansioni"},
    "identificazione": {"scansione_id": "scansioni"},
    "candidati": {"identificazione_id": "identificazione", "edizione_id": "edizioni"}
  }';
  t text;
  fk record;
  colonna record;
  modifiche text;
begin
  -- Le FK verso le tabelle convertite si tolgono e si rimettono identiche
  -- (stessa definizione) a conversione finita.
  create temp table fk_salvate on commit drop as
  select conrelid::regclass as tabella, conname, pg_get_constraintdef(oid) as def
  from pg_constraint
  where contype = 'f'
    and confrelid in (select ('public.' || x)::regclass from unnest(tabelle) as x);

  for fk in select * from fk_salvate loop
    execute format('alter table %s drop constraint %I', fk.tabella, fk.conname);
  end loop;

  foreach t in array tabelle loop
    execute format('alter table public.%I alter column id drop identity', t);
    modifiche := format(
      'alter column id type uuid using private.uuid_da_id(%L, id), '
      'alter column id set default private.uuid_v7()', t);
    for colonna in
      select key, value from jsonb_each_text(coalesce(chiavi_esterne -> t, '{}'))
    loop
      modifiche := modifiche || format(
        ', alter column %I type uuid using private.uuid_da_id(%L, %I)',
        colonna.key, colonna.value, colonna.key);
    end loop;
    execute format('alter table public.%I %s', t, modifiche);
  end loop;

  for fk in select * from fk_salvate loop
    execute format('alter table %s add constraint %I %s', fk.tabella, fk.conname, fk.def);
  end loop;
end;
$$;

alter table public.messaggio
  alter column edizione_ids type uuid[]
  using private.uuid_da_ids('edizioni', edizione_ids);

alter table public.audit_log
  alter column row_id type uuid using private.uuid_da_id(table_name, row_id);

drop function private.uuid_da_ids(text, bigint[]);
drop function private.uuid_da_id(text, bigint);

-- RPC con id uuid -----------------------------------------------------------

drop function public.rimuovi_copia(bigint);
drop function public.elimina_edizione(bigint);
drop function public.conferma_candidato(
  uuid, bigint, bigint, bigint, text, jsonb, text, double precision, text
);

create function public.elimina_edizione(target_edizione_id uuid)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  delete from public.valore_stimato v
  using public.copie c
  where v.copia_id = c.id and c.edizione_id = target_edizione_id;
  delete from public.copie where edizione_id = target_edizione_id;
  delete from public.comic_creator where edizione_id = target_edizione_id;
  delete from public.comic_character where edizione_id = target_edizione_id;
  delete from public.edizione_tag where edizione_id = target_edizione_id;
  delete from public.edizione_genere where edizione_id = target_edizione_id;
  delete from public.edizioni where id = target_edizione_id;
end;
$$;

-- Rimuove la Copia; se era l'ultima elimina anche l'Edizione (deciso su
-- #68: nessuna Edizione orfana) e restituisce true. Una Copia inesistente o
-- non modificabile dall'utente è un errore (P0002), come su drift.
create function public.rimuovi_copia(target_copia_id uuid)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_edizione_id uuid;
begin
  delete from public.valore_stimato where copia_id = target_copia_id;
  delete from public.copie where id = target_copia_id
  returning edizione_id into v_edizione_id;
  if v_edizione_id is null then
    raise exception 'Copia % inesistente', target_copia_id
      using errcode = 'P0002';
  end if;
  if exists (select 1 from public.copie where edizione_id = v_edizione_id) then
    return false;
  end if;
  perform public.elimina_edizione(v_edizione_id);
  return true;
end;
$$;

revoke execute on function public.elimina_edizione(uuid) from public, anon;
grant execute on function public.elimina_edizione(uuid) to authenticated;
revoke execute on function public.rimuovi_copia(uuid) from public, anon;
grant execute on function public.rimuovi_copia(uuid) to authenticated;

create function public.conferma_candidato(
  target_collection_id uuid,
  target_candidato_id uuid,
  target_scansione_id uuid,
  target_edizione_id uuid,
  descrizione_da_completare text,
  nuova_edizione jsonb,
  condizione text,
  prezzo double precision,
  valuta text
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_edizione_id uuid;
  v_opera_id uuid;
  v_serie_id uuid;
  v_serie text := nullif(btrim(nuova_edizione ->> 'series_name'), '');
  v_copia_id uuid;
begin
  update public.candidati set scelto = true where id = target_candidato_id;

  if nuova_edizione is null then
    if target_edizione_id is null then
      raise exception 'Candidato interno senza Edizione' using errcode = '22004';
    end if;
    v_edizione_id := target_edizione_id;
    if descrizione_da_completare is not null then
      update public.edizioni
      set description = descrizione_da_completare
      where id = v_edizione_id
        and nullif(btrim(coalesce(description, '')), '') is null;
    end if;
  else
    insert into public.opere (collection_id, title)
    values (target_collection_id, nuova_edizione ->> 'title')
    returning id into v_opera_id;

    if v_serie is not null then
      select id into v_serie_id
      from public.serie
      where collection_id = target_collection_id
        and lower(name) = lower(v_serie)
      order by id
      limit 1;
      if v_serie_id is null then
        insert into public.serie (collection_id, name)
        values (target_collection_id, v_serie)
        returning id into v_serie_id;
      end if;
    end if;

    insert into public.edizioni (
      collection_id, opera_id, serie_id, publisher, issue_number,
      issue_number_label, cover_image, release_date, year, cover_price,
      page_count, language, color, ean, description, printing_type,
      classificazione
    )
    values (
      target_collection_id, v_opera_id, v_serie_id,
      nuova_edizione ->> 'publisher',
      (nuova_edizione ->> 'issue_number')::integer,
      nuova_edizione ->> 'issue_number_label',
      nuova_edizione ->> 'cover_image',
      nuova_edizione ->> 'release_date',
      (nuova_edizione ->> 'year')::integer,
      nuova_edizione ->> 'cover_price',
      (nuova_edizione ->> 'page_count')::integer,
      nuova_edizione ->> 'language',
      nuova_edizione ->> 'color',
      nuova_edizione ->> 'ean',
      nuova_edizione ->> 'description',
      nuova_edizione ->> 'printing_type',
      nuova_edizione ->> 'classificazione'
    )
    returning id into v_edizione_id;
  end if;

  insert into public.copie (
    collection_id, edizione_id, status, condition, purchase_price,
    purchase_price_currency, scansione_id
  )
  values (
    target_collection_id, v_edizione_id, 'posseduta', condizione, prezzo,
    valuta, target_scansione_id
  )
  returning id into v_copia_id;
  return v_copia_id;
end;
$$;

revoke execute on function public.conferma_candidato(
  uuid, uuid, uuid, uuid, text, jsonb, text, double precision, text
) from public, anon;
grant execute on function public.conferma_candidato(
  uuid, uuid, uuid, uuid, text, jsonb, text, double precision, text
) to authenticated;

-- Importazione della Modalità locale (ADR-0005): gli id del payload che
-- sono già uuid (drift con chiavi uuid, ADR-0008) si conservano; gli altri
-- (id interi di drift) ricevono un uuid v7 nuovo, nell'ordine del payload e
-- deterministico per `import_id`.
drop function private.mappa_id(jsonb, text);

create function private.mappa_uuid(righe jsonb, seme text)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(
    riga->>'id',
    case
      when riga->>'id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        then (riga->>'id')::uuid
      else private.uuid_v7_da(
        floor(extract(epoch from now()) * 1000)::bigint + n, seme || ':' || n)
    end
  ), '{}'::jsonb)
  from jsonb_array_elements(coalesce(righe, '[]'::jsonb)) with ordinality as e (riga, n)
$$;

revoke execute on function private.mappa_uuid(jsonb, text) from public;
grant execute on function private.mappa_uuid(jsonb, text) to authenticated;
grant execute on function private.uuid_v7_da(bigint, text) to authenticated;

-- Una riga del payload senza `id` e chiavi esterne: quelle arrivano dalle
-- mappe, e un id intero di drift non entrerebbe in una colonna uuid.
create function private.senza_id(riga jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(k, v), '{}'::jsonb)
  from jsonb_each(riga) as e (k, v)
  where k <> 'id' and k not like '%\_id'
$$;

grant execute on function private.senza_id(jsonb) to authenticated;

create or replace function public.importa_modalita_locale(payload jsonb, import_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_collection_id uuid;
  v_esito jsonb;
  m_opere jsonb;
  m_serie jsonb;
  m_edizioni jsonb;
  m_copie jsonb;
  m_creator jsonb;
  m_tag jsonb;
  m_character jsonb;
  m_scansioni jsonb;
  m_identificazione jsonb;
  m_valore_stimato jsonb;
  m_candidati jsonb;
  m_analisi_copertina jsonb;
  m_edizione_genere jsonb;
  m_comic_character jsonb;
  m_edizione_tag jsonb;
  m_comic_creator jsonb;
begin
  if v_user_id is null then
    raise exception 'importa_modalita_locale richiede un utente autenticato'
      using errcode = '42501';
  end if;

  select collection_id into v_collection_id
  from public.collection_members
  where user_id = v_user_id and role = 'owner';
  if v_collection_id is null then
    raise exception 'nessuna Collezione di proprietà per l''utente'
      using errcode = 'P0002';
  end if;

  -- Prima della scrittura dei dati: un secondo tentativo concorrente con lo
  -- stesso id resta in attesa qui finché il primo non finisce.
  insert into public.importazioni (id, user_id, collection_id)
  values (import_id, v_user_id, v_collection_id)
  on conflict (id) do nothing;
  if not found then
    select esito into v_esito from public.importazioni where id = import_id;
    if v_esito is null then
      raise exception 'importazione % non appartiene all''utente', import_id
        using errcode = '42501';
    end if;
    return v_esito;
  end if;

  -- Catalogo ----------------------------------------------------------------

  m_opere := private.mappa_uuid(payload->'opere', import_id::text || ':opere');
  insert into public.opere (id, collection_id, created_by, title, created_at)
  select (m_opere->>(riga->>'id'))::uuid, v_collection_id, v_user_id,
         r.title, coalesce(r.created_at, now())
  from jsonb_array_elements(coalesce(payload->'opere', '[]')) as riga,
       jsonb_populate_record(null::public.opere, private.senza_id(riga)) as r;

  m_serie := private.mappa_uuid(payload->'serie', import_id::text || ':serie');
  insert into public.serie (id, collection_id, created_by, name, total_issues,
                            issn, cover_image)
  select (m_serie->>(riga->>'id'))::uuid, v_collection_id, v_user_id,
         r.name, r.total_issues, r.issn, r.cover_image
  from jsonb_array_elements(coalesce(payload->'serie', '[]')) as riga,
       jsonb_populate_record(null::public.serie, private.senza_id(riga)) as r;

  m_edizioni := private.mappa_uuid(payload->'edizioni', import_id::text || ':edizioni');
  insert into public.edizioni (id, collection_id, created_by, opera_id, serie_id,
                               publisher, issue_number, issue_number_label,
                               cover_image, release_date, cover_price, page_count,
                               language, color, ean, created_at, volume,
                               description, printing_type, classificazione,
                               year, format)
  select (m_edizioni->>(riga->>'id'))::uuid, v_collection_id, v_user_id,
         (m_opere->>(riga->>'opera_id'))::uuid,
         (m_serie->>(riga->>'serie_id'))::uuid,
         r.publisher, r.issue_number, r.issue_number_label, r.cover_image,
         r.release_date, r.cover_price, r.page_count, r.language, r.color,
         r.ean, coalesce(r.created_at, now()), r.volume, r.description, r.printing_type,
         r.classificazione, r.year, r.format
  from jsonb_array_elements(coalesce(payload->'edizioni', '[]')) as riga,
       jsonb_populate_record(null::public.edizioni, private.senza_id(riga)) as r;

  m_creator := private.mappa_uuid(payload->'creator', import_id::text || ':creator');
  insert into public.creator (id, collection_id, created_by, name)
  select (m_creator->>(riga->>'id'))::uuid, v_collection_id, v_user_id, r.name
  from jsonb_array_elements(coalesce(payload->'creator', '[]')) as riga,
       jsonb_populate_record(null::public.creator, private.senza_id(riga)) as r;

  m_comic_creator := private.mappa_uuid(payload->'comic_creator', import_id::text || ':comic_creator');
  insert into public.comic_creator (id, collection_id, created_by, edizione_id,
                                    creator_id, ruolo)
  select (m_comic_creator->>(riga->>'id'))::uuid, v_collection_id, v_user_id,
         (m_edizioni->>(riga->>'edizione_id'))::uuid,
         (m_creator->>(riga->>'creator_id'))::uuid, r.ruolo
  from jsonb_array_elements(coalesce(payload->'comic_creator', '[]')) as riga,
       jsonb_populate_record(null::public.comic_creator, private.senza_id(riga)) as r;

  m_tag := private.mappa_uuid(payload->'tag', import_id::text || ':tag');
  insert into public.tag (id, collection_id, created_by, name)
  select (m_tag->>(riga->>'id'))::uuid, v_collection_id, v_user_id, r.name
  from jsonb_array_elements(coalesce(payload->'tag', '[]')) as riga,
       jsonb_populate_record(null::public.tag, private.senza_id(riga)) as r;

  m_edizione_tag := private.mappa_uuid(payload->'edizione_tag', import_id::text || ':edizione_tag');
  insert into public.edizione_tag (id, collection_id, created_by, edizione_id, tag_id)
  select (m_edizione_tag->>(riga->>'id'))::uuid, v_collection_id, v_user_id,
         (m_edizioni->>(riga->>'edizione_id'))::uuid,
         (m_tag->>(riga->>'tag_id'))::uuid
  from jsonb_array_elements(coalesce(payload->'edizione_tag', '[]')) as riga;

  m_character := private.mappa_uuid(payload->'character', import_id::text || ':character');
  insert into public.character (id, collection_id, created_by, name)
  select (m_character->>(riga->>'id'))::uuid, v_collection_id, v_user_id, r.name
  from jsonb_array_elements(coalesce(payload->'character', '[]')) as riga,
       jsonb_populate_record(null::public.character, private.senza_id(riga)) as r;

  m_comic_character := private.mappa_uuid(payload->'comic_character', import_id::text || ':comic_character');
  insert into public.comic_character (id, collection_id, created_by, edizione_id,
                                      character_id)
  select (m_comic_character->>(riga->>'id'))::uuid, v_collection_id, v_user_id,
         (m_edizioni->>(riga->>'edizione_id'))::uuid,
         (m_character->>(riga->>'character_id'))::uuid
  from jsonb_array_elements(coalesce(payload->'comic_character', '[]')) as riga;

  m_edizione_genere := private.mappa_uuid(payload->'edizione_genere', import_id::text || ':edizione_genere');
  insert into public.edizione_genere (id, collection_id, created_by, edizione_id, genere)
  select (m_edizione_genere->>(riga->>'id'))::uuid, v_collection_id, v_user_id,
         (m_edizioni->>(riga->>'edizione_id'))::uuid, r.genere
  from jsonb_array_elements(coalesce(payload->'edizione_genere', '[]')) as riga,
       jsonb_populate_record(null::public.edizione_genere, private.senza_id(riga)) as r;

  -- Scansioni non ancora risolte in una Copia (private all'utente) ----------

  m_scansioni := private.mappa_uuid(payload->'scansioni', import_id::text || ':scansioni');
  insert into public.scansioni (id, user_id, collection_id, image, created_at)
  select (m_scansioni->>(riga->>'id'))::uuid, v_user_id, v_collection_id,
         r.image, coalesce(r.created_at, now())
  from jsonb_array_elements(coalesce(payload->'scansioni', '[]')) as riga,
       jsonb_populate_record(null::public.scansioni, private.senza_id(riga)) as r;

  m_analisi_copertina := private.mappa_uuid(payload->'analisi_copertina', import_id::text || ':analisi_copertina');
  insert into public.analisi_copertina (id, user_id, scansione_id, title,
                                        issue_number_label, publisher,
                                        series_name, isbn, barcode, price,
                                        release_date, year, page_count,
                                        language, color, issn, characters,
                                        cover_style_tags, visual_element_tags,
                                        recognized_publisher_logo,
                                        recognized_series_logo, printing_type,
                                        classificazione, description,
                                        raw_response, status, error_message,
                                        completed_at, created_at)
  select (m_analisi_copertina->>(riga->>'id'))::uuid, v_user_id, (m_scansioni->>(riga->>'scansione_id'))::uuid,
         r.title, r.issue_number_label, r.publisher, r.series_name, r.isbn,
         r.barcode, r.price, r.release_date, r.year, r.page_count, r.language,
         r.color, r.issn, coalesce(r.characters, '{}'),
         coalesce(r.cover_style_tags, '{}'), coalesce(r.visual_element_tags, '{}'),
         r.recognized_publisher_logo, r.recognized_series_logo,
         r.printing_type, r.classificazione, r.description, r.raw_response,
         coalesce(r.status, 'pending'), r.error_message, r.completed_at,
         coalesce(r.created_at, now())
  from jsonb_array_elements(coalesce(payload->'analisi_copertina', '[]')) as riga,
       jsonb_populate_record(null::public.analisi_copertina, private.senza_id(riga)) as r;

  m_identificazione := private.mappa_uuid(payload->'identificazione', import_id::text || ':identificazione');
  insert into public.identificazione (id, user_id, scansione_id, status,
                                      error_message, created_at, completed_at)
  select (m_identificazione->>(riga->>'id'))::uuid, v_user_id,
         (m_scansioni->>(riga->>'scansione_id'))::uuid,
         coalesce(r.status, 'pending'), r.error_message,
         coalesce(r.created_at, now()), r.completed_at
  from jsonb_array_elements(coalesce(payload->'identificazione', '[]')) as riga,
       jsonb_populate_record(null::public.identificazione, private.senza_id(riga)) as r;

  m_candidati := private.mappa_uuid(payload->'candidati', import_id::text || ':candidati');
  insert into public.candidati (id, user_id, identificazione_id, source, edizione_id,
                                title, series_name, issue_number_label,
                                publisher, year, cover_image_url, punteggio,
                                scelto)
  select (m_candidati->>(riga->>'id'))::uuid, v_user_id, (m_identificazione->>(riga->>'identificazione_id'))::uuid,
         r.source, (m_edizioni->>(riga->>'edizione_id'))::uuid, r.title,
         r.series_name, r.issue_number_label, r.publisher, r.year,
         r.cover_image_url, r.punteggio, coalesce(r.scelto, false)
  from jsonb_array_elements(coalesce(payload->'candidati', '[]')) as riga,
       jsonb_populate_record(null::public.candidati, private.senza_id(riga)) as r;

  -- Copie (dopo le Scansioni, che possono riferire) --------------------------

  m_copie := private.mappa_uuid(payload->'copie', import_id::text || ':copie');
  insert into public.copie (id, collection_id, created_by, edizione_id, status,
                            reading_status, condition, purchase_price,
                            purchase_price_currency, purchase_date, seller,
                            valutazione, location, notes, created_at,
                            updated_at, scansione_id, for_sale)
  select (m_copie->>(riga->>'id'))::uuid, v_collection_id, v_user_id,
         (m_edizioni->>(riga->>'edizione_id'))::uuid, r.status,
         r.reading_status, r.condition, r.purchase_price,
         r.purchase_price_currency, r.purchase_date, r.seller, r.valutazione,
         r.location, r.notes, coalesce(r.created_at, now()),
         coalesce(r.updated_at, r.created_at, now()),
         (m_scansioni->>(riga->>'scansione_id'))::uuid,
         coalesce(r.for_sale, false)
  from jsonb_array_elements(coalesce(payload->'copie', '[]')) as riga,
       jsonb_populate_record(null::public.copie, private.senza_id(riga)) as r;

  m_valore_stimato := private.mappa_uuid(payload->'valore_stimato', import_id::text || ':valore_stimato');
  insert into public.valore_stimato (id, collection_id, created_by, copia_id, status,
                                     value, error_message, completed_at,
                                     created_at)
  select (m_valore_stimato->>(riga->>'id'))::uuid, v_collection_id, v_user_id, (m_copie->>(riga->>'copia_id'))::uuid,
         r.status, r.value, r.error_message, r.completed_at,
         coalesce(r.created_at, now())
  from jsonb_array_elements(coalesce(payload->'valore_stimato', '[]')) as riga,
       jsonb_populate_record(null::public.valore_stimato, private.senza_id(riga)) as r;

  v_esito := jsonb_build_object(
    'copie_importate', jsonb_array_length(coalesce(payload->'copie', '[]')),
    'scansioni_importate', jsonb_array_length(coalesce(payload->'scansioni', '[]')),
    'copie_collezione', (select count(*) from public.copie
                         where collection_id = v_collection_id)
  );
  update public.importazioni set esito = v_esito where id = import_id;
  return v_esito;
end;
$$;

