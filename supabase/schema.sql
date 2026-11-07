-- Museu d'Informàtica IES l'Estació
-- Esquema inicial versionat: 1.2.2 (2026-10-28)
-- Apliqueu-lo només a un projecte Supabase nou o mitjançant una migració inicial.

create extension if not exists pgcrypto;

create type public.profile_role as enum ('visitor', 'student', 'teacher');
create type public.approval_state as enum ('not_required', 'pending', 'approved', 'rejected');
create type public.catalog_status as enum ('draft', 'pending_review', 'published', 'archived');
create type public.ownership_kind as enum ('donation', 'loan', 'museum_property', 'unknown');
create type public.object_condition as enum ('excellent', 'good', 'fair', 'poor', 'unknown');
create type public.proposal_status as enum ('open', 'accepted', 'rejected', 'implemented');
create type public.activity_kind as enum ('gymkhana', 'cinema', 'library');
create type public.catalog_object_history_action as enum (
  'created', 'edited', 'submitted_for_review', 'returned_to_draft', 'published', 'archived', 'tag_added'
);

-- requested_role és una petició validada, mai una concessió de privilegis.
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(trim(display_name)) between 2 and 100),
  role public.profile_role not null default 'visitor',
  requested_role text check (requested_role is null or requested_role in ('student', 'teacher')),
  approval_status public.approval_state not null default 'not_required',
  approved_by uuid references public.profiles(id) on delete set null,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_approval_consistency check (
    (role = 'visitor' and requested_role is null and approval_status = 'not_required')
    or (role = 'visitor' and requested_role = 'teacher'
        and approval_status in ('pending', 'rejected'))
    or (role = 'student' and requested_role = 'student'
        and approval_status in ('pending', 'approved', 'rejected'))
    or (role = 'teacher' and requested_role = 'teacher' and approval_status = 'approved')
  ),
  constraint profiles_approval_audit check (
    (approval_status = 'approved' and approved_by is not null and approved_at is not null)
    or approval_status <> 'approved'
  )
);

