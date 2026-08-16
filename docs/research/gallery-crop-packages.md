# Selezione da galleria e editor di ritaglio/rotazione — scelta pacchetti

Ricerca per issue [#17](https://github.com/saviogiordano/MyComicBrain/issues/17) (figlia di #15 — Mappa, requisito 5.1).

Target ambiente: **Flutter 3.38.3 / Dart 3.10.1** (vincolo `sdk: ^3.10.1` in `app/pubspec.yaml`).

Metodo: dati presi da pub.dev (pagine pacchetto + API `https://pub.dev/api/packages/<nome>`), README/CHANGELOG sui repository GitHub ufficiali, sorgente del plugin, GitHub API (`pushed_at`, `open_issues_count`, commit log) e documentazione ufficiale Android (`developer.android.com`) / Flutter (`api.flutter.dev`). Ogni affermazione è accompagnata dalla fonte.

---

## (a) Selezione da galleria

### `image_picker` — pacchetto first-party del team Flutter

- Ultima versione **1.2.3**, pubblicata 2026-06-30. Vincoli dichiarati: `sdk: ^3.10.0`, `flutter: >=3.38.0` — **corrisponde esattamente** alla toolchain del progetto (Flutter 3.38.3 / Dart 3.10.1 soddisfano il range). Fonte: [pub.dev API `image_picker`](https://pub.dev/api/packages/image_picker), [pub.dev/packages/image_picker](https://pub.dev/packages/image_picker).
- Publisher verificato `flutter.dev`, 7.75k likes, 160 pub points, ~3.85M download. Fonte: [pub.dev/packages/image_picker](https://pub.dev/packages/image_picker).
- API rilevanti: `pickImage()` (selezione singola, galleria o fotocamera) e `pickMultiImage()` (selezione multipla dalla galleria in un'unica chiamata, restituisce `List<XFile>`). Fonte: [pub.dev/packages/image_picker](https://pub.dev/packages/image_picker).
- Dalla versione 0.8.1 in poi, su iOS 14+ la selezione da galleria usa **PHPicker** (sia per `pickImage` che `pickMultiImage`); su Android 13+ usa il **system Photo Picker**, opzionale (mediante `useAndroidPhotoPicker`) su Android ≤12. Fonte: [README `image_picker`](https://raw.githubusercontent.com/flutter/packages/main/packages/image_picker/image_picker/README.md), [README `image_picker_android`](https://raw.githubusercontent.com/flutter/packages/main/packages/image_picker/image_picker_android/README.md), [CHANGELOG `image_picker_android`](https://raw.githubusercontent.com/flutter/packages/main/packages/image_picker/image_picker_android/CHANGELOG.md) (voce 0.8.5+8: "Adds Android 13 photo picker functionality"; voce 0.8.11: "Android Photo Picker use is not optional on Android 13+").

#### Permessi richiesti

**iOS**
- `Info.plist` richiede comunque tre chiavi: `NSPhotoLibraryUsageDescription`, `NSCameraUsageDescription`, `NSMicrophoneUsageDescription` (solo se si registrano video). Fonte: [README `image_picker`](https://raw.githubusercontent.com/flutter/packages/main/packages/image_picker/image_picker/README.md).
- **Punto chiave**: con PHPicker (iOS 14+, il path usato di default per la galleria), l'accesso alla libreria foto **non richiede il consenso runtime dell'utente** — PHPicker gira come processo di sistema separato e restituisce solo gli asset esplicitamente scelti, senza mai dare all'app accesso all'intera libreria. Conferma diretta dal sorgente del plugin (`launchPHPickerWithContext:` bypassa i controlli di autorizzazione usati dal path legacy). Fonte: [FLTImagePickerPlugin.m](https://github.com/flutter/packages/blob/main/packages/image_picker/image_picker_ios/ios/image_picker_ios/Sources/image_picker_ios/FLTImagePickerPlugin.m).
- Ciononostante Apple richiede la chiave `NSPhotoLibraryUsageDescription` nel `Info.plist` per la App Store review anche se non viene mai richiesta a runtime (l'analisi statica di App Store Connect rileva i framework linkati). Discusso e confermato in [flutter/flutter#113603](https://github.com/flutter/flutter/issues/113603) (rigetto App Store con errore ITMS-90683 in assenza della chiave, pur non richiedendola mai a runtime).
- La fotocamera (`ImageSource.camera`, fuori scope diretto di questo ticket ma condivide lo stesso plugin) **richiede invece un vero consenso runtime**: se negato/ristretto il plugin ritorna un `PlatformException` con codice `camera_access_denied` ("The user did not allow camera access.") o `camera_access_restricted`. Analogamente per il path fotogalleria legacy (iOS <14, non più rilevante dato il target Flutter 3.38): `photo_access_denied` / `photo_access_restricted`. Fonte: [FLTImagePickerPlugin.m](https://github.com/flutter/packages/blob/main/packages/image_picker/image_picker_ios/ios/image_picker_ios/Sources/image_picker_ios/FLTImagePickerPlugin.m), confermato anche in [flutter/flutter#177977](https://github.com/flutter/flutter/issues/177977).

**Android**
- Nessuna configurazione richiesta: il `AndroidManifest.xml` del plugin `image_picker_android` **non dichiara alcun `<uses-permission>`** (verificato leggendo il manifest sorgente: contiene solo un `FileProvider` e un servizio Play Services per il photo picker, nessun permesso). Fonte: [AndroidManifest.xml `image_picker_android`](https://github.com/flutter/packages/blob/main/packages/image_picker/image_picker_android/android/src/main/AndroidManifest.xml).
- Confermato dalla doc ufficiale Android: **il Photo Picker di sistema non richiede alcun permesso runtime** (né `READ_MEDIA_IMAGES` né `READ_EXTERNAL_STORAGE`) — l'app riceve accesso temporaneo in lettura solo agli URI selezionati dall'utente. Fonte: [developer.android.com — Photo picker](https://developer.android.com/training/data-storage/shared/photo-picker).
- Anche sul path legacy (Android ≤12 senza `useAndroidPhotoPicker`), il picking passa per un Intent verso l'app Galleria/Foto tramite Storage Access Framework, che non richiede permessi di storage all'app chiamante. Fonte: [README `image_picker`](https://raw.githubusercontent.com/flutter/packages/main/packages/image_picker/image_picker/README.md) ("should work out of the box").
- La fotocamera (`ImageSource.camera`) richiede invece che l'app dichiari esplicitamente `<uses-permission android:name="android.permission.CAMERA"/>` nel proprio manifest e gestisca la richiesta runtime; se il permesso è negato l'avvio dell'intent fallisce con un errore nativo ("Permission Denial"). Fonte: discussione e log d'errore in [flutter/flutter#13921](https://github.com/flutter/flutter/issues/13921).

#### Comportamento alla negazione dell'accesso (galleria)

Poiché sia iOS (PHPicker) sia Android (Photo Picker/SAF) usano un **picker di sistema out-of-process senza richiedere un permesso preventivo**, per la selezione da galleria non esiste un vero scenario di "negazione permesso": l'utente può sempre aprire il picker; se non seleziona nulla e annulla, `pickImage`/`pickMultiImage` restituiscono semplicemente `null` / lista vuota. Il caso "permesso negato" con eccezione (`camera_access_denied`, `photo_access_denied`) riguarda solo il path fotocamera o il path legacy iOS <14, non la galleria con lo stack corrente.

### Alternative considerate

| Pacchetto | Ultima versione / data | Vincoli SDK | Meccanismo | Permessi |
|---|---|---|---|---|
| `image_picker` (scelto) | 1.2.3 — 2026-06-30 | `sdk: ^3.10.0`, `flutter: >=3.38.0` | System picker (PHPicker/Photo Picker) | Nessuno per la galleria (vedi sopra) |
| `wechat_assets_picker` | 10.1.3 — 2026-07-19 | `sdk: ^3.6.0`, `flutter: >=3.27.0` (copre 3.38) | UI custom in-app (non il picker di sistema), basata su `photo_manager` | Richiede **veri** permessi runtime: `NSPhotoLibraryUsageDescription` su iOS, `READ_MEDIA_IMAGES`/`READ_MEDIA_VIDEO`/`READ_MEDIA_VISUAL_USER_SELECTED`/`READ_EXTERNAL_STORAGE` (SDK <33) su Android — perché bypassa il picker di sistema e legge direttamente MediaStore/PHPhotoLibrary |
| `photo_manager` | 3.12.0 — 2026-08-09 | ampio (`sdk: >=2.13.0 <4.0.0`) | Libreria di basso livello (motore di `wechat_assets_picker`), accesso diretto agli asset | Stessi permessi runtime di cui sopra |
| `file_picker` | 12.0.0 — 2026-08-14 | `sdk: >=3.10.0 <4.0.0`, `flutter: >=3.38.0` | Apre il picker/Files di sistema (documenti generici, non specifico per foto) | Storage Access Framework, generalmente permissionless, ma UX orientata a "file", non a "galleria foto" |

Fonte tabella: [pub.dev API](https://pub.dev/api/packages/wechat_assets_picker), [pub.dev/packages/wechat_assets_picker](https://pub.dev/packages/wechat_assets_picker), [pub.dev API `photo_manager`](https://pub.dev/api/packages/photo_manager), [pub.dev API `file_picker`](https://pub.dev/api/packages/file_picker).

Le alternative "custom UI" (`wechat_assets_picker`/`photo_manager`) offrono più controllo visivo (griglia multi-select in-app, anteprime, filtri per album) ma al prezzo di dover gestire un vero flusso di richiesta/negazione permesso (incluso il caso "limited access" su iOS con `PHAuthorizationStatus.limited` e "partial access" su Android 14+), oltre a un footprint di codice nativo maggiore. Per il caso d'uso del ticket (aggiungere foto già esistenti allo stesso batch di acquisizione cover), il vantaggio di zero permessi e zero UI da mantenere di `image_picker.pickMultiImage()` supera il maggiore controllo di UI offerto dalle alternative.

### Raccomandazione (a)

**Usare `image_picker` (già a un vincolo di versione compatibile con Flutter 3.38.3/Dart 3.10.1: `image_picker: ^1.2.3`), con `pickMultiImage()`** per permettere all'utente di aggiungere più foto dalla galleria nello stesso batch di acquisizione in un'unica chiamata. Motivazione:
1. Pacchetto first-party Flutter, versione pubblicata esplicitamente per `flutter >=3.38.0` — compatibilità garantita per il target del progetto.
2. `pickMultiImage()` sulla galleria non richiede **alcun** permesso runtime su iOS 14+/Android 13+ (system picker), riducendo drasticamente superficie di gestione errori/permessi rispetto alle alternative custom-UI.
3. Nessuna dipendenza nativa aggiuntiva da mantenere (a differenza di `wechat_assets_picker`/`photo_manager`, che richiedono gestione esplicita di permessi parziali/negati su iOS e Android).

Se in futuro servisse una UI di selezione più ricca (filtri per album, multi-select con anteprime persistenti oltre il singolo picker), rivalutare `wechat_assets_picker`, tenendo presente il costo aggiuntivo di gestione permessi.

---

## (b) Editor manuale di ritaglio/rotazione

### Opzione 1 — `image_cropper` (nativo)

- Ultima versione **12.2.1**, pubblicata 2026-04-15. Vincoli: `sdk: >=3.3.0 <4.0.0`, `flutter: >=1.20.0` — compatibile con Dart 3.10.1/Flutter 3.38.3. Fonte: [pub.dev API `image_cropper`](https://pub.dev/api/packages/image_cropper).
- Publisher verificato `hunghd.dev`, 2.450 likes, 140 pub points, ~455k download, licenza BSD-3-Clause. Fonte: [pub.dev/packages/image_cropper](https://pub.dev/packages/image_cropper).
- **Manutenzione**: repository GitHub (`hnvn/flutter_image_cropper`) con ultimo push **2026-07-30** (2 settimane prima di questa ricerca) e commit recenti di fix (`fix(android): forward interior drags to image pan`). Attivamente mantenuto. 339 issue aperte su un repo con 1.1k star / 479 fork — cifra alta ma coerente con un plugin nativo multipiattaforma molto usato; nessuna issue aperta che menzioni esplicitamente "3.38" (ricerca su GitHub Issues search, 0 risultati). Fonte: [GitHub API repo `flutter_image_cropper`](https://api.github.com/repos/hnvn/flutter_image_cropper), [commit log](https://github.com/hnvn/flutter_image_cropper/commits/master).
- **Meccanismo**: wrapper nativo via platform channel — **non elabora l'immagine in Dart**. Usa uCrop (Android, libreria Yalantis), TOCropViewController (iOS, libreria Tim Oliver), Cropper.js (Web). Il file ritagliato/ruotato viene prodotto **nativamente** e restituito già pronto su disco. Fonte: [pub.dev/packages/image_cropper](https://pub.dev/packages/image_cropper).
- **Nota operativa**: il file risultato viene salvato in `NSTemporaryDirectory` su iOS e nella cache dell'app su Android — è responsabilità dell'app spostarlo in storage permanente (rilevante per questo progetto, che persiste la "Scansione" nel database/filesystem). Fonte: [pub.dev/packages/image_cropper](https://pub.dev/packages/image_cropper).
- **Non richiede il pacchetto `image`**: l'intera elaborazione pixel avviene lato nativo.
- **Complessità di integrazione**: bassa-media. Fornisce UI di ritaglio/rotazione pronta all'uso (interfaccia nativa uCrop/TOCropViewController), personalizzabile via `AndroidUiSettings`/`IOSUiSettings`/`WebUiSettings`, ma la UI non è quella di Flutter (è nativa, quindi meno controllo sul look & feel rispetto a un widget Flutter custom).

### Opzione 2 — `crop_your_image` (Dart puro)

- Ultima versione **2.0.0**, pubblicata **2024-12-12** — quindi **~20 mesi fa** rispetto a oggi (2026-08-16). Vincoli dichiarati: `sdk: >=3.0.0 <4.0.0` (range ampio e permissivo, ma non aggiornato/testato più di recente). Fonte: [pub.dev API `crop_your_image`](https://pub.dev/api/packages/crop_your_image).
- **Manutenzione**: repository GitHub (`chooyan-eng/crop_your_image`) **senza commit dal 2024-12-12** — nessuna attività da ~20 mesi, di fatto stallo. 62 issue aperte, 209 star. Fonte: [GitHub API repo `crop_your_image`](https://api.github.com/repos/chooyan-eng/crop_your_image), [commit log](https://github.com/chooyan-eng/crop_your_image/commits/main).
- **Meccanismo**: widget Flutter puro (`Crop` + `CropController`), zoom/pan/aspect ratio/undo-redo. Il ritaglio/rotazione effettivo dei pixel avviene **lato Dart**, e il pacchetto **dipende esplicitamente da `image: ^4.3.0`** per fare l'elaborazione/encoding finale. Fonte: [pub.dev API `crop_your_image`](https://pub.dev/api/packages/crop_your_image) (campo `dependencies`), [pub.dev/packages/crop_your_image](https://pub.dev/packages/crop_your_image).
- Il pacchetto esplicitamente non gestisce accesso/storage dei file né componenti UI oltre al widget di ritaglio ("DON'T handle image storage access ... or provide UI controls beyond the cropping editor").
- **Rischio**: nessuna evidenza di test/fix recenti contro Flutter 3.38/Dart 3.10; l'assenza di attività per ~20 mesi è un segnale di manutenzione debole per un progetto che punta a restare aggiornato sull'ultima toolchain stabile.

### Opzione 3 — Widget custom (`InteractiveViewer` + `CustomPainter`/`RepaintBoundary`)

- `InteractiveViewer` e `CustomPainter` sono parte del framework Flutter stesso (non pacchetti pub.dev): zero problemi di compatibilità/manutenzione di terzi, sempre allineati alla versione Flutter installata.
- Per produrre il file finale ritagliato/ruotato **senza dipendenze esterne**, la tecnica standard è racchiudere il contenuto visualizzato (già trasformato/ruotato tramite `Transform`/`Matrix4`) in un `RepaintBoundary`, ottenere un `ui.Image` via `RenderRepaintBoundary.toImage(pixelRatio: ...)`, poi `image.toByteData(format: ui.ImageByteFormat.png)` per i byte finali — tutto con `dart:ui`, incluso nell'SDK Flutter. Fonte: [api.flutter.dev — `RenderRepaintBoundary.toImage`](https://api.flutter.dev/flutter/rendering/RenderRepaintBoundary/toImage.html), [api.flutter.dev — `ImageByteFormat`](https://api.flutter.dev/flutter/dart-ui/ImageByteFormat.html).
- **Limite importante**: `ui.ImageByteFormat` supporta solo `png` (oltre ai formati raw non compressi) — **non esiste un'opzione JPEG in `dart:ui`**. Fonte: [api.flutter.dev — `ImageByteFormat`](https://api.flutter.dev/flutter/dart-ui/ImageByteFormat.html). Se il progetto vuole salvare le cover come JPEG (più leggero, coerente con l'output tipico della fotocamera), la sola API Flutter/`dart:ui` non basta: serve comunque una libreria di encoding JPEG lato Dart (es. `image` package) oppure un secondo passaggio nativo.
- **Complessità di integrazione**: alta. Bisogna costruire da zero: gestione del rettangolo di ritaglio, vincoli di aspect ratio, gestures di pan/zoom/rotate sincronizzate con l'anteprima, oltre alla logica di rasterizzazione. Nessuna UI pronta all'uso.

### La domanda sulla libreria di manipolazione immagini (`image` package)

Riepilogo per approccio:

| Approccio | Serve `image` (o altra lib Dart) per produrre il file finale? | Perché |
|---|---|---|
| `image_cropper` | **No** | Ritaglio/rotazione avvengono nativamente (uCrop/TOCropViewController/Cropper.js); il plugin restituisce già il file pronto su disco via platform channel. |
| `crop_your_image` | **Sì, obbligatoriamente** | Dipende direttamente da `image: ^4.3.0` nel proprio `pubspec.yaml` — è lui stesso a richiederlo per fare l'elaborazione pixel-level lato Dart. |
| Widget custom (`InteractiveViewer`/`CustomPainter`) | **Dipende dal formato output**: no se PNG va bene (bastano `dart:ui`/`RepaintBoundary`); sì (o serve un path nativo) se serve JPEG o post-processing (compressione qualità, resize) | `dart:ui.ImageByteFormat` non ha un encoder JPEG; l'unico formato compresso disponibile nativamente in Flutter è PNG. |

Fonte: vedi citazioni nelle sezioni precedenti.

### Raccomandazione (b)

**Usare `image_cropper` (`image_cropper: ^12.2.1`)** come editor di ritaglio/rotazione per la singola cover. Motivazione:
1. È l'unico dei tre approcci con manutenzione attiva verificabile di recente (ultimo commit 2026-07-30, ~2 settimane prima di questa ricerca) e vincoli SDK espliciti compatibili con Dart 3.10/Flutter 3.38, contro `crop_your_image` fermo da ~20 mesi.
2. Elaborazione nativa (uCrop/TOCropViewController): niente dipendenza aggiuntiva dal pacchetto `image`, niente lavoro di rasterizzazione/encoding da scrivere e mantenere lato Dart.
3. UI di ritaglio/rotazione pronta all'uso (zoom, aspect ratio, rotazione), riducendo tempo di implementazione rispetto a un widget custom, a fronte di un minore controllo sul look & feel (UI nativa, non Flutter) — accettabile per un editor "utility" post-scatto.
4. Unico avvertimento operativo da gestire in fase di implementazione: il file di output va spostato dalla cartella temporanea/cache verso lo storage permanente dell'app subito dopo il ritaglio, prima che l'OS possa liberarla.

**Scartare `crop_your_image`**: stack Dart-puro interessante (nessuna dipendenza nativa, look & feel Flutter) ma manutenzione ferma da ~20 mesi al momento di questa ricerca — rischio non giustificato per una feature nuova che deve restare sostenibile.

**Non costruire un editor custom**: la complessità di reimplementare gestures di ritaglio/rotazione con `InteractiveViewer`/`CustomPainter` da zero non è ripagata da un vantaggio concreto rispetto a `image_cropper`, e comunque richiederebbe di aggiungere il pacchetto `image` (o un path nativo) se serve output JPEG — cioè lo stesso costo di dipendenza che si vorrebbe evitare, ma con più codice da mantenere internamente.

### Impatto su `pubspec.yaml`

Da aggiungere in `app/pubspec.yaml`:
```yaml
dependencies:
  image_picker: ^1.2.3
  image_cropper: ^12.2.1
```
Nessuna aggiunta del pacchetto `image` è necessaria per la scelta raccomandata (entrambi i pacchetti scelti gestiscono l'I/O immagine internamente/nativamente).
