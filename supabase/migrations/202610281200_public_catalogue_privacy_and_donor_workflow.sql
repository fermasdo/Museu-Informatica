-- Catàleg públic sense metadades internes i alta docent atòmica de procedència.
-- Impacte de dades: la nova comprovació és NOT VALID, de manera que les fitxes
-- existents no s'invaliden; sí que s'aplica a tota alta o modificació nova.
begin;

-- El públic deixa de consultar les taules internes directament. Les vistes no
-- inclouen identificadors de donant, número de sèrie, ubicació, ni autoria/revisió.
drop policy if exists "catalog: public published read" on public.catalog_objects;
drop policy if exists "photos: public published read" on public.object_photos;
drop policy if exists "tags: public relevant read" on public.tags;
drop policy if exists "object tags: public published read" on public.object_tags;

create or replace view public.public_catalog_objects
with (security_barrier = true, security_invoker = false) as
select
  o.id,
  o.inventory_code,
  o.title,
  o.description,
  o.manufacturer,
  o.model,
  o.object_type_id,
  t.name as object_type_name,
  o.production_year_start,
  o.production_year_end,
  o.period_label,
  o.ownership,
  o.physical_condition,
  o.condition_notes,
  o.information_url,
  o.video_url,
  o.published_at
from public.catalog_objects o
join public.object_types t on t.id = o.object_type_id
where o.status = 'published';

create or replace view public.public_object_photos
with (security_barrier = true, security_invoker = false) as
select
  p.id,
  p.object_id,
  p.storage_path,
  p.alt_text,
  p.caption,
  p.position,
  p.created_at
from public.object_photos p
join public.catalog_objects o on o.id = p.object_id
where o.status = 'published';

create or replace view public.public_catalog_object_tags
with (security_barrier = true, security_invoker = false) as
select
  ot.object_id,
  t.name,
  t.normalized_name
from public.object_tags ot
join public.catalog_objects o on o.id = ot.object_id
join public.tags t on t.id = ot.tag_id
where o.status = 'published';

-- `authenticated` conserva la lectura limitada per RLS per al professorat i
-- l'alumnat propietari dels seus esborranys. El rol anònim només accedeix a
-- les projeccions públiques següents.
revoke select on public.catalog_objects, public.object_photos, public.tags, public.object_tags from anon;
grant select on public.public_catalog_objects, public.public_object_photos,
  public.public_catalog_object_tags to anon, authenticated;

-- Substitueix la regla parcial de préstecs per la regla completa de procedència.
alter table public.catalog_objects
  drop constraint if exists catalog_object_loan_donor;
alter table public.catalog_objects
  add constraint catalog_object_ownership_donor_check check (
    (ownership in ('donation', 'loan') and donor_id is not null)
    or (ownership in ('museum_property', 'unknown') and donor_id is null)
  ) not valid;

-- L'alumnat només pot mantindre esborranys sense dades de donant ni procedència privada.
drop policy if exists "catalog: students create drafts" on public.catalog_objects;
drop policy if exists "catalog: students update own drafts" on public.catalog_objects;
create policy "catalog: students create drafts" on public.catalog_objects for insert to authenticated
  with check (
    public.is_approved_student()
    and created_by = auth.uid()
    and status = 'draft'
    and reviewed_by is null
    and published_at is null
    and ownership in ('museum_property', 'unknown')
    and donor_id is null
  );
create policy "catalog: students update own drafts" on public.catalog_objects for update to authenticated
  using (
    public.is_approved_student()
    and created_by = auth.uid()
    and status = 'draft'
    and ownership in ('museum_property', 'unknown')
    and donor_id is null
  )
  with check (
    public.is_approved_student()
    and created_by = auth.uid()
    and status = 'draft'
    and reviewed_by is null
    and published_at is null
    and ownership in ('museum_property', 'unknown')
    and donor_id is null
  );

