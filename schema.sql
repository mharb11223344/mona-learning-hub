-- Student accounts and per-course progress for the Mona Harb learning hub.
-- Run once in the project's SQL Editor. Supabase Auth stores passwords.

create schema if not exists private;

create table if not exists public.student_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  student_name text not null check (char_length(btrim(student_name)) between 2 and 80),
  grade smallint not null check (grade in (3, 4)),
  created_at timestamptz not null default now()
);

create table if not exists public.app_progress (
  user_id uuid not null references auth.users(id) on delete cascade,
  app_id text not null check (app_id in (
    'english3-1termapp', 'connectplus3-term1app',
    'connectplus4-term1app', 'Plus4app-term1'
  )),
  state jsonb not null default '{}'::jsonb check (jsonb_typeof(state) = 'object'),
  updated_at timestamptz not null default now(),
  primary key (user_id, app_id)
);

create or replace function private.create_student_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  chosen_name text;
  chosen_grade text;
begin
  chosen_name := btrim(coalesce(new.raw_user_meta_data ->> 'student_name', ''));
  chosen_grade := new.raw_user_meta_data ->> 'grade';
  if char_length(chosen_name) not between 2 and 80 or chosen_grade not in ('3', '4') then
    raise exception 'A student name and Grade 3 or 4 are required';
  end if;
  insert into public.student_profiles (user_id, student_name, grade)
  values (new.id, chosen_name, chosen_grade::smallint);
  return new;
end;
$$;

revoke all on function private.create_student_profile() from public, anon, authenticated;
drop trigger if exists on_student_auth_created on auth.users;
create trigger on_student_auth_created
  after insert on auth.users
  for each row execute function private.create_student_profile();

alter table public.student_profiles enable row level security;
alter table public.app_progress enable row level security;

revoke all on public.student_profiles from anon, authenticated;
revoke all on public.app_progress from anon, authenticated;
grant usage on schema public to authenticated;
grant select on public.student_profiles to authenticated;
grant select, insert, update, delete on public.app_progress to authenticated;

create policy "Students read own profile"
on public.student_profiles for select to authenticated
using ((select auth.uid()) = user_id);

create policy "Students read own grade courses"
on public.app_progress for select to authenticated
using (
  (select auth.uid()) = user_id and exists (
    select 1 from public.student_profiles p
    where p.user_id = (select auth.uid()) and
      ((p.grade = 3 and app_id in ('english3-1termapp', 'connectplus3-term1app')) or
       (p.grade = 4 and app_id in ('connectplus4-term1app', 'Plus4app-term1')))
  )
);

create policy "Students insert own grade courses"
on public.app_progress for insert to authenticated
with check (
  (select auth.uid()) = user_id and exists (
    select 1 from public.student_profiles p
    where p.user_id = (select auth.uid()) and
      ((p.grade = 3 and app_id in ('english3-1termapp', 'connectplus3-term1app')) or
       (p.grade = 4 and app_id in ('connectplus4-term1app', 'Plus4app-term1')))
  )
);

create policy "Students update own grade courses"
on public.app_progress for update to authenticated
using (
  (select auth.uid()) = user_id and exists (
    select 1 from public.student_profiles p
    where p.user_id = (select auth.uid()) and
      ((p.grade = 3 and app_id in ('english3-1termapp', 'connectplus3-term1app')) or
       (p.grade = 4 and app_id in ('connectplus4-term1app', 'Plus4app-term1')))
  )
)
with check (
  (select auth.uid()) = user_id and exists (
    select 1 from public.student_profiles p
    where p.user_id = (select auth.uid()) and
      ((p.grade = 3 and app_id in ('english3-1termapp', 'connectplus3-term1app')) or
       (p.grade = 4 and app_id in ('connectplus4-term1app', 'Plus4app-term1')))
  )
);

create policy "Students delete own grade courses"
on public.app_progress for delete to authenticated
using (
  (select auth.uid()) = user_id and exists (
    select 1 from public.student_profiles p
    where p.user_id = (select auth.uid()) and
      ((p.grade = 3 and app_id in ('english3-1termapp', 'connectplus3-term1app')) or
       (p.grade = 4 and app_id in ('connectplus4-term1app', 'Plus4app-term1')))
  )
);
