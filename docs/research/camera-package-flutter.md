# Ricerca: pacchetto `camera` per lo scanner (Wayfinder #16)

> Nota: non esiste ancora una convenzione in questo repo per le note di ricerca; `docs/research/` è
> una posizione ragionevole per raccoglierle (una per ticket `wayfinder:research`).

Contesto: risponde a [issue #16](https://github.com/saviogiordano/MyComicBrain/issues/16), figlia di
#15 (Mappa — Acquisizione della cover). Obiettivo: dati concreti, da fonti primarie (pub.dev,
repository ufficiale `flutter/packages`, documentazione Flutter/Apple/Android ufficiali), per poter
scrivere i ticket `task` di implementazione dello scanner senza sorprese sull'API del plugin.

Target progetto: Flutter 3.38.3 / Dart 3.10.1.

---

## 1. Versione del pacchetto e constraint pubspec

**Versione da usare: `camera: ^0.12.0+2`** (ultima stabile al momento della ricerca).

Il file `pubspec.yaml` del plugin nel repo ufficiale dichiara:

```yaml
environment:
  sdk: ^3.10.0
  flutter: ">=3.38.0"
```

Il changelog conferma esplicitamente il motivo della release:

> ## 0.12.0+2
> * Fixes a crash where a `CameraController` could update its value after being disposed, throwing
>   "A CameraController was used after being disposed".
> * Updates minimum supported SDK version to Flutter 3.38/Dart 3.10.

Quindi `0.12.0+2` è la prima (e a oggi unica) versione che dichiara esplicitamente `Flutter 3.38 /
Dart 3.10` come minimo supportato — combacia esattamente con la toolchain del progetto. Le versioni
precedenti (`0.12.0`, `0.12.0+1`) richiedono solo Dart `^3.9.0`/Flutter `3.35`, quindi funzionerebbero
comunque, ma `0.12.0+2` è la scelta corretta perché è quella pensata per questa combinazione esatta di
SDK e include il fix di crash su dispose.

Da mettere in `app/pubspec.yaml`:

```yaml
dependencies:
  camera: ^0.12.0+2
```

Il pacchetto `camera` è un "federated plugin": porta con sé automaticamente le implementazioni
endorsed per piattaforma — `camera_android_camerax` (^0.7.0, Android) e `camera_avfoundation`
(^0.10.0, iOS) — non vanno aggiunte a mano.

Supporto piattaforme dichiarato nel README: Android SDK 24+, iOS 13.0+.

Fonti:
- https://pub.dev/packages/camera (pagina principale, versione e tabella supporto piattaforme)
- https://raw.githubusercontent.com/flutter/packages/main/packages/camera/camera/pubspec.yaml (constraint SDK esatti)
- https://raw.githubusercontent.com/flutter/packages/main/packages/camera/camera/CHANGELOG.md (changelog 0.12.0+2 e versioni precedenti)

---

## 2. Setup: permessi iOS/Android e gestione runtime

### iOS — `ios/Runner/Info.plist`

Il README ufficiale richiede due chiavi (il plugin registra anche l'audio perché
`CameraController` può abilitare la registrazione video/audio):

```xml
<key>NSCameraUsageDescription</key>
<string>your usage description here</string>
<key>NSMicrophoneUsageDescription</key>
<string>your usage description here</string>
```

