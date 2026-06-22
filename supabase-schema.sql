-- ============================================
-- 234Stays — Fresh Project Schema
-- Safe for a brand new Supabase project.
-- Run in: SQL Editor → New Query → Run
-- ============================================

-- ============================================
-- SAFE CLEANUP (works even if tables don't exist yet)
-- ============================================
do $$ begin
  -- drop tables in reverse dependency order
  drop table if exists inspection_requests cascade;
  drop table if exists blocked_dates cascade;
  drop table if exists properties cascade;
  drop table if exists profiles cascade;

  -- drop functions
  drop function if exists handle_new_user() cascade;
  drop function if exists get_my_role() cascade;
  drop function if exists get_my_profile() cascade;

  -- drop trigger (safe — cascaded above, but belt-and-suspenders)
  -- triggers are dropped automatically when the function is dropped
exception when others then
  raise notice 'Cleanup notice: %', sqlerrm;
end $$;


-- ============================================
-- TABLE 1: profiles
-- ============================================
create table profiles (
  id              uuid primary key references auth.users(id) on delete cascade,
  created_at      timestamptz default now(),
  role            text not null default 'agency'
                    check (role in ('admin','agency')),
  full_name       text,
  agency_name     text,
  agency_logo     text,
  agency_phone    text,
  agency_whatsapp text,
  agency_bio      text,
  agency_city     text,
  agency_slug     text unique,
  is_active       boolean default true
);

alter table profiles enable row level security;

create policy "profiles_public_read"
  on profiles for select
  using (is_active = true);

create policy "profiles_self_update"
  on profiles for update
  using (auth.uid() = id);


-- ============================================
-- AUTO-CREATE PROFILE ON SIGNUP
-- ============================================
create or replace function handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, role, full_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'role', 'agency'),
    coalesce(new.raw_user_meta_data->>'full_name', new.email)
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure handle_new_user();


-- ============================================
-- TABLE 2: properties
-- ============================================
create table properties (
  id                 uuid primary key default gen_random_uuid(),
  created_at         timestamptz default now(),
  owner_id           uuid references profiles(id) on delete set null,
  title              text not null,
  listing_type       text not null default 'shortlet'
                       check (listing_type in ('shortlet','rent','sale','land')),
  category           text default 'Studio Apartment',
  featured           boolean default false,
  verified           boolean default false,
  verification_label text default 'Verified',
  address            text not null,
  city               text not null,
  state              text,
  full_location      text,
  price              numeric not null,
  price_label        text default '/ night',
  negotiable         boolean default false,
  bedrooms           int default 1,
  bathrooms          int default 1,
  sqft               numeric,
  max_guests         int default 2,
  rating             numeric default 0,
  review_count       int default 0,
  cover_image        text,
  gallery_images     text[] default '{}',
  video_url          text,
  overview           text,
  amenities          text[] default '{}',
  documents          text[] default '{}',
  transaction_terms  text[] default '{}',
  agent_name         text,
  agent_phone        text,
  agent_whatsapp     text,
  agent_avatar       text,
  agent_rating       numeric default 5.0,
  agent_deals        int default 0,
  is_active          boolean default true
);

create index idx_properties_owner  on properties (owner_id);
create index idx_properties_city   on properties (city);
create index idx_properties_type   on properties (listing_type);
create index idx_properties_active on properties (is_active);

alter table properties enable row level security;

create policy "properties_public_read"
  on properties for select
  using (is_active = true);

create policy "properties_agency_insert"
  on properties for insert to authenticated
  with check (owner_id = auth.uid());

create policy "properties_agency_update"
  on properties for update to authenticated
  using (owner_id = auth.uid());

create policy "properties_agency_delete"
  on properties for delete to authenticated
  using (owner_id = auth.uid());

create policy "properties_admin_read"
  on properties for select to authenticated
  using (
    (select role from profiles where id = auth.uid()) = 'admin'
  );