-- Administració explícita, separada dels rols sol·licitats pels usuaris.
create table public.administrators (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table public.object_types (
  id uuid primary key default gen_random_uuid(),
  name text not null unique check (char_length(trim(name)) between 2 and 80),
  description text check (char_length(description) <= 500),
  created_at timestamptz not null default now()
);

create table public.cabinets (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[A-Za-z0-9_-]{1,30}$'),
  building text not null check (building in ('Cicles', 'ESO', 'Administració')),
  cabinet text not null check (char_length(btrim(cabinet)) between 1 and 80),
  shelf text check (char_length(trim(shelf)) between 1 and 40),
  notes text check (char_length(notes) <= 500),
  created_at timestamptz not null default now()
);

comment on column public.cabinets.building is
  'Edifici de la ubicació: Cicles, ESO o Administració.';
comment on column public.cabinets.cabinet is
  'Etiqueta llegible de l''armari o vitrina.';

-- Dades de contacte privades: no s'exposen mai al catàleg públic.
create table public.donors (
  id uuid primary key default gen_random_uuid(),
  display_name text not null check (char_length(trim(display_name)) between 2 and 150),
  email text check (email ~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),
  phone text check (char_length(phone) between 5 and 40),
  address text check (char_length(address) <= 300),
  notes text check (char_length(notes) <= 2000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.catalog_objects (
  id uuid primary key default gen_random_uuid(),
  inventory_code text unique check (inventory_code ~ '^[A-Z0-9][A-Z0-9_-]{2,39}$'),
  title text not null check (char_length(trim(title)) between 2 and 180),
  description text check (char_length(description) <= 10000),
  manufacturer text check (char_length(manufacturer) <= 120),
  model text check (char_length(model) <= 120),
  serial_number text check (char_length(serial_number) <= 120),
  object_type_id uuid not null references public.object_types(id) on delete restrict,
  production_year_start smallint check (production_year_start between 1800 and 2200),
  production_year_end smallint check (production_year_end between 1800 and 2200),
  period_label text check (char_length(period_label) <= 100),
  physical_condition public.object_condition not null default 'unknown',
  condition_notes text check (char_length(condition_notes) <= 2000),
  cabinet_id uuid references public.cabinets(id) on delete set null,
  ownership public.ownership_kind not null default 'unknown',
  donor_id uuid references public.donors(id) on delete restrict,
  loan_due_date date,
  status public.catalog_status not null default 'draft',
  created_by uuid not null references public.profiles(id) on delete restrict,
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  review_note text check (char_length(review_note) <= 2000),
  information_url text check (information_url is null or (char_length(information_url) <= 2048 and information_url ~* '^https://')),
  video_url text check (video_url is null or (char_length(video_url) <= 2048 and video_url ~* '^https://')),
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint catalog_object_year_range check (
    production_year_end is null or production_year_start is null
    or production_year_end >= production_year_start
  ),
  constraint catalog_object_loan_date check (
    ownership = 'loan' or loan_due_date is null
  ),
  constraint catalog_object_publication_date check (
    status <> 'published' or published_at is not null
  )
);

-- Traça d'accions del catàleg: només l'ompli el trigger de catalog_objects.
create table public.catalog_object_history (
  id uuid primary key default gen_random_uuid(),
  object_id uuid not null references public.catalog_objects(id) on delete cascade,
  action public.catalog_object_history_action not null,
  actor_id uuid references public.profiles(id) on delete set null,
  note text check (char_length(note) <= 2000),
  review_reason text check (review_reason is null or review_reason in (
    'incomplete_data', 'verify_information', 'missing_context', 'photo_feedback',
    'classification_or_location', 'other'
  )),
  pending_tasks jsonb check (pending_tasks is null or jsonb_typeof(pending_tasks) = 'array'),
  details jsonb,
  created_at timestamptz not null default now()
);

-- NOT VALID manté la instal·lació compatible amb dades heretades; tota fila nova
-- o actualitzada ha de respectar la procedència indicada.
alter table public.catalog_objects
  add constraint catalog_object_ownership_donor_check check (
    (ownership in ('donation', 'loan') and donor_id is not null)
    or (ownership in ('museum_property', 'unknown') and donor_id is null)
  ) not valid;

create sequence public.catalog_inventory_code_seq;
create or replace function public.assign_inventory_code()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.inventory_code is null or btrim(new.inventory_code) = '' then
    new.inventory_code := 'MUS-' || lpad(nextval('public.catalog_inventory_code_seq')::text, 6, '0');
  end if;
  return new;
end;
$$;
create trigger catalog_objects_assign_inventory_code
  before insert on public.catalog_objects for each row execute procedure public.assign_inventory_code();

create table public.object_photos (
  id uuid primary key default gen_random_uuid(),
  object_id uuid not null references public.catalog_objects(id) on delete cascade,
  storage_path text not null unique check (
    storage_path ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.[A-Za-z0-9]{2,8}$'
  ),
  alt_text text not null check (char_length(trim(alt_text)) between 4 and 250),
  caption text check (char_length(caption) <= 500),
  position smallint not null default 0 check (position between 0 and 100),
  uploaded_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (object_id, position)
);

create table public.tags (
  id uuid primary key default gen_random_uuid(),
  name text not null check (name = btrim(name) and name !~ '[[:space:]#]' and char_length(name) between 2 and 80),
  normalized_name text generated always as (lower(btrim(name))) stored,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint tags_normalized_name_key unique (normalized_name)
);

create table public.object_tags (
  object_id uuid not null references public.catalog_objects(id) on delete cascade,
  tag_id uuid not null references public.tags(id) on delete restrict,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  primary key (object_id, tag_id)
);

create table public.change_proposals (
  id uuid primary key default gen_random_uuid(),
  object_id uuid references public.catalog_objects(id) on delete set null,
  subject text not null check (char_length(trim(subject)) between 4 and 180),
  message text not null check (char_length(trim(message)) between 10 and 5000),
  proposed_data jsonb not null default '{}'::jsonb check (jsonb_typeof(proposed_data) = 'object'),
  status public.proposal_status not null default 'open',
  submitted_by uuid not null references public.profiles(id) on delete restrict,
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewer_note text check (char_length(reviewer_note) <= 2000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.activities (
  id uuid primary key default gen_random_uuid(),
  kind public.activity_kind not null,
  title text not null check (char_length(trim(title)) between 2 and 180),
  description text check (char_length(description) <= 10000),
  starts_at timestamptz,
  ends_at timestamptz,
  location text check (char_length(location) <= 160),
  registration_url text check (registration_url ~* '^https://'),
  status public.catalog_status not null default 'draft',
  created_by uuid not null references public.profiles(id) on delete restrict,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint activities_date_range check (ends_at is null or starts_at is null or ends_at >= starts_at),
  constraint activities_publication_date check (status <> 'published' or published_at is not null)
);

-- Formulari públic de donacions. Només el professorat pot llegir-lo o gestionar-lo.
create table public.donation_contacts (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 2 and 120),
  email text not null check (email ~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),
  phone text check (char_length(phone) between 5 and 40),
  message text not null check (char_length(trim(message)) between 10 and 3000),
  status text not null default 'new' check (status in ('new', 'contacted', 'closed', 'spam')),
  handled_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  handled_at timestamptz
);

-- Índexs per a les consultes reals del frontend i del tauler de revisió.
create index catalog_objects_published_idx on public.catalog_objects (published_at desc)
  where status = 'published';
create index catalog_objects_creator_idx on public.catalog_objects (created_by, updated_at desc);
-- Paginació docent: tant el llistat complet com el filtrat per estat tenen un
-- ordre estable. Calen dos índexs perquè `status` només és un filtre opcional.
create index catalog_objects_updated_at_id_idx on public.catalog_objects (updated_at desc, id desc);
create index catalog_objects_status_updated_at_id_idx
  on public.catalog_objects (status, updated_at desc, id desc);
create index catalog_object_history_object_created_at_idx
  on public.catalog_object_history (object_id, created_at desc, id desc);
create index object_photos_object_idx on public.object_photos (object_id, position);
create index object_tags_tag_object_idx on public.object_tags (tag_id, object_id);
create index change_proposals_submitter_idx on public.change_proposals (submitted_by, status, created_at desc);
create index donation_contacts_status_idx on public.donation_contacts (status, created_at desc);
create index profiles_pending_teacher_requests_idx on public.profiles (created_at asc)
  where requested_role = 'teacher' and approval_status = 'pending';

create or replace function public.set_updated_at()
returns trigger language plpgsql set search_path = public as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  requested text := new.raw_user_meta_data ->> 'requested_role';
begin
  insert into public.profiles (id, display_name, role, requested_role, approval_status)
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''), 'Visitant'),
    case when requested = 'student' then 'student'::public.profile_role else 'visitor'::public.profile_role end,
    case when requested in ('student', 'teacher') then requested else null end,
    case when requested in ('student', 'teacher') then 'pending'::public.approval_state
         else 'not_required'::public.approval_state end
  );
  return new;
end;
$$;

-- Impedeix que un usuari es concedisca privilegis o s'aprove a si mateix.
create or replace function public.protect_profile_privileges()
returns trigger language plpgsql set search_path = public as $$
declare
  privilege_changed boolean := new.role is distinct from old.role
    or new.requested_role is distinct from old.requested_role
    or new.approval_status is distinct from old.approval_status
    or new.approved_by is distinct from old.approved_by
    or new.approved_at is distinct from old.approved_at;
begin
  if not privilege_changed then return new; end if;
  if public.is_administrator() then
    if old.role = 'visitor' and old.requested_role = 'teacher' and old.approval_status = 'pending'
       and new.requested_role = 'teacher' then
      if new.role = 'teacher' and new.approval_status = 'approved' then
        new.approved_by := auth.uid(); new.approved_at := now(); return new;
      elsif new.role = 'visitor' and new.approval_status = 'rejected' then
        new.approved_by := null; new.approved_at := null; return new;
      end if;
    elsif old.role = 'student' and old.approval_status = 'pending' and new.role = 'student'
       and new.requested_role is not distinct from old.requested_role then
      if new.approval_status = 'approved' then
        new.approved_by := auth.uid(); new.approved_at := now(); return new;
      elsif new.approval_status = 'rejected' then
        new.approved_by := null; new.approved_at := null; return new;
      end if;
    end if;
    raise exception 'Transició de rol o aprovació no permesa';
  end if;
  if public.is_teacher() and old.role = 'student' and new.role = 'student'
     and new.requested_role is not distinct from old.requested_role and old.approval_status = 'pending' then
    if new.approval_status = 'approved' then
      new.approved_by := auth.uid(); new.approved_at := now(); return new;
    elsif new.approval_status = 'rejected' then
      new.approved_by := null; new.approved_at := null; return new;
    end if;
  end if;
  raise exception 'No tens permís per modificar el rol o l''aprovació del perfil';
end;
$$;

create or replace function public.set_publication_timestamp()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.status = 'published' and (old.status is distinct from 'published' or new.published_at is null) then
    new.published_at := now();
  elsif new.status <> 'published' then
    new.published_at := null;
  end if;
  return new;
end;
$$;

create or replace function public.record_catalog_object_history()
returns trigger language plpgsql security definer set search_path = pg_catalog, public as $$
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

create or replace function public.protect_catalogue_review_fields()
returns trigger language plpgsql set search_path = public as $$
begin
  if (new.status is distinct from old.status
      or new.reviewed_by is distinct from old.reviewed_by
      or new.reviewed_at is distinct from old.reviewed_at
      or new.review_note is distinct from old.review_note)
     and current_setting('app.catalogue_review', true) is distinct from 'true' then
    raise exception 'Els estats i les dades de revisió només es poden modificar mitjançant el flux de revisió';
  end if;
  return new;
end;
$$;

create or replace function public.protect_catalogue_initial_status()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.status <> 'draft' then
    raise exception 'Les fitxes noves s''han de crear com a esborrany';
  end if;
  return new;
end;
$$;

-- Funcions SECURITY DEFINER petites per evitar recursió de RLS. No retornen dades.
create or replace function public.is_administrator()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.administrators where profile_id = auth.uid());
$$;

