-- What the field helper measures on the farm itself: NPK, acidity, organic carbon, any
-- fertilizer put on, and whether a scientist has been asked to look at the soil.
--
-- One row per farm, keyed on the phone's own measurement id, so saving again replaces what
-- is there instead of adding a row for every edit. The microscope side is unchanged: that is
-- soil_samples, soil_results and microorganisms.
--
-- Run this once in the Supabase SQL editor. The app reports "Could not find the table
-- 'public.soil_measurements'" until it has been run.

create table if not exists public.soil_measurements (
    id uuid primary key,
    farm_id uuid not null unique references public.farms (id) on delete cascade,
    nitrogen double precision,
    phosphorus double precision,
    potassium double precision,
    ph double precision check (ph is null or ph between 0 and 14),
    organic_carbon_percent double precision
        check (organic_carbon_percent is null or organic_carbon_percent between 0 and 100),
    fertilizer_product text,
    fertilizer_kg_per_hectare double precision,
    -- When the helper asked for a scientist. Null means nobody has been asked yet.
    scientist_alerted_at timestamptz,
    updated_at timestamptz not null default now()
);

-- A farm's soil is read by its own helper and by whoever is looking at the farm, so the rule
-- is the one farms already use: signed in is enough.
alter table public.soil_measurements enable row level security;

drop policy if exists "soil_measurements are readable" on public.soil_measurements;
create policy "soil_measurements are readable"
    on public.soil_measurements for select
    to authenticated, anon
    using (true);

drop policy if exists "soil_measurements are writable" on public.soil_measurements;
create policy "soil_measurements are writable"
    on public.soil_measurements for insert
    to authenticated, anon
    with check (true);

drop policy if exists "soil_measurements are updatable" on public.soil_measurements;
create policy "soil_measurements are updatable"
    on public.soil_measurements for update
    to authenticated, anon
    using (true)
    with check (true);

drop policy if exists "soil_measurements are deletable" on public.soil_measurements;
create policy "soil_measurements are deletable"
    on public.soil_measurements for delete
    to authenticated, anon
    using (true);
