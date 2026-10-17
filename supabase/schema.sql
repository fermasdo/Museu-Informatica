-- Museu d'Informàtica IES l'Estació
-- Esquema inicial versionat: 1.0.0 (2026-10-17)
-- Apliqueu-lo només a un projecte Supabase nou o mitjançant una migració inicial.

create extension if not exists pgcrypto;

create type public.profile_role as enum ('visitor', 'student', 'teacher');
create type public.approval_state as enum ('not_required', 'pending', 'approved', 'rejected');
create type public.catalog_status as enum ('draft', 'pending_review', 'published', 'archived');
create type public.ownership_kind as enum ('donation', 'loan', 'museum_property', 'unknown');
create type public.object_condition as enum ('excellent', 'good', 'fair', 'poor', 'unknown');
create type public.proposal_status as enum ('open', 'accepted', 'rejected', 'implemented');
create type public.activity_kind as enum ('gymkhana', 'cinema', 'library');

-- Un perfil és creat automàticament per al seu usuari d'Auth. Els rols elevats
-- no es poden escollir en el registre del client.
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(trim(display_name)) between 2 and 100),
  role public.profile_role not null default 'visitor',
  approval_status public.approval_state not null default 'not_required',
  approved_by uuid references public.profiles(id) on delete set null,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_approval_consistency check (
    (role = 'student' and approval_status in ('pending', 'approved', 'rejected'))
    or (role <> 'student' and approval_status = 'not_required')
  ),
  constraint profiles_approval_audit check (
    (approval_status = 'approved' and approved_by is not null and approved_at is not null)
    or approval_status <> 'approved'
  )
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
  room text not null check (char_length(trim(room)) between 1 and 80),
  shelf text check (char_length(trim(shelf)) between 1 and 40),
  notes text check (char_length(notes) <= 500),
  created_at timestamptz not null default now()
);

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
  inventory_code text not null unique check (inventory_code ~ '^[A-Z0-9][A-Z0-9_-]{2,39}$'),
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
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint catalog_object_year_range check (
    production_year_end is null or production_year_start is null
    or production_year_end >= production_year_start
  ),
  constraint catalog_object_loan_donor check (
    ownership <> 'loan' or donor_id is not null
  ),
  constraint catalog_object_loan_date check (
    ownership = 'loan' or loan_due_date is null
  ),
  constraint catalog_object_publication_date check (
    status <> 'published' or published_at is not null
  )
);

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
create index object_photos_object_idx on public.object_photos (object_id, position);
create index change_proposals_submitter_idx on public.change_proposals (submitted_by, status, created_at desc);
create index donation_contacts_status_idx on public.donation_contacts (status, created_at desc);

create or replace function public.set_updated_at()
returns trigger language plpgsql set search_path = public as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, display_name, role, approval_status)
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''), 'Visitant'),
    'visitor',
    'not_required'
  );
  return new;
end;
$$;

-- Impedeix que un usuari es concedisca privilegis o s'aprove a si mateix.
create or replace function public.protect_profile_privileges()
returns trigger language plpgsql set search_path = public as $$
begin
  if auth.uid() = old.id and (
    new.role is distinct from old.role
    or new.approval_status is distinct from old.approval_status
    or new.approved_by is distinct from old.approved_by
    or new.approved_at is distinct from old.approved_at
  ) then
    raise exception 'No pots modificar el rol ni l''aprovació del teu perfil';
  end if;

  if public.is_teacher() and new.role = 'student' and old.role <> 'student' then
    new.approval_status := 'pending';
    new.approved_by := null;
    new.approved_at := null;
  elsif public.is_teacher() and new.role <> 'student' then
    new.approval_status := 'not_required';
    new.approved_by := null;
    new.approved_at := null;
  elsif public.is_teacher() and new.approval_status = 'approved'
        and old.approval_status is distinct from 'approved' then
    new.approved_by := auth.uid();
    new.approved_at := now();
  end if;
  return new;
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