create or replace function public.is_teacher()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles where id = auth.uid() and role = 'teacher'
  ) or public.is_administrator();
$$;

create or replace function public.is_approved_student()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'student' and approval_status = 'approved'
  );
$$;

create or replace function public.record_object_tag_history()
returns trigger language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  tag_name text;
  batch_setting text := nullif(current_setting('app.catalogue_history_batch_id', true), '');
  history_details jsonb;
begin
  select t.name into tag_name from public.tags t where t.id = new.tag_id;
  history_details := jsonb_build_object('tag_id', new.tag_id, 'tag_name', tag_name);
  if batch_setting is not null then
    history_details := history_details || jsonb_build_object('batch_id', batch_setting::uuid);
  end if;
  insert into public.catalog_object_history (object_id, action, actor_id, details)
  values (new.object_id, 'tag_added', auth.uid(), history_details);
  return new;
end;
$$;

-- Ruta privada: <uuid-del-usuari>/<uuid-de-fitxer>.<extensió>.
create or replace function public.can_read_catalog_photo(path text)
returns boolean language sql stable security definer set search_path = public, storage as $$
  select exists (
    select 1
    from public.object_photos p
    join public.catalog_objects o on o.id = p.object_id
    where p.storage_path = path and o.status = 'published'
  );
$$;

