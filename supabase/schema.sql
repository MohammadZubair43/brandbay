-- =====================================================================
-- BrandBay live database (Supabase / Postgres)
-- Run this once in Supabase: SQL Editor -> New query -> paste -> Run.
-- Safe to re-run on an empty project only.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. PROFILES  (one row per signed-up user, linked to auth.users)
-- ---------------------------------------------------------------------
create table public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  role        text not null check (role in ('business','pro','influencer','employee')),
  status      text not null default 'Unverified' check (status in ('Active','Unverified','Suspended')),
  name        text not null,
  email       text not null,
  phone       text,
  -- business
  company     text,
  industry    text,
  address     text,
  -- social media manager / influencer
  handle      text,
  followers   text,
  rate        integer,
  bio         text,
  niche       text,     -- manager
  category    text,     -- influencer
  city        text,     -- influencer
  -- employee
  dept        text,
  created_at  timestamptz not null default now()
);

-- Is the current user an active BrandBay employee?
create or replace function public.is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from profiles where id = auth.uid() and role = 'employee' and status = 'Active');
$$;

create or replace function public.my_role() returns text
language sql stable security definer set search_path = public as $$
  select role from profiles where id = auth.uid();
$$;

create or replace function public.profile_name(uid uuid) returns text
language sql stable security definer set search_path = public as $$
  select coalesce(company, name) from profiles where id = uid;
$$;

-- Create the profile automatically when someone signs up.
-- The app sends role and details as sign-up metadata.
-- Nobody can sign up as an employee: staff are promoted by an admin (see SETUP.md).
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  m jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  r text  := coalesce(m->>'role', 'business');
begin
  if r not in ('business','pro','influencer') then r := 'business'; end if;
  insert into profiles(id, role, status, name, email, phone, company, industry, address,
                       handle, followers, rate, bio, niche, category, city)
  values (new.id, r,
          case when r = 'business' then 'Active' else 'Unverified' end,
          coalesce(nullif(m->>'name',''), split_part(new.email,'@',1)),
          new.email, m->>'phone', m->>'company', m->>'industry', m->>'address',
          m->>'handle', m->>'followers', nullif(m->>'rate','')::integer, m->>'bio',
          m->>'niche', m->>'category', m->>'city');
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Users may edit their own details, but only staff may change role or status.
create or replace function public.guard_profile() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and not is_staff() and (new.role is distinct from old.role or new.status is distinct from old.status
                         or new.email is distinct from old.email) then
    raise exception 'Only the BrandBay team can change role, status or email';
  end if;
  return new;
end $$;
create trigger guard_profile before update on public.profiles
  for each row execute function public.guard_profile();

alter table public.profiles enable row level security;
create policy "see own profile or staff sees all" on public.profiles
  for select using (id = auth.uid() or is_staff());
create policy "edit own profile or staff edits any" on public.profiles
  for update using (id = auth.uid() or is_staff());

-- Public directory: what other users may see about each other (no email or phone).
create view public.directory as
  select id, role, status, name, company, industry, address, handle, followers, rate,
         bio, niche, category, city, created_at
  from public.profiles
  where status = 'Active' or id = auth.uid();
grant select on public.directory to authenticated;

-- ---------------------------------------------------------------------
-- 2. CAMPAIGNS (requests from businesses)
-- ---------------------------------------------------------------------
create table public.campaigns (
  id          bigint generated always as identity (start with 1001) primary key,
  ref         text generated always as ('BB-' || id::text) stored,
  business_id uuid not null references public.profiles(id) on delete cascade,
  manager_id  uuid references public.profiles(id) on delete set null,
  title       text not null,
  goal        text,
  audience    text,
  package     text not null default 'Custom',
  platforms   text[] not null default '{}',
  services    text[] not null default '{}',
  budget      integer not null check (budget >= 1000),
  stage       text not null default 'Submitted' check (stage in ('Submitted','Research','Content','Live')),
  deadline    date,
  notes       text,
  research    jsonb not null default '{"audience":"","competitors":"","hashtags":""}',
  created_at  timestamptz not null default now()
);

