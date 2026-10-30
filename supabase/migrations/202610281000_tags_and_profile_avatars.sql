-- Etiquetes normalitzades per al catàleg i avatars privats dels perfils.
-- No es creen URL públiques: l'accés als avatars passa sempre per Storage amb RLS.
begin;

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

-- Les cerques de peces publicades per etiqueta comencen habitualment per tag_id.
create index object_tags_tag_object_idx on public.object_tags (tag_id, object_id);

alter table public.profiles
  add column avatar_path text,
  add constraint profiles_avatar_path_format_check check (
    avatar_path is null or avatar_path ~
      '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[A-Za-z0-9][A-Za-z0-9._-]{0,127}\.(jpeg|jpg|png|webp)$'
  );

-- La columna només pot apuntar al directori privat del seu propietari.
-- Això evita que professorat amb permís de gestionar perfils publique o redirigisca
-- l'avatar d'una altra persona.
create or replace function public.protect_profile_avatar_path()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.avatar_path is distinct from old.avatar_path then
    if auth.uid() is distinct from old.id then
      raise exception 'Només la persona propietària pot modificar el seu avatar';
    end if;
    if new.avatar_path is not null
       and split_part(new.avatar_path, '/', 1) <> old.id::text then
      raise exception 'La ruta de l''avatar ha de pertànyer al perfil';
    end if;
  end if;
  return new;
end;
$$;

create trigger profiles_protect_avatar_path before update on public.profiles
  for each row execute procedure public.protect_profile_avatar_path();

revoke all on function public.protect_profile_avatar_path() from public;

alter table public.tags enable row level security;
alter table public.object_tags enable row level security;

-- El públic només coneix etiquetes que ja apareixen en una peça publicada.
create policy "tags: public relevant read" on public.tags for select to anon, authenticated
  using (exists (
    select 1
    from public.object_tags ot
    join public.catalog_objects o on o.id = ot.object_id
    where ot.tag_id = public.tags.id and o.status = 'published'
  ));
create policy "tags: collaborators read" on public.tags for select to authenticated
  using (public.is_teacher() or public.is_approved_student());
create policy "tags: teachers create" on public.tags for insert to authenticated
  with check (public.is_teacher() and created_by = auth.uid());
create policy "tags: teachers update" on public.tags for update to authenticated
  using (public.is_teacher()) with check (public.is_teacher());
create policy "tags: teachers delete" on public.tags for delete to authenticated
  using (public.is_teacher());

create policy "object tags: public published read" on public.object_tags for select to anon, authenticated
  using (exists (
    select 1 from public.catalog_objects o
    where o.id = object_id and o.status = 'published'
  ));
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

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'profile-avatars', 'profile-avatars', false, 2097152,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Una ruta d'avatar és exactament <auth.uid()>/<fitxer>.extensió.
create policy "profile avatars: owner read" on storage.objects for select to authenticated
  using (
    bucket_id = 'profile-avatars'
    and name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[A-Za-z0-9][A-Za-z0-9._-]{0,127}\.(jpeg|jpg|png|webp)$'
    and split_part(name, '/', 1) = auth.uid()::text
  );
create policy "profile avatars: owner upload" on storage.objects for insert to authenticated
  with check (
    bucket_id = 'profile-avatars'
    and name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[A-Za-z0-9][A-Za-z0-9._-]{0,127}\.(jpeg|jpg|png|webp)$'
    and split_part(name, '/', 1) = auth.uid()::text
  );
create policy "profile avatars: owner replace" on storage.objects for update to authenticated
  using (bucket_id = 'profile-avatars' and split_part(name, '/', 1) = auth.uid()::text)
  with check (
    bucket_id = 'profile-avatars'
    and name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[A-Za-z0-9][A-Za-z0-9._-]{0,127}\.(jpeg|jpg|png|webp)$'
    and split_part(name, '/', 1) = auth.uid()::text
  );
create policy "profile avatars: owner delete" on storage.objects for delete to authenticated
  using (
    bucket_id = 'profile-avatars'
    and split_part(name, '/', 1) = auth.uid()::text
  );

grant select on public.tags, public.object_tags to anon;
grant select, insert, update, delete on public.tags to authenticated;
grant select, insert, delete on public.object_tags to authenticated;

comment on table public.tags is 'Vocabulari normalitzat d''etiquetes, gestionat pel professorat.';
comment on table public.object_tags is 'Associacions entre peces del catàleg i etiquetes normalitzades.';
comment on column public.profiles.avatar_path is 'Ruta privada <profile-id>/<fitxer> al bucket profile-avatars; no és una URL pública.';

commit;
