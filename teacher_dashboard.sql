-- Mona Learning Hub teacher dashboard. Run after schema.sql.
-- Teacher authorization is tied to an immutable Auth user ID, never user metadata.
begin;

create table if not exists public.teacher_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.teacher_admins enable row level security;
revoke all on public.teacher_admins from anon, authenticated;
grant select on public.teacher_admins to authenticated;
drop policy if exists "Teacher reads own role" on public.teacher_admins;
create policy "Teacher reads own role" on public.teacher_admins
  for select to authenticated using (user_id = (select auth.uid()));

-- The teacher role is granted only after one-time activation in the Edge Function.
create table if not exists public.teacher_activation (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  code_hash text not null,
  expires_at timestamptz not null,
  attempts smallint not null default 0,
  used_at timestamptz
);
alter table public.teacher_activation enable row level security;
revoke all on public.teacher_activation from public, anon, authenticated;
grant select, update on public.teacher_activation to service_role;

alter table public.student_profiles
  add column if not exists status text not null default 'active'
    check (status in ('active', 'suspended'));
alter table public.student_profiles add column if not exists last_seen_at timestamptz;
alter table public.student_profiles add column if not exists reset_at timestamptz;
create index if not exists student_profiles_last_seen_idx on public.student_profiles (last_seen_at desc);

drop policy if exists "Teacher reads student profiles" on public.student_profiles;
create policy "Teacher reads student profiles" on public.student_profiles
  for select to authenticated using (
    exists (select 1 from public.teacher_admins t where t.user_id = (select auth.uid()))
  );
grant update (status) on public.student_profiles to authenticated;
drop policy if exists "Teacher updates student status" on public.student_profiles;
create policy "Teacher updates student status" on public.student_profiles
  for update to authenticated using (
    exists (select 1 from public.teacher_admins t where t.user_id = (select auth.uid()))
  ) with check (
    exists (select 1 from public.teacher_admins t where t.user_id = (select auth.uid()))
    and not exists (select 1 from public.teacher_admins t where t.user_id = student_profiles.user_id)
  );
drop policy if exists "Student updates own activity" on public.student_profiles;

create or replace function public.mark_student_active()
returns void language plpgsql security definer set search_path = '' as $$
begin
  if (select auth.uid()) is null then raise exception 'Authentication required'; end if;
  update public.student_profiles set last_seen_at = now()
    where user_id = (select auth.uid()) and status = 'active'
      and not exists (select 1 from public.teacher_admins t where t.user_id = (select auth.uid()));
end $$;
revoke all on function public.mark_student_active() from public, anon;
grant execute on function public.mark_student_active() to authenticated;