Per uno scanner "solo foto" senza registrazione video/audio va comunque aggiunta la chiave
microfono se si istanzia `CameraController` con `enableAudio: true` (default); impostando
`enableAudio: false` nel costruttore si evita il prompt del microfono (comportamento della classe,
non discusso esplicitamente nel README ma coerente con l'API — vedi §4).

### Android — `android/app/src/main/AndroidManifest.xml`

L'implementazione endorsed `camera_android_camerax` dichiara già nel proprio manifest interno
(che viene fuso automaticamente da Gradle nel manifest finale dell'app):

```xml
<uses-feature android:name="android.hardware.camera.any" />
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"
    android:maxSdkVersion="28" />
```

Quindi **non è necessario aggiungere manualmente** `<uses-permission android:name="android.permission.CAMERA"/>`
nel manifest dell'app: viene ereditato per manifest merge dal plugin. Va aggiunto a mano solo per
casi speciali non rilevanti per questo scanner:
- `FOREGROUND_SERVICE_CAMERA` — solo se serve streaming immagini in background su Android 14+.
- `WRITE_EXTERNAL_STORAGE` con `maxSdkVersion="28"` — già incluso dal plugin, riguarda solo
  Android ≤9.

### Gestione runtime del permesso non concesso/negato

Il plugin **non** espone una API dedicata di richiesta permessi: il prompt di sistema (iOS/Android)
scatta automaticamente quando si chiama `CameraController.initialize()`. Se l'utente nega o ha già
negato, `initialize()` (o la successiva `takePicture()`) lancia una `CameraException` con uno di
questi codici, documentati nel README:

- `CameraAccessDenied` — utente ha negato il permesso camera.
- `CameraAccessDeniedWithoutPrompt` — **solo iOS**: l'utente aveva già negato in precedenza; iOS
  non permette un secondo prompt di sistema, va indirizzato a Impostazioni > Privacy > Fotocamera.
- `CameraAccessRestricted` — **solo iOS**: restrizione da controllo parentale, l'utente non può
  concedere il permesso.
- `AudioAccessDenied`, `AudioAccessDeniedWithoutPrompt`, `AudioAccessRestricted` — equivalenti per
  il microfono (irrilevanti se `enableAudio: false`).

Pattern consigliato dal README (esempio adattato):

```dart
controller.initialize().then((_) {
  if (!mounted) return;
  setState(() {});
}).catchError((Object e) {
  if (e is CameraException) {
    switch (e.code) {
      case 'CameraAccessDenied':
        // mostra UI che spiega perché serve il permesso, offri retry
        break;
      case 'CameraAccessDeniedWithoutPrompt':
        // iOS: non si può ri-prompare, serve un CTA che apra le Impostazioni di sistema
        break;
      case 'CameraAccessRestricted':
        // permesso bloccato da restrizioni, nessuna azione utile lato app
        break;
      default:
        // altri errori (hardware non disponibile, ecc.)
        break;
    }
  }
});
```

Fonti:
- https://raw.githubusercontent.com/flutter/packages/main/packages/camera/camera/README.md (sezioni "Setup" e "Handling camera access permissions", testo citato verbatim sopra)
- https://raw.githubusercontent.com/flutter/packages/main/packages/camera/camera_android_camerax/android/src/main/AndroidManifest.xml (contenuto esatto del manifest del plugin)
- https://pub.dev/packages/camera_android_camerax (limitazioni e note setup Android 14+)

---

## 3. Overlay custom sopra `CameraPreview` senza distorsioni

Punto chiave: **`CameraPreview` accetta già un parametro `child` opzionale ed è pensato esattamente
per sovrapporre widget custom senza rompere l'aspect ratio.** Il `build()` del widget (sorgente
ufficiale) è:

```dart
@override
Widget build(BuildContext context) {
  return controller.value.isInitialized
      ? ValueListenableBuilder<CameraValue>(
          valueListenable: controller,
          builder: (BuildContext context, Object? value, Widget? child) {
            return AspectRatio(
              aspectRatio: _isLandscape()
                  ? controller.value.aspectRatio
                  : (1 / controller.value.aspectRatio),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  _wrapInRotatedBox(child: controller.buildPreview()),
                  child ?? Container(),
                ],
              ),
            );
          },
          child: child,
        )
      : Container();
}
```

Quindi il widget internamente:
1. Avvolge tutto in un `AspectRatio` calcolato da `controller.value.aspectRatio` (con inversione
   1/aspectRatio in portrait) — questo garantisce che l'anteprima non venga stirata su schermi di
   dimensioni diverse: lo spazio disponibile viene vincolato all'aspect ratio reale del sensore,
   non riempito forzatamente.
2. Mette in uno `Stack` il feed camera (`controller.buildPreview()`) sotto e il `child` passato
   sopra, entrambi con `StackFit.expand`.

Implicazione pratica per lo scanner: passare l'overlay (cornice guida + testo) come `child` di
`CameraPreview`, **non** come `Stack` esterno attorno a `CameraPreview`:

```dart
CameraPreview(
  controller,
  child: ScannerOverlay(...), // cornice + testo, disegnati con CustomPaint o Container/Border
)
```

In questo modo l'overlay eredita automaticamente lo stesso rettangolo con aspect ratio corretto
del feed camera, e resta coerente su schermi di dimensioni/proporzioni diverse senza calcoli manuali
aggiuntivi. Se lo schermo ha un aspect ratio diverso da quello della camera, l'`AspectRatio` lascerà
spazio vuoto (letterbox) intorno al blocco preview+overlay: è un comportamento voluto del widget per
evitare la distorsione, da tenere in conto nel design (es. sfondo nero/branded attorno al riquadro).

Fonte:
- https://raw.githubusercontent.com/flutter/packages/main/packages/camera/camera/lib/src/camera_preview.dart (sorgente completo del metodo `build()`, citato verbatim sopra)

---

## 4. API di scatto foto

```dart
Future<XFile> takePicture()
```

- Metodo su `CameraController`. Cattura un'immagina e la salva su un file, restituendo un `XFile`
  (astrazione cross-platform di `cross_file`, usata anche su web).
- Il percorso del file va letto da `file.path` (`String`).
- Se si invoca `takePicture()` mentre una cattura precedente è ancora in corso, lancia una
  `CameraException` ("Previous capture has not returned yet.") — va quindi disabilitato il
  pulsante di scatto finché il `Future` precedente non si è risolto.
- Esempio ufficiale (Flutter cookbook):

```dart
try {
  await _initializeControllerFuture;
  final image = await _controller.takePicture();
  // image.path -> percorso del file JPEG salvato in una cache directory del device
} on CameraException catch (e) {
  // gestione errori
}
```

Il file viene salvato automaticamente in una directory di cache del dispositivo gestita dal plugin
(non serve specificare un path in `takePicture()`); se il percorso finale nell'app deve essere
persistente (es. cartella dei dati dell'app), va copiato esplicitamente con `path_provider` dopo la
cattura — questo passaggio non è nel plugin `camera` ma nella ricetta ufficiale Flutter, che infatti
lo elenca come dipendenza consigliata insieme a `path`.

Fonti:
- https://pub.dev/documentation/camera/latest/camera/CameraController/takePicture.html (firma, tipo di ritorno, eccezioni)
- https://docs.flutter.dev/cookbook/plugins/picture-using-camera (ricetta ufficiale Flutter, esempio completo end-to-end con `takePicture`, `path_provider`, `image.path`)

---

## 5. Ciclo di vita: pause/resume e hot reload

### Pause/resume (documentato esplicitamente)

Dal README, sezione "Handling Lifecycle states":

> As of version 0.5.0 of the camera plugin, lifecycle changes are no longer handled by the plugin.
> This means developers are now responsible to control camera resources when the lifecycle state is
> updated.

Pattern raccomandato (da implementare con `WidgetsBindingObserver`):

```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  final CameraController? cameraController = controller;

  // App state changed before we got the chance to initialize.
  if (cameraController == null || !cameraController.value.isInitialized) {
    return;
  }

  if (state == AppLifecycleState.inactive) {
    cameraController.dispose();
  } else if (state == AppLifecycleState.resumed) {
    _initializeCameraController(cameraController.description);
  }
}
```

Cioè: **dispose del controller quando l'app va in `inactive`, reinizializzazione completa (nuovo
`CameraController` + `initialize()`) quando torna in `resumed`.** Non c'è un metodo "pausa/riprendi"
nativo del controller: il pattern è dispose totale + ricreazione. La classe che implementa lo
scanner screen deve quindi mixare `WidgetsBindingObserver` e registrarsi/derigistrarsi in
`initState`/`dispose`.

### Hot reload

Il README e il changelog **non hanno una sezione dedicata all'hot reload** — l'unico meccanismo
documentato è quello di lifecycle sopra. Considerazioni pratiche (dedotte dalla semantica generale
di hot reload di Flutter, non da doc specifiche del plugin, quindi da trattare come nota implementativa
e non come fatto documentato):
- L'hot reload preserva lo stato del widget tree (non rirunna `initState`), quindi un
  `CameraController` già inizializzato resta vivo e valido attraverso un hot reload — non serve
  gestione speciale.
- Un **hot restart** invece ricrea l'intero stato dell'app da zero (`main()` rieseguito): il
  controller precedente viene perso senza che `dispose()` venga chiamato esplicitamente dal
  framework sul vecchio processo Dart, ma poiché la sessione nativa viene ricreata da capo non
  causa memory leak persistente nell'app in esecuzione (il processo viene sostituito). Da
  verificare comunque in pratica quando si implementa lo screen, perché non è un comportamento
  garantito per iscritto dal plugin.

Fonte:
- https://raw.githubusercontent.com/flutter/packages/main/packages/camera/camera/README.md (sezione "Handling Lifecycle states", testo citato verbatim sopra; nessuna menzione di "hot reload" nel file, verificato con ricerca testuale)

---

## 6. Limitazioni note su iOS Simulator / Android emulator

### iOS Simulator

Non esiste una nota ufficiale del plugin `camera`/`camera_avfoundation` specifica sul Simulator, ma
la documentazione Apple per AVFoundation (framework nativo su cui si basa `camera_avfoundation`) è
esplicita:

> Because Xcode doesn't have access to the device camera, this sample won't work in Simulator.

(dalla guida ufficiale Apple "AVCam: Building a camera app"). Conseguenza pratica per questo
progetto: sull'iOS Simulator `availableCameras()` restituisce una lista vuota (nessun
`AVCaptureDevice` disponibile) e lo scanner screen non può mostrare un feed live — va testato su un
dispositivo fisico iOS, oppure va previsto un fallback/mock nello screen quando la lista camere è
vuota per non bloccare lo sviluppo UI su Simulator.

