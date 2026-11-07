-- Feedback estructurat per a les fitxes retornades a esborrany.
-- Impacte de dades: només afegeix columnes nullable; l'historial existent no canvia.
-- Permisos: manté l'historial privat i les RPC només executables per usuaris autenticats.
begin;

alter table public.catalog_object_history
  add column review_reason text,
  add column pending_tasks jsonb,
  add constraint catalog_object_history_review_reason_check
    check (review_reason is null or review_reason in (
      'incomplete_data',
      'verify_information',
      'missing_context',
      'photo_feedback',
      'classification_or_location',
      'other'
    )),
  add constraint catalog_object_history_pending_tasks_array_check
    check (pending_tasks is null or jsonb_typeof(pending_tasks) = 'array');

create or replace function public.record_catalog_object_history()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  history_action public.catalog_object_history_action;
  history_note text;
  history_review_reason text;
  history_pending_tasks jsonb;
begin
  if tg_op = 'INSERT' then
    insert into public.catalog_object_history (object_id, action, actor_id)
    values (new.id, 'created', auth.uid());
    return new;
  end if;

  if new.status is distinct from old.status then
    history_action := case new.status
      when 'pending_review' then 'submitted_for_review'::public.catalog_object_history_action
      when 'draft' then 'returned_to_draft'::public.catalog_object_history_action
      when 'published' then 'published'::public.catalog_object_history_action
      when 'archived' then 'archived'::public.catalog_object_history_action
    end;
    history_note := nullif(current_setting('app.catalogue_history_note', true), '');

    if history_action = 'returned_to_draft' then
      history_review_reason := nullif(current_setting('app.catalogue_history_review_reason', true), '');
      history_pending_tasks := nullif(current_setting('app.catalogue_history_pending_tasks', true), '')::jsonb;
    end if;

    insert into public.catalog_object_history (
      object_id, action, actor_id, note, review_reason, pending_tasks
    )
    values (
      new.id, history_action, auth.uid(), history_note,
      history_review_reason, history_pending_tasks
    );
  elsif (to_jsonb(new) - array['updated_at', 'published_at', 'reviewed_by', 'reviewed_at', 'review_note'])
      is distinct from
        (to_jsonb(old) - array['updated_at', 'published_at', 'reviewed_by', 'reviewed_at', 'review_note']) then
    insert into public.catalog_object_history (object_id, action, actor_id)
    values (new.id, 'edited', auth.uid());
  end if;

  return new;
end;
$$;

drop function public.review_catalog_object(uuid, public.catalog_status, text);

create function public.review_catalog_object(
  object_uuid uuid,
  next_status public.catalog_status,
  note text default null,
  p_review_reason text default null,
  p_pending_tasks jsonb default null
)
returns public.catalog_objects
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  current_object public.catalog_objects;
  normalized_note text := nullif(trim(note), '');
  normalized_reason text := nullif(trim(p_review_reason), '');
begin
  if normalized_note is not null and char_length(normalized_note) > 1000 then
    raise exception 'El comentari no pot superar 1000 caràcters';
  end if;

  if next_status = 'draft' then
    if normalized_reason is null or normalized_reason not in (
      'incomplete_data', 'verify_information', 'missing_context', 'photo_feedback',
      'classification_or_location', 'other'
    ) then
      raise exception 'Cal indicar un motiu de revisió vàlid';
    end if;

    if p_pending_tasks is null or jsonb_typeof(p_pending_tasks) <> 'array'
       or jsonb_array_length(p_pending_tasks) not between 1 and 5
       or exists (
         select 1
         from jsonb_array_elements(p_pending_tasks) as task(value)
         where jsonb_typeof(task.value) <> 'string'
            or char_length(btrim(task.value #>> '{}')) not between 1 and 180
       ) then
      raise exception 'Cal indicar entre 1 i 5 tasques de text no buit de fins a 180 caràcters';
    end if;
  elsif p_review_reason is not null or p_pending_tasks is not null then
    raise exception 'El motiu i les tasques només es permeten en retornar a esborrany';
  end if;

  perform set_config('app.catalogue_review', 'true', true);
  perform set_config('app.catalogue_history_note', coalesce(normalized_note, ''), true);
  perform set_config('app.catalogue_history_review_reason', coalesce(normalized_reason, ''), true);
  perform set_config('app.catalogue_history_pending_tasks', coalesce(p_pending_tasks::text, ''), true);

  select * into current_object from public.catalog_objects where id = object_uuid for update;
  if not found then raise exception 'Fitxa no trobada'; end if;

  if next_status = 'pending_review' then
    if current_object.created_by <> auth.uid() or not public.is_approved_student() or current_object.status <> 'draft' then
      raise exception 'No pots enviar aquesta fitxa a revisió';
    end if;
  elsif next_status in ('draft', 'published', 'archived') then
    if not public.is_teacher() then raise exception 'No tens permís per revisar fitxes'; end if;
    if next_status = 'draft' and current_object.status <> 'pending_review' then
      raise exception 'Només es poden retornar fitxes pendents';
    end if;
    if next_status = 'published' and current_object.status not in ('draft', 'pending_review') then
      raise exception 'Transició de publicació no permesa';
    end if;
  else
    raise exception 'Estat no permés';
  end if;

  update public.catalog_objects
  set status = next_status,
      reviewed_by = case when public.is_teacher() then auth.uid() else reviewed_by end,
      reviewed_at = case when public.is_teacher() then now() else reviewed_at end,
      review_note = case when public.is_teacher() then normalized_note else review_note end
  where id = object_uuid
  returning * into current_object;

  return current_object;
end;
$$;

revoke all on function public.review_catalog_object(uuid, public.catalog_status, text, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.review_catalog_object(uuid, public.catalog_status, text, text, jsonb)
  to authenticated;

drop function public.get_catalog_object_history(uuid, integer, timestamptz, uuid);

create function public.get_catalog_object_history(
  object_uuid uuid,
  page_limit integer default 10,
  before_at timestamptz default null,
  before_id uuid default null
)
returns table (
  id uuid,
  action public.catalog_object_history_action,
  note text,
  review_reason text,
  pending_tasks jsonb,
  created_at timestamptz,
  display_name text
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if page_limit is null or page_limit not between 1 and 50 then
    raise exception 'El límit ha d''estar entre 1 i 50';
  end if;

  if not public.is_teacher() and not exists (
    select 1
    from public.catalog_objects o
    where o.id = object_uuid
      and o.created_by = auth.uid()
      and public.is_approved_student()
  ) then
    raise exception 'No tens permís per consultar l''historial d''aquesta fitxa';
  end if;

  return query
  select h.id, h.action, h.note, h.review_reason, h.pending_tasks, h.created_at, p.display_name
  from public.catalog_object_history h
  left join public.profiles p on p.id = h.actor_id
  where h.object_id = object_uuid
    and (
      before_at is null
      or (h.created_at < before_at or (h.created_at = before_at and h.id < before_id))
    )
  order by h.created_at desc, h.id desc
  limit page_limit;
end;
$$;

revoke all on function public.get_catalog_object_history(uuid, integer, timestamptz, uuid)
  from public, anon, authenticated;
grant execute on function public.get_catalog_object_history(uuid, integer, timestamptz, uuid)
  to authenticated;

commit;
