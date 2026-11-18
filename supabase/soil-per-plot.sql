-- Moves soil measurements from one row per farm to one row per plot, so each plot of a farm
-- keeps its own NPK, acidity, organic carbon and fertilizer.
--
-- Run this once in the Supabase SQL editor, after soil-measurements.sql. Until it has been
-- run, saving soil reports an error about the missing plot_id column.
--
-- Rows already there were a farm's soil, so they go to that farm's first plot. A farm with no
-- plots has nowhere to put its soil, so that row is dropped.

alter table public.soil_measurements
    add column if not exists plot_id uuid references public.plots (id) on delete cascade;

update public.soil_measurements s
set plot_id = (
    select p.id from public.plots p
    where p.farm_id = s.farm_id
    order by p.plot_number
    limit 1
)
where s.plot_id is null;

delete from public.soil_measurements where plot_id is null;

alter table public.soil_measurements alter column plot_id set not null;
alter table public.soil_measurements drop constraint if exists soil_measurements_farm_id_key;
alter table public.soil_measurements
    add constraint soil_measurements_plot_id_key unique (plot_id);