### Android Emulator

La documentazione ufficiale Android Studio per l'emulatore ("Set up the Android Emulator camera")
descrive tre modalità configurabili per AVD:
- **None** — nessuna camera.
- **Emulated** — feed sintetico generato dall'emulatore (immagini virtuali importabili in "Virtual
  scene").
- **Webcam0** — passthrough della webcam del computer host.

Con **Emulated** il feed è sintetico (non una vera foto del mondo reale) — utile per verificare che
UI/overlay/scatto funzionino, ma non rappresentativo di una foto reale di copertina fumetto; con
**Webcam0** si ottiene un feed video reale (quello della webcam del laptop) che può servire per un
test più realistico dell'interazione, ma non è comunque la fotocamera posteriore di un telefono. Le
funzionalità camera avanzate (RAW capture, YUV reprocessing, logical camera, video stabilization)
sono garantite dai doc solo su emulatori Android 11+; su versioni precedenti solo funzionalità di
base.

Raccomandazione pratica: sviluppo/debug dell'overlay e della UI si possono fare su emulatore
(Webcam0 per un feed reale), ma la validazione finale di scatto/qualità foto copertina va fatta su
dispositivo fisico sia iOS sia Android.

Fonti:
- https://developer.apple.com/documentation/avfoundation/avcam-building-a-camera-app (nota ufficiale Apple sul Simulator, citata verbatim sopra)
- https://developer.android.com/studio/run/emulator-use-camera (modalità camera AVD: None/Emulated/Webcam0, funzionalità avanzate legate ad Android 11+)
- https://pub.dev/packages/camera_android_camerax#limitations (limitazioni note dell'implementazione CameraX, nessuna specifica per emulatore ma rilevanti per lo sviluppo Android in generale: risoluzione video 240p non supportata, `streamOptions` in `VideoCaptureOptions` ignorato, formato NV21 riportato come yuv420 nello stream)

