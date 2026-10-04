-- A glass of tea is the third thing Egyptians drink all day, and the Water
-- node offers it beside the glass and the bottle. 0035 allowed two units;
-- the check was written inline on the column, so its generated name is
-- water_logs_unit_check.

alter table public.water_logs drop constraint if exists water_logs_unit_check;
alter table public.water_logs
  add constraint water_logs_unit_check check (unit in ('glass', 'bottle', 'tea'));

comment on column public.water_logs.unit is
  'glass (250 ml), bottle (500 ml) or tea (200 ml). The millilitres are stored beside it; the unit is how it was tapped.';
