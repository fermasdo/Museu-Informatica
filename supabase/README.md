# Supabase: Museu d'Informàtica

`schema.sql` és l'esquema inicial **versionat 1.1.0**. Apliqueu-lo des de l'SQL Editor d'un projecte Supabase nou o convertiu-lo en la primera migració del CLI abans de desplegar. No el reexecuteu contra una base amb l'esquema ja creat sense una migració incremental.

## Auth i rols

1. Activeu el proveïdor d'Auth que use el centre (correu/contrasenya o Magic Link) i configureu les URL de redirecció del domini local i del domini de producció.
2. En el registre, el client pot enviar `raw_user_meta_data.display_name` i `raw_user_meta_data.requested_role` amb valor exacte `student` o `teacher`. Un valor absent o invàlid crea un `visitor` sense sol·licitud. Mai confieu en `role`, `approval_status` o camps d'auditoria enviats pel client.
3. Una petició `student` crea `role = student`, `requested_role = student`, `approval_status = pending`. Una petició `teacher` crea `role = visitor`, `requested_role = teacher`, `approval_status = pending`: no concedeix accés docent.
4. Només una sessió el JWT de la qual tinga l'email `f.masdomenech@edu.gva.es` pot aprovar o rebutjar docents. En aprovar, el trigger converteix la petició pendent en `role = teacher`; el professorat ordinari només pot aprovar o rebutjar alumnat pendent. El primer administrador també s'ha de registrar demanant `teacher` abans d'aprovar-se.
5. `profiles` no guarda correus i `auth.users` no s'exposa mitjançant l'API pública. No creeu vistes, polítiques ni RPC que hi revelen emails.

### Aplicar a un projecte existent

Després de la migració ja existent, apliqueu la nova amb el CLI en l'entorn vinculat:

```bash
supabase db push
```

O executeu `migrations/202610171900_requested_roles_and_teacher_approval.sql` des de l'SQL Editor, una sola vegada i després de `202610171800_prevent_teacher_role_escalation.sql`. La migració conserva perfils existents: alumnat i professorat antics mantenen `requested_role = null`; les altes noves fan servir el flux nou. Proveu primer l'aprovació i el rebuig amb un compte d'alumne, un de docent sol·licitant i un d'administrador.

## Client, servidor i Storage

- Al client només són necessàries `PUBLIC_SUPABASE_URL` i `PUBLIC_SUPABASE_KEY`. No exposeu mai `service_role`, tokens d'administració ni credencials SMTP. Les variables de servidor, si calen per a tasques internes, són `SUPABASE_URL` i `SUPABASE_SERVICE_ROLE_KEY`, exclusivament al servidor i sense valors al repositori.
- Qualsevol tasca privilegiada de servidor ha de validar l'entrada, comprovar la sessió i usar `service_role` exclusivament en variables d'entorn del servidor.
- El bucket privat `catalog-photos` admet JPEG, PNG i WebP fins a 10 MiB. Les fotos es pugen a `<auth.uid()>/<uuid>.<extensió>`; la política només fa públiques les vinculades a objectes publicats.
- Les dades de donants i els missatges de `donation_contacts` són privats. Per al formulari públic, valideu també al servidor longituds, correu i protecció antiabús (rate limit/CAPTCHA); la RLS només permet la inserció d'un missatge nou.

## Impacte i desplegament

És un esquema inicial: no transforma dades existents. En una base ja en ús, prepareu migracions amb `alter table` i reviseu prèviament rols, fitxes i fitxers. L'aplicació activa RLS en totes les taules i crea les polítiques del bucket; reviseu-les en un entorn de prova abans de producció.
