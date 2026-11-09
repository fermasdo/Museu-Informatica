-- Personatges històrics: contingut editorial separat de les peces del catàleg.
-- Impacte de dades: crea una taula i un bucket nous; no modifica cap fila existent.
-- Permisos: només professorat/administració gestiona les fitxes; el públic accedeix
-- a la projecció publicada i a les imatges que aquella projecció vincula.

begin;

create type public.historical_figure_status as enum ('draft', 'published', 'archived');

create or replace function public.historical_figure_sources_valid(p_sources jsonb)
returns boolean
language sql
immutable
set search_path = pg_catalog
as $$
  select jsonb_typeof(p_sources) = 'array'
    and jsonb_array_length(p_sources) between 1 and 8
    and not exists (
      select 1
      from jsonb_array_elements(p_sources) as source(value)
      where jsonb_typeof(source.value) <> 'object'
        or source.value - array['label', 'url'] <> '{}'::jsonb
        or not (source.value ? 'label' and source.value ? 'url')
        or jsonb_typeof(source.value -> 'label') <> 'string'
        or char_length(btrim(source.value ->> 'label')) not between 2 and 200
        or jsonb_typeof(source.value -> 'url') <> 'string'
        or char_length(source.value ->> 'url') not between 9 and 2048
        or source.value ->> 'url' !~* '^https://[^[:space:]]+$'
    );
$$;

create table public.historical_figures (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (
    char_length(slug) between 2 and 120
    and slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'
  ),
  full_name text not null check (char_length(btrim(full_name)) between 2 and 180),
  birth_year smallint check (birth_year between -5000 and 2100),
  death_year smallint check (death_year between -5000 and 2100),
  field text not null check (char_length(btrim(field)) between 2 and 120),
  summary text not null check (char_length(btrim(summary)) between 20 and 600),
  biography text not null check (char_length(btrim(biography)) between 20 and 8000),
  contribution text not null check (char_length(btrim(contribution)) between 10 and 4000),
  notable_fact text check (notable_fact is null or char_length(btrim(notable_fact)) <= 1000),
  sources jsonb not null check (public.historical_figure_sources_valid(sources)),
  image_path text,
  image_alt text,
  image_credit text,
  status public.historical_figure_status not null default 'draft',
  published_at timestamptz,
  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint historical_figures_year_range check (
    death_year is null or birth_year is null or death_year >= birth_year
  ),
  -- La imatge és opcional: les fitxes també poden usar una composició tipogràfica.
  constraint historical_figures_image_metadata check (
    (image_path is null and image_alt is null and image_credit is null)
    or (
      image_path is not null and image_path = btrim(image_path)
      and char_length(image_path) between 1 and 1024
      and image_alt is not null and char_length(btrim(image_alt)) between 4 and 250
      and image_credit is not null and char_length(btrim(image_credit)) between 2 and 500
    )
  ),
  constraint historical_figures_publication_date check (
    status <> 'published' or published_at is not null
  )
);

-- Llistats públics ordenats per data de publicació; slug ja queda indexat per UNIQUE.
create index historical_figures_published_at_idx on public.historical_figures (published_at desc)
  where status = 'published';

create or replace function public.set_historical_figure_audit_fields()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if auth.uid() is not null then
      new.created_by := auth.uid();
      new.updated_by := auth.uid();
    end if;
  else
    new.updated_at := now();
    new.updated_by := coalesce(auth.uid(), old.updated_by);
  end if;

  if new.status = 'published' then
    if tg_op = 'INSERT' or old.status is distinct from 'published' or new.published_at is null then
      new.published_at := coalesce(new.published_at, now());
    end if;
  else
    new.published_at := null;
  end if;
  return new;
end;
$$;

create trigger historical_figures_audit_and_publication
  before insert or update on public.historical_figures
  for each row execute procedure public.set_historical_figure_audit_fields();

alter table public.historical_figures enable row level security;
create policy "historical figures: teachers manage" on public.historical_figures
  for all to authenticated
  using (public.is_teacher())
  with check (public.is_teacher());