-- Aquesta és l'única operació que crea o associa donants des del flux del catàleg.
-- El bloqueig assessor evita duplicats de nom normalitzat durant dues altes concurrents.
create or replace function public.upsert_catalog_object_with_donor(
  p_object_id uuid,
  p_inventory_code text,
  p_title text,
  p_description text,
  p_manufacturer text,
  p_model text,
  p_serial_number text,
  p_object_type_id uuid,
  p_production_year_start smallint,
  p_production_year_end smallint,
  p_period_label text,
  p_physical_condition public.object_condition,
  p_condition_notes text,
  p_cabinet_id uuid,
  p_ownership public.ownership_kind,
  p_donor_name text,
  p_loan_due_date date,
  p_information_url text,
  p_video_url text
)
returns public.catalog_objects
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_donor_id uuid;
  v_normalized_donor_name text;
  v_object public.catalog_objects;
begin
  if not public.is_teacher() then
    raise exception 'No tens permís per gestionar procedència de peces';
  end if;

  if p_ownership is null then
    raise exception 'Cal indicar la procedència de la peça';
  end if;

  if p_ownership in ('donation', 'loan') then
    v_normalized_donor_name := lower(btrim(coalesce(p_donor_name, '')));
    if char_length(v_normalized_donor_name) not between 2 and 150 then
      raise exception 'Cal un nom de donant o prestador de 2 a 150 caràcters';
    end if;

    perform pg_advisory_xact_lock(hashtext(v_normalized_donor_name));
    select d.id into v_donor_id
    from public.donors d
    where lower(btrim(d.display_name)) = v_normalized_donor_name
    order by d.id
    limit 1;

    if v_donor_id is null then
      insert into public.donors (display_name)
      values (btrim(p_donor_name))
      returning id into v_donor_id;
    end if;
  else
    -- museum_property i unknown no conserven cap associació de donant.
    v_donor_id := null;
  end if;

  if p_object_id is null then
    insert into public.catalog_objects (
      inventory_code, title, description, manufacturer, model, serial_number,
      object_type_id, production_year_start, production_year_end, period_label,
      physical_condition, condition_notes, cabinet_id, ownership, donor_id,
      loan_due_date, information_url, video_url, status, created_by
    ) values (
      nullif(btrim(p_inventory_code), ''), p_title, p_description, p_manufacturer, p_model, p_serial_number,
      p_object_type_id, p_production_year_start, p_production_year_end, p_period_label,
      coalesce(p_physical_condition, 'unknown'::public.object_condition), p_condition_notes,
      p_cabinet_id, p_ownership, v_donor_id, p_loan_due_date, p_information_url, p_video_url,
      'draft', auth.uid()
    ) returning * into v_object;
  else
    perform 1 from public.catalog_objects where id = p_object_id for update;
    if not found then
      raise exception 'Fitxa no trobada';
    end if;

    update public.catalog_objects
    set inventory_code = coalesce(nullif(btrim(p_inventory_code), ''), inventory_code),
        title = p_title, description = p_description, manufacturer = p_manufacturer,
        model = p_model, serial_number = p_serial_number, object_type_id = p_object_type_id,
        production_year_start = p_production_year_start, production_year_end = p_production_year_end,
        period_label = p_period_label,
        physical_condition = coalesce(p_physical_condition, 'unknown'::public.object_condition),
        condition_notes = p_condition_notes, cabinet_id = p_cabinet_id, ownership = p_ownership,
        donor_id = v_donor_id, loan_due_date = p_loan_due_date,
        information_url = p_information_url, video_url = p_video_url
    where id = p_object_id
    returning * into v_object;
  end if;

  return v_object;
end;
$$;

revoke all on function public.upsert_catalog_object_with_donor(
  uuid, text, text, text, text, text, text, uuid, smallint, smallint, text,
  public.object_condition, text, uuid, public.ownership_kind, text, date, text, text
) from public, anon, authenticated;

-- Compatibilitat amb el contracte RPC del frontend. La funció accepta només
-- el subconjunt editable del formulari, el valida abans de convertir tipus i
-- delega l'escriptura atòmica i la gestió privada del donant a la funció interna.
create or replace function public.save_catalog_object_with_contact(
  object_id uuid,
  object_data jsonb,
  contact_name text
)
returns public.catalog_objects
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_inventory_code text;
  v_title text;
  v_description text;
  v_manufacturer text;
  v_model text;
  v_object_type_id uuid;
  v_cabinet_id uuid;
  v_production_year_start smallint;
  v_production_year_end smallint;
  v_ownership public.ownership_kind;
  v_information_url text;
  v_video_url text;
