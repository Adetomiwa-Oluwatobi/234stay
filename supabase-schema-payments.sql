-- ============================================
-- 234Stays — Payment Schema (add-on)
-- Run AFTER the main supabase-schema.sql
-- ============================================

-- ============================================
-- SETTINGS TABLE (platform config)
-- ============================================
create table if not exists settings (
  key   text primary key,
  value text not null
);

-- Insert default settings
insert into settings (key, value) values
  ('platform_fee_percent', '0'),
  ('launch_mode', 'true'),
  ('launch_end_date', '2025-09-30')
on conflict (key) do nothing;

alter table settings enable row level security;

-- Anyone can read settings (needed for frontend fee display)
create policy "settings_public_read"
  on settings for select using (true);

-- Only admin can update settings
create policy "settings_admin_update"
  on settings for update to authenticated
  using ((select role from profiles where id = auth.uid()) = 'admin');


-- ============================================
-- WALLETS TABLE
-- ============================================
create table if not exists wallets (
  id                uuid primary key default gen_random_uuid(),
  created_at        timestamptz default now(),
  agency_id         uuid not null unique references profiles(id) on delete cascade,
  available_balance numeric not null default 0,
  pending_balance   numeric not null default 0,
  total_earned      numeric not null default 0
);

alter table wallets enable row level security;

-- Agency can only read their own wallet
create policy "wallet_agency_read"
  on wallets for select to authenticated
  using (agency_id = auth.uid());

-- Admin can read all wallets
create policy "wallet_admin_read"
  on wallets for select to authenticated
  using ((select role from profiles where id = auth.uid()) = 'admin');

-- NO update policy for anyone — only Edge Functions (service role) can write


-- ============================================
-- BOOKINGS TABLE (replaces inspection_requests for paid bookings)
-- ============================================
create table if not exists bookings (
  id                 uuid primary key default gen_random_uuid(),
  created_at         timestamptz default now(),

  -- Property & ownership
  property_id        uuid references properties(id) on delete set null,
  property_title     text,
  owner_id           uuid references profiles(id) on delete set null,

  -- Guest details
  guest_name         text not null,
  guest_phone        text not null,
  guest_email        text,
  num_guests         int default 1,
  special_requests   text,

  -- Stay details
  checkin_date       date not null,
  checkout_date      date not null,
  nights             int not null,

  -- Pricing snapshot (captured at booking time)
  price_per_night    numeric not null,
  total_amount       numeric not null,
  platform_fee       numeric not null default 0,
  agency_earning     numeric not null,

  -- Payment config (from property at time of booking)
  payment_type       text not null default 'full'
                       check (payment_type in ('full','deposit')),
  deposit_percent    int default 100,
  deposit_amount     numeric not null,
  balance_amount     numeric not null default 0,
  balance_due        text default 'on_arrival'
                       check (balance_due in ('on_arrival','before_checkin')),

  -- Payment status
  payment_reference  text unique,
  payment_status     text not null default 'pending'
                       check (payment_status in ('pending','deposit_paid','fully_paid','refunded','failed')),

  -- Stay status
  stay_status        text not null default 'upcoming'
                       check (stay_status in ('upcoming','active','completed','cancelled')),

  -- Fund release
  funds_released     boolean default false,
  funds_released_at  timestamptz
);

create index idx_bookings_owner      on bookings (owner_id);
create index idx_bookings_property   on bookings (property_id);
create index idx_bookings_checkin    on bookings (checkin_date);
create index idx_bookings_status     on bookings (payment_status);
create index idx_bookings_funds      on bookings (funds_released);

alter table bookings enable row level security;

-- Public can insert (guests booking)
create policy "bookings_public_insert"
  on bookings for insert
  to anon, authenticated
  with check (true);

-- Public can read their own booking by reference (for confirmation page)
create policy "bookings_public_read_by_ref"
  on bookings for select
  using (true);

-- Agency reads their own bookings
create policy "bookings_agency_read"
  on bookings for select to authenticated
  using (owner_id = auth.uid());

-- Admin reads all
create policy "bookings_admin_read"
  on bookings for select to authenticated
  using ((select role from profiles where id = auth.uid()) = 'admin');

create policy "bookings_admin_update"
  on bookings for update to authenticated
  using ((select role from profiles where id = auth.uid()) = 'admin');


-- ============================================
-- TRANSACTIONS TABLE (audit trail)
-- ============================================
create table if not exists transactions (
  id          uuid primary key default gen_random_uuid(),
  created_at  timestamptz default now(),
  agency_id   uuid references profiles(id) on delete set null,
  booking_id  uuid references bookings(id) on delete set null,
  type        text not null
                check (type in ('credit','debit','withdrawal','refund','platform_fee')),
  amount      numeric not null,
  reference   text,
  description text,
  status      text not null default 'success'
                check (status in ('pending','success','failed'))
);

create index idx_transactions_agency  on transactions (agency_id);
create index idx_transactions_booking on transactions (booking_id);
create index idx_transactions_ref     on transactions (reference);

alter table transactions enable row level security;

-- Agency reads their own transactions
create policy "transactions_agency_read"
  on transactions for select to authenticated
  using (agency_id = auth.uid());

-- Admin reads all
create policy "transactions_admin_read"
  on transactions for select to authenticated
  using ((select role from profiles where id = auth.uid()) = 'admin');

