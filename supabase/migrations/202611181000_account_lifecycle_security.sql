-- Cicle de vida de comptes: confirmació, suspensió i gestió administrativa.
-- Impacte: tots els perfils existents passen a estat actiu. No s'elimina cap dada.
begin;

create type public.account_state as enum ('active', 'suspended');

alter table public.profiles
  add column account_status public.account_state not null default 'active',
  add column suspended_by uuid references public.profiles(id) on delete set null,
  add column suspended_at timestamptz,
  add column suspension_reason text,
  add constraint profiles_account_suspension_audit check (
    (account_status = 'active' and suspended_by is null and suspended_at is null and suspension_reason is null)
    or (
      account_status = 'suspended' and suspended_by is not null and suspended_at is not null
      and char_length(btrim(suspension_reason)) between 3 and 1000
    )
  );

-- SECURITY DEFINER evita que les polítiques de profiles es criden recursivament.
-- La confirmació es consulta en auth.users; aquest fet no s'exposa per l'API.
create or replace function public.is_active_confirmed_user()
returns boolean language sql stable security definer set search_path = pg_catalog, public as $$
  select auth.uid() is not null and exists (
    select 1
    from auth.users u
    join public.profiles p on p.id = u.id
    where u.id = auth.uid()
      and u.email_confirmed_at is not null
      and p.account_status = 'active'
  );
$$;

create or replace function public.is_administrator()
returns boolean language sql stable security definer set search_path = pg_catalog, public as $$
  select public.is_active_confirmed_user() and exists (
    select 1 from public.administrators a where a.profile_id = auth.uid()
  );
$$;

create or replace function public.is_teacher()
returns boolean language sql stable security definer set search_path = pg_catalog, public as $$
  select public.is_administrator() or (
    public.is_active_confirmed_user() and exists (
      select 1 from public.profiles
      where id = auth.uid() and role = 'teacher' and approval_status = 'approved'
    )
  );
$$;

create or replace function public.is_approved_student()
returns boolean language sql stable security definer set search_path = pg_catalog, public as $$
  select public.is_active_confirmed_user() and exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'student' and approval_status = 'approved'
  );
$$;

-- Ús intern de les accions de cicle de vida; no exposa identitats ni correus.
create or replace function public.active_confirmed_administrator_count(p_exclude_profile_id uuid default null)
returns integer language sql stable security definer set search_path = pg_catalog, public as $$
  select count(*)::integer
  from public.administrators a
  join public.profiles p on p.id = a.profile_id
  join auth.users u on u.id = a.profile_id
  where a.profile_id is distinct from p_exclude_profile_id
    and p.account_status = 'active'
    and u.email_confirmed_at is not null;
$$;

