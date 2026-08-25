# Rilevamento contorni cover e correzione prospettica — scelta pacchetto

Ricerca per issue [#87](https://github.com/saviogiordano/MyComicBrain/issues/87) (figlia della mappa
[#86](https://github.com/saviogiordano/MyComicBrain/issues/86)).

Target ambiente: `app/pubspec.yaml` dichiara `environment: sdk: ^3.10.1` e (dal `pubspec.lock`)
`sdks: flutter: ">=3.38.0"`, `dart: ">=3.11.0-0 <4.0.0"`. Editor di crop già scelto (issue #17):
`image_cropper: ^12.2.1` (wrapper nativo, uCrop su Android / TOCropViewController su iOS).

Metodo: dati presi da pub.dev (pagine pacchetto + API `https://pub.dev/api/packages/<nome>`),
sorgenti/README sui repository GitHub ufficiali, GitHub API (`pushed_at`, `open_issues_count`,
`stargazers_count`) e documentazione ufficiale Google (`developers.google.com/ml-kit`) / Apple
(`developer.apple.com/documentation/visionkit`). Ogni affermazione è accompagnata dalla fonte.

---

## Risposta diretta alle domande del ticket

### 1. Il pacchetto fornisce le coordinate del quadrilatero da passare a `image_cropper`, o produce già l'immagine ritagliata/raddrizzata?

**Nessuno dei plugin "document scanner" pronti all'uso valutati espone le coordinate del
quadrilatero rilevato all'app Flutter.** Tutti (Google ML Kit Document Scanner, `cunning_document_scanner`,
`flutter_doc_scanner`) implementano un **flusso UI nativo a schermo intero** (fotocamera + rilevamento
bordi in tempo reale + cattura + raddrizzamento prospettico + filtro) e restituiscono a Dart solo il
**path del file immagine già ritagliato/raddrizzato** (o un PDF), mai i quattro punti del contorno.
Fonti:
- Google ML Kit: "The entire document scanner flow operates on-device" e fornisce "a high-quality,
  consistent UI flow" — non un'API di rilevamento contorni isolata. Fonte: [developers.google.com/ml-kit/vision/doc-scanner](https://developers.google.com/ml-kit/vision/doc-scanner).
- `cunning_document_scanner`: `getPictures()` "returns a list of file paths", nessuna menzione di
  corner/quad points nel README. Fonte: [README `cunning_document_scanner`](https://raw.githubusercontent.com/vicajilau/cunning_document_scanner/main/README.md), [sorgente `cunning_document_scanner.dart`](https://raw.githubusercontent.com/vicajilau/cunning_document_scanner/main/lib/src/cunning_document_scanner.dart).
- `flutter_doc_scanner`: i metodi (`getScanDocuments`, `getScannedDocumentAsImages`,
  `getScannedDocumentAsPdf`) restituiscono URI di PDF/immagini finali, non coordinate. Fonte: [pub.dev/packages/flutter_doc_scanner](https://pub.dev/packages/flutter_doc_scanner).
- `edge_detection`: stessa logica — "returns the path of the cropped image", nessun dato di
  quadrilatero. Fonte: [README `edge_detection`](https://raw.githubusercontent.com/sawankumarbundelkhandi/edge_detection/master/README.md).

L'unico modo per ottenere davvero le coordinate del contorno (per poi eventualmente pre-compilare
un editor) è **non usare un plugin "scanner" già confezionato**, ma costruire la pipeline a mano con
una libreria di computer vision di basso livello come `opencv_dart` (bindings OpenCV via `dart:ffi`):
`cv.findContours` + `cv.approxPolyDP` restituiscono il poligono, che poi si raddrizza con
`cv.getPerspectiveTransform` + `cv.warpPerspective`. Fonte: [pub.dev/packages/opencv_dart](https://pub.dev/packages/opencv_dart), [repo `rainyl/opencv_dart`](https://github.com/rainyl/opencv_dart).

**Conclusione**: con qualunque dei pacchetti "scanner" pronti, l'integrazione con `image_cropper` non è
"passa il quadrilatero rilevato come area iniziale" (nessuno dei due lati espone quel dato), ma
eventualmente "usa l'immagine già raddrizzata restituita dallo scanner come **input** di un secondo
passaggio di rifinitura manuale in `image_cropper`" (vedi §2-3).

### 2. `image_cropper` supporta un'area di ritaglio iniziale pre-impostata via API?

**Solo parzialmente, e solo su iOS.** Il README ufficiale documenta, dentro `IOSUiSettings`, quattro
proprietà esplicite per il rettangolo iniziale di ritaglio: `rectX`, `rectY`, `rectWidth`,
`rectHeight` ("The initial rect of cropping: x/y/width/height", tipo `double`) — passate a
TOCropViewController. Fonte: [README `flutter_image_cropper`](https://raw.githubusercontent.com/hnvn/flutter_image_cropper/master/README.md), [pub.dev/packages/image_cropper](https://pub.dev/packages/image_cropper).

Su **Android**, `AndroidUiSettings` **non** espone un equivalente `rectX/Y/W/H`: l'unico controllo
sulla geometria iniziale è `initAspectRatio` (un aspect ratio applicato all'avvio, es. quadrato o
libero) combinato con `lockAspectRatio`, non una posizione/rettangolo arbitrario. Fonte: [README `flutter_image_cropper`](https://raw.githubusercontent.com/hnvn/flutter_image_cropper/master/README.md).

Quindi: **non esiste, in `image_cropper`, un modo cross-platform per pre-compilare un rettangolo di
crop con coordinate arbitrarie** — funziona solo su iOS, e comunque solo per un rettangolo
assiale (mai per un quadrilatero/prospettiva, vedi punto 3). Su Android il massimo ottenibile è un
aspect ratio iniziale.

### 3. Se il pacchetto restituisce un quadrilatero non rettangolare, va raddrizzato prima di `image_cropper`, o esiste un'alternativa che gestisce la prospettiva direttamente?

`image_cropper` **lavora esclusivamente su rettangoli** (uCrop e TOCropViewController sono editor di
crop/rotazione rettangolari, nessuna delle due librerie native sottostanti espone una trasformazione
prospettica a 4 punti) — non c'è alcuna opzione, in nessuna delle due `UiSettings`, per un
ritaglio a quadrilatero libero. Fonte: [README `flutter_image_cropper`](https://raw.githubusercontent.com/hnvn/flutter_image_cropper/master/README.md) (l'intera superficie di configurazione elencata riguarda aspect ratio, rotazione, rettangolo assiale — mai punti d'angolo indipendenti).

Di conseguenza, se una fase della pipeline produce un quadrilatero in prospettiva, **il warp va fatto
prima** di aprire `image_cropper` (che a quel punto interviene solo per un'eventuale rifinitura
rettangolare sull'immagine già raddrizzata). Le alternative pronte all'uso (Google ML Kit, `cunning_document_scanner`,
`flutter_doc_scanner`) risolvono il problema **non esponendo mai un quadrilatero**: fanno il
rilevamento *e* il warp internamente, nativamente, e restituiscono direttamente l'immagine già
raddrizzata — quindi per chi le usa la domanda "va raddrizzata prima di `image_cropper`" non si pone
nemmeno, perché il raddrizzamento è già avvenuto quando arriva il file. L'unico scenario in cui si
otterrebbe davvero un quadrilatero grezzo da raddrizzare a mano è l'approccio custom con `opencv_dart`
(vedi §1 e §5).

### 4. On-device, compatibilità SDK, iOS+Android

| Pacchetto | Ultima versione / data | Vincoli SDK dichiarati | Compatibile con `sdk: ^3.10.1` / `flutter: >=3.38.0`? | Piattaforme | On-device |
|---|---|---|---|---|---|
| `google_mlkit_document_scanner` | 0.6.1 — 2026-08-17 | `sdk: ^3.12.0`, `flutter: >=3.44.0` | **No** (richiede Flutter/Dart più recenti di quelli del progetto) | **Solo Android** (Beta, nessuna versione iOS: "This feature is still in Beta, and it is only available for Android") | Sì |
| `cunning_document_scanner` | 3.0.1 — 2026-08-11 | `sdk: >=3.5.0 <4.0.0`, `flutter: >=3.24.0` | **Sì** | iOS + Android | Sì |
| `flutter_doc_scanner` | 0.0.21 — 2026-07-09 | `sdk: >=2.18.0 <4.0.0`, `flutter: >=1.17.0` | **Sì** | iOS + Android | Sì |
| `edge_detection` | 1.1.3 — 2023-10-17 | `sdk: >=2.12.0 <4.0.0`, `flutter: >=1.20.0` | Sì (range permissivo, ma nessuna release da 3 anni) | iOS + Android | Sì |
| `opencv_dart` | 2.2.2 — 2026-08-16 | `sdk: >=3.10.0 <4.0.0`, `flutter: >=3.38.1` | **Sì** | iOS + Android (+ desktop/web) | Sì |

Fonti versioni/vincoli: [pub.dev API `google_mlkit_document_scanner`](https://pub.dev/api/packages/google_mlkit_document_scanner), [pub.dev API `cunning_document_scanner`](https://pub.dev/api/packages/cunning_document_scanner), [pub.dev API `flutter_doc_scanner`](https://pub.dev/api/packages/flutter_doc_scanner), [pub.dev API `edge_detection`](https://pub.dev/api/packages/edge_detection), [pub.dev API `opencv_dart`](https://pub.dev/api/packages/opencv_dart). Piattaforma ML Kit Document Scanner: [developers.google.com/ml-kit/vision/doc-scanner](https://developers.google.com/ml-kit/vision/doc-scanner) (unico link di piattaforma presente è "Android", nessun link "iOS").

Tutti i pacchetti nativi valutati processano **interamente on-device**: Google ML Kit Document
Scanner dichiara esplicitamente "The entire document scanner flow operates on-device" (fonte sopra);
`cunning_document_scanner` dichiara "no third-party runtime dependencies" (fonte README linkato
sopra); Apple VisionKit (`VNDocumentCameraViewController`, usato da `cunning_document_scanner` e
`flutter_doc_scanner` su iOS) è un framework di sistema locale, nessuna chiamata di rete. Fonte:
[developer.apple.com/documentation/visionkit/vndocumentcameraviewcontroller](https://developer.apple.com/documentation/visionkit/vndocumentcameraviewcontroller) ("presents UI for a camera pass-through that helps people scan physical documents").

Nota importante su `google_mlkit_document_scanner`: anche ignorando l'incompatibilità di versione,
**resterebbe comunque scartato per requisito cross-platform** — è Android-only, confermato dalla
documentazione ufficiale Google (unico link di piattaforma è `/ml-kit/vision/doc-scanner/android`).
Le versioni precedenti (es. 0.5.0, `sdk: ^3.8.0`, compatibile con la toolchain del progetto) non
cambiano questo limite: la Document Scanner API di Google ML Kit non è mai stata disponibile per iOS.

### 5. Tempi di elaborazione e setup nativo aggiuntivo

**Tempi**: nessuno dei vendor (Google, Apple, i maintainer dei plugin Flutter) pubblica benchmark
numerici ufficiali per il rilevamento bordi/cattura — non è quindi possibile citare una cifra precisa
da fonte primaria. Quanto è documentato ufficialmente:
- Google ML Kit Document Scanner: il rilevamento bordi avviene nel flusso camera **in tempo reale**
  durante l'inquadratura (parte del "high-quality, consistent UI flow"), quindi la latenza percepita
  dopo lo scatto per il crop/raddrizzamento finale è nell'ordine di un singolo frame di elaborazione
  immagine on-device (< 1s tipico per un'immagine still, in linea con altre pipeline ML Kit
  single-image on-device), non un batch separato. Fonte: [developers.google.com/ml-kit/vision/doc-scanner](https://developers.google.com/ml-kit/vision/doc-scanner).
- Apple VisionKit (`VNDocumentCameraViewController`) è descritto come "camera pass-through" con
  rilevamento bordi live durante l'inquadratura, stesso principio. Fonte: [developer.apple.com/documentation/visionkit/vndocumentcameraviewcontroller](https://developer.apple.com/documentation/visionkit/vndocumentcameraviewcontroller).
- Per un approccio custom con `opencv_dart` (Canny/soglia adattiva + `findContours` +
  `warpPerspective` su una singola foto ad alta risoluzione da fotocamera telefono), il tempo dipende
  interamente dall'implementazione (risoluzione di lavoro, se si fa downscaling prima del rilevamento
  bordi) e non è documentato dal pacchetto stesso: va misurato empiricamente nel progetto se si
  sceglie questa via.

**Permessi/setup nativo aggiuntivo oltre a `camera` (già presente)**:
- `cunning_document_scanner`: richiede comunque il permesso fotocamera dichiarato dall'app
  (`<uses-permission android:name="android.permission.CAMERA"/>` su Android,
  `NSCameraUsageDescription` in `Info.plist` su iOS) — permessi già presenti nel progetto per il
  pacchetto `camera` (issue #16), quindi **nessuna configurazione nuova richiesta** per questi. Su
  Android richiede **Google Play Services** per usare ML Kit; se assenti, il plugin ha un **fallback
  automatico** a uno scanner integrato con crop manuale a rettangolo fisso (nessun crash, solo UX
  degradata). minSdk Android 24, iOS 13.0 — entrambi già rispettati dai vincoli di `camera` (Android
  24+, iOS 13.0+) documentati nella ricerca precedente. Fonte: [README `cunning_document_scanner`](https://raw.githubusercontent.com/vicajilau/cunning_document_scanner/main/README.md), [research/camera-package-flutter.md](https://github.com/saviogiordano/MyComicBrain/blob/research/camera-package-flutter/docs/research/camera-package-flutter.md).
- Nessuna chiave `Info.plist`/manifest aggiuntiva oltre camera è documentata da nessuno dei due
  plugin scelti/runner-up per il solo scanning (a differenza di `edge_detection`, che richiede in più
  fix manuali al `Podfile` per Xcode 15+ e l'impostazione esplicita di Kotlin 1.8.0 lato Android —
  fonte: [README `edge_detection`](https://raw.githubusercontent.com/sawankumarbundelkhandi/edge_detection/master/README.md)).
- Se in futuro si scegliesse `google_mlkit_document_scanner` per il solo Android (accettando
  l'assenza iOS), va notato che l'API nativa **non richiede il permesso camera dell'app**, perché la
  UI di scansione gira come componente separato di Google Play Services con permesso proprio — un
  comportamento diverso dagli altri pacchetti. Fonte: [developers.google.com/ml-kit/vision/doc-scanner](https://developers.google.com/ml-kit/vision/doc-scanner) ("No camera permission is required from your app").

---

## Alternative valutate in dettaglio

### `cunning_document_scanner` (consigliato)

- Versione **3.0.1**, pubblicata 2026-08-11 (14 giorni prima di questa ricerca). Vincoli:
  `sdk: >=3.5.0 <4.0.0`, `flutter: >=3.24.0` — compatibile con `sdk: ^3.10.1`/`flutter >=3.38.0` del
  progetto. Fonte: [pub.dev API `cunning_document_scanner`](https://pub.dev/api/packages/cunning_document_scanner).
- Publisher verificato `victorcarreras.dev`, 160/160 pub points, 266 like, ~51.4k download
  settimanali, licenza MIT. Repository GitHub `vicajilau/cunning_document_scanner`: ultimo push
  **2026-08-11**, 116 star, **0 issue aperte**, non archiviato. Fonte: [pub.dev/packages/cunning_document_scanner](https://pub.dev/packages/cunning_document_scanner), [GitHub API repo](https://github.com/vicajilau/cunning_document_scanner) (interrogato via `gh api repos/vicajilau/cunning_document_scanner`).
- Storia release: 3.0.0 → 3.0.1 in rapida successione con fix mirati (`cleanCache()` su Android,
  bump `minSdk` 21→24); serie 2.x con miglioramenti incrementali per tutto il 2024-2025 (filtri
  documento, export PDF, import da galleria, migrazione iOS a Swift Package Manager). Cadenza di
  rilascio attiva e recente. Fonte: [changelog `cunning_document_scanner`](https://pub.dev/packages/cunning_document_scanner/changelog).
- **Meccanismo**: Android usa **Google ML Kit** per il rilevamento bordi automatico quando Google
  Play Services è disponibile, con **fallback** a uno scanner integrato (crop manuale a rettangolo
  fisso) se assente; iOS usa **Vision framework** tramite `VNDocumentCameraViewController` (stessa
  UI di sistema usata dall'app Note di Apple). Nessuna dipendenza runtime di terze parti. Fonte:
  [README `cunning_document_scanner`](https://raw.githubusercontent.com/vicajilau/cunning_document_scanner/main/README.md).
- **API**: `CunningDocumentScanner.getPictures({int noOfPages = 100, ScannerSource? scannerSource,
  AndroidScannerMode androidScannerMode = AndroidScannerMode.full, IosScannerOptions?
  iosScannerOptions, bool asPdf = false})` → `Future<List<String>?>` (path dei file, `null` se
  annullato su tutte le piattaforme). `iosScannerOptions` permette di impostare formato immagine
  (`IosImageFormat.jpg`), qualità di compressione JPEG, filtro di default e visibilità della barra
  filtri. Esiste anche `cleanCache()` per liberare i file temporanei generati dal plugin. Fonte:
  [sorgente `cunning_document_scanner.dart`](https://raw.githubusercontent.com/vicajilau/cunning_document_scanner/main/lib/src/cunning_document_scanner.dart).
- **Nota operativa file**: dalla 3.0.0 i file iOS sono spostati in cache privata (non più
  `Documents`) e sono "non garantiti", soggetti a rimozione di sistema — va copiato subito il file
  nello storage permanente dell'app dopo lo scan, stesso pattern già gestito per `image_cropper`
  nella ricerca #17. Fonte: [changelog `cunning_document_scanner`](https://pub.dev/packages/cunning_document_scanner/changelog).
- **Limiti noti**: su iOS il componente di sistema (`VNDocumentCameraViewController`) non espone
  toggle per modalità scanner o limite pagine (limiti imposti solo lato Dart dopo il fatto); i colori
  della UI iOS sono fissi (solo il testo è personalizzabile). Fonte: [README `cunning_document_scanner`](https://raw.githubusercontent.com/vicajilau/cunning_document_scanner/main/README.md).

### `flutter_doc_scanner` (runner-up)

- Versione **0.0.21**, pubblicata 2026-07-09. Vincoli: `sdk: >=2.18.0 <4.0.0`,
  `flutter: >=1.17.0` — compatibile. Fonte: [pub.dev API `flutter_doc_scanner`](https://pub.dev/api/packages/flutter_doc_scanner).
- Stesso meccanismo di fondo: **Google ML Kit Document Scanner API** su Android + **VisionKit**
  su iOS. Repository GitHub `shirsh94/flutter_doc_scanner`: ultimo push 2026-07-09, 73 star, **18
  issue aperte**, mantenuto da un singolo sviluppatore (verificato via `gh api repos/shirsh94/flutter_doc_scanner`).
  Fonte: [pub.dev/packages/flutter_doc_scanner](https://pub.dev/packages/flutter_doc_scanner).
- API: `getScanDocuments({int page})`, `getScannedDocumentAsImages({int page})`,
  `getScannedDocumentAsPdf({int page})`, più `getScanDocumentsUri()` **solo Android**. Restituiscono
  URI di immagini/PDF già pronti (mai coordinate). Fonte: [pub.dev/packages/flutter_doc_scanner](https://pub.dev/packages/flutter_doc_scanner).
- **Perché è solo runner-up**: manutenzione da singolo maintainer con un rapporto issue-aperte/star
  più sfavorevole (18/73 contro 0/116 di `cunning_document_scanner`); nessuna documentazione
  esplicita di un fallback quando Google Play Services non è disponibile su Android (a differenza di
  `cunning_document_scanner`, che lo dichiara esplicitamente); superficie di configurazione iOS/Android
  meno ricca (niente equivalente di `IosScannerOptions` per formato/qualità/filtro). Resta comunque
  una alternativa valida e architetturalmente equivalente se `cunning_document_scanner` avesse
  problemi in fase di integrazione.

### Google ML Kit Document Scanner (`google_mlkit_document_scanner`) — scartato

- Versione **0.6.1**, pubblicata 2026-08-17. Vincoli: `sdk: ^3.12.0`, `flutter: >=3.44.0` —
  **incompatibile** con la toolchain del progetto (richiede Flutter/Dart più recenti). Anche la
  0.5.0 (`sdk: ^3.8.0`, compatibile) non risolverebbe il problema di fondo. Fonte: [pub.dev API `google_mlkit_document_scanner`](https://pub.dev/api/packages/google_mlkit_document_scanner), storico versioni via pub.dev.
- **Motivo di scarto principale**: **API nativa Google Android-only**, in Beta, mai stata portata su
  iOS — non un limite del binding Flutter ma della piattaforma sottostante. Fonte primaria:
  [developers.google.com/ml-kit/vision/doc-scanner](https://developers.google.com/ml-kit/vision/doc-scanner)
  ("This feature is still in Beta, and it is only available for Android"; unico link di piattaforma
  è `/android`). Per un'app mobile-only che deve coprire iOS **e** Android (requisito di progetto),
  questo pacchetto da solo non è utilizzabile.
- Repository upstream `flutter-ml/google_ml_kit_flutter` è comunque attivamente mantenuto (ultimo
  push 2026-08-17, 1274 star, solo 5 issue aperte) — la scelta di scarto è puramente per copertura
  piattaforma, non per qualità/manutenzione del pacchetto.

### `edge_detection` — scartato

- Versione **1.1.3**, pubblicata **2023-10-17** (~3 anni fa) — **nessuna nuova release da allora**,
  nonostante il repository GitHub `sawankumarbundelkhandi/edge_detection` mostri un push più recente
  (2026-03-09): il codice sul repo si è mosso ma non è mai stato tagliato in una nuova versione
  pub.dev. 270 star ma **57 issue aperte**. Fonte: [pub.dev API `edge_detection`](https://pub.dev/api/packages/edge_detection), GitHub API (`gh api repos/sawankumarbundelkhandi/edge_detection`).
- Meccanismo: usa librerie native meno moderne/meno mantenute rispetto a ML Kit/VisionKit — WeScan
  (iOS, terza parte, non un framework di sistema Apple) e SmartPaperScan (Android, terza parte).
  Fonte: [README `edge_detection`](https://raw.githubusercontent.com/sawankumarbundelkhandi/edge_detection/master/README.md).
- Richiede setup nativo manuale non banale: fissare Kotlin a 1.8.0 lato Android, patch al `Podfile`
  per Xcode 15+, localizzazioni manuali dei pulsanti WeScan in Xcode — un costo di manutenzione
  concreto assente negli altri candidati. Fonte: stesso README.
- **Motivo di scarto**: combinazione di stallo di release (3 anni), alto numero di issue aperte
  relative alle star, e setup nativo manuale più oneroso, a fronte di alternative (`cunning_document_scanner`,
  `flutter_doc_scanner`) che ottengono lo stesso risultato appoggiandosi a framework di sistema
  (ML Kit/VisionKit) mantenuti direttamente da Google/Apple.

### `opencv_dart` — alternativa per pipeline custom (non consigliata come prima scelta)

- Versione **2.2.2**, pubblicata 2026-08-16 (OpenCV 4.13.0 sotto il cofano). Vincoli:
  `sdk: >=3.10.0 <4.0.0`, `flutter: >=3.38.1` — compatibile. Repository `rainyl/opencv_dart`:
  ultimo push 2026-08-19, 252 star, 8 issue aperte, attivamente mantenuto. Fonte: [pub.dev API `opencv_dart`](https://pub.dev/api/packages/opencv_dart), GitHub API (`gh api repos/rainyl/opencv_dart`).
- **Unico approccio tra quelli valutati che permetterebbe davvero** di ottenere un quadrilatero
  esplicito (`cv.findContours` + `cv.approxPolyDP`) da mostrare/editare come overlay prima del warp
  (`cv.getPerspectiveTransform` + `cv.warpPerspective`), rispondendo alla lettera alla domanda
  originale del ticket ("coordinate del contorno da passare come area iniziale").
- **Costo**: nessuna UI pronta — bisogna scrivere e tarare da zero l'intera pipeline (conversione
  scala di grigi, blur, edge detection o soglia adattiva, ricerca contorni, euristica per scegliere
  il contorno "cover" tra i candidati, ordinamento dei 4 punti, calcolo della trasformazione), oltre
  a gestire pixel/coordinate a mano per un eventuale overlay Flutter interattivo di conferma/modifica
  dei 4 angoli. Tempi di sviluppo e di elaborazione runtime non documentati dal pacchetto (dipendono
  dall'implementazione), a differenza delle soluzioni "a scatola chiusa" sopra.
- Ha senso valutarla solo se in futuro servisse un controllo estremamente fine sulla UX di
  rilevamento (es. overlay Flutter nativo con i 4 angoli trascinabili sopra la fotocamera, invece
  della UI di sistema di ML Kit/VisionKit), non per la prima implementazione di questa feature.

---

## Raccomandazione

**Usare `cunning_document_scanner: ^3.0.1`** come step di acquisizione "scansione automatica" della
cover, **prima** (non al posto) di `image_cropper`. Motivazione:

1. È l'unico, tra i pacchetti "scanner pronti", compatibile con la toolchain del progetto
   (`sdk: ^3.10.1`/`flutter >=3.38.0`) **e** con supporto reale sia iOS sia Android — Google ML Kit
   Document Scanner nativo è Android-only (limite di piattaforma Google, non del binding), quindi da
   solo non copre il requisito cross-platform del progetto.
2. Manutenzione attiva verificabile e recente (release 2026-08-11, 0 issue aperte, 160/160 pub
   points), a differenza di `edge_detection` (ferma dal 2023, 57 issue aperte, setup nativo più
   oneroso) e con un profilo di manutenzione migliore del runner-up `flutter_doc_scanner` (18 issue
   aperte su un solo maintainer).
3. Elaborazione interamente on-device su entrambe le piattaforme (ML Kit su Android con fallback
   automatico senza Google Play Services, Vision framework/VisionKit su iOS) — nessuna chiamata cloud,
   nessun costo di rete o privacy da gestire.
4. Riusa permessi/setup già presenti per il pacchetto `camera` (issue #16): stessa
   `NSCameraUsageDescription`/`CAMERA` permission, stessi minimi di piattaforma (iOS 13.0+, Android
   24+). Nessuna configurazione nativa aggiuntiva necessaria oltre l'aggiunta della dipendenza.

**Integrazione con `image_cropper`**: non esiste un percorso "passa il quadrilatero rilevato come
area iniziale" — nessuno dei pacchetti scanner valutati espone quel dato, e comunque `image_cropper`
non accetta un quadrilatero (solo rettangoli, e solo su iOS con posizione arbitraria via
`rectX/Y/W/H`). Il pattern corretto è quindi **in sequenza**: (1) l'utente scatta con
`CunningDocumentScanner.getPictures()`, che rileva i bordi, raddrizza la prospettiva e restituisce già
l'immagine cover ritagliata/corretta; (2) **facoltativamente**, si apre quell'immagine già raddrizzata
in `image_cropper` per un'eventuale rifinitura manuale del rettangolo (es. l'utente vuole stringere
ulteriormente il bordo, o lo scanner ha incluso un bordo di tavolo) — a quel punto è un puro problema
di crop rettangolare, esattamente il caso d'uso per cui `image_cropper` è già stato scelto in #17.

**Piano B**: se in fase di integrazione `cunning_document_scanner` mostrasse problemi (bug, rottura
di build su una versione futura di Flutter/Xcode/AGP), il sostituto diretto con la stessa architettura
(ML Kit Android + VisionKit iOS) è `flutter_doc_scanner: ^0.0.21` — stesso pattern di
integrazione con `image_cropper`, stesse considerazioni sui permessi.

**Da non fare**: costruire da zero una pipeline `opencv_dart` (contorni + warp manuali) come prima
implementazione — è l'unica strada che darebbe davvero un quadrilatero esplicito da mostrare
all'utente, ma il costo di sviluppo/tuning non è giustificato quando ML Kit/VisionKit (già maturi,
mantenuti da Google/Apple, esposti da `cunning_document_scanner`) risolvono lo stesso problema con
zero codice di visione artificiale da scrivere e mantenere internamente. Da rivalutare solo se in
futuro servisse un controllo granulare sulla UX (es. overlay con i 4 angoli trascinabili) che i
componenti di sistema non permettono di personalizzare.
