-- Governança del catàleg: administració explícita, revisió traçable i flux segur.
begin;

create table public.administrators (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.administrators enable row level security;

-- Conserva l'administrador inicial mentre es migra des de la regla anterior basada en correu.
insert into public.administrators (profile_id)
select p.id
from public.profiles p
join auth.users u on u.id = p.id
where lower(u.email) = 'f.masdomenech@edu.gva.es'
on conflict do nothing;

create or replace function public.is_administrator()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.administrators where profile_id = auth.uid());
$$;

create or replace function public.bootstrap_administrator()
returns void language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.administrators) then
    raise exception 'Ja existeix una administració configurada';
  end if;
  if lower(coalesce(auth.jwt() ->> 'email', '')) <> 'f.masdomenech@edu.gva.es' then
    raise exception 'No tens permís per inicialitzar l''administració';
  end if;
  if not exists (select 1 from public.profiles where id = auth.uid()) then
    raise exception 'El perfil encara no està disponible';
  end if;
  insert into public.administrators (profile_id) values (auth.uid());
end;
$$;

-- Els administradors tenen les capacitats operatives del professorat sense duplicar polítiques.
create or replace function public.is_teacher()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles where id = auth.uid() and role = 'teacher'
  ) or public.is_administrator();
$$;

alter table public.catalog_objects
  add column if not exists reviewed_at timestamptz,
  add column if not exists review_note text check (char_length(review_note) <= 2000);

alter table public.change_proposals
  add column if not exists reviewed_at timestamptz;

alter table public.donation_contacts
  add column if not exists consent_at timestamptz,
  add column if not exists consent_version text check (char_length(consent_version) <= 40);

drop policy if exists "donation contacts: public create" on public.donation_contacts;
drop policy if exists "catalog photos: students delete own folder" on storage.objects;
create policy "catalog photos: students delete own draft files" on storage.objects for delete to authenticated
  using (bucket_id = 'catalog-photos' and public.is_approved_student()
    and (storage.foldername(name))[1] = auth.uid()::text
    and (not exists (select 1 from public.object_photos p where p.storage_path = name)
      or exists (
        select 1 from public.object_photos p
        join public.catalog_objects o on o.id = p.object_id
        where p.storage_path = name and o.created_by = auth.uid() and o.status = 'draft'
      )));

create table public.catalog_object_revisions (
  id uuid primary key default gen_random_uuid(),
  object_id uuid not null references public.catalog_objects(id) on delete cascade,
  status public.catalog_status not null,
  note text check (char_length(note) <= 2000),
  changed_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create index catalog_object_revisions_object_idx on public.catalog_object_revisions (object_id, created_at desc);
alter table public.catalog_object_revisions enable row level security;
create policy "revisions: authors and managers read" on public.catalog_object_revisions for select to authenticated
  using (public.is_teacher() or exists (
    select 1 from public.catalog_objects o
    where o.id = object_id and o.created_by = auth.uid() and public.is_approved_student()
  ));

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

drop trigger if exists catalog_objects_protect_review_fields on public.catalog_objects;
create trigger catalog_objects_protect_review_fields before update on public.catalog_objects
  for each row execute procedure public.protect_catalogue_review_fields();

create or replace function public.protect_catalogue_initial_status()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.status <> 'draft' then
    raise exception 'Les fitxes noves s''han de crear com a esborrany';
  end if;
  return new;
end;
$$;

drop trigger if exists catalog_objects_protect_initial_status on public.catalog_objects;
create trigger catalog_objects_protect_initial_status before insert on public.catalog_objects
  for each row execute procedure public.protect_catalogue_initial_status();

-- L'única via per a enviar, retornar, publicar o arxivar una fitxa és aquesta funció.
create or replace function public.review_catalog_object(
  object_uuid uuid,
  next_status public.catalog_status,
  note text default null
)
returns public.catalog_objects language plpgsql security definer set search_path = public as $$
declare
  current_object public.catalog_objects;
begin
  perform set_config('app.catalogue_review', 'true', true);
  select * into current_object from public.catalog_objects where id = object_uuid for update;
  if not found then raise exception 'Fitxa no trobada'; end if;
  if next_status = 'pending_review' then
    if current_object.created_by <> auth.uid() or not public.is_approved_student() or current_object.status <> 'draft' then
      raise exception 'No pots enviar aquesta fitxa a revisió';
    end if;
  elsif next_status in ('draft', 'published', 'archived') then
    if not public.is_teacher() then raise exception 'No tens permís per revisar fitxes'; end if;
    if next_status = 'draft' and current_object.status <> 'pending_review' then raise exception 'Només es poden retornar fitxes pendents'; end if;
    if next_status = 'published' and current_object.status not in ('draft', 'pending_review') then raise exception 'Transició de publicació no permesa'; end if;
  else
    raise exception 'Estat no permés';
  end if;
  if next_status = 'draft' and coalesce(length(trim(note)), 0) = 0 then raise exception 'Cal indicar un comentari en retornar una fitxa'; end if;
  update public.catalog_objects
  set status = next_status,
      reviewed_by = case when public.is_teacher() then auth.uid() else reviewed_by end,
      reviewed_at = case when public.is_teacher() then now() else reviewed_at end,
      review_note = case when public.is_teacher() then nullif(trim(note), '') else review_note end
  where id = object_uuid
  returning * into current_object;
  insert into public.catalog_object_revisions (object_id, status, note, changed_by)
  values (object_uuid, next_status, nullif(trim(note), ''), auth.uid());
  return current_object;
end;
$$;

-- Els esborranys d'alumnat s'editen directament; enviar-los a revisió passa per la RPC.
revoke update on public.catalog_objects from authenticated;
grant update on public.catalog_objects to authenticated;
grant execute on function public.review_catalog_object(uuid, public.catalog_status, text) to authenticated;
grant execute on function public.bootstrap_administrator() to authenticated;

create or replace function public.review_change_proposal(
  proposal_uuid uuid,
  next_status public.proposal_status,
  note text default null
)
returns public.change_proposals language plpgsql security definer set search_path = public as $$
declare
  proposal public.change_proposals;
begin
  if not public.is_teacher() then raise exception 'No tens permís per revisar propostes'; end if;
  if next_status not in ('accepted', 'rejected', 'implemented') then raise exception 'Estat no permés'; end if;
  if next_status = 'rejected' and coalesce(length(trim(note)), 0) = 0 then
    raise exception 'Cal explicar el motiu del rebuig';
  end if;
  update public.change_proposals
  set status = next_status,
      reviewed_by = auth.uid(),
      reviewed_at = now(),
      reviewer_note = nullif(trim(note), '')
  where id = proposal_uuid and status in ('open', 'accepted')
  returning * into proposal;
  if not found then raise exception 'La proposta no es pot revisar en l''estat actual'; end if;
  return proposal;
end;
$$;

drop policy if exists "proposals: teachers manage" on public.change_proposals;
create policy "proposals: managers read" on public.change_proposals for select to authenticated
  using (public.is_teacher());
grant execute on function public.review_change_proposal(uuid, public.proposal_status, text) to authenticated;
grant select on public.catalog_object_revisions to authenticated;

commit;
