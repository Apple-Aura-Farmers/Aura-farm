-- Gives every new account a row in public.profiles.
--
-- Run once in the Supabase SQL editor. Without it, signing up in the app succeeds and then
-- every insert fails: soil_results.operated_by, farms.created_by, plots.mapped_by and
-- soil_samples.collected_by all default to auth.uid() and all reference profiles(id), so an
-- account with no profile row cannot write anything.
--
-- The role comes from the app, which is a deliberate trade and not the safe default.
--
-- Anyone who can reach this project can now make themselves a field_helper by signing in and
-- tapping a role, because an anonymous sign-in needs no invitation. That is acceptable only
-- while the app is handed out inside the team and the anon key is not published. The moment
-- it goes further than that, take the role out of the metadata below, leave it null, and
-- grant it from the dashboard instead.
--
-- Only the two labels the app offers are accepted. Anything else, including a label this
-- enum does not have, falls back to field_helper rather than failing the sign-in: a cast of
-- unchecked metadata would let a typo lock somebody out of their own account.

create or replace function public.create_profile_for_new_user()
returns trigger
language plpgsql
security definer
-- Pinned, because search_path is attacker-controlled in a security definer function.
set search_path = public, pg_temp
as $$
begin
  insert into public.profiles (id, full_name, role)
  values (
    new.id,
    nullif(trim(coalesce(new.raw_user_meta_data ->> 'full_name', '')), ''),
    case new.raw_user_meta_data ->> 'role'
      when 'microscope_operator' then 'microscope_operator'::user_role
      else 'field_helper'::user_role
    end
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists create_profile_for_new_user on auth.users;

create trigger create_profile_for_new_user
after insert on auth.users
for each row execute function public.create_profile_for_new_user();

-- Backfills the accounts that signed up before this trigger existed, and gives a role to the
-- ones that were made while it was still left null.
insert into public.profiles (id, full_name, role)
select
  u.id,
  nullif(trim(coalesce(u.raw_user_meta_data ->> 'full_name', '')), ''),
  'field_helper'::user_role
from auth.users u
left join public.profiles p on p.id = u.id
where p.id is null;

update public.profiles set role = 'field_helper'::user_role where role is null;

-- Lets a phone put its own name and role on its own profile, which is how switching role in
-- the app reaches the records. Same trade as above: it is the account's own row only, but
-- within that row the role is self-assigned.
drop policy if exists profiles_write_own on public.profiles;

create policy profiles_write_own on public.profiles
for update to authenticated
using (id = auth.uid())
with check (id = auth.uid());

-- An account has to be able to read its own profile for my_role() to mean anything in a
-- policy, unless that function is security definer.
drop policy if exists profiles_read_own on public.profiles;

create policy profiles_read_own on public.profiles
for select to authenticated
using (id = auth.uid());
