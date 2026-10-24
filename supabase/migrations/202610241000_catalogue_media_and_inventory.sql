-- Extensions de catàleg: codis automàtics, enllaços de peça i vídeos moderats.
begin;

alter table public.catalog_objects
  alter column inventory_code drop not null,
  add column if not exists information_url text check (information_url is null or (char_length(information_url) <= 2048 and information_url ~* '^https://')),
  add column if not exists video_url text check (video_url is null or (char_length(video_url) <= 2048 and video_url ~* '^https://'));

create sequence if not exists public.catalog_inventory_code_seq;
select setval(
  'public.catalog_inventory_code_seq',
  coalesce((select max(nullif(substring(inventory_code from '^MUS-([0-9]+)$'), '')::bigint) from public.catalog_objects), 0) + 1,
  false
);

create or replace function public.assign_inventory_code()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.inventory_code is null or btrim(new.inventory_code) = '' then
    new.inventory_code := 'MUS-' || lpad(nextval('public.catalog_inventory_code_seq')::text, 6, '0');
  end if;
  return new;
end;
$$;

drop trigger if exists catalog_objects_assign_inventory_code on public.catalog_objects;
create trigger catalog_objects_assign_inventory_code
  before insert on public.catalog_objects for each row execute procedure public.assign_inventory_code();

create table public.video_proposals (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(trim(title)) between 4 and 180),
  description text check (char_length(description) <= 2000),
  video_url text not null check (char_length(video_url) <= 2048 and video_url ~* '^https://'),
  era smallint check (era between 1800 and 2200),
  category text not null check (category in ('Ordinador personal', 'Consola', 'Videojoc', 'Programari')),
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  submitted_by uuid not null references public.profiles(id) on delete restrict,
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  reviewer_note text check (char_length(reviewer_note) <= 2000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index video_proposals_pending_idx on public.video_proposals (created_at desc) where status = 'pending';
create trigger video_proposals_updated_at before update on public.video_proposals
  for each row execute procedure public.set_updated_at();
alter table public.video_proposals enable row level security;
create policy "video proposals: public approved read" on public.video_proposals for select to anon, authenticated using (status = 'approved');
create policy "video proposals: submitters read own" on public.video_proposals for select to authenticated using (submitted_by = auth.uid());
create policy "video proposals: students submit" on public.video_proposals for insert to authenticated
  with check (public.is_approved_student() and submitted_by = auth.uid() and status = 'pending' and reviewed_by is null and reviewed_at is null);
create policy "video proposals: teachers manage" on public.video_proposals for all to authenticated
  using (public.is_teacher()) with check (public.is_teacher());

grant select, insert, update, delete on public.video_proposals to authenticated;
grant select on public.video_proposals to anon;
revoke all on function public.assign_inventory_code() from public;
grant execute on function public.assign_inventory_code() to authenticated;

commit;
