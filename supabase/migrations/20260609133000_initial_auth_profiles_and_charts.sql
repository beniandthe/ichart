create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

create table public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    email text,
    phone text,
    mailing_address text,
    payment_summary text,
    stripe_customer_id text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table public.chart_documents (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid not null references auth.users(id) on delete cascade,
    title text not null default 'Untitled Chart',
    layout_style text not null check (layout_style in ('simpleChordSheet', 'rhythmSectionSheet', 'leadSheet')),
    latest_snapshot_id uuid,
    deleted_at timestamptz,
    remote_revision bigint not null default 0,
    client_updated_at timestamptz,
    last_snapshot_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table public.chart_snapshots (
    id uuid primary key default gen_random_uuid(),
    chart_id uuid not null references public.chart_documents(id) on delete cascade,
    owner_id uuid not null references auth.users(id) on delete cascade,
    version bigint not null check (version > 0),
    chart_json jsonb not null,
    client_updated_at timestamptz,
    created_at timestamptz not null default now(),
    unique (chart_id, version)
);

alter table public.chart_documents
    add constraint chart_documents_latest_snapshot_id_fkey
    foreign key (latest_snapshot_id)
    references public.chart_snapshots(id)
    on delete set null;

create table public.subscriptions (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid not null references auth.users(id) on delete cascade unique,
    plan text not null default 'free',
    status text not null default 'inactive',
    stripe_customer_id text,
    stripe_subscription_id text,
    current_period_end timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table public.devices (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid not null references auth.users(id) on delete cascade,
    device_name text,
    last_seen_at timestamptz not null default now(),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index chart_documents_owner_id_idx on public.chart_documents(owner_id);
create index chart_documents_owner_deleted_idx on public.chart_documents(owner_id, deleted_at);
create index chart_documents_owner_revision_idx on public.chart_documents(owner_id, remote_revision desc);
create index chart_snapshots_chart_id_version_idx on public.chart_snapshots(chart_id, version desc);
create index chart_snapshots_owner_id_idx on public.chart_snapshots(owner_id);
create index devices_owner_id_idx on public.devices(owner_id);

alter table public.profiles enable row level security;
alter table public.chart_documents enable row level security;
alter table public.chart_snapshots enable row level security;
alter table public.subscriptions enable row level security;
alter table public.devices enable row level security;

create policy "profiles_select_own"
    on public.profiles
    for select
    to authenticated
    using (auth.uid() = id);

create policy "profiles_insert_own"
    on public.profiles
    for insert
    to authenticated
    with check (auth.uid() = id);

create policy "profiles_update_own"
    on public.profiles
    for update
    to authenticated
    using (auth.uid() = id)
    with check (auth.uid() = id);

create policy "chart_documents_select_own"
    on public.chart_documents
    for select
    to authenticated
    using (auth.uid() = owner_id);

create policy "chart_documents_insert_own"
    on public.chart_documents
    for insert
    to authenticated
    with check (
        auth.uid() = owner_id
        and (
            latest_snapshot_id is null
            or exists (
                select 1
                from public.chart_snapshots
                where chart_snapshots.id = chart_documents.latest_snapshot_id
                    and chart_snapshots.chart_id = chart_documents.id
                    and chart_snapshots.owner_id = auth.uid()
            )
        )
    );

create policy "chart_documents_update_own"
    on public.chart_documents
    for update
    to authenticated
    using (auth.uid() = owner_id)
    with check (
        auth.uid() = owner_id
        and (
            latest_snapshot_id is null
            or exists (
                select 1
                from public.chart_snapshots
                where chart_snapshots.id = chart_documents.latest_snapshot_id
                    and chart_snapshots.chart_id = chart_documents.id
                    and chart_snapshots.owner_id = auth.uid()
            )
        )
    );

create policy "chart_documents_delete_own"
    on public.chart_documents
    for delete
    to authenticated
    using (auth.uid() = owner_id);

create policy "chart_snapshots_select_own"
    on public.chart_snapshots
    for select
    to authenticated
    using (auth.uid() = owner_id);

create policy "chart_snapshots_insert_own"
    on public.chart_snapshots
    for insert
    to authenticated
    with check (
        auth.uid() = owner_id
        and exists (
            select 1
            from public.chart_documents
            where chart_documents.id = chart_snapshots.chart_id
                and chart_documents.owner_id = auth.uid()
        )
    );

create policy "subscriptions_select_own"
    on public.subscriptions
    for select
    to authenticated
    using (auth.uid() = owner_id);

create policy "devices_select_own"
    on public.devices
    for select
    to authenticated
    using (auth.uid() = owner_id);

create policy "devices_insert_own"
    on public.devices
    for insert
    to authenticated
    with check (auth.uid() = owner_id);

create policy "devices_update_own"
    on public.devices
    for update
    to authenticated
    using (auth.uid() = owner_id)
    with check (auth.uid() = owner_id);

create policy "devices_delete_own"
    on public.devices
    for delete
    to authenticated
    using (auth.uid() = owner_id);

create trigger profiles_set_updated_at
    before update on public.profiles
    for each row
    execute function public.set_updated_at();

create trigger chart_documents_set_updated_at
    before update on public.chart_documents
    for each row
    execute function public.set_updated_at();

create trigger subscriptions_set_updated_at
    before update on public.subscriptions
    for each row
    execute function public.set_updated_at();

create trigger devices_set_updated_at
    before update on public.devices
    for each row
    execute function public.set_updated_at();

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    insert into public.profiles (id, email, phone)
    values (new.id, new.email, coalesce(new.phone, new.raw_user_meta_data ->> 'phone'))
    on conflict (id) do update
        set email = excluded.email,
            phone = coalesce(public.profiles.phone, excluded.phone),
            updated_at = now();

    insert into public.subscriptions (owner_id)
    values (new.id)
    on conflict (owner_id) do nothing;

    return new;
end;
$$;

create trigger on_auth_user_created_create_profile
    after insert on auth.users
    for each row
    execute function public.handle_new_auth_user();
