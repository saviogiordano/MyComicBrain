-- Bucket Storage privati per le immagini (ADR-0007). Nel DB si salva la
-- chiave Storage, mai un URL; nessun URL pubblico.
--
-- - `covers`: <collection_id>/<uuid>.jpg — lettura ai membri della
--   Collezione, scrittura a Proprietario ed Editor;
-- - `scansioni`: <user_id>/<uuid>.jpg — solo l'utente che le ha scattate.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('covers', 'covers', false, 10485760, array['image/jpeg', 'image/png', 'image/webp']),
  ('scansioni', 'scansioni', false, 10485760, array['image/jpeg', 'image/png', 'image/webp']);

create policy "covers read by collection members" on storage.objects
for select to authenticated
using (
  bucket_id = 'covers'
  and (storage.foldername(name))[1] in (
    select id::text from private.visible_collection_ids() as id
  )
);

create policy "covers insert by owner and editor" on storage.objects
for insert to authenticated
with check (
  bucket_id = 'covers'
  and (storage.foldername(name))[1] in (
    select id::text from private.editable_collection_ids() as id
  )
);

create policy "covers update by owner and editor" on storage.objects
for update to authenticated
using (
  bucket_id = 'covers'
  and (storage.foldername(name))[1] in (
    select id::text from private.editable_collection_ids() as id
  )
)
with check (
  bucket_id = 'covers'
  and (storage.foldername(name))[1] in (
    select id::text from private.editable_collection_ids() as id
  )
);

create policy "covers delete by owner and editor" on storage.objects
for delete to authenticated
using (
  bucket_id = 'covers'
  and (storage.foldername(name))[1] in (
    select id::text from private.editable_collection_ids() as id
  )
);

create policy "scansioni owned by uploader" on storage.objects
for all to authenticated
using (
  bucket_id = 'scansioni'
  and (storage.foldername(name))[1] = (select auth.uid())::text
)
with check (
  bucket_id = 'scansioni'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);