-- Funcions SECURITY DEFINER petites per evitar recursió de RLS. No retornen dades.
create or replace function public.is_teacher()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles where id = auth.uid() and role = 'teacher'
  );
$$;

create or replace function public.is_approved_student()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'student' and approval_status = 'approved'
  );
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
create trigger proposals_updated_at before update on public.change_proposals
  for each row execute procedure public.set_updated_at();
create trigger activities_updated_at before update on public.activities
  for each row execute procedure public.set_updated_at();
create trigger activities_publication before update on public.activities
  for each row execute procedure public.set_publication_timestamp();

alter table public.profiles enable row level security;
alter table public.object_types enable row level security;
alter table public.cabinets enable row level security;
alter table public.donors enable row level security;
alter table public.catalog_objects enable row level security;
alter table public.object_photos enable row level security;
alter table public.change_proposals enable row level security;
alter table public.activities enable row level security;
alter table public.donation_contacts enable row level security;

-- Perfils: cada persona veu/edita les seues dades bàsiques; el professorat gestiona rols i aprovacions.
create policy "profiles: own or teacher read" on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_teacher());
create policy "profiles: own or teacher update" on public.profiles for update to authenticated
  using (id = auth.uid() or public.is_teacher())
  with check (id = auth.uid() or public.is_teacher());
create policy "profiles: direct insert disabled" on public.profiles for insert to authenticated
  with check (false);
create policy "profiles: teachers delete" on public.profiles for delete to authenticated
  using (public.is_teacher());

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

-- Catàleg: només les fitxes publicades són visibles anònimament.
create policy "catalog: public published read" on public.catalog_objects for select to anon, authenticated
  using (status = 'published');
create policy "catalog: students read own" on public.catalog_objects for select to authenticated
  using (public.is_approved_student() and created_by = auth.uid());
create policy "catalog: teachers manage" on public.catalog_objects for all to authenticated
  using (public.is_teacher()) with check (public.is_teacher());
create policy "catalog: students create drafts" on public.catalog_objects for insert to authenticated
  with check (public.is_approved_student() and created_by = auth.uid() and status = 'draft'
              and reviewed_by is null and published_at is null);
create policy "catalog: students update own drafts" on public.catalog_objects for update to authenticated
  using (public.is_approved_student() and created_by = auth.uid() and status = 'draft')
  with check (public.is_approved_student() and created_by = auth.uid() and status = 'draft'
              and reviewed_by is null and published_at is null);
create policy "catalog: students delete own drafts" on public.catalog_objects for delete to authenticated
  using (public.is_approved_student() and created_by = auth.uid() and status = 'draft');

create policy "photos: public published read" on public.object_photos for select to anon, authenticated
  using (exists (select 1 from public.catalog_objects o where o.id = object_id and o.status = 'published'));
create policy "photos: teachers manage" on public.object_photos for all to authenticated
  using (public.is_teacher()) with check (public.is_teacher());
create policy "photos: students manage own drafts" on public.object_photos for all to authenticated
  using (public.is_approved_student() and uploaded_by = auth.uid() and exists (
    select 1 from public.catalog_objects o where o.id = object_id and o.created_by = auth.uid() and o.status = 'draft'
  ))
  with check (public.is_approved_student() and uploaded_by = auth.uid() and exists (
    select 1 from public.catalog_objects o where o.id = object_id and o.created_by = auth.uid() and o.status = 'draft'
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
alter table storage.objects enable row level security;
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
grant select on public.catalog_objects, public.object_photos, public.activities to anon;
grant insert on public.donation_contacts to anon;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on function public.is_teacher(), public.is_approved_student(), public.can_read_catalog_photo(text) to anon, authenticated;

comment on table public.donation_contacts is 'Dades de contacte privades; l''alta pública no implica lectura pública.';
comment on table public.object_photos is 'Metadades d''imatges emmagatzemades al bucket privat catalog-photos.';
