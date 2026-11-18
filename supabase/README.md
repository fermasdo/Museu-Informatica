# Supabase: Museu d'Informàtica

`schema.sql` és l'esquema inicial **versionat 1.3.0**. Apliqueu-lo des de l'SQL Editor d'un projecte Supabase nou o convertiu-lo en la primera migració del CLI abans de desplegar. No el reexecuteu contra una base amb l'esquema ja creat sense una migració incremental.

## Auth i rols

1. Activeu el proveïdor d'Auth que use el centre (correu/contrasenya o Magic Link) i exigiu la confirmació de correu. A **Authentication → URL Configuration**, configureu exactament `Site URL = https://fermasdo.github.io/Museu-Informatica/` i afegiu a **Redirect URLs** `https://fermasdo.github.io/Museu-Informatica/` i `https://fermasdo.github.io/Museu-Informatica/col·labora/` (recuperació de contrasenya). Per al desenvolupament local, afegiu `http://localhost:4321/**`.
2. En el registre, el client pot enviar `raw_user_meta_data.display_name` i `raw_user_meta_data.requested_role` amb valor exacte `student` o `teacher`. Un valor absent o invàlid crea un `visitor` sense sol·licitud. Mai confieu en `role`, `approval_status` o camps d'auditoria enviats pel client.
3. Una petició `student` crea `role = student`, `requested_role = student`, `approval_status = pending`. Una petició `teacher` crea `role = visitor`, `requested_role = teacher`, `approval_status = pending`: no concedeix accés docent.
4. La migració `202610261230_catalogue_governance_and_review.sql` crea la taula `administrators`. Migra automàticament l'administrador inicial identificat anteriorment pel correu. Si aquest perfil es registra després de la migració, la RPC d'un sol ús `bootstrap_administrator()` l'inicialitza en entrar; només la pot executar aquest correu mentre la taula estiga buida. Les altes posteriors s'han de gestionar inserint el seu `profile_id` des d'un entorn administratiu segur. El professorat i l'administració poden aprovar alumnat; només l'administració aprova professorat.
5. `profiles` no guarda correus i `auth.users` no s'exposa mitjançant l'API pública. No creeu vistes, polítiques ni RPC que hi revelen emails.
6. La migració `202611181000_account_lifecycle_security.sql` incorpora `account_status` (`active`/`suspended`) i la traça obligatòria de suspensió. `is_active_confirmed_user()` exigeix sessió, correu confirmat i compte actiu; les funcions de docent, administració i alumnat aprovat en depenen. Això manté el catàleg públic i el formulari anònim de donació, però bloqueja accions de col·laboració a comptes no confirmats o suspesos.
7. Les decisions passen per `decide_profile_approval(profile_id, 'approve'|'reject')`: el professorat aprova o rebutja alumnat i només l'administració decideix professorat. La suspensió/restauració és només administrativa amb `set_profile_account_status(profile_id, 'suspended'|'active', reason)`; no es permet l'autosuspensió ni suspendre l'últim administrador actiu i confirmat. L'editor personal conserva únicament `display_name` i `avatar_path`.

### Aplicar a un projecte existent

Després de les migracions ja existents, apliqueu totes les migracions pendents amb el CLI en l'entorn vinculat:

```bash
supabase db push
```

Si useu l'SQL Editor, executeu les migracions per ordre de nom, una sola vegada. La migració de governança conserva les fitxes i propostes actuals, afegeix camps de revisió inicialment buits i crea un historial a partir dels canvis nous. També canvia les polítiques perquè l'administració gestione el catàleg i perquè les decisions de revisió passen per RPC. Proveu primer l'aprovació i el rebuig amb un compte d'alumne, un de docent sol·licitant i un d'administrador.

La migració de cicle de vida no modifica autoria ni elimina perfils: els perfils existents reben `active`. Abans de producció, proveu un usuari sense confirmar, un de suspés, l'aprovació d'alumnat per professorat, l'aprovació docent per administració i la protecció de l'últim administrador. La configuració explícita existent de Ferran Mas a `administrators` i el bootstrap de recuperació es conserven; no afegiu comprovacions de correu o d'administració al navegador.

## Client, servidor i Storage

- Al client només són necessàries `PUBLIC_SUPABASE_URL` i `PUBLIC_SUPABASE_KEY`. No exposeu mai `service_role`, tokens d'administració ni credencials SMTP. Les variables de servidor, si calen per a tasques internes, són `SUPABASE_URL` i `SUPABASE_SERVICE_ROLE_KEY`, exclusivament al servidor i sense valors al repositori.
- Qualsevol tasca privilegiada de servidor ha de validar l'entrada, comprovar la sessió i usar `service_role` exclusivament en variables d'entorn del servidor.
- La funció `manage-user-account` és l'única via per eliminar un usuari d'`auth.users`. Desplegueu-la amb `supabase functions deploy manage-user-account` i configureu-hi, sense versionar valors, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` i `ALLOWED_ORIGINS=https://fermasdo.github.io,http://localhost:4321`. Exigeix un Bearer token d'un administrador actiu, confirmat i diferent del compte objectiu; rebutja l'últim administrador actiu i confirmat i qualsevol dada d'autoria o auditoria per no alterar la procedència. No invoqueu mai l'Admin API ni la service role des del client.
- El bucket privat `catalog-photos` admet JPEG, PNG i WebP fins a 10 MiB. Les fotos es pugen a `<auth.uid()>/<uuid>.<extensió>`; la política només fa públiques les vinculades a objectes publicats.
- Les dades de donants i els missatges de `donation_contacts` són privats. El formulari registra la data i la versió del consentiment i s'envia a la Edge Function `submit-donation`, que valida Cloudflare Turnstile abans d'escriure amb permisos de servidor. Configureu `PUBLIC_TURNSTILE_SITE_KEY` al web i `TURNSTILE_SECRET_KEY` com a secret de la funció. No exposeu mai la clau secreta.

## Impacte i desplegament

És un esquema inicial: no transforme dades existents. En una base ja en ús, apliqueu només les migracions incrementals i reviseu prèviament rols, fitxes i fitxers. L'aplicació activa RLS en totes les taules i crea les polítiques del bucket; reviseu-les en un entorn de prova abans de producció.
