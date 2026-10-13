-- Rimozione di Copie ed Edizioni dall'adapter Supabase (ADR-0007, #177):
-- scritture multi-tabella che devono essere atomiche, quindi RPC
-- `SECURITY INVOKER` — le RLS di ADR-0004 restano l'unica barriera.
--
-- Le FK di ADR-0004 non hanno `on delete cascade` fra tabelle di dominio:
-- prima della riga si eliminano i collegamenti che la referenziano
-- (Valore stimato delle Copie; Autori, Personaggi, Tag e Generi
-- dell'Edizione). `identificazione`/`candidati` puntano all'Edizione con
-- `on delete set null` e restano.

-- Elimina l'Edizione con tutte le sue Copie. Un'Edizione inesistente o non
-- modificabile dall'utente non è un errore: non c'è nulla da eliminare.
create function public.elimina_edizione(target_edizione_id bigint)
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
create function public.rimuovi_copia(target_copia_id bigint)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_edizione_id bigint;
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

revoke execute on function public.elimina_edizione(bigint) from public, anon;
grant execute on function public.elimina_edizione(bigint) to authenticated;
revoke execute on function public.rimuovi_copia(bigint) from public, anon;
grant execute on function public.rimuovi_copia(bigint) to authenticated;
