-- Índexs per al tauler docent paginat de fitxes del catàleg.
-- No modifiquen dades, RLS ni permisos.
begin;

-- Sense filtre d'estat: ordre estable per a la paginació de tot el catàleg.
create index if not exists catalog_objects_updated_at_id_idx
  on public.catalog_objects (updated_at desc, id desc);

-- Amb filtre d'estat: evita llegir i ordenar les fitxes dels altres estats.
create index if not exists catalog_objects_status_updated_at_id_idx
  on public.catalog_objects (status, updated_at desc, id desc);

commit;
