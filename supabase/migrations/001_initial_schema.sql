-- Create users table extension (Supabase auth.users is built-in)
create table if not exists public.profiles (
  id uuid references auth.users on delete cascade primary key,
  email text unique not null,
  name text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- Create business managers table
create table if not exists public.business_managers (
  id uuid default gen_random_uuid() primary key,
  name text not null,
  facebook_id text unique not null,
  access_token text,
  status text default 'active',
  user_id uuid references public.profiles(id) on delete cascade not null,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- Create ad accounts table
create table if not exists public.ad_accounts (
  id uuid default gen_random_uuid() primary key,
  name text not null,
  facebook_id text unique not null,
  account_status text not null,
  currency text not null,
  timezone text,
  business_manager_id uuid references public.business_managers(id) on delete cascade not null,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- Create pixels table
create table if not exists public.pixels (
  id uuid default gen_random_uuid() primary key,
  name text not null,
  facebook_id text unique not null,
  status text not null,
  business_manager_id uuid references public.business_managers(id) on delete cascade not null,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- Create campaigns table
create table if not exists public.campaigns (
  id uuid default gen_random_uuid() primary key,
  name text not null,
  facebook_id text unique not null,
  objective text not null,
  status text not null,
  daily_budget numeric,
  total_budget numeric,
  start_date timestamptz,
  end_date timestamptz,
  business_manager_id uuid references public.business_managers(id) on delete cascade not null,
  ad_account_id uuid references public.ad_accounts(id) on delete cascade not null,
  pixel_id uuid references public.pixels(id),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- Create ad sets table
create table if not exists public.ad_sets (
  id uuid default gen_random_uuid() primary key,
  name text not null,
  facebook_id text unique not null,
  status text not null,
  daily_budget numeric,
  total_budget numeric,
  bid_strategy text,
  optimization text,
  targeting jsonb,
  start_date timestamptz,
  end_date timestamptz,
  campaign_id uuid references public.campaigns(id) on delete cascade not null,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- Create ads table
create table if not exists public.ads (
  id uuid default gen_random_uuid() primary key,
  name text not null,
  facebook_id text unique not null,
  status text not null,
  creative jsonb,
  ad_type text,
  ad_set_id uuid references public.ad_sets(id) on delete cascade not null,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- Create change logs table
create table if not exists public.change_logs (
  id uuid default gen_random_uuid() primary key,
  entity_type text not null,
  entity_id uuid not null,
  action text not null,
  old_values jsonb,
  new_values jsonb,
  description text,
  user_id uuid references public.profiles(id) on delete cascade not null,
  created_at timestamptz default now()
);

-- Create indexes
create index if not exists idx_business_managers_user_id on public.business_managers(user_id);
create index if not exists idx_ad_accounts_business_manager_id on public.ad_accounts(business_manager_id);
create index if not exists idx_pixels_business_manager_id on public.pixels(business_manager_id);
create index if not exists idx_campaigns_business_manager_id on public.campaigns(business_manager_id);
create index if not exists idx_campaigns_ad_account_id on public.campaigns(ad_account_id);
create index if not exists idx_ad_sets_campaign_id on public.ad_sets(campaign_id);
create index if not exists idx_ads_ad_set_id on public.ads(ad_set_id);
create index if not exists idx_change_logs_entity on public.change_logs(entity_type, entity_id);
create index if not exists idx_change_logs_user_id on public.change_logs(user_id);

-- Enable Row Level Security
alter table public.profiles enable row level security;
alter table public.business_managers enable row level security;
alter table public.ad_accounts enable row level security;
alter table public.pixels enable row level security;
alter table public.campaigns enable row level security;
alter table public.ad_sets enable row level security;
alter table public.ads enable row level security;
alter table public.change_logs enable row level security;

-- Create RLS policies
-- Profiles
create policy "Users can view own profile" on public.profiles
  for select using (auth.uid() = id);
create policy "Users can update own profile" on public.profiles
  for update using (auth.uid() = id);

-- Business Managers
create policy "Users can view own business managers" on public.business_managers
  for select using (auth.uid() = user_id);
create policy "Users can insert own business managers" on public.business_managers
  for insert with check (auth.uid() = user_id);
create policy "Users can update own business managers" on public.business_managers
  for update using (auth.uid() = user_id);
create policy "Users can delete own business managers" on public.business_managers
  for delete using (auth.uid() = user_id);

-- Ad Accounts
create policy "Users can view own ad accounts" on public.ad_accounts
  for select using (
    auth.uid() in (
      select user_id from public.business_managers
      where id = business_manager_id
    )
  );
create policy "Users can insert own ad accounts" on public.ad_accounts
  for insert with check (
    auth.uid() in (
      select user_id from public.business_managers
      where id = business_manager_id
    )
  );
create policy "Users can update own ad accounts" on public.ad_accounts
  for update using (
    auth.uid() in (
      select user_id from public.business_managers
      where id = business_manager_id
    )
  );
create policy "Users can delete own ad accounts" on public.ad_accounts
  for delete using (
    auth.uid() in (
      select user_id from public.business_managers
      where id = business_manager_id
    )
  );

-- Similar policies for other tables...
-- (Pixels, Campaigns, Ad Sets, Ads, Change Logs follow the same pattern)

-- Function to automatically create profile on user signup
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, email, name)
  values (new.id, new.email, new.raw_user_meta_data->>'name');
  return new;
end;
$$ language plpgsql security definer;

-- Trigger to create profile on signup
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- Function to update updated_at timestamp
create or replace function public.update_updated_at_column()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

-- Add updated_at triggers to all tables
create trigger update_profiles_updated_at before update on public.profiles
  for each row execute procedure public.update_updated_at_column();
create trigger update_business_managers_updated_at before update on public.business_managers
  for each row execute procedure public.update_updated_at_column();
create trigger update_ad_accounts_updated_at before update on public.ad_accounts
  for each row execute procedure public.update_updated_at_column();
create trigger update_pixels_updated_at before update on public.pixels
  for each row execute procedure public.update_updated_at_column();
create trigger update_campaigns_updated_at before update on public.campaigns
  for each row execute procedure public.update_updated_at_column();
create trigger update_ad_sets_updated_at before update on public.ad_sets
  for each row execute procedure public.update_updated_at_column();
create trigger update_ads_updated_at before update on public.ads
  for each row execute procedure public.update_updated_at_column();