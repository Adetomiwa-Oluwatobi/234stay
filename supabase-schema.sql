-- ============================================
-- 234Stays — Supabase Schema (Shortlet Edition)
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- ============================================

-- Drop old tables if migrating from 234estate
-- (comment these out if you want to keep existing data)
-- drop table if exists inspection_requests cascade;
-- drop table if exists properties cascade;

-- ============================================
-- PROPERTIES TABLE (shortlet-focused)
-- ============================================
create table if not exists properties (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz default now(),

  -- Core
  title text not null,
  listing_type text not null default 'shortlet'
    check (listing_type in ('shortlet','rent','sale','land')),
  category text default 'Studio Apartment',
    -- Studio Apartment, 1 Bedroom Apartment, 2 Bedroom Apartment,
    -- 3 Bedroom Apartment, Duplex, Penthouse, Villa
  featured boolean default false,
  verified boolean default false,
  verification_label text default 'Verified',

  -- Location
  address text not null,
  city text not null,
  state text,
  full_location text,

  -- Price
  price numeric not null,
  price_label text default '/ night',   -- e.g. "/ night", "/ weekend", "/ week"
  negotiable boolean default false,

  -- Specs
  bedrooms int default 1,
  bathrooms int default 1,
  sqft numeric,
  garage int default 0,
  max_guests int default 2,

  -- Rating
  rating numeric default 0,
  review_count int default 0,

  -- Media
  cover_image text,
  gallery_images text[] default '{}',
  video_url text,

  -- Content
  overview text,
  amenities text[] default '{}',
    -- e.g. {"24/7 Electricity","High-Speed Wi-Fi","PS5","Smart TV","Netflix",
    --        "Air Conditioning","Swimming Pool","Gym","CCTV","Fully Fitted Kitchen"}
  documents text[] default '{}',        -- house rules
  transaction_terms text[] default '{}', -- booking terms

  -- Host / Agent
  agent_name text,
  agent_phone text,
  agent_whatsapp text,
  agent_avatar text,
  agent_rating numeric default 5.0,
  agent_deals int default 0,

  -- Status
  is_active boolean default true
);

create index if not exists idx_properties_city on properties (city);
create index if not exists idx_properties_type on properties (listing_type);
create index if not exists idx_properties_active on properties (is_active);

-- RLS
alter table properties enable row level security;

create policy "Public can view active properties"
  on properties for select using (is_active = true);

create policy "Authenticated staff can insert"
  on properties for insert to authenticated with check (true);

create policy "Authenticated staff can update"
  on properties for update to authenticated using (true);

create policy "Authenticated staff can delete"
  on properties for delete to authenticated using (true);


-- ============================================
-- BLOCKED DATES TABLE  ← NEW
-- Admin blocks/unblocks dates per property.
-- Guests cannot book blocked dates.
-- ============================================
create table if not exists blocked_dates (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz default now(),
  property_id uuid references properties(id) on delete cascade,
  blocked_date date not null,
  reason text default 'Booked',   -- e.g. "Booked", "Maintenance", "Owner stay"
  unique (property_id, blocked_date)   -- prevents duplicate entries
);

create index if not exists idx_blocked_property on blocked_dates (property_id);
create index if not exists idx_blocked_date on blocked_dates (blocked_date);

-- RLS
alter table blocked_dates enable row level security;

-- Public (guests) can READ blocked dates — needed for availability calendar
create policy "Public can view blocked dates"
  on blocked_dates for select using (true);

-- Only authenticated staff (admin) can manage blocked dates
create policy "Staff can insert blocked dates"
  on blocked_dates for insert to authenticated with check (true);

create policy "Staff can delete blocked dates"
  on blocked_dates for delete to authenticated using (true);

create policy "Staff can update blocked dates"
  on blocked_dates for update to authenticated using (true);


