-- Flux de fitxes de personatges aportades per alumnat.
-- Impacte: les fitxes existents conserven l'estat i l'autoria; les noves
-- fitxes d'alumnat s'etiqueten automàticament com pending_review.
-- Permisos: només alumnat aprovat pot consultar i modificar les seues fitxes
-- no publicades. Professorat i administració continuen sent les úniques
-- identitats que poden publicar o arxivar.

-- PostgreSQL no permet usar amb seguretat un valor d'enum acabat d'afegir
-- dins de la mateixa transacció; per això aquesta sentència queda fora.
alter type public.historical_figure_status add value if not exists 'pending_review';

begin;

-- La protecció complementa RLS: encara que el client envie un altre estat, un
-- insert d'alumnat sempre entra en la cua de revisió i mai no pot canviar-lo.
create or replace function public.protect_student_historical_figure_workflow()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  if public.is_teacher() then
    return new;
  end if;

  if not public.is_approved_student() then
    raise exception 'Només l''alumnat aprovat pot crear o editar fitxes de personatge';
  end if;

  if tg_op = 'INSERT' then
    new.created_by := auth.uid();
    new.updated_by := auth.uid();
    new.status := 'pending_review'::public.historical_figure_status;
    new.published_at := null;
  else
    if old.created_by is distinct from auth.uid() then
      raise exception 'No pots modificar una fitxa d''un altre compte';
    end if;
    if old.status = 'published'::public.historical_figure_status then
      raise exception 'No pots modificar una fitxa publicada';
    end if;
    if new.status is distinct from old.status then
      raise exception 'L''estat de revisió només el pot modificar el professorat';
    end if;
    -- Els camps d'auditoria i de publicació són gestionats pel servidor.
    new.created_by := old.created_by;
    new.published_at := old.published_at;
  end if;

  return new;
end;
$$;

revoke all on function public.protect_student_historical_figure_workflow() from public, anon, authenticated;

drop trigger if exists historical_figures_student_workflow on public.historical_figures;
create trigger historical_figures_student_workflow
  before insert or update on public.historical_figures
  for each row execute procedure public.protect_student_historical_figure_workflow();

drop policy if exists "historical figures: teachers manage" on public.historical_figures;

create policy "historical figures: teachers manage" on public.historical_figures
  for all to authenticated
  using (public.is_teacher())
  with check (public.is_teacher());

create policy "historical figures: approved students read own unpublished" on public.historical_figures
  for select to authenticated
  using (
    public.is_approved_student()
    and created_by = auth.uid()
    and status <> 'published'::public.historical_figure_status
  );

create policy "historical figures: approved students create pending" on public.historical_figures
  for insert to authenticated
  with check (
    public.is_approved_student()
    and created_by = auth.uid()
    and status = 'pending_review'::public.historical_figure_status
  );

create policy "historical figures: approved students edit own unpublished" on public.historical_figures
  for update to authenticated
  using (
    public.is_approved_student()
    and created_by = auth.uid()
    and status <> 'published'::public.historical_figure_status
  )
  with check (
    public.is_approved_student()
    and created_by = auth.uid()
    and status <> 'published'::public.historical_figure_status
  );

-- La cua de revisió és la consulta docent més freqüent. L'índex parcial no
-- afecta les fitxes publicades ni les creades fins ara.
create index historical_figures_pending_review_updated_at_idx
  on public.historical_figures (updated_at desc)
  where status = 'pending_review'::public.historical_figure_status;

-- Imatges d'esborrany: l'alumnat només pot pujar i esborrar dins del seu
-- prefix privat. La lectura queda limitada a imatges vinculades a fitxes seues
-- no publicades; la política existent conserva l'accés públic a les publicades.
create policy "historical figure images: students read own unpublished" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'historical-figure-images'
    and public.is_approved_student()
    and (storage.foldername(name))[1] = auth.uid()::text
    and exists (
      select 1 from public.historical_figures f
      where f.image_path = name
        and f.created_by = auth.uid()
        and f.status <> 'published'::public.historical_figure_status
    )
  );

create policy "historical figure images: students upload own folder" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'historical-figure-images'
    and public.is_approved_student()
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "historical figure images: students delete own folder" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'historical-figure-images'
    and public.is_approved_student()
    and (storage.foldername(name))[1] = auth.uid()::text
    and exists (
      select 1 from public.historical_figures f
      where f.image_path = name
        and f.created_by = auth.uid()
        and f.status <> 'published'::public.historical_figure_status
    )
  );

comment on function public.protect_student_historical_figure_workflow() is
  'Força pending_review en crear fitxes d''alumnat i impedeix que l''alumnat modifique l''estat o publique.';
comment on index public.historical_figures_pending_review_updated_at_idx is
  'Accelera la cua docent de fitxes de personatges pendents de revisió.';

commit;