create policy "properties_admin_insert"
  on properties for insert to authenticated
  with check (
    (select role from profiles where id = auth.uid()) = 'admin'
  );

create policy "properties_admin_update"
  on properties for update to authenticated
  using (
    (select role from profiles where id = auth.uid()) = 'admin'
  );

create policy "properties_admin_delete"
  on properties for delete to authenticated
  using (
    (select role from profiles where id = auth.uid()) = 'admin'
  );


-- ============================================
-- TABLE 3: blocked_dates
-- ============================================
create table blocked_dates (
  id           uuid primary key default gen_random_uuid(),
  created_at   timestamptz default now(),
  property_id  uuid not null references properties(id) on delete cascade,
  blocked_date date not null,
  reason       text default 'Booked',
  unique (property_id, blocked_date)
);

create index idx_blocked_property on blocked_dates (property_id);
create index idx_blocked_date     on blocked_dates (blocked_date);

alter table blocked_dates enable row level security;

create policy "blocked_dates_public_read"
  on blocked_dates for select
  using (true);

create policy "blocked_dates_agency_insert"
  on blocked_dates for insert to authenticated
  with check (
    property_id in (
      select id from properties where owner_id = auth.uid()
    )
  );

create policy "blocked_dates_agency_update"
  on blocked_dates for update to authenticated
  using (
    property_id in (
      select id from properties where owner_id = auth.uid()
    )
  );

create policy "blocked_dates_agency_delete"
  on blocked_dates for delete to authenticated
  using (
    property_id in (
      select id from properties where owner_id = auth.uid()
    )
  );

create policy "blocked_dates_admin_all"
  on blocked_dates for all to authenticated
  using (
    (select role from profiles where id = auth.uid()) = 'admin'
  );


-- ============================================
-- TABLE 4: inspection_requests
-- ============================================
create table inspection_requests (
  id             uuid primary key default gen_random_uuid(),
  created_at     timestamptz default now(),
  property_id    uuid references properties(id) on delete set null,
  property_title text,
  owner_id       uuid references profiles(id) on delete set null,
  full_name      text not null,
  phone          text not null,
  preferred_date date,
  preferred_time time,
  buyer_type     text,
  payment_plan   text default 'shortlet',
  message        text,
  status         text default 'new'
                   check (status in ('new','contacted','completed','cancelled'))
);

create index idx_requests_owner    on inspection_requests (owner_id);
create index idx_requests_property on inspection_requests (property_id);

alter table inspection_requests enable row level security;

create policy "requests_public_insert"
  on inspection_requests for insert
  to anon, authenticated
  with check (true);

create policy "requests_agency_read"
  on inspection_requests for select to authenticated
  using (owner_id = auth.uid());

create policy "requests_agency_update"
  on inspection_requests for update to authenticated
  using (owner_id = auth.uid());

create policy "requests_admin_read"
  on inspection_requests for select to authenticated
  using (
    (select role from profiles where id = auth.uid()) = 'admin'
  );

create policy "requests_admin_update"
  on inspection_requests for update to authenticated
  using (
    (select role from profiles where id = auth.uid()) = 'admin'
  );


-- ============================================
-- HELPER FUNCTIONS
-- ============================================
create or replace function get_my_role()
returns text
language sql
security definer
set search_path = public
as $$
  select role from public.profiles where id = auth.uid();
$$;

create or replace function get_my_profile()
returns json
language sql
security definer
set search_path = public
as $$
  select row_to_json(p) from public.profiles p where id = auth.uid();
$$;


-- ============================================
-- DONE. Next step — promote yourself to admin:
--
-- 1. Go to login.html and create an account
-- 2. Go to Supabase Dashboard → Authentication → Users
-- 3. Copy your user UUID
-- 4. Open SQL Editor and run:
--
--    update profiles set role = 'admin' where id = 'PASTE-UUID-HERE';
--
-- ============================================