create trigger on_auth_user_created
  after insert on auth.users for each row execute procedure public.handle_new_user();
create trigger profiles_updated_at before update on public.profiles
  for each row execute procedure public.set_updated_at();
create trigger profiles_protect_privileges before update on public.profiles
  for each row execute procedure public.protect_profile_privileges();
create trigger donors_updated_at before update on public.donors
  for each row execute procedure public.set_updated_at();
create trigger catalog_objects_updated_at before update on public.catalog_objects
  for each row execute procedure public.set_updated_at();
create trigger catalog_objects_publication before update on public.catalog_objects
  for each row execute procedure public.set_publication_timestamp();
create trigger catalog_objects_protect_review_fields before update on public.catalog_objects
  for each row execute procedure public.protect_catalogue_review_fields();
create trigger catalog_objects_protect_initial_status before insert on public.catalog_objects
  for each row execute procedure public.protect_catalogue_initial_status();
create trigger catalog_objects_record_history after insert or update on public.catalog_objects
  for each row execute procedure public.record_catalog_object_history();
create trigger object_tags_record_history after insert on public.object_tags
  for each row execute procedure public.record_object_tag_history();
create trigger proposals_updated_at before update on public.change_proposals
  for each row execute procedure public.set_updated_at();
create trigger activities_updated_at before update on public.activities
  for each row execute procedure public.set_updated_at();
