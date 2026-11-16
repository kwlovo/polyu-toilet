-- PolyU toilet map: tables and access rules.
-- Paste the whole file into Supabase > SQL Editor and press Run. Run it once.

-- Who may approve, edit and delete. Nobody can read or change this table through the website.
create table public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);
alter table public.admins enable row level security;

create function public.is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.admins where user_id = (select auth.uid()));
$$;

-- Toilets. A row is visible to everyone only once status = 'approved'.
-- A row with "target" set is a proposed change to the row with that id.
create table public.toilets (
  id         text primary key check (id ~ '^[a-z0-9-]{8,40}$'),
  place      text not null check (place in ('A','B','C','D','E','F','G','H','J','P','Q','S','T','U','R','L','M','N','V','VA','VS','W','X','Y','Z')),
  floor      text not null check (floor ~ '^(B|G|P|[1-9]|1[0-9]|20)$'),
  descr      text not null default '' check (char_length(descr) <= 80),
  gender     text not null default 'both' check (gender in ('both','m','f','all')),
  paper      text not null default 'unknown' check (paper in ('unknown','yes','sometimes','no')),
  crowd      text not null default 'unknown' check (crowd in ('unknown','low','mid','high')),
  accessible boolean not null default false,
  status     text not null default 'pending' check (status in ('pending','approved')),
  target     text check (target is null or target ~ '^[a-z0-9-]{8,40}$'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.toilets enable row level security;

create policy "anyone reads approved" on public.toilets for select
  using (status = 'approved' or public.is_admin());
create policy "anyone submits pending" on public.toilets for insert
  with check (status = 'pending' or public.is_admin());
create policy "admin updates" on public.toilets for update
  using (public.is_admin()) with check (public.is_admin());
create policy "admin deletes" on public.toilets for delete
  using (public.is_admin());

-- Comments appear at once; only the admin can delete them.
create table public.comments (
  id         uuid primary key default gen_random_uuid(),
  toilet_id  text not null references public.toilets(id) on delete cascade,
  name       text not null check (char_length(btrim(name)) between 1 and 20),
  body       text not null check (char_length(btrim(body)) between 1 and 300),
  created_at timestamptz not null default now()
);
create index comments_toilet on public.comments (toilet_id, created_at desc);
alter table public.comments enable row level security;

create policy "anyone reads comments" on public.comments for select using (true);
create policy "anyone comments on approved toilets" on public.comments for insert
  with check (exists (select 1 from public.toilets t where t.id = toilet_id and t.status = 'approved'));
create policy "admin deletes comments" on public.comments for delete
  using (public.is_admin());

-- Flood brake: stops a script from filling the database. It is not a per-person limit.
create function public.brake() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if public.is_admin() then return new; end if;
  new.created_at := now();
  if tg_table_name = 'toilets' then
    new.updated_at := now();
    if (select count(*) from public.toilets where status = 'pending') >= 300 then
      raise exception 'too many submissions are waiting for approval';
    end if;
  else
    if (select count(*) from public.comments where created_at > now() - interval '1 minute') >= 20 then
      raise exception 'too many comments right now, try again in a minute';
    end if;
  end if;
  return new;
end $$;
create trigger toilets_brake before insert on public.toilets for each row execute function public.brake();
create trigger comments_brake before insert on public.comments for each row execute function public.brake();

-- Lets a device ask whether its own submissions are still waiting. Ids are random, so they cannot be guessed.
create function public.my_status(ids text[]) returns table (id text, status text)
language sql stable security definer set search_path = '' as $$
  select t.id, t.status from public.toilets t where t.id = any (ids[1:200]);
$$;

grant select, insert on public.toilets, public.comments to anon, authenticated;
grant update, delete on public.toilets to authenticated;
grant delete on public.comments to authenticated;
grant execute on function public.is_admin(), public.my_status(text[]) to anon, authenticated;