-- ============================================
-- INSPECTION / BOOKING REQUESTS TABLE
-- ============================================
create table if not exists inspection_requests (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz default now(),
  property_id uuid references properties(id) on delete set null,
  property_title text,
  full_name text not null,
  phone text not null,
  preferred_date date,             -- check-in date
  preferred_time time,             -- optional
  buyer_type text,                 -- number of guests or buyer type
  payment_plan text default 'shortlet',
  message text,
  status text default 'new'
    check (status in ('new','contacted','completed','cancelled'))
);

alter table inspection_requests enable row level security;

-- Anyone (including non-logged-in visitors) can submit a booking request
create policy "Anyone can submit a booking request"
  on inspection_requests for insert
  to anon, authenticated
  with check (true);

create policy "Staff can view booking requests"
  on inspection_requests for select to authenticated using (true);

create policy "Staff can update booking requests"
  on inspection_requests for update to authenticated using (true);


-- ============================================
-- SAMPLE DATA — Premium Shortlet Listings
-- Replace image URLs with your own Supabase Storage URLs.
-- ============================================
insert into properties (
  title, listing_type, category, featured, verified, verification_label,
  address, city, state, full_location,
  price, price_label,
  bedrooms, bathrooms, sqft, max_guests,
  rating, review_count,
  cover_image, gallery_images,
  overview, amenities, documents, transaction_terms,
  agent_name, agent_phone, agent_whatsapp, agent_avatar, agent_rating, agent_deals
) values

-- 1. Lekki Luxury
(
  'Luxury 3-Bedroom Shortlet, Lekki Phase 1', 'shortlet', '3 Bedroom Apartment',
  true, true, 'Verified',
  '15 Admiralty Way, Lekki Phase 1', 'Lagos', 'Lagos State',
  '15 Admiralty Way, Lekki Phase 1, Lagos State, Nigeria',
  95000, '/ night', 3, 3, 2200, 6,
  4.9, 184,
  'https://images.unsplash.com/photo-1522708323590-d24dbb6b0267?w=900&q=80',
  array[
    'https://images.unsplash.com/photo-1522708323590-d24dbb6b0267?w=900&q=80',
    'https://images.unsplash.com/photo-1493809842364-78817add7ffb?w=900&q=80',
    'https://images.unsplash.com/photo-1556909114-f6e7ad7d3136?w=900&q=80',
    'https://images.unsplash.com/photo-1560448204-e02f11c3d0e2?w=900&q=80'
  ],
  'A stunning 3-bedroom shortlet apartment in the heart of Lekki Phase 1. This fully-serviced unit features floor-to-ceiling windows, Italian marble floors, a gourmet kitchen, and a private balcony. Guests enjoy a PlayStation 5, 65" Smart TV, Netflix access, 24/7 electricity, and high-speed fibre internet throughout.',
  array['24/7 Electricity','High-Speed Wi-Fi (100Mbps)','PS5 + 2 Controllers','65" Smart TV','Netflix & DSTV','Air Conditioning (All Rooms)','Fully Fitted Kitchen','Swimming Pool Access','Gym Access','CCTV Security','Private Parking','Daily Housekeeping'],
  array['No smoking inside the apartment','No unregistered guests overnight','No loud music after 11PM','Pets allowed on request only'],
  array['50% deposit required to confirm booking','Balance due on check-in day','Refundable caution deposit: ₦20,000','Check-in: 2PM | Check-out: 12PM noon'],
  'Temi Adeyemi', '08001234567', '2348001234567',
  'https://randomuser.me/api/portraits/women/44.jpg', 4.9, 128
),