create trigger activities_publication before update on public.activities
  for each row execute procedure public.set_publication_timestamp();

alter table public.profiles enable row level security;
alter table public.administrators enable row level security;
alter table public.object_types enable row level security;
alter table public.cabinets enable row level security;
alter table public.donors enable row level security;
alter table public.catalog_objects enable row level security;
alter table public.catalog_object_history enable row level security;
alter table public.object_photos enable row level security;
alter table public.tags enable row level security;
alter table public.object_tags enable row level security;
alter table public.change_proposals enable row level security;
alter table public.activities enable row level security;
alter table public.donation_contacts enable row level security;

-- Perfils: no contenen correus. L'administrador gestiona tots els perfils i el
-- professorat ordinari només veu o resol sol·licituds d'alumnat.
create policy "profiles: own, student manager or admin read" on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_administrator()
    or (public.is_teacher() and role = 'student'));
create policy "profiles: own, student manager or admin update" on public.profiles for update to authenticated
  using (id = auth.uid() or public.is_administrator()
    or (public.is_teacher() and role = 'student'))
  with check (id = auth.uid() or public.is_administrator()
    or (public.is_teacher() and role = 'student'));
create policy "profiles: direct insert disabled" on public.profiles for insert to authenticated
  with check (false);
create policy "profiles: administrators delete" on public.profiles for delete to authenticated
  using (public.is_administrator());

-- Taules auxiliars internes: necessàries als col·laboradors, no al públic anònim.
create policy "object types: collaborators read" on public.object_types for select to authenticated
  using (public.is_teacher() or public.is_approved_student());
create policy "object types: teachers manage" on public.object_types for all to authenticated
  using (public.is_teacher()) with check (public.is_teacher());
create policy "cabinets: collaborators read" on public.cabinets for select to authenticated
  using (public.is_teacher() or public.is_approved_student());
create policy "cabinets: teachers manage" on public.cabinets for all to authenticated
  using (public.is_teacher()) with check (public.is_teacher());
create policy "donors: teachers manage" on public.donors for all to authenticated
  using (public.is_teacher()) with check (public.is_teacher());

-- Catàleg: la lectura pública passa exclusivament per les vistes amb camps segurs.
create policy "catalog: students read own" on public.catalog_objects for select to authenticated
  using (public.is_approved_student() and created_by = auth.uid());
create policy "catalog: teachers manage" on public.catalog_objects for all to authenticated
  using (public.is_teacher()) with check (public.is_teacher());
create policy "catalog: students create drafts" on public.catalog_objects for insert to authenticated
  with check (public.is_approved_student() and created_by = auth.uid() and status = 'draft'
              and reviewed_by is null and published_at is null
              and ownership in ('museum_property', 'unknown') and donor_id is null);
create policy "catalog: students update own drafts" on public.catalog_objects for update to authenticated
  using (public.is_approved_student() and created_by = auth.uid() and status = 'draft'
         and ownership in ('museum_property', 'unknown') and donor_id is null)
  with check (public.is_approved_student() and created_by = auth.uid() and status = 'draft'
              and reviewed_by is null and published_at is null
              and ownership in ('museum_property', 'unknown') and donor_id is null);
create policy "catalog: students delete own drafts" on public.catalog_objects for delete to authenticated
  using (public.is_approved_student() and created_by = auth.uid() and status = 'draft');
create policy "catalog history: managers and authors read" on public.catalog_object_history for select to authenticated
  using (public.is_teacher() or (
    public.is_approved_student() and exists (
      select 1 from public.catalog_objects o where o.id = object_id and o.created_by = auth.uid()
    )
  ));