create or replace function public.is_member(cid bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select is_staff() or exists(select 1 from campaigns c where c.id = cid
         and (c.business_id = auth.uid() or c.manager_id = auth.uid()));
$$;

-- What each role may change on a campaign.
create or replace function public.guard_campaign() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or is_staff() then return new; end if;  -- admin (SQL editor) or team
  if new.business_id is distinct from old.business_id or new.budget is distinct from old.budget
     or new.package is distinct from old.package then
    raise exception 'Only the BrandBay team can change the business, budget or package';
  end if;
  if old.business_id = auth.uid() then
    if new.manager_id is distinct from old.manager_id or new.stage is distinct from old.stage
       or new.research is distinct from old.research then
      raise exception 'Businesses cannot change the manager, stage or research brief';
    end if;
  elsif my_role() = 'pro' then
    -- a manager may accept an open campaign (assign themselves) and move its stage
    if new.manager_id is distinct from old.manager_id and not (old.manager_id is null and new.manager_id = auth.uid()) then
      raise exception 'Managers can only assign an open campaign to themselves';
    end if;
    if new.title is distinct from old.title or new.goal is distinct from old.goal or new.research is distinct from old.research then
      raise exception 'Managers cannot edit the request details or research brief';
    end if;
  end if;
  return new;
end $$;
create trigger guard_campaign before update on public.campaigns
  for each row execute function public.guard_campaign();

alter table public.campaigns enable row level security;
create or replace function public.is_active_role(r text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from profiles where id = auth.uid() and role = r and status = 'Active');
$$;
create or replace function public.is_active_influencer(uid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from profiles where id = uid and role = 'influencer' and status = 'Active');
$$;

create policy "members, staff, and managers browsing open campaigns can see" on public.campaigns
  for select using (business_id = auth.uid() or manager_id = auth.uid() or is_staff()
                    or (manager_id is null and is_active_role('pro')));
create policy "businesses create their own requests" on public.campaigns
  for insert with check (business_id = auth.uid() and my_role() = 'business'
                         and stage = 'Submitted' and manager_id is null);
create policy "members and open-campaign managers can update" on public.campaigns
  for update using (business_id = auth.uid() or manager_id = auth.uid() or is_staff()
                    or (manager_id is null and is_active_role('pro')))
  with check (business_id = auth.uid() or manager_id = auth.uid() or is_staff());

-- ---------------------------------------------------------------------
-- 3. CONTENT DRAFTS (manager -> business approval)
-- ---------------------------------------------------------------------
create table public.drafts (
  id          bigint generated always as identity primary key,
  campaign_id bigint not null references public.campaigns(id) on delete cascade,
  manager_id  uuid not null references public.profiles(id),
  type        text not null check (type in ('Post','Reel','Story')),
  platform    text not null,
  caption     text not null,
  hashtags    text,
  post_date   date not null,
  status      text not null default 'Pending' check (status in ('Pending','Approved','Changes')),
  feedback    text,
  created_at  timestamptz not null default now()
);

create or replace function public.guard_draft() returns trigger
language plpgsql security definer set search_path = public as $$
declare biz uuid;
begin
  if auth.uid() is null or is_staff() then return new; end if;  -- admin (SQL editor) or team
  select business_id into biz from campaigns where id = old.campaign_id;
  if biz = auth.uid() then
    if new.caption is distinct from old.caption or new.post_date is distinct from old.post_date
       or new.type is distinct from old.type or new.platform is distinct from old.platform
       or new.status not in ('Approved','Changes') or old.status <> 'Pending' then
      raise exception 'Businesses can only approve a pending draft or ask for changes';
    end if;
  elsif old.manager_id = auth.uid() then
    if new.status = 'Approved' and old.status <> 'Approved' then
      raise exception 'Only the business can approve a draft';
    end if;
  end if;
  return new;
end $$;
create trigger guard_draft before update on public.drafts
  for each row execute function public.guard_draft();

alter table public.drafts enable row level security;
create policy "campaign members see drafts" on public.drafts for select using (is_member(campaign_id));
create policy "assigned manager submits drafts" on public.drafts for insert
  with check (manager_id = auth.uid() and status = 'Pending' and exists(
    select 1 from campaigns c where c.id = campaign_id and c.manager_id = auth.uid()));
create policy "members update drafts" on public.drafts for update using (is_member(campaign_id));

-- ---------------------------------------------------------------------
-- 4. MESSAGES (one thread per campaign)
-- ---------------------------------------------------------------------
create table public.messages (
  id          bigint generated always as identity primary key,
  campaign_id bigint not null references public.campaigns(id) on delete cascade,
  sender_id   uuid not null references public.profiles(id),
  body        text not null check (length(body) between 1 and 4000),
  created_at  timestamptz not null default now()
);
alter table public.messages enable row level security;
create policy "members read the thread" on public.messages for select using (is_member(campaign_id));
create policy "members post as themselves" on public.messages for insert
  with check (sender_id = auth.uid() and is_member(campaign_id));

-- ---------------------------------------------------------------------
-- 5. INVOICES  (created automatically; marked paid by the team until Razorpay is added)
-- ---------------------------------------------------------------------
create table public.invoices (
  id          bigint generated always as identity (start with 201) primary key,
  ref         text generated always as ('INV-' || id::text) stored,
  campaign_id bigint not null references public.campaigns(id) on delete cascade,
  business_id uuid not null references public.profiles(id),
  amount      integer not null,
  status      text not null default 'Due' check (status in ('Due','Paid')),
  due         date not null default (current_date + 7),
  paid_at     timestamptz,
  created_at  timestamptz not null default now()
);
alter table public.invoices enable row level security;
create policy "business, manager and staff see invoices" on public.invoices for select
  using (business_id = auth.uid() or is_member(campaign_id));
create policy "only staff update invoices" on public.invoices for update using (is_staff());

-- ---------------------------------------------------------------------
-- 6. REVIEWS (business rates the manager after Live)
-- ---------------------------------------------------------------------
create table public.reviews (
  id          bigint generated always as identity primary key,
  campaign_id bigint not null unique references public.campaigns(id) on delete cascade,
  manager_id  uuid not null references public.profiles(id),
  business_id uuid not null references public.profiles(id),
  stars       smallint not null check (stars between 1 and 5),
  body        text,
  created_at  timestamptz not null default now()
);
alter table public.reviews enable row level security;
create policy "signed-in users read reviews" on public.reviews for select using (auth.uid() is not null);
create policy "business reviews its live campaign" on public.reviews for insert
  with check (business_id = auth.uid() and exists(select 1 from campaigns c where c.id = campaign_id
              and c.business_id = auth.uid() and c.stage = 'Live' and c.manager_id = reviews.manager_id));

-- ---------------------------------------------------------------------
-- 7. BRAND KITS, SOCIAL ACCOUNTS, OWN POSTS (business tools)
-- ---------------------------------------------------------------------
create table public.brand_kits (
  business_id uuid primary key references public.profiles(id) on delete cascade,
  tone        text, colors text[] not null default '{}', hashtags text, audience text, dos text, donts text,
  updated_at  timestamptz not null default now()
);
alter table public.brand_kits enable row level security;
create policy "owner, staff and their managers read the kit" on public.brand_kits for select
  using (business_id = auth.uid() or is_staff() or exists(select 1 from campaigns c
         where c.business_id = brand_kits.business_id and c.manager_id = auth.uid()));
create policy "owner writes the kit" on public.brand_kits for insert with check (business_id = auth.uid());
create policy "owner updates the kit" on public.brand_kits for update using (business_id = auth.uid());

-- Phase 3 connects these to the real platforms; for now they hold the handle and numbers.
create table public.social_accounts (
  business_id uuid not null references public.profiles(id) on delete cascade,
  platform    text not null,
  connected   boolean not null default false,
  handle      text, followers integer not null default 0, growth integer not null default 0,
  primary key (business_id, platform)
);
alter table public.social_accounts enable row level security;
create policy "owner and staff manage social accounts" on public.social_accounts for all
  using (business_id = auth.uid() or is_staff()) with check (business_id = auth.uid() or is_staff());

create table public.posts (
  id          bigint generated always as identity primary key,
  business_id uuid not null references public.profiles(id) on delete cascade,
  platform    text not null,
  type        text not null check (type in ('Post','Reel','Story')),
  caption     text not null,
  hashtags    text,
  post_date   date not null,
  post_time   time not null default '18:00',
  status      text not null default 'Scheduled' check (status in ('Scheduled','Posted')),
  created_at  timestamptz not null default now()
);
alter table public.posts enable row level security;
create policy "owner and staff manage posts" on public.posts for all
  using (business_id = auth.uid() or is_staff()) with check (business_id = auth.uid() or is_staff());

-- ---------------------------------------------------------------------
-- 8. INFLUENCER BOOKINGS
-- ---------------------------------------------------------------------
create table public.bookings (
  id            bigint generated always as identity (start with 301) primary key,
  ref           text generated always as ('BK-' || id::text) stored,
  influencer_id uuid not null references public.profiles(id),
  business_id   uuid not null references public.profiles(id),
  campaign_id   bigint references public.campaigns(id) on delete set null,
  booked_by     uuid not null references public.profiles(id),
  shoot_date    date not null,
  shoot_time    time not null,
  location      text not null,
  deliverable   text not null,
  fee           integer not null check (fee >= 0),
  brief         text,
  status        text not null default 'Requested'
                check (status in ('Requested','Accepted','Declined','Uploaded','Reshoot','Approved','Cancelled')),
  upload_link   text,
  upload_path   text,          -- file in storage bucket "uploads"
  caption       text,
  feedback      text,
  created_at    timestamptz not null default now()
);

create or replace function public.can_see_booking(b public.bookings) returns boolean
language sql stable security definer set search_path = public as $$
  select is_staff() or auth.uid() in (b.influencer_id, b.business_id, b.booked_by)
         or (b.campaign_id is not null and exists(select 1 from campaigns c where c.id = b.campaign_id and c.manager_id = auth.uid()));
$$;

-- Who may move a booking to which status.
create or replace function public.guard_booking() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or is_staff() then return new; end if;  -- admin (SQL editor) or team
  if new.influencer_id is distinct from old.influencer_id or new.business_id is distinct from old.business_id
     or new.fee is distinct from old.fee then
    raise exception 'The influencer, business and fee cannot be changed after booking';
  end if;
  if new.status = old.status then return new; end if;
  if auth.uid() = old.influencer_id then
    if not ((old.status = 'Requested' and new.status in ('Accepted','Declined'))
         or (old.status in ('Accepted','Reshoot') and new.status = 'Uploaded')) then
      raise exception 'Influencers can accept or decline a request, then upload content';
    end if;
  else
    if not ((old.status = 'Uploaded' and new.status in ('Approved','Reshoot'))
         or (old.status in ('Requested','Accepted') and new.status = 'Cancelled')) then
      raise exception 'Brands can approve or ask for changes on uploads, or cancel before the shoot';
    end if;
  end if;
  return new;
end $$;
create trigger guard_booking before update on public.bookings
  for each row execute function public.guard_booking();

alter table public.bookings enable row level security;
create policy "people on the booking see it" on public.bookings for select using (can_see_booking(bookings));
create policy "business, its manager or staff book" on public.bookings for insert
  with check (booked_by = auth.uid() and status = 'Requested' and shoot_date >= current_date
    and is_active_influencer(influencer_id)
    and (is_staff()
         or (business_id = auth.uid() and my_role() = 'business')
         or (campaign_id is not null and exists(select 1 from campaigns c where c.id = campaign_id
             and c.manager_id = auth.uid() and c.business_id = bookings.business_id))));
create policy "people on the booking update it" on public.bookings for update using (can_see_booking(bookings));

-- ---------------------------------------------------------------------
-- 9. NOTIFICATIONS + ACTIVITY LOG (written only by the triggers below)
-- ---------------------------------------------------------------------
create table public.notifications (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  body       text not null,
  link       text,
  read       boolean not null default false,
  created_at timestamptz not null default now()
);
alter table public.notifications enable row level security;
create policy "read own notifications" on public.notifications for select using (user_id = auth.uid());
create policy "mark own notifications read" on public.notifications for update using (user_id = auth.uid());

create table public.activity (
  id          bigint generated always as identity primary key,
  campaign_id bigint references public.campaigns(id) on delete cascade,
  actor_id    uuid references public.profiles(id) on delete set null,
  body        text not null,
  created_at  timestamptz not null default now()
);
alter table public.activity enable row level security;
create policy "staff see everything, members see their campaign" on public.activity for select
  using (is_staff() or (campaign_id is not null and is_member(campaign_id)));

create or replace function public.notify(uids uuid[], msg text, lnk text) returns void
language sql security definer set search_path = public as $$
  insert into notifications(user_id, body, link)
  select distinct u, msg, lnk from unnest(uids) as t(u)
  where u is not null and u is distinct from auth.uid();
$$;

create or replace function public.staff_ids() returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(id), '{}') from profiles where role = 'employee' and status = 'Active';
$$;

