-- ============================================
-- 234Stays — Full Schema with Auth Roles
-- Run ONCE in: Supabase Dashboard → SQL Editor → New Query
-- ============================================

-- ============================================
-- PROFILES TABLE (extends Supabase auth.users)
-- ============================================
create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz default now(),
  role text not null default 'agency'
    check (role in ('admin', 'agency')),
  full_name text,
  agency_name text,
  agency_logo text,
  agency_phone text,
  agency_whatsapp text,
  agency_bio text,
  agency_city text,
  agency_slug text unique,
  is_active boolean default true
);

-- Auto-create profile on signup
create or replace function handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into profiles (id, role, full_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'role', 'agency'),
    coalesce(new.raw_user_meta_data->>'full_name', new.email)
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure handle_new_user();

alter table profiles enable row level security;
create policy "Public can read active agency profiles" on profiles for select using (is_active = true);
create policy "User can update own profile" on profiles for update using (auth.uid() = id);

-- ============================================
-- PROPERTIES TABLE
-- ============================================
create table if not exists properties (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz default now(),
  owner_id uuid references profiles(id) on delete set null,
  title text not null,
  listing_type text not null default 'shortlet' check (listing_type in ('shortlet','rent','sale','land')),
  category text default 'Studio Apartment',
  featured boolean default false,
  verified boolean default false,
  verification_label text default 'Verified',
  address text not null,
  city text not null,
  state text,
  full_location text,
  price numeric not null,
  price_label text default '/ night',
  negotiable boolean default false,
  bedrooms int default 1,
  bathrooms int default 1,
  sqft numeric,
  max_guests int default 2,
  rating numeric default 0,
  review_count int default 0,
  cover_image text,
  gallery_images text[] default '{}',
  video_url text,
  overview text,
  amenities text[] default '{}',
  documents text[] default '{}',
  transaction_terms text[] default '{}',
  agent_name text,
  agent_phone text,
  agent_whatsapp text,
  agent_avatar text,
  agent_rating numeric default 5.0,
  agent_deals int default 0,
  is_active boolean default true
);

create index if not exists idx_properties_owner on properties (owner_id);
create index if not exists idx_properties_city on properties (city);
create index if not exists idx_properties_type on properties (listing_type);
create index if not exists idx_properties_active on properties (is_active);

alter table properties enable row level security;
create policy "Public view active properties" on properties for select using (is_active = true);
create policy "Agency insert own" on properties for insert to authenticated with check (owner_id = auth.uid());
create policy "Agency update own" on properties for update to authenticated using (owner_id = auth.uid());
create policy "Agency delete own" on properties for delete to authenticated using (owner_id = auth.uid());
create policy "Admin full access" on properties for all to authenticated
  using (exists (select 1 from profiles where id = auth.uid() and role = 'admin'));

-- ============================================
-- BLOCKED DATES TABLE
-- ============================================
create table if not exists blocked_dates (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz default now(),
  property_id uuid references properties(id) on delete cascade,
  blocked_date date not null,
  reason text default 'Booked',
  unique (property_id, blocked_date)
);

create index if not exists idx_blocked_property on blocked_dates (property_id);
alter table blocked_dates enable row level security;
create policy "Public view blocked dates" on blocked_dates for select using (true);
create policy "Owner manage blocked dates" on blocked_dates for all to authenticated
  using (exists (
    select 1 from properties p
    left join profiles pr on pr.id = auth.uid()
    where p.id = blocked_dates.property_id
      and (p.owner_id = auth.uid() or pr.role = 'admin')
  ));

-- ============================================
-- BOOKING REQUESTS TABLE
-- ============================================
create table if not exists inspection_requests (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz default now(),
  property_id uuid references properties(id) on delete set null,
  property_title text,
  owner_id uuid references profiles(id) on delete set null,
  full_name text not null,
  phone text not null,
  preferred_date date,
  preferred_time time,
  buyer_type text,
  payment_plan text default 'shortlet',
  message text,
  status text default 'new' check (status in ('new','contacted','completed','cancelled'))
);

create index if not exists idx_requests_owner on inspection_requests (owner_id);
alter table inspection_requests enable row level security;
create policy "Anyone can submit" on inspection_requests for insert to anon, authenticated with check (true);
create policy "Agency sees own requests" on inspection_requests for select to authenticated using (owner_id = auth.uid());
create policy "Agency updates own requests" on inspection_requests for update to authenticated using (owner_id = auth.uid());
create policy "Admin sees all requests" on inspection_requests for all to authenticated
  using (exists (select 1 from profiles where id = auth.uid() and role = 'admin'));

-- ============================================
-- HELPER FUNCTIONS
-- ============================================
create or replace function get_my_role()
returns text language sql security definer as $$
  select role from profiles where id = auth.uid();
$$;

create or replace function get_my_profile()
returns json language sql security definer as $$
  select row_to_json(p) from profiles p where id = auth.uid();
$$;

-- ============================================
-- AFTER SETUP: Promote a user to admin
-- 1. Create a user via Supabase Auth dashboard or the signup page
-- 2. Copy their UUID from Authentication → Users
-- 3. Run: UPDATE profiles SET role = 'admin' WHERE id = 'PASTE-UUID-HERE';
-- ============================================
