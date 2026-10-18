-- Pulizia una tantum delle Serie senza Edizioni (fix/serie-orfane).
-- Prima della correzione, cambiare nome alla Serie di un fumetto, togliere
-- la Serie o eliminare l'ultimo fumetto lasciavano la Serie vuota.
-- Il trigger `registra_eliminazione` scrive ogni Serie cancellata in
-- `eliminazioni`, così i device la tolgono dalla Replica al prossimo pull.
--
-- Prima di lanciarlo: sincronizzare tutti i device (nessuna Modifica in
-- sospeso), perché un fumetto ancora da inviare potrebbe puntare a una di
-- queste Serie.

begin;

-- Anteprima: le Serie che verranno cancellate.
select s.id, s.name, s.collection_id
from public.serie s
where not exists (select 1 from public.edizioni e where e.serie_id = s.id)
order by s.collection_id, s.name;

delete from public.serie s
where not exists (select 1 from public.edizioni e where e.serie_id = s.id);

commit;
