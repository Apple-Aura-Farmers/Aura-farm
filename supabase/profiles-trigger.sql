-- Gives every new account a row in public.profiles.
--
-- Run once in the Supabase SQL editor. Without it, signing up in the app succeeds and then
-- every insert fails: soil_results.operated_by, farms.created_by, plots.mapped_by and
-- soil_samples.collected_by all default to auth.uid() and all reference profiles(id), so an
-- account with no profile row cannot write anything.
--
-- role is deliberately left null. The app must never choose it: anyone can call signUp, so an
-- app-supplied role would let a stranger make themselves whatever the most privileged value
-- in that enum is. Set it from the dashboard, or from a policy that only an existing admin
-- can run.

create or replace function public.create_profile_for_new_user()
returns trigger
language plpgsql
security definer
-- Pinned, because search_path is attacker-controlled in a security definer function.
set search_path = public, pg_temp
as $$
begin
  insert into public.profiles (id, full_name)
  values (
    new.id,
    nullif(trim(coalesce(new.raw_user_meta_data ->> 'full_name', '')), '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists create_profile_for_new_user on auth.users;

create trigger create_profile_for_new_user
after insert on auth.users
for each row execute function public.create_profile_for_new_user();

-- Backfills the accounts that signed up before this trigger existed.
insert into public.profiles (id)
select u.id from auth.users u
left join public.profiles p on p.id = u.id
where p.id is null;