create policy "photos: teachers manage" on public.object_photos for all to authenticated
  using (public.is_teacher()) with check (public.is_teacher());
create policy "photos: students manage own drafts" on public.object_photos for all to authenticated
  using (public.is_approved_student() and uploaded_by = auth.uid() and exists (
    select 1 from public.catalog_objects o where o.id = object_id and o.created_by = auth.uid() and o.status = 'draft'
  ))
  with check (public.is_approved_student() and uploaded_by = auth.uid() and exists (
    select 1 from public.catalog_objects o where o.id = object_id and o.created_by = auth.uid() and o.status = 'draft'
  ));

create policy "tags: collaborators read" on public.tags for select to authenticated
  using (public.is_teacher() or public.is_approved_student());
create policy "tags: teachers create" on public.tags for insert to authenticated
  with check (public.is_teacher() and created_by = auth.uid());
create policy "tags: teachers update" on public.tags for update to authenticated
  using (public.is_teacher()) with check (public.is_teacher());
create policy "tags: teachers delete" on public.tags for delete to authenticated
  using (public.is_teacher());

create policy "object tags: teachers read" on public.object_tags for select to authenticated
  using (public.is_teacher());
create policy "object tags: students read own drafts" on public.object_tags for select to authenticated
  using (public.is_approved_student() and exists (
    select 1 from public.catalog_objects o
    where o.id = object_id and o.created_by = auth.uid() and o.status = 'draft'
  ));
create policy "object tags: teachers associate" on public.object_tags for insert to authenticated
  with check (public.is_teacher() and created_by = auth.uid());
create policy "object tags: students associate own drafts" on public.object_tags for insert to authenticated
  with check (public.is_approved_student() and created_by = auth.uid() and exists (
    select 1 from public.catalog_objects o
    where o.id = object_id and o.created_by = auth.uid() and o.status = 'draft'
  ));
create policy "object tags: teachers remove" on public.object_tags for delete to authenticated
  using (public.is_teacher());
create policy "object tags: students remove own drafts" on public.object_tags for delete to authenticated
  using (public.is_approved_student() and exists (
    select 1 from public.catalog_objects o
    where o.id = object_id and o.created_by = auth.uid() and o.status = 'draft'
  ));

create policy "proposals: submitters read own" on public.change_proposals for select to authenticated
  using (submitted_by = auth.uid());
create policy "proposals: teachers manage" on public.change_proposals for all to authenticated
  using (public.is_teacher()) with check (public.is_teacher());
create policy "proposals: students create" on public.change_proposals for insert to authenticated
  with check (public.is_approved_student() and submitted_by = auth.uid() and status = 'open'
              and reviewed_by is null and reviewer_note is null);

create policy "activities: public published read" on public.activities for select to anon, authenticated
  using (status = 'published');
create policy "activities: teachers manage" on public.activities for all to authenticated
  using (public.is_teacher()) with check (public.is_teacher());

create policy "donation contacts: public create" on public.donation_contacts for insert to anon, authenticated
  with check (status = 'new' and handled_by is null and handled_at is null);
create policy "donation contacts: teachers manage" on public.donation_contacts for all to authenticated
  using (public.is_teacher()) with check (public.is_teacher());

