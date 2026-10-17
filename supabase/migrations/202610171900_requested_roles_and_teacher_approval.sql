-- Apliqueu després de 202610171800_prevent_teacher_role_escalation.sql.
-- Separa les sol·licituds de rol de l'assignació efectiva del rol.
begin;

alter table public.profiles add column requested_role text;
alter table public.profiles add constraint profiles_requested_role_check
  check (requested_role is null or requested_role in ('student', 'teacher'));

-- Els perfils preexistents conserven la seua forma vàlida (requested_role null).
alter table public.profiles drop constraint profiles_approval_consistency;
alter table public.profiles add constraint profiles_approval_consistency check (
  (role = 'visitor' and requested_role is null and approval_status = 'not_required')
  or (role = 'visitor' and requested_role = 'teacher' and approval_status in ('pending', 'rejected'))
  or (role = 'student' and requested_role = 'student' and approval_status in ('pending', 'approved', 'rejected'))
  or (role = 'student' and requested_role is null and approval_status in ('pending', 'approved', 'rejected'))
  or (role = 'teacher' and requested_role is null and approval_status = 'not_required')
  or (role = 'teacher' and requested_role = 'teacher' and approval_status = 'approved')
);

-- El tauler de l'administrador consulta només les sol·licituds docents pendents.
create index profiles_pending_teacher_requests_idx on public.profiles (created_at asc)
  where requested_role = 'teacher' and approval_status = 'pending';

-- L'email és una claim signada del JWT d'Auth, no una dada de profiles ni del client.
create or replace function public.is_administrator()
returns boolean language sql stable security definer set search_path = pg_catalog as $$
  select lower(coalesce(auth.jwt() ->> 'email', '')) = 'f.masdomenech@edu.gva.es';
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

-- Només l'administrador identificat pel JWT pot aprovar/rebutjar docents.
-- El professorat ordinari només resol sol·licituds d'alumnat ja creades.
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

drop policy "profiles: own or teacher read" on public.profiles;
drop policy "profiles: own or teacher update" on public.profiles;
drop policy "profiles: teachers delete" on public.profiles;
create policy "profiles: own, student manager or admin read" on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_administrator() or (public.is_teacher() and role = 'student'));
create policy "profiles: own, student manager or admin update" on public.profiles for update to authenticated
  using (id = auth.uid() or public.is_administrator() or (public.is_teacher() and role = 'student'))
  with check (id = auth.uid() or public.is_administrator() or (public.is_teacher() and role = 'student'));
create policy "profiles: administrators delete" on public.profiles for delete to authenticated
  using (public.is_administrator());

revoke all on function public.is_administrator() from public;
grant execute on function public.is_administrator() to authenticated;
comment on column public.profiles.requested_role is
  'Petició validada en el registre: student o teacher. No concedeix privilegis per si mateixa.';
commit;
