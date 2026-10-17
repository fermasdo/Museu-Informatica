# Supabase: Museu d'Informàtica

`schema.sql` és l'esquema inicial **versionat 1.0.0**. Apliqueu-lo des de l'SQL Editor d'un projecte Supabase nou o convertiu-lo en la primera migració del CLI abans de desplegar. No el reexecuteu contra una base amb l'esquema ja creat sense una migració incremental.

## Auth i rols

1. Activeu el proveïdor d'Auth que use el centre (correu/contrasenya o Magic Link) i configureu les URL de redirecció del domini local i del domini de producció.
2. El trigger `on_auth_user_created` crea sempre un perfil `visitor`; ignoreu qualsevol `role` enviat en les metadades del client.
3. Després de registrar el primer docent, des de l'SQL Editor amb un administrador, assigneu-li el rol:

   ```sql
   update public.profiles
   set role = 'teacher', approval_status = 'not_required'
   where id = '<uuid-del-primer-docent>';
   ```

   A partir d'ací, el professorat pot convertir visitants en `student` i aprovar-los. Només l'alumnat amb `approval_status = 'approved'` pot crear o editar les seues fitxes en esborrany i enviar propostes.

## Client, servidor i Storage

- Al client només són necessàries `PUBLIC_SUPABASE_URL` i `PUBLIC_SUPABASE_KEY`. No exposeu mai `service_role`, tokens d'administració ni credencials SMTP.
- Qualsevol tasca privilegiada de servidor ha de validar l'entrada, comprovar la sessió i usar `service_role` exclusivament en variables d'entorn del servidor.
- El bucket privat `catalog-photos` admet JPEG, PNG i WebP fins a 10 MiB. Les fotos es pugen a `<auth.uid()>/<uuid>.<extensió>`; la política només fa públiques les vinculades a objectes publicats.
- Les dades de donants i els missatges de `donation_contacts` són privats. Per al formulari públic, valideu també al servidor longituds, correu i protecció antiabús (rate limit/CAPTCHA); la RLS només permet la inserció d'un missatge nou.

## Impacte i desplegament

És un esquema inicial: no transforma dades existents. En una base ja en ús, prepareu migracions amb `alter table` i reviseu prèviament rols, fitxes i fitxers. L'aplicació activa RLS en totes les taules i crea les polítiques del bucket; reviseu-les en un entorn de prova abans de producció.
