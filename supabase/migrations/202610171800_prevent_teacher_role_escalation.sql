-- Apliqueu aquesta migració als projectes creats amb schema.sql 1.0.0.
-- Impedeix que un professor atorgue el rol de professor a un altre perfil des del client.
create or replace function public.protect_profile_privileges()
returns trigger language plpgsql set search_path = public as $$
begin
  -- Només l'administració SQL pot crear o elevar un perfil a professorat.
  if auth.uid() is not null and new.role = 'teacher' and old.role is distinct from 'teacher' then
    raise exception 'El rol de professorat només el pot assignar l''administració';
  end if;

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