---

## Riepilogo per chi implementa

1. `pubspec.yaml`: `camera: ^0.12.0+2`.
2. iOS: 2 chiavi in `Info.plist` (`NSCameraUsageDescription`, `NSMicrophoneUsageDescription` — la
   seconda solo se `enableAudio: true`). Android: nessuna modifica manuale al manifest necessaria
   per il permesso camera base (fuso automaticamente dal plugin).
3. Gestire `CameraException` da `initialize()`/`takePicture()` con `switch` sul codice
   (`CameraAccessDenied`, `CameraAccessDeniedWithoutPrompt` → CTA verso Impostazioni su iOS, ecc.).
4. Overlay: passarlo come `child:` di `CameraPreview(controller, child: overlay)`, non wrapparlo
   esternamente — l'`AspectRatio` interno del widget evita la distorsione.
5. Scatto: `final XFile file = await controller.takePicture(); final path = file.path;` — disabilitare
   il bottone di scatto mentre un `takePicture()` è già in volo.
6. Lifecycle: `WidgetsBindingObserver` + `didChangeAppLifecycleState` → dispose su `inactive`,
   reinizializzazione completa su `resumed`. Hot reload non richiede gestione speciale (stato
   preservato); hot restart ricrea tutto da `main()`.
7. Sviluppo locale: iOS Simulator non ha camera (lista vuota, serve device fisico o fallback UI);
   Android Emulator supporta un feed reale solo in modalità Webcam0, altrimenti feed sintetico —
   per la qualità reale delle foto copertina serve comunque un device fisico.
