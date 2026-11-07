-- Accions atòmiques en lot per a la gestió docent del catàleg.
-- Impacte de dades: amplia l'historial amb detalls opcionals; no altera files existents.
-- Permisos: les taules continuen protegides per RLS; només la RPC autenticada i
-- autoritzada pot fer aquestes operacions en lot.

alter type public.catalog_object_history_action add value if not exists 'tag_added';

begin;

alter table public.catalog_object_history
  add column if not exists details jsonb;

create or replace function public.record_object_tag_history()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  tag_name text;
  batch_setting text := nullif(current_setting('app.catalogue_history_batch_id', true), '');
  history_details jsonb;
begin
  select t.name into tag_name
  from public.tags t
  where t.id = new.tag_id;

  history_details := jsonb_build_object('tag_id', new.tag_id, 'tag_name', tag_name);
  if batch_setting is not null then
    history_details := history_details || jsonb_build_object('batch_id', batch_setting::uuid);
  end if;

  insert into public.catalog_object_history (object_id, action, actor_id, details)
  values (new.object_id, 'tag_added', auth.uid(), history_details);

  return new;
end;
$$;

revoke all on function public.record_object_tag_history() from public, anon, authenticated;

drop trigger if exists object_tags_record_history on public.object_tags;
create trigger object_tags_record_history
  after insert on public.object_tags
  for each row execute procedure public.record_object_tag_history();

create or replace function public.bulk_manage_catalog_objects(
  p_object_ids uuid[],
  p_operation text,
  p_tag_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  requested integer := coalesce(cardinality(p_object_ids), 0);
  locked_ids uuid[] := '{}'::uuid[];
  locked_object record;
  tag_name text;
  batch_id uuid;
  errors jsonb := '[]'::jsonb;
  validation_errors jsonb;
begin
  if not public.is_teacher() then
    raise exception 'No tens permís per gestionar fitxes en lot';
  end if;

  if requested not between 1 and 100 then
    errors := errors || jsonb_build_array(jsonb_build_object('code', 'invalid_object_count'));
  end if;
  if array_position(p_object_ids, null) is not null then
    errors := errors || jsonb_build_array(jsonb_build_object('code', 'null_object_id'));
  end if;
  if requested <> coalesce((select count(distinct object_id) from unnest(p_object_ids) as input(object_id)), 0) then
    errors := errors || jsonb_build_array(jsonb_build_object('code', 'duplicate_object_id'));
  end if;
  if p_operation is null or p_operation not in ('add_tag', 'publish', 'archive') then
    errors := errors || jsonb_build_array(jsonb_build_object('code', 'invalid_operation'));
  end if;
  if p_operation = 'add_tag' and p_tag_id is null then
    errors := errors || jsonb_build_array(jsonb_build_object('code', 'tag_required'));
  elsif p_operation <> 'add_tag' and p_tag_id is not null then
    errors := errors || jsonb_build_array(jsonb_build_object('code', 'tag_not_allowed'));
  end if;

  if errors <> '[]'::jsonb then
    return jsonb_build_object('ok', false, 'requested', requested, 'changed', 0, 'errors', errors);
  end if;

  -- El mateix ordre d'identificadors evita interbloquejos entre lots simultanis.
  for locked_object in
    select o.id, o.status
    from public.catalog_objects o
    where o.id = any(p_object_ids)
    order by o.id
    for update
  loop
    locked_ids := array_append(locked_ids, locked_object.id);
  end loop;

  if cardinality(locked_ids) <> requested then
    errors := errors || jsonb_build_array(jsonb_build_object('code', 'object_not_found'));
  end if;

  if p_operation = 'add_tag' then
    select t.name into tag_name
    from public.tags t
    where t.id = p_tag_id
    for key share;

    if not found then
      errors := errors || jsonb_build_array(jsonb_build_object('code', 'tag_not_found'));
    elsif exists (
      select 1 from public.object_tags ot
      where ot.tag_id = p_tag_id and ot.object_id = any(locked_ids)
    ) then
      errors := errors || jsonb_build_array(jsonb_build_object('code', 'tag_already_associated'));
    end if;
  elsif p_operation = 'publish' then
    select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'status', o.status) order by o.id), '[]'::jsonb)
      into validation_errors
    from public.catalog_objects o
    where o.id = any(locked_ids) and o.status not in ('draft', 'pending_review');
    if validation_errors <> '[]'::jsonb then
      errors := errors || jsonb_build_array(jsonb_build_object('code', 'invalid_publish_status', 'objects', validation_errors));
    end if;
  elsif p_operation = 'archive' then
    select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'status', o.status) order by o.id), '[]'::jsonb)
      into validation_errors
    from public.catalog_objects o
    where o.id = any(locked_ids) and o.status not in ('draft', 'pending_review', 'published');
    if validation_errors <> '[]'::jsonb then
      errors := errors || jsonb_build_array(jsonb_build_object('code', 'invalid_archive_status', 'objects', validation_errors));
    end if;
  end if;

  if errors <> '[]'::jsonb then
    return jsonb_build_object('ok', false, 'requested', requested, 'changed', 0, 'errors', errors);
  end if;

  if p_operation = 'add_tag' then
    batch_id := gen_random_uuid();
    perform set_config('app.catalogue_history_batch_id', batch_id::text, true);
    begin
      insert into public.object_tags (object_id, tag_id, created_by)
      select object_id, p_tag_id, auth.uid()
      from unnest(locked_ids) as input(object_id);
    exception when unique_violation then
      return jsonb_build_object(
        'ok', false, 'requested', requested, 'changed', 0,
        'errors', jsonb_build_array(jsonb_build_object('code', 'tag_already_associated'))
      );
    end;
  else
    -- Necessari per al trigger que protegeix el flux de revisió; el trigger
    -- d'historial registra una entrada per cada canvi d'estat.
    perform set_config('app.catalogue_review', 'true', true);
    perform set_config('app.catalogue_history_note', '', true);
    update public.catalog_objects
    set status = p_operation::public.catalog_status,
        reviewed_by = auth.uid(),
        reviewed_at = now(),
        review_note = null
    where id = any(locked_ids);
  end if;

  return jsonb_build_object(
    'ok', true, 'requested', requested, 'changed', requested,
    'ids', to_jsonb(locked_ids),
    'batch_id', case when batch_id is null then null else to_jsonb(batch_id) end
  );
end;
$$;

revoke all on function public.bulk_manage_catalog_objects(uuid[], text, uuid)
  from public, anon, authenticated;
grant execute on function public.bulk_manage_catalog_objects(uuid[], text, uuid)
  to authenticated;

comment on function public.bulk_manage_catalog_objects(uuid[], text, uuid) is
  'Gestiona en una única transacció lots de fins a 100 fitxes per professorat o administració.';

commit;
