-- Update for a database that was set up before avatars existed.
-- Paste the whole file into Supabase > SQL Editor and press Run. Safe to run more than once.

alter table public.comments add column if not exists avatar text check (avatar is null or char_length(avatar) <= 8);
alter table public.comments add column if not exists by_admin boolean not null default false;

create or replace function public.brake() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  -- Only the database decides whether a comment is the admin's.
  if tg_table_name = 'comments' then new.by_admin := public.is_admin(); end if;
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

-- One row of site-wide settings: the admin's photo. Everyone reads it, only the admin changes it.
create table if not exists public.site (
  id          int primary key check (id = 1),
  boss_avatar text check (boss_avatar is null or char_length(boss_avatar) <= 40000)
);
alter table public.site enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'site' and policyname = 'anyone reads site') then
    create policy "anyone reads site" on public.site for select using (true);
    create policy "admin adds site" on public.site for insert with check (public.is_admin());
    create policy "admin changes site" on public.site for update using (public.is_admin()) with check (public.is_admin());
  end if;
end $$;
grant select on public.site to anon, authenticated;
grant insert, update on public.site to authenticated;
