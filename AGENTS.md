# Museu d'Informatica

## Projecte

- Web estatica amb Astro 5. El desplegament es fa a GitHub Pages des de `main`.
- Conserva `base: '/Museu-Informatica/'` i construeix les URL internes amb `import.meta.env.BASE_URL`.
- Executa `npm run build` abans de donar per acabat qualsevol canvi de codi.
- No exposesques mai secrets, claus de Supabase, contrasenyes ni fitxers `.env`.

## Coordinacio

- Consulta `art-director` abans de canvis visuals o de navegacio amb impacte rellevant.
- Delega la implementacio de la interfície a `astro-experience`.
- Delega l'esquema, RLS, Storage i migracions a `supabase-curator`.
- Demana una revisio a `museum-qa` abans de publicar canvis visibles o formularis.
- Usa `gh-pages-release` per a canvis de desplegament, rutes o GitHub Actions.

## Base de dades

- Cada canvi d'esquema ha de ser una migracio SQL nova dins `supabase/migrations/`.
- No reescrigues migracions que ja s'hagen aplicat a remot.
- Explica l'impacte de les dades i les politiques RLS abans d'aplicar migracions a produccio.
