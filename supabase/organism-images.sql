-- The picture of each organism a test counted, sent by the app's Upload button.
--
-- One JPEG per organism, at "<soil_results.id>/organism-001.jpg". Which picture is of what is in
-- soil_results.report, under organismImages (taxon and path), so no table is needed.
--
-- Run this once in the Supabase SQL editor. Until it has been run, Upload files the result and
-- then says its pictures were not sent.
--
-- Deleting a result does not delete its pictures: nobody can open them any more (the rules below
-- look for the result), but the files stay until they are removed in Storage by hand.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('organism-images', 'organism-images', false, 2097152, array['image/jpeg'])
on conflict (id) do nothing;

-- A picture can be reached by whoever can read its result. The lookup runs under soil_results'
-- own row-level security, so these follow whatever that table allows. The result is filed before
-- its pictures, and sending a test again replaces them, which storage checks as a read and an
-- update as well as an insert.
drop policy if exists "organism images are readable" on storage.objects;
create policy "organism images are readable"
    on storage.objects for select
    to authenticated
    using (
        bucket_id = 'organism-images'
        and exists (
            select 1 from public.soil_results r
            where r.id::text = (storage.foldername(objects.name))[1]
        )
    );

drop policy if exists "organism images are writable" on storage.objects;
create policy "organism images are writable"
    on storage.objects for insert
    to authenticated
    with check (
        bucket_id = 'organism-images'
        and exists (
            select 1 from public.soil_results r
            where r.id::text = (storage.foldername(objects.name))[1]
        )
    );

drop policy if exists "organism images are updatable" on storage.objects;
create policy "organism images are updatable"
    on storage.objects for update
    to authenticated
    using (
        bucket_id = 'organism-images'
        and exists (
            select 1 from public.soil_results r
            where r.id::text = (storage.foldername(objects.name))[1]
        )
    )
    with check (
        bucket_id = 'organism-images'
        and exists (
            select 1 from public.soil_results r
            where r.id::text = (storage.foldername(objects.name))[1]
        )
    );