-- Les modificacions de privilegis i de cicle de vida només passen per les RPC.
create or replace function public.protect_profile_privileges()
returns trigger language plpgsql set search_path = pg_catalog, public as $$
begin
  if new.role is distinct from old.role
     or new.requested_role is distinct from old.requested_role
     or new.approval_status is distinct from old.approval_status
     or new.approved_by is distinct from old.approved_by
     or new.approved_at is distinct from old.approved_at
     or new.account_status is distinct from old.account_status
     or new.suspended_by is distinct from old.suspended_by
     or new.suspended_at is distinct from old.suspended_at
     or new.suspension_reason is distinct from old.suspension_reason then
    if current_setting('app.profile_lifecycle', true) is distinct from 'true' then
      raise exception 'El rol, l''aprovació i l''estat del compte només es poden modificar mitjançant les accions de gestió autoritzades';
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.decide_profile_approval(
  p_profile_id uuid,
  p_decision text
)
returns void language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_profile public.profiles;
begin
  if auth.uid() is null or not public.is_active_confirmed_user() then
    raise exception 'Cal un compte actiu i confirmat';
  end if;
  if p_profile_id is null or p_decision not in ('approve', 'reject') then
    raise exception 'La decisió o el perfil no són vàlids';
  end if;
  if p_profile_id = auth.uid() then raise exception 'No pots decidir la teua pròpia sol·licitud'; end if;

  select * into v_profile from public.profiles where id = p_profile_id for update;
  if not found then raise exception 'Perfil no trobat'; end if;
  if v_profile.account_status <> 'active' then raise exception 'No es pot decidir un compte suspés'; end if;

  if v_profile.role = 'student' and v_profile.requested_role = 'student'
     and v_profile.approval_status = 'pending' then
    if not public.is_teacher() then raise exception 'No tens permís per decidir sol·licituds d''alumnat'; end if;
    perform set_config('app.profile_lifecycle', 'true', true);
    update public.profiles set approval_status = case when p_decision = 'approve' then 'approved'::public.approval_state else 'rejected'::public.approval_state end,
      approved_by = case when p_decision = 'approve' then auth.uid() else null end,
      approved_at = case when p_decision = 'approve' then now() else null end
    where id = p_profile_id;
  elsif v_profile.role = 'visitor' and v_profile.requested_role = 'teacher'
     and v_profile.approval_status = 'pending' then
    if not public.is_administrator() then raise exception 'Només l''administració pot decidir sol·licituds docents'; end if;
    perform set_config('app.profile_lifecycle', 'true', true);
    update public.profiles set role = case when p_decision = 'approve' then 'teacher'::public.profile_role else 'visitor'::public.profile_role end,
      approval_status = case when p_decision = 'approve' then 'approved'::public.approval_state else 'rejected'::public.approval_state end,
      approved_by = case when p_decision = 'approve' then auth.uid() else null end,
      approved_at = case when p_decision = 'approve' then now() else null end
    where id = p_profile_id;
  else
    raise exception 'La sol·licitud no es pot decidir en l''estat actual';
  end if;
end;
$$;

create or replace function public.set_profile_account_status(
  p_profile_id uuid,
  p_status public.account_state,
  p_reason text default null
)
returns void language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  v_profile public.profiles;
  v_reason text := nullif(btrim(p_reason), '');
  v_other_active_administrators integer;
begin
  if not public.is_administrator() then raise exception 'Només l''administració pot suspendre o restaurar comptes'; end if;
  if p_profile_id is null or p_status is null then raise exception 'El perfil i l''estat són obligatoris'; end if;
  if p_profile_id = auth.uid() then raise exception 'No pots suspendre ni restaurar el teu propi compte'; end if;
  if p_status = 'suspended' and (v_reason is null or char_length(v_reason) not between 3 and 1000) then
    raise exception 'La suspensió requereix un motiu de 3 a 1000 caràcters';
  end if;
  if p_status = 'active' and v_reason is not null then raise exception 'La restauració no admet un motiu de suspensió'; end if;

  select * into v_profile from public.profiles where id = p_profile_id for update;
  if not found then raise exception 'Perfil no trobat'; end if;
  if v_profile.account_status = p_status then raise exception 'El compte ja té aquest estat'; end if;
  if p_status = 'suspended' and exists (select 1 from public.administrators where profile_id = p_profile_id) then
    select public.active_confirmed_administrator_count(p_profile_id) into v_other_active_administrators;
    if v_other_active_administrators = 0 then raise exception 'No es pot suspendre l''últim compte administrador actiu'; end if;
  end if;

  perform set_config('app.profile_lifecycle', 'true', true);
  update public.profiles set account_status = p_status,
    suspended_by = case when p_status = 'suspended' then auth.uid() else null end,
    suspended_at = case when p_status = 'suspended' then now() else null end,
    suspension_reason = case when p_status = 'suspended' then v_reason else null end
  where id = p_profile_id;
end;
$$;