-- Storage privat: el frontend només pot llegir fotos vinculades a fitxes publicades.
-- Supabase ja aplica RLS a storage.objects; la taula és gestionada pel servei.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('catalog-photos', 'catalog-photos', false, 10485760, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;
create policy "catalog photos: public linked read" on storage.objects for select to anon, authenticated
  using (bucket_id = 'catalog-photos' and public.can_read_catalog_photo(name));
create policy "catalog photos: students upload own folder" on storage.objects for insert to authenticated
  with check (bucket_id = 'catalog-photos' and public.is_approved_student()
    and (storage.foldername(name))[1] = auth.uid()::text);
create policy "catalog photos: students delete own folder" on storage.objects for delete to authenticated
  using (bucket_id = 'catalog-photos' and public.is_approved_student()
    and (storage.foldername(name))[1] = auth.uid()::text);
create policy "catalog photos: teachers manage" on storage.objects for all to authenticated
  using (bucket_id = 'catalog-photos' and public.is_teacher())
  with check (bucket_id = 'catalog-photos' and public.is_teacher());

revoke all on all tables in schema public from anon, authenticated;
grant usage on schema public to anon, authenticated;
grant select on public.activities to anon;
grant insert on public.donation_contacts to anon;
grant select, insert, update, delete on all tables in schema public to authenticated;
-- Les taules del catàleg no s'exposen al públic: anon només pot consultar les
-- vistes amb columnes segures. `authenticated` manté l'accés sotmés a RLS per
-- al professorat i a l'alumnat propietari dels seus esborranys.
revoke select on public.catalog_objects, public.object_photos, public.tags, public.object_tags from anon;
revoke all on public.catalog_object_history from anon, authenticated;
grant select on public.catalog_object_history to authenticated;
revoke all on function public.is_administrator() from public;
grant execute on function public.is_administrator() to authenticated;
grant execute on function public.is_teacher(), public.is_approved_student(), public.can_read_catalog_photo(text) to anon, authenticated;
revoke all on function public.assign_inventory_code() from public;
grant execute on function public.assign_inventory_code() to authenticated;
revoke all on function public.record_catalog_object_history() from public, anon, authenticated;
revoke all on function public.record_object_tag_history() from public, anon, authenticated;

comment on table public.donation_contacts is 'Dades de contacte privades; l''alta pública no implica lectura pública.';
comment on table public.object_photos is 'Metadades d''imatges emmagatzemades al bucket privat catalog-photos.';
comment on column public.profiles.requested_role is 'Petició validada en el registre: student o teacher. No concedeix privilegis per si mateixa.';

-- API pública mínima: les taules del catàleg conserven camps interns i només
-- aquestes vistes SECURITY DEFINER exposen les columnes segures de peces publicades.
create view public.public_catalog_objects
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

create view public.public_object_photos
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

create view public.public_catalog_object_tags
with (security_barrier = true, security_invoker = false) as
select
  ot.object_id,
  t.name,
  t.normalized_name
from public.object_tags ot
join public.catalog_objects o on o.id = ot.object_id
join public.tags t on t.id = ot.tag_id
where o.status = 'published';

grant select on public.public_catalog_objects, public.public_object_photos,
  public.public_catalog_object_tags to anon, authenticated;

-- Ús exclusiu del professorat o l'administració: la funció resol el donant
-- privat i la peça en una única transacció, sense exposar dades de donants.
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
    select d.id into v_donor_id from public.donors d
    where lower(btrim(d.display_name)) = v_normalized_donor_name
    order by d.id limit 1;
    if v_donor_id is null then
      insert into public.donors (display_name) values (btrim(p_donor_name))
      returning id into v_donor_id;
    end if;
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
    if not found then raise exception 'Fitxa no trobada'; end if;
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

-- Contracte RPC del frontend: valida el JSON abans de delegar l'escriptura
-- atòmica i la gestió privada del donant a la funció interna.
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

-- Única via per a les transicions d'estat: el trigger n'escriu la traça amb la nota.
create or replace function public.review_catalog_object(
  object_uuid uuid,
  next_status public.catalog_status,
  note text default null,
  p_review_reason text default null,
  p_pending_tasks jsonb default null
)
returns public.catalog_objects language plpgsql security definer set search_path = pg_catalog, public as $$
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
         select 1 from jsonb_array_elements(p_pending_tasks) as task(value)
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
  review_reason text,
  pending_tasks jsonb,
  created_at timestamptz,
  display_name text
)
language plpgsql security definer set search_path = pg_catalog, public as $$
begin
  if page_limit is null or page_limit not between 1 and 50 then
    raise exception 'El límit ha d''estar entre 1 i 50';
  end if;
  if not public.is_teacher() and not exists (
    select 1 from public.catalog_objects o
    where o.id = object_uuid and o.created_by = auth.uid() and public.is_approved_student()
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

-- Accions docents atòmiques: valida i bloqueja tot el lot abans de modificar-lo.
create or replace function public.bulk_manage_catalog_objects(
  p_object_ids uuid[],
  p_operation text,
  p_tag_id uuid default null
)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  requested integer := coalesce(cardinality(p_object_ids), 0);
  locked_ids uuid[] := '{}'::uuid[];
  locked_object record;
  tag_name text;
  batch_id uuid;
  errors jsonb := '[]'::jsonb;
  validation_errors jsonb;
begin
  if not public.is_teacher() then raise exception 'No tens permís per gestionar fitxes en lot'; end if;
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

  for locked_object in
    select o.id, o.status from public.catalog_objects o
    where o.id = any(p_object_ids) order by o.id for update
  loop
    locked_ids := array_append(locked_ids, locked_object.id);
  end loop;
  if cardinality(locked_ids) <> requested then
    errors := errors || jsonb_build_array(jsonb_build_object('code', 'object_not_found'));
  end if;

  if p_operation = 'add_tag' then
    select t.name into tag_name from public.tags t where t.id = p_tag_id for key share;
    if not found then
      errors := errors || jsonb_build_array(jsonb_build_object('code', 'tag_not_found'));
    elsif exists (select 1 from public.object_tags ot where ot.tag_id = p_tag_id and ot.object_id = any(locked_ids)) then
      errors := errors || jsonb_build_array(jsonb_build_object('code', 'tag_already_associated'));
    end if;
  elsif p_operation = 'publish' then
    select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'status', o.status) order by o.id), '[]'::jsonb)
      into validation_errors from public.catalog_objects o
      where o.id = any(locked_ids) and o.status not in ('draft', 'pending_review');
    if validation_errors <> '[]'::jsonb then
      errors := errors || jsonb_build_array(jsonb_build_object('code', 'invalid_publish_status', 'objects', validation_errors));
    end if;
  elsif p_operation = 'archive' then
    select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'status', o.status) order by o.id), '[]'::jsonb)
      into validation_errors from public.catalog_objects o
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
      select object_id, p_tag_id, auth.uid() from unnest(locked_ids) as input(object_id);
    exception when unique_violation then
      return jsonb_build_object('ok', false, 'requested', requested, 'changed', 0,
        'errors', jsonb_build_array(jsonb_build_object('code', 'tag_already_associated')));
    end;
  else
    perform set_config('app.catalogue_review', 'true', true);
    perform set_config('app.catalogue_history_note', '', true);
    update public.catalog_objects
    set status = p_operation::public.catalog_status, reviewed_by = auth.uid(),
        reviewed_at = now(), review_note = null
    where id = any(locked_ids);
  end if;

  return jsonb_build_object('ok', true, 'requested', requested, 'changed', requested,
    'ids', to_jsonb(locked_ids),
    'batch_id', case when batch_id is null then null else to_jsonb(batch_id) end);
end;
$$;

revoke all on function public.save_catalog_object_with_contact(uuid, jsonb, text)
  from public, anon, authenticated;
grant execute on function public.save_catalog_object_with_contact(uuid, jsonb, text)
  to authenticated;
revoke all on function public.review_catalog_object(uuid, public.catalog_status, text, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.review_catalog_object(uuid, public.catalog_status, text, text, jsonb) to authenticated;
revoke all on function public.get_catalog_object_history(uuid, integer, timestamptz, uuid)
  from public, anon, authenticated;
grant execute on function public.get_catalog_object_history(uuid, integer, timestamptz, uuid) to authenticated;
revoke all on function public.bulk_manage_catalog_objects(uuid[], text, uuid)
  from public, anon, authenticated;
grant execute on function public.bulk_manage_catalog_objects(uuid[], text, uuid) to authenticated;

comment on view public.public_catalog_objects is
  'Catàleg públic: camps explícitament segurs de peces publicades, amb procedència no identificativa i sense metadades internes.';
comment on view public.public_object_photos is
  'Metadades públiques de fotos vinculades exclusivament a peces publicades.';
comment on view public.public_catalog_object_tags is
  'Etiquetes públiques de peces publicades, per a filtres sense exposar les taules base.';