create or replace function public.log(cid bigint, msg text) returns void
language sql security definer set search_path = public as $$
  insert into activity(campaign_id, actor_id, body) values (cid, auth.uid(), msg);
$$;

-- New user -> tell the team if they need verifying
create or replace function public.on_profile_created() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'Unverified' then
    perform notify(staff_ids(), new.name || ' registered as ' ||
      case new.role when 'pro' then 'Social Media Manager' when 'influencer' then 'Influencer' else 'Business' end ||
      ' and needs verification', 'users');
  end if;
  perform notify(array[new.id], 'Welcome to BrandBay, ' || split_part(new.name,' ',1) || '!' ||
    case when new.status = 'Unverified' then ' Our team will verify your account soon.' else '' end, 'overview');
  insert into activity(actor_id, body) values (new.id, new.name || ' registered');
  return new;
end $$;
create trigger on_profile_created after insert on public.profiles
  for each row execute function public.on_profile_created();

-- Profile verified
create or replace function public.on_profile_status() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'Active' and old.status <> 'Active' then
    perform notify(array[new.id], 'Your BrandBay account is verified. You''re all set!', 'overview');
    perform log(null, profile_name(auth.uid()) || ' verified ' || new.name);
  elsif new.status = 'Suspended' and old.status <> 'Suspended' then
    perform log(null, profile_name(auth.uid()) || ' suspended ' || new.name);
  end if;
  return new;
