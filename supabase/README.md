# Supabase: Museu d'Informàtica

`schema.sql` és l'esquema inicial **versionat 1.1.0**. Apliqueu-lo des de l'SQL Editor d'un projecte Supabase nou o convertiu-lo en la primera migració del CLI abans de desplegar. No el reexecuteu contra una base amb l'esquema ja creat sense una migració incremental.

## Auth i rols

1. Activeu el proveïdor d'Auth que use el centre (correu/contrasenya o Magic Link) i configureu les URL de redirecció del domini local i del domini de producció.
2. En el registre, el client pot enviar `raw_user_meta_data.display_name` i `raw_user_meta_data.requested_role` amb valor exacte `student` o `teacher`. Un valor absent o invàlid crea un `visitor` sense sol·licitud. Mai confieu en `role`, `approval_status` o camps d'auditoria enviats pel client.
3. Una petició `student` crea `role = student`, `requested_role = student`, `approval_status = pending`. Una petició `teacher` crea `role = visitor`, `requested_role = teacher`, `approval_status = pending`: no concedeix accés docent.
4. La migració `202610261230_catalogue_governance_and_review.sql` crea la taula `administrators`. Migra automàticament l'administrador inicial identificat anteriorment pel correu. Si aquest perfil es registra després de la migració, la RPC d'un sol ús `bootstrap_administrator()` l'inicialitza en entrar; només la pot executar aquest correu mentre la taula estiga buida. Les altes posteriors s'han de gestionar inserint el seu `profile_id` des d'un entorn administratiu segur. El professorat i l'administració poden aprovar alumnat; només l'administració aprova professorat.
5. `profiles` no guarda correus i `auth.users` no s'exposa mitjançant l'API pública. No creeu vistes, polítiques ni RPC que hi revelen emails.

### Aplicar a un projecte existent

Després de les migracions ja existents, apliqueu totes les migracions pendents amb el CLI en l'entorn vinculat:

```bash
supabase db push
```

Si useu l'SQL Editor, executeu les migracions per ordre de nom, una sola vegada. La migració de governança conserva les fitxes i propostes actuals, afegeix camps de revisió inicialment buits i crea un historial a partir dels canvis nous. També canvia les polítiques perquè l'administració gestione el catàleg i perquè les decisions de revisió passen per RPC. Proveu primer l'aprovació i el rebuig amb un compte d'alumne, un de docent sol·licitant i un d'administrador.

## Client, servidor i Storage

- Al client només són necessàries `PUBLIC_SUPABASE_URL` i `PUBLIC_SUPABASE_KEY`. No exposeu mai `service_role`, tokens d'administració ni credencials SMTP. Les variables de servidor, si calen per a tasques internes, són `SUPABASE_URL` i `SUPABASE_SERVICE_ROLE_KEY`, exclusivament al servidor i sense valors al repositori.
- Qualsevol tasca privilegiada de servidor ha de validar l'entrada, comprovar la sessió i usar `service_role` exclusivament en variables d'entorn del servidor.
- El bucket privat `catalog-photos` admet JPEG, PNG i WebP fins a 10 MiB. Les fotos es pugen a `<auth.uid()>/<uuid>.<extensió>`; la política només fa públiques les vinculades a objectes publicats.
- Les dades de donants i els missatges de `donation_contacts` són privats. El formulari registra la data i la versió del consentiment i s'envia a la Edge Function `submit-donation`, que valida Cloudflare Turnstile abans d'escriure amb permisos de servidor. Configureu `PUBLIC_TURNSTILE_SITE_KEY` al web i `TURNSTILE_SECRET_KEY` com a secret de la funció. No exposeu mai la clau secreta.

## Impacte i desplegament

És un esquema inicial: no transforme dades existents. En una base ja en ús, apliqueu només les migracions incrementals i reviseu prèviament rols, fitxes i fitxers. L'aplicació activa RLS en totes les taules i crea les polítiques del bucket; reviseu-les en un entorn de prova abans de producció.
