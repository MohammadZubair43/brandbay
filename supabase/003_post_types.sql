-- BrandBay update 003: each platform has its own post types (YouTube Video/Short, X Thread, Google Business Offer, ...).
alter table public.posts  drop constraint if exists posts_type_check;
alter table public.drafts drop constraint if exists drafts_type_check;
alter table public.posts  add constraint posts_type_check  check (type in ('Post','Carousel','Reel','Story','Video','Short','Thread','Update','Offer','Event','Ad','Status','Broadcast'));
alter table public.drafts add constraint drafts_type_check check (type in ('Post','Carousel','Reel','Story','Video','Short','Thread','Update','Offer','Event','Ad','Status','Broadcast'));
