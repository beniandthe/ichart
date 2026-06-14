create policy "forum_chart_pdfs_delete_unattached_owner_upload"
    on storage.objects
    for delete
    to authenticated
    using (
        bucket_id = 'forum_chart_pdfs'
        and public.current_user_has_active_pro()
        and (storage.foldername(name))[1] = auth.uid()::text
        and not exists (
            select 1
            from public.forum_chart_posts
            where forum_chart_posts.pdf_storage_path = storage.objects.name
        )
    );
