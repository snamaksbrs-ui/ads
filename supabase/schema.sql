-- Souq Sanam: Supabase schema
-- Run in Supabase SQL Editor. Public visitors can submit ads for moderation;
-- only approved ads are publicly readable. Authenticated users own/manage their ads.

create extension if not exists pgcrypto;

create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  slug text not null unique,
  icon text,
  sort_order int not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

insert into public.categories (name, slug, sort_order) values
 ('عقارات','real-estate',1),('سيارات','cars',2),('أجهزة','electronics',3),
 ('وظائف','jobs',4),('أثاث','furniture',5),('خدمات','services',6)
on conflict (slug) do nothing;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  phone text,
  city text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.ads (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  category_id uuid references public.categories(id) on delete set null,
  title text not null check (char_length(title) between 5 and 140),
  description text not null check (char_length(description) between 10 and 10000),
  price numeric(14,2),
  price_type text not null default 'fixed' check (price_type in ('fixed','negotiable','free','contact')),
  city text,
  contact_name text,
  contact_phone text,
  image_url text,
  status text not null default 'pending' check (status in ('pending','approved','rejected','sold','archived')),
  views_count bigint not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.ad_images (
  id uuid primary key default gen_random_uuid(),
  ad_id uuid not null references public.ads(id) on delete cascade,
  image_url text not null,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.favorites (
  user_id uuid not null references auth.users(id) on delete cascade,
  ad_id uuid not null references public.ads(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, ad_id)
);

create table if not exists public.likes (
  user_id uuid not null references auth.users(id) on delete cascade,
  ad_id uuid not null references public.ads(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, ad_id)
);

create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  ad_id uuid not null references public.ads(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  guest_name text,
  body text not null check (char_length(body) between 1 and 2000),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz not null default now()
);

create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  ad_id uuid not null references public.ads(id) on delete cascade,
  reporter_id uuid references auth.users(id) on delete set null,
  reason text not null,
  details text,
  status text not null default 'open' check (status in ('open','reviewed','dismissed')),
  created_at timestamptz not null default now()
);

alter table public.ads add column if not exists image_url text;

create index if not exists ads_status_created_idx on public.ads(status, created_at desc);
create index if not exists ads_category_idx on public.ads(category_id);
create index if not exists ads_city_idx on public.ads(city);
create index if not exists comments_ad_status_idx on public.comments(ad_id, status, created_at);

alter table public.categories enable row level security;
alter table public.profiles enable row level security;
alter table public.ads enable row level security;
alter table public.ad_images enable row level security;
alter table public.favorites enable row level security;
alter table public.likes enable row level security;
alter table public.comments enable row level security;
alter table public.reports enable row level security;

drop policy if exists "Categories are public read" on public.categories;
create policy "Categories are public read" on public.categories for select using (is_active = true);

drop policy if exists "Profiles are publicly readable" on public.profiles;
create policy "Profiles are publicly readable" on public.profiles for select using (true);
drop policy if exists "Users insert own profile" on public.profiles;
create policy "Users insert own profile" on public.profiles for insert to authenticated with check (auth.uid() = id);
drop policy if exists "Users update own profile" on public.profiles;
create policy "Users update own profile" on public.profiles for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);

drop policy if exists "Public can read approved ads" on public.ads;
create policy "Public can read approved ads" on public.ads for select using (status = 'approved' or user_id = auth.uid());
drop policy if exists "Visitors can submit pending ads" on public.ads;
create policy "Visitors can submit pending ads" on public.ads for insert to anon, authenticated with check (status = 'pending' and (user_id is null or user_id = auth.uid()));
drop policy if exists "Owners update own ads" on public.ads;
create policy "Owners update own ads" on public.ads for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "Owners delete own ads" on public.ads;
create policy "Owners delete own ads" on public.ads for delete to authenticated using (user_id = auth.uid());

drop policy if exists "Images of visible ads are public" on public.ad_images;
create policy "Images of visible ads are public" on public.ad_images for select using (
 exists (select 1 from public.ads a where a.id = ad_id and (a.status = 'approved' or a.user_id = auth.uid()))
);
drop policy if exists "Submit images for pending ads" on public.ad_images;
create policy "Submit images for pending ads" on public.ad_images for insert to anon, authenticated with check (
 exists (select 1 from public.ads a where a.id = ad_id and a.status = 'pending' and (a.user_id is null or a.user_id = auth.uid()))
);

drop policy if exists "Users manage own favorites" on public.favorites;
create policy "Users manage own favorites" on public.favorites for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "Users manage own likes" on public.likes;
create policy "Users manage own likes" on public.likes for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "Public read approved comments" on public.comments;
create policy "Public read approved comments" on public.comments for select using (
 status = 'approved' or user_id = auth.uid()
);
drop policy if exists "Signed in users submit comments" on public.comments;
create policy "Signed in users submit comments" on public.comments for insert to authenticated with check (user_id = auth.uid() and status = 'pending');

drop policy if exists "Users submit reports" on public.reports;
create policy "Users submit reports" on public.reports for insert to anon, authenticated with check (true);
drop policy if exists "Users read own reports" on public.reports;
create policy "Users read own reports" on public.reports for select to authenticated using (reporter_id = auth.uid());

-- Create a public bucket for listing photos. Uploads should be limited to safe image MIME types.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('ad-images','ad-images',true,5242880,array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

drop policy if exists "Public read ad images" on storage.objects;
create policy "Public read ad images" on storage.objects for select using (bucket_id = 'ad-images');
drop policy if exists "Visitors upload ad images" on storage.objects;
create policy "Visitors upload ad images" on storage.objects for insert to anon, authenticated with check (bucket_id = 'ad-images');

-- Explicit Data API grants (RLS remains the row-level security boundary).
grant usage on schema public to anon, authenticated;
grant select on public.categories to anon, authenticated;
grant select, insert on public.ads to anon, authenticated;
grant update, delete on public.ads to authenticated;
grant select, insert on public.ad_images to anon, authenticated;
grant select, insert, update, delete on public.profiles to authenticated;
grant select, insert, update, delete on public.favorites to authenticated;
grant select, insert, update, delete on public.likes to authenticated;
grant select on public.comments to anon, authenticated;
grant insert on public.comments to authenticated;
grant select, insert on public.reports to anon, authenticated;

-- Keep private profile fields private; users can read only their own profile.
drop policy if exists "Profiles are publicly readable" on public.profiles;
drop policy if exists "Users read own profile" on public.profiles;
create policy "Users read own profile" on public.profiles for select to authenticated using (id = auth.uid());

-- Uploading files requires an account and stores them under that account's folder.
drop policy if exists "Visitors upload ad images" on storage.objects;
drop policy if exists "Authenticated users upload own ad images" on storage.objects;
create policy "Authenticated users upload own ad images" on storage.objects
for insert to authenticated
with check (
  bucket_id = 'ad-images'
  and (storage.foldername(name))[1] = 'ads'
  and (storage.foldername(name))[2] = auth.uid()::text
);
