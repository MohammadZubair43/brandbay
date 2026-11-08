-- BrandBay update 005: desktop / phone pop-up notifications (Web Push).
-- Every new row in public.notifications is also sent as a pop-up to the user's devices.

create extension if not exists pg_net with schema extensions;

-- 1. Devices that agreed to receive pop-ups
create table if not exists public.push_subscriptions (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  endpoint    text not null unique,
  p256dh      text not null,
  auth        text not null,
  user_agent  text,
  created_at  timestamptz not null default now()
);
alter table public.push_subscriptions enable row level security;
drop policy if exists "see own devices" on public.push_subscriptions;
create policy "see own devices" on public.push_subscriptions for select using (user_id = auth.uid());
create index if not exists push_subscriptions_user_idx on public.push_subscriptions (user_id);

-- Save this browser for the signed-in user (a shared computer moves to whoever is logged in).
create or replace function public.save_push_subscription(p_endpoint text, p_p256dh text, p_auth text, p_user_agent text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Please log in first'; end if;
  if p_endpoint !~ '^https://' then raise exception 'Invalid device address'; end if;
  delete from push_subscriptions where endpoint = p_endpoint;
  insert into push_subscriptions(user_id, endpoint, p256dh, auth, user_agent)
  values (auth.uid(), p_endpoint, p_p256dh, p_auth, left(p_user_agent, 200));
end $$;

create or replace function public.remove_push_subscription(p_endpoint text)
returns void language sql security definer set search_path = public as $$
  delete from push_subscriptions where endpoint = p_endpoint and user_id = auth.uid();
$$;

-- 2. Private settings (not reachable from the website): where the sending function lives and its password
create schema if not exists private;
create table if not exists private.config (key text primary key, value text not null);
revoke all on schema private from public, anon, authenticated;

-- 3. When a notification is created, ask the "send-push" function to pop it up on the user's devices
create or replace function public.on_notification_push() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare
  fn_url text; fn_secret text; subs jsonb;
begin
  select value into fn_url from private.config where key = 'push_url';
  select value into fn_secret from private.config where key = 'push_secret';
  if fn_url is null or fn_secret is null then return new; end if;

  select jsonb_agg(jsonb_build_object('endpoint', endpoint, 'p256dh', p256dh, 'auth', auth))
    into subs from push_subscriptions where user_id = new.user_id;
  if subs is null then return new; end if;

  perform net.http_post(
    url     := fn_url,
    body    := jsonb_build_object('body', new.body, 'link', coalesce(new.link, 'overview'), 'tag', 'n' || new.id, 'subscriptions', subs),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', fn_secret)
  );
  return new;
exception when others then
  return new;   -- a failed pop-up must never stop the in-app notification
end $$;

drop trigger if exists on_notification_push on public.notifications;
create trigger on_notification_push after insert on public.notifications
  for each row execute function public.on_notification_push();
