-- BrandBay update 007: prices in US dollars, and packages per industry managed by the team.

-- 1. Packages
create table if not exists public.packages (
  id          bigint generated always as identity primary key,
  niche       text not null,
  name        text not null,
  price       integer not null check (price >= 0),
  period      text not null default 'month' check (period in ('month','once')),
  description text,
  features    text[] not null default '{}',
  active      boolean not null default true,
  sort        integer not null default 0,
  created_at  timestamptz not null default now()
);
alter table public.packages enable row level security;
drop policy if exists "anyone sees packages on the website" on public.packages;
drop policy if exists "team sees all packages" on public.packages;
drop policy if exists "team manages packages" on public.packages;
create policy "anyone sees packages on the website" on public.packages for select using (active);
create policy "team sees all packages" on public.packages for select using (is_staff());
create policy "team manages packages" on public.packages for all using (is_staff()) with check (is_staff());
grant select on public.packages to anon;

-- 2. Budgets in dollars: minimum $100
alter table public.campaigns drop constraint if exists campaigns_budget_check;
alter table public.campaigns add constraint campaigns_budget_check check (budget >= 100);

-- 3. Notifications show $ instead of ₹
create or replace function public.on_invoice() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'Paid' and old.status <> 'Paid' then
    new.paid_at := now();
    perform notify(array[new.business_id], 'Payment received for INV-' || new.id || ' ($' || to_char(new.amount, 'FM9,999,999') || '). Thank you!', 'billing');
    perform log(new.campaign_id, 'INV-' || new.id || ' marked as paid');
  end if;
  return new;
end $$;

create or replace function public.on_booking() returns trigger
language plpgsql security definer set search_path = public as $$
declare who text := profile_name(new.influencer_id); biz text := profile_name(new.business_id);
        others uuid[] := array[new.business_id, new.booked_by] || staff_ids();
begin
  if tg_op = 'INSERT' then
    perform notify(array[new.influencer_id],
      'New shoot from ' || biz || ' (' || new.deliverable || '): please come on ' || to_char(new.shoot_date, 'Dy, DD Mon') ||
      ' at ' || to_char(new.shoot_time, 'HH24:MI') || '. 📍 ' || new.location ||
      '. Fee $' || to_char(new.fee, 'FM9,999,999') || '.', 'bookings');
    perform notify(others, profile_name(new.booked_by) || ' booked ' || who || ' for ' || new.deliverable || ' on ' || to_char(new.shoot_date, 'DD Mon'), 'influencers');
    perform log(new.campaign_id, profile_name(new.booked_by) || ' booked ' || who || ' for ' || biz || ' (' || new.ref || ')');
  elsif new.status is distinct from old.status then
    case new.status
      when 'Accepted' then perform notify(others, who || ' accepted the shoot on ' || to_char(new.shoot_date, 'DD Mon') || ' at ' || to_char(new.shoot_time,'HH24:MI'), 'influencers');
      when 'Declined' then perform notify(others, who || ' declined the shoot on ' || to_char(new.shoot_date, 'DD Mon') || '. Try booking another influencer.', 'influencers');
      when 'Uploaded' then perform notify(others, who || ' uploaded the ' || new.deliverable || ' for ' || biz || '. Please review it.', 'influencers');
      when 'Approved' then perform notify(array[new.influencer_id], biz || ' approved your ' || new.deliverable || '. $' || to_char(new.fee, 'FM9,999,999') || ' will be released.', 'earnings');
      when 'Reshoot'  then perform notify(array[new.influencer_id], biz || ' asked for changes on your ' || new.deliverable || ': ' || coalesce(new.feedback,''), 'bookings');
      when 'Cancelled' then perform notify(array[new.influencer_id], biz || ' cancelled the shoot on ' || to_char(new.shoot_date, 'DD Mon'), 'bookings');
      else null;
    end case;
    perform log(new.campaign_id, profile_name(auth.uid()) || ' set ' || new.ref || ' to ' || new.status);
  end if;
  return new;
end $$;

create or replace function public.remind_invoice(iid bigint) returns void
language plpgsql security definer set search_path = public as $$
declare i invoices;
begin
  if not is_staff() then raise exception 'Only the BrandBay team can send payment reminders'; end if;
  select * into i from invoices where id = iid;
  if i.id is null then raise exception 'Invoice not found'; end if;
  perform notify(array[i.business_id], 'Reminder: INV-' || i.id || ' for $' || to_char(i.amount, 'FM9,999,999') ||
    ' is due on ' || to_char(i.due, 'DD Mon') || '.', 'billing');
end $$;