end $$;
create trigger on_profile_status after update of status on public.profiles
  for each row execute function public.on_profile_status();

-- New campaign -> invoice + tell team and active managers
create or replace function public.on_campaign_created() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into invoices(campaign_id, business_id, amount) values (new.id, new.business_id, new.budget);
  perform notify(staff_ids(), 'New request from ' || profile_name(new.business_id) || ': ' || new.title, 'c-' || new.ref);
  perform notify((select array_agg(id) from profiles where role = 'pro' and status = 'Active'),
                 'New campaign open: ' || new.title, 'market');
  perform log(new.id, profile_name(new.business_id) || ' submitted ' || new.title);
  return new;
end $$;
create trigger on_campaign_created after insert on public.campaigns
  for each row execute function public.on_campaign_created();

-- Manager assigned / stage moved
create or replace function public.on_campaign_updated() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.manager_id is distinct from old.manager_id and new.manager_id is not null then
    perform notify(array[new.manager_id], 'You''re now managing ' || new.title, 'c-' || new.ref);
    perform notify(array[new.business_id] || staff_ids(), profile_name(new.manager_id) || ' will manage ' || new.title, 'c-' || new.ref);
    perform log(new.id, profile_name(new.manager_id) || ' was assigned to ' || new.ref);
  end if;
  if new.stage is distinct from old.stage then
    perform notify(array[new.business_id, new.manager_id] || staff_ids(), new.title || ' moved to ' || new.stage, 'c-' || new.ref);
    perform log(new.id, profile_name(auth.uid()) || ' moved ' || new.ref || ' to ' || new.stage);
  end if;
  if new.research is distinct from old.research then
    perform notify(array[new.business_id, new.manager_id], 'Research brief updated for ' || new.title, 'c-' || new.ref);
    perform log(new.id, profile_name(auth.uid()) || ' updated the research brief');
  end if;
  return new;