begin
  if object_data is null or jsonb_typeof(object_data) <> 'object' then
    raise exception 'Les dades de la fitxa han de ser un objecte JSON';
  end if;

  if object_data - array[
    'inventory_code', 'title', 'description', 'manufacturer', 'model',
    'object_type_id', 'cabinet_id', 'production_year_start',
    'production_year_end', 'ownership', 'information_url', 'video_url'
  ] <> '{}'::jsonb then
    raise exception 'Les dades de la fitxa contenen camps no permesos';
  end if;

  if jsonb_typeof(object_data -> 'title') <> 'string'
     or char_length(btrim(object_data ->> 'title')) not between 2 and 180 then
    raise exception 'El títol ha de tindre entre 2 i 180 caràcters';
  end if;
  if jsonb_typeof(object_data -> 'object_type_id') <> 'string'
     or object_data ->> 'object_type_id' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'La tipologia no és vàlida';
  end if;
  if jsonb_typeof(object_data -> 'ownership') <> 'string'
     or object_data ->> 'ownership' not in ('museum_property', 'unknown', 'donation', 'loan') then
    raise exception 'La procedència no és vàlida';
  end if;
  if object_data ? 'cabinet_id' and object_data -> 'cabinet_id' <> 'null'::jsonb
     and (jsonb_typeof(object_data -> 'cabinet_id') <> 'string'
       or object_data ->> 'cabinet_id' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') then
    raise exception 'L''armari no és vàlid';
  end if;
  if object_data ? 'production_year_start' and object_data -> 'production_year_start' <> 'null'::jsonb
     and (jsonb_typeof(object_data -> 'production_year_start') <> 'number'
       or object_data ->> 'production_year_start' !~ '^-?[0-9]+$') then
    raise exception 'L''any inicial no és vàlid';
  end if;
  if object_data ? 'production_year_end' and object_data -> 'production_year_end' <> 'null'::jsonb
     and (jsonb_typeof(object_data -> 'production_year_end') <> 'number'
       or object_data ->> 'production_year_end' !~ '^-?[0-9]+$') then
    raise exception 'L''any final no és vàlid';
  end if;

  foreach v_title in array array['inventory_code', 'description', 'manufacturer', 'model', 'information_url', 'video_url'] loop
    if object_data ? v_title and object_data -> v_title <> 'null'::jsonb
       and jsonb_typeof(object_data -> v_title) <> 'string' then
      raise exception 'El camp % ha de ser text o nul', v_title;
    end if;
  end loop;

  v_inventory_code := nullif(btrim(object_data ->> 'inventory_code'), '');
  v_title := btrim(object_data ->> 'title');
  v_description := nullif(btrim(object_data ->> 'description'), '');
  v_manufacturer := nullif(btrim(object_data ->> 'manufacturer'), '');
  v_model := nullif(btrim(object_data ->> 'model'), '');
  v_object_type_id := (object_data ->> 'object_type_id')::uuid;
  v_cabinet_id := nullif(object_data ->> 'cabinet_id', '')::uuid;
  v_production_year_start := (object_data ->> 'production_year_start')::smallint;
  v_production_year_end := (object_data ->> 'production_year_end')::smallint;
  v_ownership := (object_data ->> 'ownership')::public.ownership_kind;
  v_information_url := nullif(btrim(object_data ->> 'information_url'), '');
  v_video_url := nullif(btrim(object_data ->> 'video_url'), '');

  return public.upsert_catalog_object_with_donor(
    object_id, v_inventory_code, v_title, v_description, v_manufacturer, v_model,
    null, v_object_type_id, v_production_year_start, v_production_year_end, null,
    null, null, v_cabinet_id, v_ownership, contact_name, null,
    v_information_url, v_video_url
  );
end;
$$;

revoke all on function public.save_catalog_object_with_contact(uuid, jsonb, text)
  from public, anon, authenticated;
grant execute on function public.save_catalog_object_with_contact(uuid, jsonb, text)
  to authenticated;

comment on view public.public_catalog_objects is
  'Catàleg públic: camps explícitament segurs de peces publicades, amb procedència no identificativa i sense metadades internes.';
comment on view public.public_object_photos is
  'Metadades públiques de fotos vinculades exclusivament a peces publicades.';
comment on view public.public_catalog_object_tags is
  'Etiquetes públiques de peces publicades, per a filtres sense exposar les taules base.';

commit;