-- NO insert/update from client — Edge Function only


-- ============================================
-- WITHDRAWAL REQUESTS TABLE
-- ============================================
create table if not exists withdrawal_requests (
  id                      uuid primary key default gen_random_uuid(),
  created_at              timestamptz default now(),
  agency_id               uuid not null references profiles(id) on delete cascade,
  amount                  numeric not null,
  bank_name               text not null,
  account_number          text not null,
  account_name            text not null,
  paystack_recipient_code text,
  admin_note              text,
  processed_at            timestamptz,
  status                  text not null default 'pending'
                            check (status in ('pending','approved','paid','rejected'))
);

create index idx_withdrawals_agency on withdrawal_requests (agency_id);
create index idx_withdrawals_status on withdrawal_requests (status);

alter table withdrawal_requests enable row level security;

-- Agency can insert and read their own
create policy "withdrawals_agency_insert"
  on withdrawal_requests for insert to authenticated
  with check (agency_id = auth.uid());

create policy "withdrawals_agency_read"
  on withdrawal_requests for select to authenticated
  using (agency_id = auth.uid());

-- Admin reads and updates all
create policy "withdrawals_admin_read"
  on withdrawal_requests for select to authenticated
  using ((select role from profiles where id = auth.uid()) = 'admin');

create policy "withdrawals_admin_update"
  on withdrawal_requests for update to authenticated
  using ((select role from profiles where id = auth.uid()) = 'admin');


-- ============================================
-- REFUND REQUESTS TABLE
-- ============================================
create table if not exists refund_requests (
  id             uuid primary key default gen_random_uuid(),
  created_at     timestamptz default now(),
  booking_id     uuid not null references bookings(id) on delete cascade,
  owner_id       uuid references profiles(id) on delete set null,
  requested_by   text not null check (requested_by in ('guest','agency')),
  reason         text not null,
  amount         numeric not null,
  admin_note     text,
  processed_at   timestamptz,
  status         text not null default 'pending'
                   check (status in ('pending','approved','rejected','processed'))
);

create index idx_refunds_booking on refund_requests (booking_id);
create index idx_refunds_owner   on refund_requests (owner_id);
create index idx_refunds_status  on refund_requests (status);

alter table refund_requests enable row level security;

-- Public (guests) can insert refund requests
create policy "refunds_public_insert"
  on refund_requests for insert
  to anon, authenticated
  with check (true);

-- Agency reads refunds for their bookings
create policy "refunds_agency_read"
  on refund_requests for select to authenticated
  using (owner_id = auth.uid());

-- Admin reads and updates all
create policy "refunds_admin_read"
  on refund_requests for select to authenticated
  using ((select role from profiles where id = auth.uid()) = 'admin');

create policy "refunds_admin_update"
  on refund_requests for update to authenticated
  using ((select role from profiles where id = auth.uid()) = 'admin');


-- ============================================
-- ADD PAYMENT FIELDS TO PROPERTIES TABLE
-- ============================================
alter table properties
  add column if not exists payment_type    text default 'full'
                                             check (payment_type in ('full','deposit')),
  add column if not exists deposit_percent int default 100,
  add column if not exists balance_due     text default 'on_arrival'
                                             check (balance_due in ('on_arrival','before_checkin')),
  add column if not exists cancellation_policy text;


-- ============================================
-- AUTO-CREATE WALLET WHEN AGENCY SIGNS UP
-- ============================================
create or replace function handle_new_wallet()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.role = 'agency' then
    insert into public.wallets (agency_id)
    values (new.id)
    on conflict (agency_id) do nothing;
  end if;
  return new;
end;
$$;

create trigger on_profile_created_create_wallet
  after insert on profiles
  for each row execute procedure handle_new_wallet();

-- Create wallets for any existing agencies that don't have one
insert into wallets (agency_id)
select id from profiles
where role = 'agency'
  and id not in (select agency_id from wallets)
on conflict (agency_id) do nothing;


-- ============================================
-- HELPER: get platform fee percent
-- ============================================
create or replace function get_platform_fee()
returns numeric
language sql
security definer
set search_path = public
as $$
  select value::numeric from settings where key = 'platform_fee_percent';
$$;


-- ============================================
-- WALLET RPC FUNCTIONS (called by Edge Functions only)
-- These use service role — clients cannot call them directly
-- ============================================

-- Credit pending balance (after payment)
create or replace function credit_pending_balance(p_agency_id uuid, p_amount numeric)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update wallets
  set
    pending_balance = pending_balance + p_amount,
    total_earned    = total_earned + p_amount
  where agency_id = p_agency_id;

  if not found then
    insert into wallets (agency_id, pending_balance, total_earned)
    values (p_agency_id, p_amount, p_amount);
  end if;
end;
$$;

-- Release pending → available (after stay + 24hr)
create or replace function release_funds_to_available(p_agency_id uuid, p_amount numeric)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update wallets
  set
    pending_balance   = greatest(0, pending_balance - p_amount),
    available_balance = available_balance + p_amount
  where agency_id = p_agency_id;
end;
$$;

-- Debit available balance (after withdrawal paid)
create or replace function debit_available_balance(p_agency_id uuid, p_amount numeric)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update wallets
  set available_balance = greatest(0, available_balance - p_amount)
  where agency_id = p_agency_id;
end;
$$;
