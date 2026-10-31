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

### Credibilitat editorial

- [ ] Substituir missatges tecnics visibles per textos orientats a la persona visitant, sense explicar JavaScript, Supabase, migracions ni altres detalls interns.
- [ ] Canviar el titol institucional del museu a "Museu d'Informatica de l'IES l'Estacio" en tota la web i les metadades.
- [ ] Revisar el to de tota la web: reduir frases generiques de marca i prioritzar informacio concreta, contrastada i local.
- [ ] Definir un model editorial unic per a les fitxes: que es, per que importa, historia i us, procedencia, ubicacio publica i fonts.
- [ ] Distingir clarament peça exposada, documentacio, imatge de referencia i contingut pendent de verificar.
- [ ] Mostrar credits, llicencies, fonts i data de revisio de cada fitxa quan estiguen disponibles.

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

- [ ] Prioritzar fotografies propies i identificables de les peces abans d'ampliar el cataleg public.
- [ ] Substituir les imatges o il·lustracions generiques repetides per fotografies reals, o indicar clarament "Fotografia del museu pendent".
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

## Prioritat 4 - Disseny i Experiencia Publica

### Jerarquia visual i navegacio

- [ ] Simplificar la navegacio principal segons el contingut real publicat; mantindre com a seccions secundaries les que encara no tinguen prou contingut propi.
- [ ] Donar una jerarquia visual estable a totes les pagines: seccio, titol, context, contingut principal i accio.
- [ ] Moderar l'us simultani dels accents verd, cian, magenta i taronja; reservar cada color per a una funcio concreta.
- [ ] Reservar DM Mono per a anys, inventari, dades curtes, controls i senyaletica; usar Outfit per al relat i la lectura principal.
- [ ] Augmentar la mida i llegibilitat de credits, peus de foto i metadades importants.
- [ ] Reduir l'espaiat excessivament tancat dels titulars secundaris i evitar patrons de targeta repetits sense necessitat.

### Portada i relat del museu

- [ ] Destacar una peça real, una incorporacio o un procés de restauracio a la portada, amb fotografia i context verificat.
- [ ] Afegir fotografies reals de l'espai, vitrines o processos de documentacio, amb els permisos necessaris.
- [ ] Substituir blocs decoratius o redundants per accessos que responguen a preguntes reals: que hi ha, on es, com visitar-lo i com participar.
- [ ] Crear una pagina "Sobre el museu" amb origen, criteri de col·leccio, responsables i objectius educatius.
- [ ] Afegir una linia temporal curta que connecte fites tecnologiques amb peces reals de la col·leccio.

### Cataleg i fitxes publiques

- [ ] Prioritzar fotografia, nom, any i rellevancia a les targetes del cataleg.
- [ ] Mostrar relacions entre peces nomes quan siguen documentades: mateixa decada, fabricant, tecnologia, ubicacio o recorregut.
- [ ] Simplificar les metadades publiques i protegir les dades que no aporten valor al visitant general.
- [ ] Mantindre el retorn al cataleg amb filtres sense mostrar mecanismes tecnics a la persona visitant.

## Prioritat 5 - Contingut i Experiencia Publica

### Contingut editable

- [ ] Permetre gestionar activitats, anuncis, recorreguts i laboratori des del tauler.
- [ ] Afegir programacio de publicacio i despublicacio.
- [ ] Fer editable el contingut destacat de la portada.
- [ ] Gestionar recorreguts: parades, ordre, textos, preguntes, QR i peces relacionades.
- [ ] Gestionar cada recurs d'emulacio: origen, llicencia, enllaç, controls, peça relacionada i revisio de l'enllaç.

### Visita i comunicacio

- [ ] Confirmar i publicar adreca, horaris, accés, reserva, capacitat, contacte i accessibilitat.
- [ ] Crear una pagina de visita practica amb fotografies reals d'arribada i acollida, duracio, edats, normes i condicions confirmades.
- [ ] Crear un formulari de reserva de grups amb franges gestionables.
- [ ] Permetre avisos de tancament temporal o activitats especials.
- [ ] Afegir un mapa o plànol accessible amb alternativa textual.

## Prioritat 6 - Millora Continua

- [ ] Mesurar peces mes consultades, cerques sense resultats, recorreguts iniciats i formularis rebuts.
- [ ] Revisar l'accessibilitat amb teclat, lector de pantalla, zoom i mobil real.
- [ ] Fer revisions periodiques d'enllaços externs, emuladors, credits i llicencies.
- [ ] Definir un calendari de manteniment editorial i tecnic.
- [ ] Fer una revisio editorial humana abans de publicar: noms propis, dates, credits, llicencies, valencia i dades contrastades.

## Idees i Issues Oberts

Anota aci propostes noves, incidencies o decisions per revisar. Indica la data si es util.

- [ ]

## Registre de Canvis

| Data | Canvi | Estat | Notes |
| --- | --- | --- | --- |
| 2026-10-30 | Creacio del full de ruta inicial | Fet | Base per al seguiment del projecte |