-- Defensa en profunditat per a l'Admin API: una baixa d'auth.users provoca el
-- cascada del perfil, així que el trigger impedeix que una carrera esborre la
-- procedència entre les comprovacions de la Edge Function i la baixa real.
create or replace function public.prevent_profile_deletion_with_provenance()
returns trigger language plpgsql security definer set search_path = pg_catalog, public as $$
begin
  if exists (select 1 from public.administrators where profile_id = old.id)
     and public.active_confirmed_administrator_count(old.id) = 0 then
    raise exception 'No es pot eliminar l''últim compte administrador actiu i confirmat';
  end if;
  if exists (select 1 from public.catalog_objects where created_by = old.id)
     or exists (select 1 from public.catalog_objects where reviewed_by = old.id)
     or exists (select 1 from public.catalog_object_history where actor_id = old.id)
     or exists (select 1 from public.catalog_object_revisions where changed_by = old.id)
     or exists (select 1 from public.object_photos where uploaded_by = old.id)
     or exists (select 1 from public.tags where created_by = old.id)
     or exists (select 1 from public.object_tags where created_by = old.id)
     or exists (select 1 from public.change_proposals where submitted_by = old.id or reviewed_by = old.id)
     or exists (select 1 from public.activities where created_by = old.id)
     or exists (select 1 from public.donation_contacts where handled_by = old.id)
     or exists (select 1 from public.video_proposals where submitted_by = old.id or reviewed_by = old.id)
     or exists (select 1 from public.historical_figures where created_by = old.id or updated_by = old.id)
     or exists (select 1 from public.profiles where approved_by = old.id or suspended_by = old.id) then
    raise exception 'No es pot eliminar un perfil amb dades d''autoria o auditoria';
  end if;
  return old;
end;
$$;
drop trigger if exists profiles_prevent_provenance_delete on public.profiles;
create trigger profiles_prevent_provenance_delete before delete on public.profiles
  for each row execute procedure public.prevent_profile_deletion_with_provenance();

drop policy if exists "profiles: own, student manager or admin read" on public.profiles;
drop policy if exists "profiles: own, student manager or admin update" on public.profiles;
drop policy if exists "profiles: administrators delete" on public.profiles;
create policy "profiles: active own, student manager or admin read" on public.profiles for select to authenticated
  using (
    (id = auth.uid() and public.is_active_confirmed_user())
    or public.is_administrator()
    or (public.is_teacher() and role = 'student')
  );
create policy "profiles: own limited update" on public.profiles for update to authenticated
  using (id = auth.uid() and public.is_active_confirmed_user())
  with check (id = auth.uid() and public.is_active_confirmed_user());
create policy "profiles: direct delete disabled" on public.profiles for delete to authenticated using (false);

-- L'editor personal només necessita aquests dos camps; les RPC SECURITY DEFINER
-- mantenen separades les transicions d'aprovació i suspensió.
revoke update on public.profiles from authenticated;
grant update (display_name, avatar_path) on public.profiles to authenticated;
revoke delete on public.profiles from authenticated;

revoke all on function public.is_active_confirmed_user() from public, anon, authenticated;
revoke all on function public.is_administrator() from public, anon, authenticated;
revoke all on function public.is_teacher() from public, anon, authenticated;
revoke all on function public.is_approved_student() from public, anon, authenticated;
revoke all on function public.active_confirmed_administrator_count(uuid) from public, anon, authenticated;
grant execute on function public.is_active_confirmed_user(), public.is_administrator(), public.is_teacher(), public.is_approved_student() to authenticated;
grant execute on function public.active_confirmed_administrator_count(uuid) to service_role;
revoke all on function public.decide_profile_approval(uuid, text) from public, anon, authenticated;
grant execute on function public.decide_profile_approval(uuid, text) to authenticated;
revoke all on function public.set_profile_account_status(uuid, public.account_state, text) from public, anon, authenticated;
grant execute on function public.set_profile_account_status(uuid, public.account_state, text) to authenticated;
revoke all on function public.prevent_profile_deletion_with_provenance() from public, anon, authenticated;

comment on column public.profiles.account_status is 'Estat operatiu del compte. Les suspensions conserven qui, quan i per què.';
comment on function public.is_active_confirmed_user() is 'Comprova sessió, confirmació d''email i estat actiu sense exposar auth.users.';

commit;