end $$;
create trigger on_campaign_updated after update on public.campaigns
  for each row execute function public.on_campaign_updated();

-- Drafts
create or replace function public.on_draft() returns trigger
language plpgsql security definer set search_path = public as $$
declare c campaigns;
begin
  select * into c from campaigns where id = new.campaign_id;
  if tg_op = 'INSERT' then
    if c.stage in ('Submitted','Research') then update campaigns set stage = 'Content' where id = c.id; end if;
    perform notify(array[c.business_id], profile_name(new.manager_id) || ' sent a new ' || new.type || ' for approval', 'approvals');
    perform log(c.id, profile_name(new.manager_id) || ' submitted a ' || new.type || ' draft');
  elsif new.status is distinct from old.status then
    if new.status = 'Approved' then
      perform notify(array[new.manager_id], profile_name(c.business_id) || ' approved your ' || new.type || ' for ' || c.title, 'c-' || c.ref);
      perform log(c.id, profile_name(c.business_id) || ' approved a ' || new.type || ' draft');
    elsif new.status = 'Changes' then
      perform notify(array[new.manager_id], profile_name(c.business_id) || ' asked for changes on a ' || new.type || ': ' || coalesce(new.feedback,''), 'c-' || c.ref);
      perform log(c.id, profile_name(c.business_id) || ' requested changes on a ' || new.type || ' draft');
    elsif new.status = 'Pending' then
      perform notify(array[c.business_id], profile_name(new.manager_id) || ' updated a ' || new.type || ' draft', 'approvals');
      perform log(c.id, profile_name(new.manager_id) || ' resubmitted a ' || new.type || ' draft');
    end if;
  end if;
  return new;
