-- Historial immutable d'accions de fitxes, separat de les revisions antigues.
-- Impacte de dades: conserva les revisions existents i les copia com a accions
-- d'estat. No elimina la taula de revisions ni modifica cap fitxa existent.
begin;

create type public.catalog_object_history_action as enum (
  'created',
  'edited',
  'submitted_for_review',
  'returned_to_draft',
  'published',
  'archived'
);

create table public.catalog_object_history (
  id uuid primary key default gen_random_uuid(),
  object_id uuid not null references public.catalog_objects(id) on delete cascade,
  action public.catalog_object_history_action not null,
  actor_id uuid references public.profiles(id) on delete set null,
  note text check (char_length(note) <= 2000),
  created_at timestamptz not null default now()
);

-- Serveix tant la pàgina d'una fitxa com la paginació per cursor estable.
create index catalog_object_history_object_created_at_idx
  on public.catalog_object_history (object_id, created_at desc, id desc);

alter table public.catalog_object_history enable row level security;

create policy "catalog history: managers and authors read"
  on public.catalog_object_history for select to authenticated
  using (
    public.is_teacher()
    or (
      public.is_approved_student()
      and exists (
        select 1
        from public.catalog_objects o
        where o.id = object_id and o.created_by = auth.uid()
      )
    )
  );

-- No hi ha polítiques d'escriptura: el trigger és l'única via d'alta.
revoke all on table public.catalog_object_history from anon, authenticated;
grant select on table public.catalog_object_history to authenticated;

-- Les revisions prèvies només descriuen transicions d'estat; es conserven amb
-- el mateix identificador, actor, nota i instant per mantenir la traça.
insert into public.catalog_object_history (id, object_id, action, actor_id, note, created_at)
select
  r.id,
  r.object_id,
  case r.status
    when 'pending_review' then 'submitted_for_review'::public.catalog_object_history_action
    when 'draft' then 'returned_to_draft'::public.catalog_object_history_action
    when 'published' then 'published'::public.catalog_object_history_action
    when 'archived' then 'archived'::public.catalog_object_history_action
  end,
  r.changed_by,
  r.note,
  r.created_at
from public.catalog_object_revisions r
where r.status in ('pending_review', 'draft', 'published', 'archived')
on conflict (id) do nothing;

create or replace function public.record_catalog_object_history()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  history_action public.catalog_object_history_action;
  history_note text;
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

    insert into public.catalog_object_history (object_id, action, actor_id, note)
    values (new.id, history_action, auth.uid(), history_note);
  elsif (to_jsonb(new) - array['updated_at', 'published_at', 'reviewed_by', 'reviewed_at', 'review_note'])
      is distinct from
        (to_jsonb(old) - array['updated_at', 'published_at', 'reviewed_by', 'reviewed_at', 'review_note']) then
    insert into public.catalog_object_history (object_id, action, actor_id)
    values (new.id, 'edited', auth.uid());
  end if;

  return new;
end;
$$;

revoke all on function public.record_catalog_object_history() from public, anon, authenticated;

drop trigger if exists catalog_objects_record_history on public.catalog_objects;
create trigger catalog_objects_record_history
  after insert or update on public.catalog_objects
  for each row execute procedure public.record_catalog_object_history();

-- El trigger registra la transició; la RPC només valida i hi adjunta la nota.
create or replace function public.review_catalog_object(
  object_uuid uuid,
  next_status public.catalog_status,
  note text default null
)
returns public.catalog_objects
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  current_object public.catalog_objects;
  normalized_note text := nullif(trim(note), '');
begin
  perform set_config('app.catalogue_review', 'true', true);
  perform set_config('app.catalogue_history_note', coalesce(normalized_note, ''), true);

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

  if next_status = 'draft' and normalized_note is null then
    raise exception 'Cal indicar un comentari en retornar una fitxa';
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

revoke all on function public.review_catalog_object(uuid, public.catalog_status, text)
  from public, anon, authenticated;
grant execute on function public.review_catalog_object(uuid, public.catalog_status, text)
  to authenticated;

create or replace function public.get_catalog_object_history(
  object_uuid uuid,
  page_limit integer default 10,
  before_at timestamptz default null,
  before_id uuid default null
)
returns table (
  id uuid,
  action public.catalog_object_history_action,
  note text,
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
  select h.id, h.action, h.note, h.created_at, p.display_name
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