-- API pública amb camps explícits: no filtra autories, estat ni esborranys.
create view public.public_historical_figures
with (security_barrier = true, security_invoker = false) as
select
  f.id,
  f.slug,
  f.full_name,
  f.birth_year,
  f.death_year,
  f.field,
  f.summary,
  f.biography,
  f.contribution,
  f.notable_fact,
  f.sources,
  f.image_path,
  f.image_alt,
  f.image_credit,
  f.published_at
from public.historical_figures f
where f.status = 'published';

revoke all on public.historical_figures from anon;
grant select, insert, update, delete on public.historical_figures to authenticated;
grant select on public.public_historical_figures to anon, authenticated;

-- El bucket és privat; una imatge només és llegible si continua vinculada a una
-- fitxa publicada. Les rutes no associades no es poden llegir des del client.
create or replace function public.can_read_historical_figure_image(path text)
returns boolean
language sql
stable
security definer
set search_path = public, storage
as $$
  select exists (
    select 1 from public.historical_figures f
    where f.image_path = path and f.status = 'published'
  );
$$;

revoke all on function public.can_read_historical_figure_image(text) from public;
grant execute on function public.can_read_historical_figure_image(text) to anon, authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('historical-figure-images', 'historical-figure-images', false, 10485760,
  array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy "historical figure images: published linked read" on storage.objects
  for select to anon, authenticated
  using (bucket_id = 'historical-figure-images' and public.can_read_historical_figure_image(name));
create policy "historical figure images: teachers manage" on storage.objects
  for all to authenticated
  using (bucket_id = 'historical-figure-images' and public.is_teacher())
  with check (bucket_id = 'historical-figure-images' and public.is_teacher());

-- Les fitxes inicials no inventen autoria interna ni depenen d'una imatge.
insert into public.historical_figures (
  slug, full_name, birth_year, death_year, field, summary, biography, contribution,
  notable_fact, sources, status
) values
(
  'ada-lovelace', 'Ada Lovelace', 1815, 1852, 'Matemàtiques i computació',
  'Matemàtica britànica coneguda per les seues notes sobre la màquina analítica de Charles Babbage.',
  'Augusta Ada King, comtessa de Lovelace, va estudiar matemàtiques en un context en què les oportunitats acadèmiques per a les dones eren limitades. El seu treball va aparéixer el 1843 en una traducció comentada d''un text de Luigi Menabrea sobre la màquina analítica.',
  'Les notes de Lovelace descriuen un mètode per calcular nombres de Bernoulli amb la màquina analítica i exploren que una màquina podria manipular símbols segons regles, més enllà de l''aritmètica.',
  'La màquina analítica no es va construir completament durant la seua vida.',
  '[{"label":"Encyclopaedia Britannica: Ada Lovelace","url":"https://www.britannica.com/biography/Ada-Lovelace"}]'::jsonb,
  'published'
),
(
  'alan-turing', 'Alan Turing', 1912, 1954, 'Matemàtiques, lògica i computació',
  'Matemàtic britànic que va fer aportacions fonamentals a la teoria de la computació i a la criptanàlisi.',
  'Alan Turing va estudiar matemàtiques a Cambridge i Princeton. Durant la Segona Guerra Mundial va treballar a Bletchley Park en l''anàlisi de comunicacions xifrades alemanyes. Després va participar en projectes de computació al Regne Unit.',
  'L''article de 1936 sobre nombres computables va formalitzar el model avui anomenat màquina de Turing. El seu treball també va influir en la criptanàlisi i en les primeres discussions sobre intel·ligència artificial.',
  'Va ser perseguit per la seua homosexualitat, aleshores criminalitzada al Regne Unit.',
  '[{"label":"Encyclopaedia Britannica: Alan Turing","url":"https://www.britannica.com/biography/Alan-Turing"}]'::jsonb,
  'published'
),
(
  'grace-hopper', 'Grace Hopper', 1906, 1992, 'Programació i llenguatges de programació',
  'Matemàtica i oficial naval dels Estats Units, pionera dels compiladors i de la programació empresarial.',
  'Grace Murray Hopper va combinar la formació matemàtica amb el treball en els primers ordinadors, inclòs el Harvard Mark I. Va participar en equips que buscaven fer la programació més accessible i portable entre màquines.',
  'Va impulsar eines que traduïen instruccions semblants a l''anglés a codi executable i va contribuir al desenvolupament de FLOW-MATIC, una influència en COBOL.',
  'Va arribar al rang de contraalmirall de la Marina dels Estats Units.',
  '[{"label":"Encyclopaedia Britannica: Grace Hopper","url":"https://www.britannica.com/biography/Grace-Hopper"}]'::jsonb,
  'published'
),
(
  'hedy-lamarr', 'Hedy Lamarr', 1914, 2000, 'Tecnologia de comunicacions',
  'Actriu i inventora que va codesenvolupar una patent relacionada amb comunicacions de salt de freqüència.',
  'Hedy Lamarr va ser una actriu nascuda a Viena que va treballar a Europa i als Estats Units. Durant la Segona Guerra Mundial, ella i el compositor George Antheil van presentar una idea per reduir la interferència en sistemes de control per ràdio.',
  'La patent de Lamarr i Antheil descrivia un sistema de canvi coordinat de freqüències. És un antecedent històric citat en l''evolució de tècniques de comunicació de espectre eixamplat, sense atribuir-li directament les tecnologies actuals.',
  'La patent estatunidenca es va concedir el 1942.',
  '[{"label":"Encyclopaedia Britannica: Hedy Lamarr","url":"https://www.britannica.com/biography/Hedy-Lamarr"}]'::jsonb,
  'published'
),
(
  'margaret-hamilton', 'Margaret Hamilton', 1936, null, 'Enginyeria de programari',
  'Enginyera de programari nord-americana coneguda pel seu treball en el programari de vol del programa Apollo.',
  'Margaret Hamilton va dirigir l''equip de programari de vol del MIT Instrumentation Laboratory per a les missions Apollo. El seu equip va desenvolupar programari per al mòdul de comandament i el mòdul lunar en un context amb fortes exigències de fiabilitat.',
  'El treball del seu equip va incloure mecanismes de detecció i recuperació d''errors que ajudaren a gestionar sobrecàrregues durant l''allunatge de l''Apollo 11. Hamilton també va difondre l''ús del terme enginyeria de programari.',
  'El 2016 va rebre la Presidential Medal of Freedom dels Estats Units.',
  '[{"label":"Encyclopaedia Britannica: Margaret Hamilton","url":"https://www.britannica.com/biography/Margaret-Hamilton"}]'::jsonb,
  'published'
),
(
  'frances-allen', 'Frances Allen', 1932, 2020, 'Compiladors i optimització',
  'Científica de la computació nord-americana, referent en optimització de compiladors i computació d''alt rendiment.',
  'Frances E. Allen va treballar a IBM des de 1957 en investigació sobre compiladors, anàlisi de programes i arquitectures de computació. La seua carrera va incloure projectes relacionats amb rendiment i paral·lelisme.',
  'Les seues aportacions a l''anàlisi de flux de control i a l''optimització ajudaren a establir tècniques emprades pels compiladors moderns. El 2006 va ser la primera dona a rebre el Premi Turing.',
  'Va rebre el Premi Turing de l''ACM pel seu treball pioner en optimització de compiladors.',
  '[{"label":"IBM: Frances Allen","url":"https://www.ibm.com/history/frances-allen"}]'::jsonb,
  'published'
)
on conflict (slug) do nothing;

comment on table public.historical_figures is
  'Biografies editorials; les imatges són opcionals i es desen al bucket privat historical-figure-images.';
comment on view public.public_historical_figures is
  'Projecció pública explícita de personatges publicats, sense estat ni camps d''autoria.';

commit;
