# Continuation Notes

Updated: 2026-11-06

## Completed

- Commit `9f9d9e8` was pushed to `origin/main` with donation management and catalogue image credits.
- Three published remote demonstration objects exist in Supabase: `DEMO-ZX-001`, `DEMO-C64-001`, and `DEMO-GB-001`. Their reference photos are in the private `catalog-photos` bucket and include Wikimedia Commons attribution in the caption.
- The Supabase CLI is available through `npx supabase`; authentication was completed with `npx supabase login`.

## Location Work

- Migration `supabase/migrations/202610271000_cabinet_buildings_and_labels.sql` is applied to the remote project.
- It renames `cabinets.room` to `building`, restricts the building to `Cicles`, `ESO`, or `Administració`, and adds a required `cabinet` label.
- Existing `Edifici Cicles`, `Edifici ESO`, and `Edifici Administració` values were normalised. Other legacy room values fall back to `Administració`; `cabinet` was initialised from the existing `code`.
- RLS is unchanged. `supabase/schema.sql` now reflects this structure for new installations.
- The frontend queries and displays `building` and `cabinet` in `src/pages/col·labora.astro`, `src/components/Catalogue.astro`, and `src/pages/cataleg/detall.astro`.
- The teacher location form requires Codi, Edifici and Armari; Prestatge and Notes remain optional.

## Ownership And Contributor Work

- Migration `supabase/migrations/202610281200_public_catalogue_privacy_and_donor_workflow.sql` is applied to the remote project.
- Teachers select Centre, Donació or Préstec. Donació and Préstec require a private name for the donor or lender; the teacher-only RPC creates or reuses that private record atomically.
- Students can only create or edit their own Centre drafts and cannot supply private contact data.
- `donor_id` is required for donations and loans, and prohibited for Centre or legacy unknown ownership. The constraint is `NOT VALID`, so existing inconsistent records must be audited before validation.
- Public catalogue, photos and tags are served through explicit views that exclude donor data, audit metadata, serial numbers and precise locations. The frontend no longer reads public data from internal tables.
- Legacy `unknown` ownership is shown explicitly to teachers and must be deliberately changed before saving; it is never silently converted.
- `donors` remains teacher/admin-only and is not linked automatically to public `donation_contacts` submissions.

Follow-up verification:

1. Test the public catalogue, an approved student draft, and teacher donation/loan create and edit flows against the remote project.
2. Audit legacy donations without a donor and Centre/unknown pieces with a donor before validating the `NOT VALID` constraint.

## Remote Schema Note

- `npx supabase migration list --remote` on 2026-11-06 confirms that all local migrations through `202610281200` are applied to the linked remote project.

## Validation

- Run `npm run build` after each code change.
- For database work, inspect migration history first with `npx supabase migration list` and apply only after reviewing data/RLS impact.