create or replace function public.teacher_reset_student_progress(target_user uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if (select auth.uid()) is null or not exists (
    select 1 from public.teacher_admins t where t.user_id = (select auth.uid())
  ) then raise exception 'Teacher permission required'; end if;
  if not exists (select 1 from public.student_profiles p where p.user_id = target_user)
     or exists (select 1 from public.teacher_admins t where t.user_id = target_user)
  then raise exception 'Student account not found'; end if;
  delete from public.app_progress where user_id = target_user;
  update public.student_profiles set reset_at = now() where user_id = target_user;
end $$;
revoke all on function public.teacher_reset_student_progress(uuid) from public, anon;
grant execute on function public.teacher_reset_student_progress(uuid) to authenticated;

drop policy if exists "Students read own grade courses" on public.app_progress;
drop policy if exists "Students insert own grade courses" on public.app_progress;
drop policy if exists "Students update own grade courses" on public.app_progress;
drop policy if exists "Students delete own grade courses" on public.app_progress;
create policy "Students read own grade courses" on public.app_progress for select to authenticated
using (user_id = (select auth.uid()) and exists (
  select 1 from public.student_profiles p where p.user_id = (select auth.uid()) and p.status = 'active'
  and ((p.grade = 3 and app_id in ('english3-1termapp','connectplus3-term1app'))
    or (p.grade = 4 and app_id in ('connectplus4-term1app','Plus4app-term1')))
));
create policy "Students insert own grade courses" on public.app_progress for insert to authenticated
with check (user_id = (select auth.uid()) and exists (
  select 1 from public.student_profiles p where p.user_id = (select auth.uid()) and p.status = 'active'
  and ((p.grade = 3 and app_id in ('english3-1termapp','connectplus3-term1app'))
    or (p.grade = 4 and app_id in ('connectplus4-term1app','Plus4app-term1')))
));
create policy "Students update own grade courses" on public.app_progress for update to authenticated
using (user_id = (select auth.uid()) and exists (
  select 1 from public.student_profiles p where p.user_id = (select auth.uid()) and p.status = 'active'
)) with check (user_id = (select auth.uid()) and exists (
  select 1 from public.student_profiles p where p.user_id = (select auth.uid()) and p.status = 'active'
  and ((p.grade = 3 and app_id in ('english3-1termapp','connectplus3-term1app'))
    or (p.grade = 4 and app_id in ('connectplus4-term1app','Plus4app-term1')))
));
create policy "Students delete own grade courses" on public.app_progress for delete to authenticated
using (user_id = (select auth.uid()) and exists (
  select 1 from public.student_profiles p where p.user_id = (select auth.uid()) and p.status = 'active'
));
drop policy if exists "Teacher reads progress" on public.app_progress;
create policy "Teacher reads progress" on public.app_progress for select to authenticated
using (exists (select 1 from public.teacher_admins t where t.user_id = (select auth.uid())));
drop policy if exists "Teacher resets progress" on public.app_progress;
create policy "Teacher resets progress" on public.app_progress for delete to authenticated
using (exists (select 1 from public.teacher_admins t where t.user_id = (select auth.uid())));

create table if not exists public.course_controls (
  app_id text primary key check (app_id in ('english3-1termapp','connectplus3-term1app','connectplus4-term1app','Plus4app-term1')),
  grade smallint not null check (grade in (3,4)),
  visible boolean not null default true,
  open_units integer[] not null default '{1,2,3,4,5,6}',
  updated_at timestamptz not null default now()
);
alter table public.course_controls enable row level security;
revoke all on public.course_controls from anon, authenticated;
grant select, update (visible, open_units, updated_at) on public.course_controls to authenticated;
insert into public.course_controls (app_id, grade) values
  ('english3-1termapp',3),('connectplus3-term1app',3),
  ('connectplus4-term1app',4),('Plus4app-term1',4)
on conflict do nothing;
drop policy if exists "Signed-in users read course controls" on public.course_controls;
create policy "Signed-in users read course controls" on public.course_controls
for select to authenticated using (
  exists (select 1 from public.teacher_admins t where t.user_id = (select auth.uid()))
  or exists (select 1 from public.student_profiles p where p.user_id = (select auth.uid()) and p.status = 'active' and p.grade = course_controls.grade)
);
drop policy if exists "Teacher updates course controls" on public.course_controls;
create policy "Teacher updates course controls" on public.course_controls for update to authenticated
using (exists (select 1 from public.teacher_admins t where t.user_id = (select auth.uid())))
with check (exists (select 1 from public.teacher_admins t where t.user_id = (select auth.uid())));

create table if not exists public.weekly_star (
  singleton boolean primary key default true check (singleton),
  student_name text not null default '' check (char_length(student_name) <= 80),
  image_path text,
  published boolean not null default false,
  updated_at timestamptz not null default now()
);
alter table public.weekly_star enable row level security;
revoke all on public.weekly_star from anon, authenticated;
grant select, insert, update on public.weekly_star to authenticated;
insert into public.weekly_star (singleton) values (true) on conflict do nothing;
drop policy if exists "Students read published star" on public.weekly_star;
create policy "Students read published star" on public.weekly_star for select to authenticated
using (exists (select 1 from public.teacher_admins t where t.user_id = (select auth.uid()))
  or (published and exists (select 1 from public.student_profiles p where p.user_id = (select auth.uid()) and p.status = 'active')));
drop policy if exists "Teacher edits star" on public.weekly_star;
create policy "Teacher edits star" on public.weekly_star for all to authenticated
using (exists (select 1 from public.teacher_admins t where t.user_id = (select auth.uid())))
with check (exists (select 1 from public.teacher_admins t where t.user_id = (select auth.uid())));

create table if not exists public.student_logins (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  logged_at timestamptz not null default now()
);
create index if not exists student_logins_user_time_idx on public.student_logins (user_id, logged_at desc);
alter table public.student_logins enable row level security;
revoke all on public.student_logins from anon, authenticated;
grant select, insert on public.student_logins to authenticated;
drop policy if exists "Student records own login" on public.student_logins;
create policy "Student records own login" on public.student_logins for insert to authenticated
with check (user_id = (select auth.uid()) and exists (
  select 1 from public.student_profiles p where p.user_id = (select auth.uid()) and p.status = 'active'
));
drop policy if exists "Teacher reads logins" on public.student_logins;
create policy "Teacher reads logins" on public.student_logins for select to authenticated
using (exists (select 1 from public.teacher_admins t where t.user_id = (select auth.uid())));

insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('weekly-star','weekly-star',false,5242880,array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = false, file_size_limit = 5242880,
  allowed_mime_types = array['image/jpeg','image/png','image/webp'];
drop policy if exists "Teacher manages star photos" on storage.objects;
create policy "Teacher manages star photos" on storage.objects for all to authenticated
using (bucket_id = 'weekly-star' and exists (select 1 from public.teacher_admins t where t.user_id = (select auth.uid())))
with check (bucket_id = 'weekly-star' and exists (select 1 from public.teacher_admins t where t.user_id = (select auth.uid())));
drop policy if exists "Students read published star photo" on storage.objects;
create policy "Students read published star photo" on storage.objects for select to authenticated
using (bucket_id = 'weekly-star' and exists (
  select 1 from public.weekly_star s where s.published and s.image_path = name
) and exists (
  select 1 from public.student_profiles p where p.user_id = (select auth.uid()) and p.status = 'active'
));

commit;