end $$;
create trigger on_draft after insert or update on public.drafts
  for each row execute function public.on_draft();

-- Messages
create or replace function public.on_message() returns trigger
language plpgsql security definer set search_path = public as $$
declare c campaigns;
begin
  select * into c from campaigns where id = new.campaign_id;
  perform notify(array[c.business_id, c.manager_id] || staff_ids(),
    profile_name(new.sender_id) || ' in ' || c.title || ': ' || left(new.body, 60), 'messages');
  return new;
end $$;
create trigger on_message after insert on public.messages
  for each row execute function public.on_message();

-- Invoice paid
create or replace function public.on_invoice() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'Paid' and old.status <> 'Paid' then
    new.paid_at := now();
    perform notify(array[new.business_id], 'Payment received for INV-' || new.id || ' (₹' || to_char(new.amount, 'FM9,999,999') || '). Thank you!', 'billing');
    perform log(new.campaign_id, 'INV-' || new.id || ' marked as paid');
  end if;
  return new;
end $$;
create trigger on_invoice before update on public.invoices
  for each row execute function public.on_invoice();

-- Reviews
create or replace function public.on_review() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform notify(array[new.manager_id], profile_name(new.business_id) || ' left you a ' || new.stars || '-star review', 'settings');
  perform log(new.campaign_id, profile_name(new.business_id) || ' rated ' || profile_name(new.manager_id) || ' ' || new.stars || ' stars');
  return new;
end $$;
create trigger on_review after insert on public.reviews
  for each row execute function public.on_review();

-- Bookings: the influencer is told where and when; everyone is kept in the loop
create or replace function public.on_booking() returns trigger
language plpgsql security definer set search_path = public as $$
declare who text := profile_name(new.influencer_id); biz text := profile_name(new.business_id);
        others uuid[] := array[new.business_id, new.booked_by] || staff_ids();
