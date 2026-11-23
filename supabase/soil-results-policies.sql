-- Lets the phone write the microscope side of the records: soil_samples, soil_results and
-- microorganisms.
--
-- Run this once in the Supabase SQL editor. Until it has been run, publishing a test fails
-- with "new row violates row-level security policy for table soil_results". The tables were
-- made in the dashboard with row-level security on and nothing granting an insert, so every
-- send was refused however the app was signed in.
--
-- The rule here is ownership rather than the "signed in is enough" that soil_measurements
-- uses: a result is filed under whoever operated the microscope, and operated_by already
-- defaults to auth.uid(), so a phone can write its own rows and not anybody else's. An
-- anonymous sign-in is an authenticated account with an id of its own, so it passes too.
--
-- Nothing here is dropped or rewritten except the policies named below, and every one is
-- created under a name of this file's own, so a policy the dashboard already has keeps
-- working beside them.

-- A sample is registered by the field helper who collected the soil, or by the operator
-- sending the first test of it, which is what collected_by records.
alter table public.soil_samples enable row level security;

drop policy if exists "soil_samples are writable by their collector" on public.soil_samples;
create policy "soil_samples are writable by their collector"
    on public.soil_samples for insert
    to authenticated
    with check (collected_by = auth.uid());

-- A result is written once and then rewritten whenever the same sweep is sent again, which
-- is how a helper retries on a bad connection: the id is the sweep's own, so the second send
-- updates the row instead of adding one. An upsert needs both of these.
alter table public.soil_results enable row level security;

drop policy if exists "soil_results are writable by their operator" on public.soil_results;
create policy "soil_results are writable by their operator"
    on public.soil_results for insert
    to authenticated
    with check (operated_by = auth.uid());

drop policy if exists "soil_results are updatable by their operator" on public.soil_results;
create policy "soil_results are updatable by their operator"
    on public.soil_results for update
    to authenticated
    using (operated_by = auth.uid())
    with check (operated_by = auth.uid());

-- The counts have no operator of their own; they belong to the result they are counts of.
-- Deleting is part of sending: a re-sent sweep clears its old counts first, so a group it no
-- longer counts does not linger.
--
-- Signed in is enough here, the way soil_measurements has it. A policy reading
-- soil_results.operated_by instead would be the tighter rule, but it would hold only as far
-- as that table's own select policy lets this account see the parent row, so a write would
-- turn on a policy somewhere else. The result_id column already references soil_results, so
-- counts cannot be attached to a result that is not there.
alter table public.microorganisms enable row level security;

drop policy if exists "microorganisms are writable" on public.microorganisms;
create policy "microorganisms are writable"
    on public.microorganisms for insert
    to authenticated
    with check (true);

drop policy if exists "microorganisms are deletable" on public.microorganisms;
create policy "microorganisms are deletable"
    on public.microorganisms for delete
    to authenticated
    using (true);
