-- BrandBay update 004: file uploads in chat (10 MB) and the brand kit (25 MB).

-- 1. Chat messages can carry a file (and the text becomes optional when they do)
alter table public.messages add column if not exists file_path text;
alter table public.messages add column if not exists file_name text;
alter table public.messages add column if not exists file_size integer;
alter table public.messages alter column body set default '';
alter table public.messages drop constraint if exists messages_body_check;
alter table public.messages drop constraint if exists messages_content_check;
alter table public.messages add constraint messages_content_check
  check (length(body) <= 4000 and (length(body) > 0 or file_path is not null));

-- 2. Brand kit files (logo, guidelines, photos, fonts)
create table if not exists public.brand_files (
  id          bigint generated always as identity primary key,
  business_id uuid not null references public.profiles(id) on delete cascade,
  path        text not null unique,
  name        text not null,
  size        integer not null,
  uploaded_by uuid not null references public.profiles(id),
  created_at  timestamptz not null default now()
);

-- Who may see a business's brand material: the business, the team, its managers, and influencers it booked.
create or replace function public.can_see_brand(biz uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() = biz or is_staff()
      or exists(select 1 from campaigns c where c.business_id = biz and c.manager_id = auth.uid())
      or exists(select 1 from bookings b where b.business_id = biz and b.influencer_id = auth.uid()
                and b.status not in ('Declined','Cancelled'));
$$;

alter table public.brand_files enable row level security;
drop policy if exists "brand files visible to the right people" on public.brand_files;
drop policy if exists "business adds its own brand files" on public.brand_files;
drop policy if exists "business or team removes brand files" on public.brand_files;
create policy "brand files visible to the right people" on public.brand_files for select using (can_see_brand(business_id));
create policy "business adds its own brand files" on public.brand_files for insert
  with check (business_id = auth.uid() and uploaded_by = auth.uid() and my_role() = 'business');
create policy "business or team removes brand files" on public.brand_files for delete
  using (business_id = auth.uid() or is_staff());
create index if not exists brand_files_business_idx on public.brand_files (business_id);

-- 3. Private storage areas with size limits enforced by Supabase itself
insert into storage.buckets (id, name, public, file_size_limit)
  values ('chat-files', 'chat-files', false, 10485760), ('brand-files', 'brand-files', false, 26214400)
  on conflict (id) do update set file_size_limit = excluded.file_size_limit, public = false;

-- chat-files/<campaign id>/<file>   : campaign members only
drop policy if exists "campaign members upload chat files" on storage.objects;
drop policy if exists "campaign members open chat files" on storage.objects;
create policy "campaign members upload chat files" on storage.objects for insert to authenticated
  with check (bucket_id = 'chat-files' and (storage.foldername(name))[1] ~ '^[0-9]+$'
              and public.is_member(((storage.foldername(name))[1])::bigint));
create policy "campaign members open chat files" on storage.objects for select to authenticated
  using (bucket_id = 'chat-files' and (storage.foldername(name))[1] ~ '^[0-9]+$'
         and public.is_member(((storage.foldername(name))[1])::bigint));

-- brand-files/<business id>/<file>  : the business uploads; the right people can open
drop policy if exists "business uploads brand files" on storage.objects;
drop policy if exists "right people open brand files" on storage.objects;
drop policy if exists "business removes brand files" on storage.objects;
create policy "business uploads brand files" on storage.objects for insert to authenticated
  with check (bucket_id = 'brand-files' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "right people open brand files" on storage.objects for select to authenticated
  using (bucket_id = 'brand-files' and (storage.foldername(name))[1] ~ '^[0-9a-f-]{36}$'
         and public.can_see_brand(((storage.foldername(name))[1])::uuid));
create policy "business removes brand files" on storage.objects for delete to authenticated
  using (bucket_id = 'brand-files' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_staff()));

-- 4. Chat notifications mention the file when there's no text
create or replace function public.on_message() returns trigger
language plpgsql security definer set search_path = public as $$
declare c campaigns;
begin
  select * into c from campaigns where id = new.campaign_id;
  perform notify(array[c.business_id, c.manager_id] || staff_ids(),
    profile_name(new.sender_id) || ' in ' || c.title || ': ' ||
    case when coalesce(new.body,'') = '' then '📎 ' || coalesce(new.file_name,'a file') else left(new.body, 60) end, 'messages');
  return new;
end $$;

-- 5. Live updates for brand files
do $$ begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'brand_files') then
    alter publication supabase_realtime add table public.brand_files;
  end if;
end $$;

-- 6. Fix: changes made by an admin in the SQL Editor (no signed-in user) are logged as "BrandBay team"
create or replace function public.profile_name(uid uuid) returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select coalesce(company, name) from profiles where id = uid), 'BrandBay team');
$$;
