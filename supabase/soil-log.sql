-- A plot keeps a log of soil measurements, one row per visit, instead of a single row.
-- Run this once in the Supabase SQL editor, after soil-per-plot.sql.

alter table public.soil_measurements drop constraint if exists soil_measurements_plot_id_key;

-- The day the helper took the readings. Rows saved before this are dated by when they were saved.
alter table public.soil_measurements add column if not exists measured_at timestamptz;
update public.soil_measurements set measured_at = updated_at where measured_at is null;
alter table public.soil_measurements alter column measured_at set not null;
alter table public.soil_measurements alter column measured_at set default now();