-- 2. Victoria Island Penthouse
(
  'Sea-View Penthouse Suite, Victoria Island', 'shortlet', 'Penthouse',
  true, true, 'Verified',
  '7B Ocean Drive, Victoria Island', 'Lagos', 'Lagos State',
  '7B Ocean Drive, Victoria Island, Lagos State, Nigeria',
  175000, '/ night', 4, 4, 3800, 8,
  5.0, 97,
  'https://images.unsplash.com/photo-1617098900591-3f90928e8c54?w=900&q=80',
  array[
    'https://images.unsplash.com/photo-1617098900591-3f90928e8c54?w=900&q=80',
    'https://images.unsplash.com/photo-1613490493576-7fde63acd811?w=900&q=80',
    'https://images.unsplash.com/photo-1502672260266-1c1ef2d93688?w=900&q=80'
  ],
  'The ultimate Lagos experience. This ocean-view penthouse sits atop one of Victoria Island''s most sought-after towers with breathtaking Atlantic views. It features a private rooftop Jacuzzi, PS5, home cinema system, and a fully-equipped chef''s kitchen. Perfect for couples, celebrations, and executive stays.',
  array['24/7 Electricity (Dedicated Generator)','Fibre Internet (200Mbps)','PS5 + 4K Gaming Setup','75" OLED Smart TV','Netflix, DSTV & Apple TV','Air Conditioning (All Rooms)','Private Rooftop Jacuzzi','Home Cinema Room','Smart Door Lock','Dedicated Parking (x2)','24/7 Concierge Service','Airport Pickup Available'],
  array['No parties or events without prior approval','Maximum 8 guests as registered','No smoking — smoking balcony available'],
  array['Full payment required for 1-2 night stays','50% deposit for 3+ nights','Refundable caution: ₦50,000','Check-in: 3PM | Check-out: 12PM noon'],
  'Biodun Okonkwo', '08009876543', '2348009876543',
  'https://randomuser.me/api/portraits/men/55.jpg', 5.0, 74
),

-- 3. Abuja Studio
(
  'Modern Studio Apartment, Maitama Abuja', 'shortlet', 'Studio Apartment',
  false, true, 'Verified',
  '12 Aminu Kano Crescent, Maitama', 'Abuja', 'FCT',
  '12 Aminu Kano Crescent, Maitama, Abuja, FCT, Nigeria',
  45000, '/ night', 1, 1, 650, 2,
  4.7, 63,
  'https://images.unsplash.com/photo-1502672260266-1c1ef2d93688?w=900&q=80',
  array[
    'https://images.unsplash.com/photo-1502672260266-1c1ef2d93688?w=900&q=80',
    'https://images.unsplash.com/photo-1560448204-e02f11c3d0e2?w=900&q=80'
  ],
  'A sleek, modern studio apartment ideal for solo travellers and corporate guests visiting Abuja. Fully air-conditioned with high-speed internet, smart TV, and a compact but fully equipped kitchen. 24/7 power supply guaranteed.',
  array['24/7 Electricity','High-Speed Wi-Fi (50Mbps)','43" Smart TV','Netflix','Air Conditioning','Compact Fitted Kitchen','CCTV Security','Dedicated Parking'],
  array['No smoking','No third-party guests','Quiet hours after 10PM'],
  array['Full payment on booking','Refundable caution: ₦10,000','Check-in: 2PM | Check-out: 11AM'],
  'Fatima Musa', '08007654321', '2348007654321',
  'https://randomuser.me/api/portraits/women/22.jpg', 4.7, 45
);

-- ============================================
-- SAMPLE BLOCKED DATES
-- You can remove these or add via the Admin Portal
-- ============================================
-- (These use subqueries to get the IDs of the properties above)
insert into blocked_dates (property_id, blocked_date, reason)
select id, current_date + interval '2 days', 'Booked — external reservation'
from properties where title like 'Luxury 3-Bedroom%' limit 1;

insert into blocked_dates (property_id, blocked_date, reason)
select id, current_date + interval '3 days', 'Booked — external reservation'
from properties where title like 'Luxury 3-Bedroom%' limit 1;

insert into blocked_dates (property_id, blocked_date, reason)
select id, current_date + interval '7 days', 'Owner stay'
from properties where title like 'Sea-View Penthouse%' limit 1;
