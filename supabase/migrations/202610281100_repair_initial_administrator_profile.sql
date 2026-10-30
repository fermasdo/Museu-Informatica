-- Reparació puntual i idempotent de l'administració inicial.
-- Impacte de dades: només crea el perfil si existeix l'usuari d'Auth indicat i
-- encara no té fila a public.profiles; no modifica perfils ni rols existents.
-- Permisos: public.administrators ja té RLS activada i les seues polítiques no
-- canvien. Aquesta migració s'executa amb privilegis de migració, no des del client.
begin;

-- public.profiles usa id, display_name, role, requested_role i approval_status.
-- Es manté com a visitant sense sol·licitud: l'administració ve donada per la
-- relació explícita public.administrators(profile_id), no pel rol teacher.
insert into public.profiles (
  id,
  display_name,
  role,
  requested_role,
  approval_status
)
select
  u.id,
  'F. Masdomenech',
  'visitor'::public.profile_role,
  null,
  'not_required'::public.approval_state
from auth.users u
where lower(u.email) = 'f.masdomenech@edu.gva.es'
  and not exists (
    select 1
    from public.profiles p
    where p.id = u.id
  );

-- public.administrators usa profile_id com a clau primària. La inserció només
-- pot arribar a un perfil existent i es pot repetir sense canviar cap fila.
insert into public.administrators (profile_id)
select p.id
from public.profiles p
join auth.users u on u.id = p.id
where lower(u.email) = 'f.masdomenech@edu.gva.es'
on conflict do nothing;

-- No es modifica public.handle_new_user ni el trigger on_auth_user_created:
-- ja creen un perfil per a cada futur insert en auth.users.
commit;