begin
  if tg_op = 'INSERT' then
    perform notify(array[new.influencer_id],
      'New shoot from ' || biz || ' (' || new.deliverable || '): please come on ' || to_char(new.shoot_date, 'Dy, DD Mon') ||
      ' at ' || to_char(new.shoot_time, 'HH24:MI') || '. 📍 ' || new.location ||
      '. Fee ₹' || to_char(new.fee, 'FM9,999,999') || '.', 'bookings');
    perform notify(others, profile_name(new.booked_by) || ' booked ' || who || ' for ' || new.deliverable || ' on ' || to_char(new.shoot_date, 'DD Mon'), 'influencers');
    perform log(new.campaign_id, profile_name(new.booked_by) || ' booked ' || who || ' for ' || biz || ' (' || new.ref || ')');
  elsif new.status is distinct from old.status then
    case new.status
      when 'Accepted' then perform notify(others, who || ' accepted the shoot on ' || to_char(new.shoot_date, 'DD Mon') || ' at ' || to_char(new.shoot_time,'HH24:MI'), 'influencers');
      when 'Declined' then perform notify(others, who || ' declined the shoot on ' || to_char(new.shoot_date, 'DD Mon') || '. Try booking another influencer.', 'influencers');
      when 'Uploaded' then perform notify(others, who || ' uploaded the ' || new.deliverable || ' for ' || biz || '. Please review it.', 'influencers');
      when 'Approved' then perform notify(array[new.influencer_id], biz || ' approved your ' || new.deliverable || '. ₹' || to_char(new.fee, 'FM9,999,999') || ' will be released.', 'earnings');
      when 'Reshoot'  then perform notify(array[new.influencer_id], biz || ' asked for changes on your ' || new.deliverable || ': ' || coalesce(new.feedback,''), 'bookings');
      when 'Cancelled' then perform notify(array[new.influencer_id], biz || ' cancelled the shoot on ' || to_char(new.shoot_date, 'DD Mon'), 'bookings');
      else null;
    end case;
    perform log(new.campaign_id, profile_name(auth.uid()) || ' set ' || new.ref || ' to ' || new.status);
  end if;
  return new;
end $$;
create trigger on_booking after insert or update on public.bookings
  for each row execute function public.on_booking();

-- A small RPC so any member can send a booking reminder without write access to notifications
create or replace function public.remind_booking(bid bigint) returns void
language plpgsql security definer set search_path = public as $$
declare b bookings;
begin
  select * into b from bookings where id = bid;
  if b.id is null or not can_see_booking(b) or auth.uid() = b.influencer_id then
    raise exception 'Not allowed';
  end if;
  perform notify(array[b.influencer_id], 'Reminder: ' || b.deliverable || ' shoot at ' || b.location || ' on ' ||
    to_char(b.shoot_date, 'Dy, DD Mon') || ' at ' || to_char(b.shoot_time,'HH24:MI'), 'bookings');
end $$;

-- ---------------------------------------------------------------------
-- 10. FILE UPLOADS (influencer videos) in a private bucket
--     Files are stored as  bookings/<booking id>/<file name>
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public) values ('uploads', 'uploads', false)
  on conflict (id) do nothing;

create policy "influencer uploads to own booking" on storage.objects for insert to authenticated
  with check (bucket_id = 'uploads' and (storage.foldername(name))[1] = 'bookings'
    and exists(select 1 from public.bookings b where b.id::text = (storage.foldername(name))[2]
               and b.influencer_id = auth.uid() and b.status in ('Accepted','Reshoot')));
create policy "people on the booking can view its files" on storage.objects for select to authenticated
  using (bucket_id = 'uploads' and (storage.foldername(name))[1] = 'bookings'
    and exists(select 1 from public.bookings b where b.id::text = (storage.foldername(name))[2]
               and public.can_see_booking(b)));

-- ---------------------------------------------------------------------
-- 11. LIVE UPDATES  (new notifications and chat messages appear instantly)
-- ---------------------------------------------------------------------
do $$ begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.notifications, public.messages;
  end if;
end $$;

-- Helpful indexes
create index on public.campaigns (business_id);
create index on public.campaigns (manager_id);
create index on public.drafts (campaign_id);
create index on public.messages (campaign_id, created_at);
create index on public.bookings (influencer_id);
create index on public.bookings (business_id);
create index on public.notifications (user_id, created_at desc);
create index on public.activity (created_at desc);
-- BrandBay update 002: lets the team send a payment reminder for an invoice.
create or replace function public.remind_invoice(iid bigint) returns void
language plpgsql security definer set search_path = public as $$
declare i invoices;
begin
  if not is_staff() then raise exception 'Only the BrandBay team can send payment reminders'; end if;
  select * into i from invoices where id = iid;
  if i.id is null then raise exception 'Invoice not found'; end if;
  perform notify(array[i.business_id], 'Reminder: INV-' || i.id || ' for ₹' || to_char(i.amount, 'FM9,999,999') ||
    ' is due on ' || to_char(i.due, 'DD Mon') || '.', 'billing');
end $$;
