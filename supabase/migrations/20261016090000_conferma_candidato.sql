-- Conferma di un Candidato dall'adapter Supabase (ADR-0007, #196): marca il
-- Candidato scelto, crea o completa l'Edizione e aggiunge la Copia in una
-- sola transazione, quindi RPC `SECURITY INVOKER` — le RLS di ADR-0004
-- restano l'unica barriera.
--
-- I valori da scrivere li calcola l'app (`conferma_candidato.dart`,
-- condiviso con l'adapter drift): qui c'è solo la scrittura atomica. La
-- cover dell'Edizione nuova è già su Storage (o è l'URL ComicVine di
-- ripiego) quando la funzione viene chiamata.
--
-- Candidato `interno`: `nuova_edizione` è null e la Copia va su
-- `target_edizione_id`, a cui si applica `descrizione_da_completare` solo se
-- non ha ancora una Descrizione. Candidato `esterno`: `nuova_edizione` porta
-- `title`, `series_name` e i campi dell'Edizione; la Serie con lo stesso nome
-- (senza distinzione di maiuscole) viene riusata, come `aggiungiSerie`.
-- Restituisce l'id della Copia creata.
create function public.conferma_candidato(
  target_collection_id uuid,
  target_candidato_id bigint,
  target_scansione_id bigint,
  target_edizione_id bigint,
  descrizione_da_completare text,
  nuova_edizione jsonb,
  condizione text,
  prezzo double precision,
  valuta text
)
returns bigint
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_edizione_id bigint;
  v_opera_id bigint;
  v_serie_id bigint;
  v_serie text := nullif(btrim(nuova_edizione ->> 'series_name'), '');
  v_copia_id bigint;
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
  uuid, bigint, bigint, bigint, text, jsonb, text, double precision, text
) from public, anon;
grant execute on function public.conferma_candidato(
  uuid, bigint, bigint, bigint, text, jsonb, text, double precision, text
) to authenticated;
