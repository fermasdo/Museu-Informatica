# Full de Ruta de Gestio del Museu

Document viu per prioritzar, anotar i fer seguiment de la gestio del Museu d'Informatica.

## Com usar-lo

- `[ ]` Pendent
- `[-]` En curs
- `[x]` Fet
- Afig una nota breu sota cada punt si cal concretar una decisio, responsable o incidencia.
- No marques un punt com a fet fins que estiga comprovat en produccio.

## Prioritat 1 - Operativa Essencial

### Administracio del cataleg

- [x] Crear un panell inicial amb comptadors de fitxes pendents, donacions, usuaris pendents i contingut arxivat.
- [ ] Afegir cerca, filtres persistents i paginacio a la gestio de fitxes.
- [ ] Afegir historial d'accions: creacio, edicio, revisio, publicacio, arxiu i persona responsable.
- [ ] Afegir comentaris de revisio estructurats amb motiu i tasques pendents.
- [ ] Permetre accions en lot sobre fitxes: etiquetar, arxivar i publicar quan siga segur.
- [ ] Afegir una llista clara de fitxes pendents de revisio com a vista principal docent.

### Persones i permisos

- [ ] Crear una llista d'usuaris amb cerca, rol, estat d'aprovacio i ultima activitat.
- [ ] Completar el flux d'aprovacio: aprovar, rebutjar amb motiu i demanar informacio.
- [ ] Definir els rols definitius: administracio, professorat editor, alumnat col·laborador i visitant.
- [ ] Permetre desactivar comptes sense eliminar l'historial editorial.
- [ ] Registrar canvis de rol i permisos en l'auditoria.

### Dades i seguretat

- [ ] Programar copies de seguretat de Supabase i Storage.
- [ ] Revisar les politiques RLS abans de cada funcionalitat administrativa nova.
- [ ] Detectar i eliminar de manera segura fitxers de Storage sense fitxa associada.
- [ ] Documentar el procediment de restauracio davant d'una incidencia.
- [ ] Crear una comprovacio de salut: migracions, bucket, errors i ultima copia de seguretat.

## Prioritat 2 - Gestio de la Col·leccio Fisica

### Inventari i ubicacions

- [ ] Gestionar edifici, corredor, vitrina, armari, prestatge i estat d'exposicio.
- [ ] Crear una vista operativa per localitzar una peça fisicament.
- [ ] Generar etiquetes imprimibles amb codi QR cap a la fitxa publica.
- [ ] Permetre importar i exportar l'inventari en CSV.
- [ ] Validar que els codis d'inventari siguen unics i traçables.

### Conservacio i moviments

- [ ] Afegir estat de conservacio, incidencia, data de revisio i persona responsable.
- [ ] Permetre fotografies documentals de l'estat de la peça.
- [ ] Registrar préstecs, moviments interns, responsable, data de retorn i condicions.
- [ ] Separar les dades publiques de les sensibles: serie, ubicacio exacta, assegurança, propietat i donants.

### Fotografies i documentacio

- [ ] Definir fotografia principal, ordre de galeria, peu, credit i llicencia.
- [ ] Afegir un control editorial que avise de fotografies pendents o sense credit.
- [ ] Afegir camps separats per importancia, historia, us original i procedencia.
- [ ] Relacionar peces per decada, fabricant, tecnologia, ubicacio o recorregut.

## Prioritat 3 - Donacions i Incorporacions

- [ ] Crear estats de donacio: nova, contactada, pendent de valoracio, acceptada, rebutjada i incorporada.
- [ ] Afegir una fitxa privada de donacio amb contacte, consentiment, condicions i observacions.
- [ ] Convertir una donacio acceptada en una fitxa d'inventari guiada.
- [ ] Preparar plantilles de resposta per confirmar recepcio, demanar dades o comunicar una decisio.
- [ ] Publicar i gestionar la politica de cessio, préstec, drets d'imatge i privacitat.

## Prioritat 4 - Contingut i Experiencia Publica

### Contingut editable

- [ ] Canviar el titol institucional del museu a "Museu d'Informatica de l'IES l'Estacio" en tota la web i les metadades.
- [ ] Permetre gestionar activitats, anuncis, recorreguts i laboratori des del tauler.
- [ ] Afegir programacio de publicacio i despublicacio.
- [ ] Fer editable el contingut destacat de la portada.
- [ ] Gestionar recorreguts: parades, ordre, textos, preguntes, QR i peces relacionades.
- [ ] Gestionar cada recurs d'emulacio: origen, llicencia, enllaç, controls, peça relacionada i revisio de l'enllaç.

### Visita i comunicacio

- [ ] Confirmar i publicar adreca, horaris, accés, reserva, capacitat, contacte i accessibilitat.
- [ ] Crear un formulari de reserva de grups amb franges gestionables.
- [ ] Permetre avisos de tancament temporal o activitats especials.
- [ ] Afegir un mapa o plànol accessible amb alternativa textual.

## Prioritat 5 - Millora Continua

- [ ] Mesurar peces mes consultades, cerques sense resultats, recorreguts iniciats i formularis rebuts.
- [ ] Revisar l'accessibilitat amb teclat, lector de pantalla, zoom i mobil real.
- [ ] Fer revisions periodiques d'enllaços externs, emuladors, credits i llicencies.
- [ ] Definir un calendari de manteniment editorial i tecnic.

## Idees i Issues Oberts

Anota aci propostes noves, incidencies o decisions per revisar. Indica la data si es util.

- [ ]

## Registre de Canvis

| Data | Canvi | Estat | Notes |
| --- | --- | --- | --- |
| 2026-10-30 | Creacio del full de ruta inicial | Fet | Base per al seguiment del projecte |
