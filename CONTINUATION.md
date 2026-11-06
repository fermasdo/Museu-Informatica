# Continuation Notes

Updated: 2026-10-27

## Completed

- Commit `9f9d9e8` was pushed to `origin/main` with donation management and catalogue image credits.
- Three published remote demonstration objects exist in Supabase: `DEMO-ZX-001`, `DEMO-C64-001`, and `DEMO-GB-001`. Their reference photos are in the private `catalog-photos` bucket and include Wikimedia Commons attribution in the caption.
- The Supabase CLI is available through `npx supabase`; authentication was completed with `npx supabase login`.

## Uncommitted Location Work

- New migration: `supabase/migrations/202610271000_cabinet_buildings_and_labels.sql`.
- It renames `cabinets.room` to `building`, restricts the building to `Cicles`, `ESO`, or `Administració`, and adds a required `cabinet` label.
- Existing `Edifici Cicles`, `Edifici ESO`, and `Edifici Administració` values are normalised. Other legacy room values fall back to `Administració`; `cabinet` is initialised from the existing `code`.
- RLS is unchanged. No migration has been applied to the remote project yet.
- The frontend was already updated to query and display `building` and `cabinet` in `src/pages/col·labora.astro`, `src/components/Catalogue.astro`, and `src/pages/cataleg/detall.astro`.
- The teacher location form now requires: Codi, Edifici, Armari; Prestatge and Notes remain optional.
- Before applying the migration, update `supabase/schema.sql` so new projects start with `building` and `cabinet`, then run `npx supabase db push` and verify existing locations and catalogue queries.

## Pending Ownership And Contributor Work

Required behaviour:

- Property choices must be Centre, Préstec, and Donació.
- For Préstec or Donació, teachers must enter the name of the person lending or donating the item.
- That identity must remain private and never appear in public catalogue responses.

Current model:

- `catalog_objects.ownership` already has `museum_property`, `loan`, and `donation` values, plus legacy `unknown`.
- `catalog_objects.donor_id` points to the private `donors` table.
- Existing constraints require `donor_id` for `loan`, but not for `donation`.

Recommended implementation:

1. Add a new migration that requires `donor_id` for both `loan` and `donation`, and requires no donor or loan due date for `museum_property`.
2. Do not silently convert legacy `unknown` or old donations without a donor. Audit them first, or add the new constraint as `NOT VALID` until they are resolved.
3. Add an authenticated teacher-only RPC that atomically creates or reuses a `donors` record and creates or updates the catalogue object. This prevents orphan private records.
4. Change ownership labels in the teacher UI to Centre, Préstec, and Donació. Show a required person-name field only for Préstec and Donació.
5. Expose published objects through a public view with an explicit column list, rather than direct public reads of `catalog_objects`. The view must exclude `donor_id`, audit fields, and other private columns. Update public catalogue queries to use this view.
6. Keep the `donors` table teacher/admin-only; do not connect it automatically to public `donation_contacts` submissions.

## Remote Schema Note

- The linked remote database does not yet contain the `administrators` table from `202610261230_catalogue_governance_and_review.sql`.
- Review and apply pending migrations deliberately before relying on the newer catalogue-review workflow. Do not use `db push` blindly until the migration history and existing remote data have been checked.

## Validation

- Run `npm run build` after each code change.
- For database work, inspect migration history first with `npx supabase migration list` and apply only after reviewing data/RLS impact.
