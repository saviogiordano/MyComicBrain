-- Indice della Collezione per l'adapter Supabase (ADR-0007, #193): le
-- Edizioni possedute (almeno una Copia `posseduta`/`prestata`) di una
-- Collezione, ciascuna con Opera, Serie, Autori, Personaggi, Tag, Generi e
-- gli assi delle Copie possedute. Una funzione invece di una select
-- PostgREST annidata: un solo valore jsonb, quindi nessun tetto `max_rows`
-- anche su Collezioni con migliaia di Edizioni. `SECURITY INVOKER`: le RLS
-- di ADR-0004 filtrano ogni tabella letta.
create function public.indice_collezione(target_collection_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(riga order by id), '[]'::jsonb)
  from (
    select e.id, jsonb_build_object(
      'id', e.id,
      'titolo', o.title,
      'serie_id', s.id,
      'serie_name', s.name,
      'publisher', e.publisher,
      'issue_number', e.issue_number,
      'issue_number_label', e.issue_number_label,
      'year', e.year,
      'format', e.format,
      'language', e.language,
      'ean', e.ean,
      'autori', coalesce((
        select jsonb_agg(cr.name order by cc.id)
        from public.comic_creator cc
        join public.creator cr on cr.id = cc.creator_id
        where cc.edizione_id = e.id), '[]'::jsonb),
      'personaggi', coalesce((
        select jsonb_agg(ch.name order by cch.id)
        from public.comic_character cch
        join public.character ch on ch.id = cch.character_id
        where cch.edizione_id = e.id), '[]'::jsonb),
      'tag', coalesce((
        select jsonb_agg(t.name order by et.id)
        from public.edizione_tag et
        join public.tag t on t.id = et.tag_id
        where et.edizione_id = e.id), '[]'::jsonb),
      'generi', coalesce((
        select jsonb_agg(g.genere order by g.id)
        from public.edizione_genere g
        where g.edizione_id = e.id), '[]'::jsonb),
      'copie', (
        select jsonb_agg(jsonb_build_object(
          'reading_status', c.reading_status,
          'condition', c.condition,
          'location', c.location,
          'created_at', c.created_at,
          'for_sale', c.for_sale) order by c.id)
        from public.copie c
        where c.edizione_id = e.id and c.status in ('posseduta', 'prestata'))
    ) as riga
    from public.edizioni e
    join public.opere o on o.id = e.opera_id
    left join public.serie s on s.id = e.serie_id
    where e.collection_id = target_collection_id
      and exists (
        select 1 from public.copie c
        where c.edizione_id = e.id and c.status in ('posseduta', 'prestata'))
  ) edizioni_possedute
$$;

revoke execute on function public.indice_collezione(uuid) from public, anon;
grant execute on function public.indice_collezione(uuid) to authenticated;
