-- Ubicacions físiques: edifici controlat i etiqueta d'armari explícita.
-- Aquesta migració conserva el codi, prestatge i notes, i transforma room en building.
begin;

alter table public.cabinets
  rename column room to building;

-- La restricció antiga només validava longitud. La substituïm després de normalitzar
-- les files existents perquè cap valor històric impedisca la migració.
update public.cabinets
set building = case btrim(building)
  when 'Edifici Cicles' then 'Cicles'
  when 'Edicifi Cicles' then 'Cicles'
  when 'Cicles' then 'Cicles'
  when 'Edifici ESO' then 'ESO'
  when 'ESO' then 'ESO'
  when 'Edifici Administració' then 'Administració'
  when 'Administració' then 'Administració'
  else 'Administració'
end;

alter table public.cabinets
  drop constraint cabinets_room_check,
  add column cabinet text;

-- No existia cap camp d'armari: el codi únic actual és l'única font no ambigua.
-- Es replica com a etiqueta inicial per mantindre cada ubicació identificable.
update public.cabinets
set cabinet = code;

alter table public.cabinets
  alter column cabinet set not null,
  add constraint cabinets_building_check
    check (building in ('Cicles', 'ESO', 'Administració')),
  add constraint cabinets_cabinet_check
    check (char_length(btrim(cabinet)) between 1 and 80);

comment on column public.cabinets.building is
  'Edifici de la ubicació: Cicles, ESO o Administració.';
comment on column public.cabinets.cabinet is
  'Etiqueta llegible de l''armari o vitrina; les files històriques s''inicialitzen amb code.';

commit;
