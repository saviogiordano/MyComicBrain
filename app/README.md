# MyComicBrain

Catalogo personale di fumetti: cattura una collezione fisica con scansione/riconoscimento AI, la organizza per opera/edizione/copia e ne calcola statistiche e completezza delle serie.

App Flutter per iOS e Android, stato con Riverpod, persistenza locale con Drift/SQLite (nessun backend in questa fase).

## Prerequisiti

- **Flutter 3.38.3 / Dart 3.10.1** — verifica con `flutter --version`; se non coincide, `flutter upgrade` o `fvm use` a seconda di come gestisci le versioni.
- **Per iOS**: Xcode con iOS Simulator installato, CocoaPods (`sudo gem install cocoapods` se manca).
- **Per Android**: Android Studio con Android SDK e almeno un AVD (emulatore) configurato, oppure un device fisico con debug USB attivo.
- `flutter doctor` senza errori bloccanti per le piattaforme che ti interessano.

## Setup

Dalla cartella `app/`:

```bash
flutter pub get
```

Il codice generato da Drift (`lib/core/data/database.g.dart`) è già committato: non serve rigenerarlo per lanciare l'app. Se modifichi lo schema in `lib/core/data/database.dart`, rigeneralo con:

```bash
dart run build_runner build --delete-conflicting-outputs
```

## Configurare le chiavi API dei provider AI

L'analisi AI della copertina (OCR §6.1 + computer vision §6.2) chiama l'API di un provider AI direttamente dal client — Claude di default, OpenAI come alternativa selezionabile (vedi `CoverAnalysisProviderConfig`). Le chiavi non vanno mai committate: vengono incorporate a build-time via `--dart-define-from-file`.

1. Copia il template: `cp dart_define.example.json dart_define.json` (dalla cartella `app/`).
2. Apri `dart_define.json` e imposta `ANTHROPIC_API_KEY` con la tua chiave Anthropic (obbligatoria col provider di default). Il file è in `.gitignore`, resta locale.
3. Se vuoi usare OpenAI invece di Claude: imposta `OPENAI_API_KEY` con la tua chiave OpenAI e `COVER_ANALYSIS_PROVIDER` a `"openai"` (default `"claude"`, nessuna UI per la scelta).
4. Usa `scripts/flutter.sh` al posto di `flutter` per i comandi `run` e `build`: rileva `dart_define.json` e aggiunge automaticamente `--dart-define-from-file`, così i comandi restano quelli standard senza ripeterlo ogni volta:
   ```bash
   scripts/flutter.sh run -d "iPhone 16"
   ```
   Equivalente manuale, se preferisci non usare lo script:
   ```bash
   flutter run --dart-define-from-file=dart_define.json -d "iPhone 16"
   ```

Senza `dart_define.json` (o senza passare il flag manualmente) `ClaudeApiConfig.apiKey`/`OpenAiApiConfig.apiKey` restano vuote e `isConfigured` è `false`.

## Eseguire su iOS Simulator

Avvia un simulatore (uno a scelta fra quelli disponibili):

```bash
open -a Simulator
xcrun simctl list devices available   # per vedere gli id disponibili
xcrun simctl boot "iPhone 16"         # o l'id/nome che preferisci, se non già avviato
```

Poi lancia l'app:

```bash
flutter devices                       # conferma che il simulatore compaia in lista
scripts/flutter.sh run -d "iPhone 16" # o l'id del device mostrato da `flutter devices`
```

## Eseguire su Android emulator

Avvia un emulatore (uno a scelta fra quelli configurati):

```bash
flutter emulators                     # elenca gli emulatori disponibili
flutter emulators --launch <id>       # es. Pixel_4_API_34
```

Poi lancia l'app:

```bash
flutter devices                       # conferma che l'emulatore compaia in lista
scripts/flutter.sh run -d emulator-5554  # o l'id mostrato da `flutter devices`
```

In alternativa, con un device fisico Android collegato via USB (debug USB attivo), `flutter devices` lo elenca allo stesso modo e puoi lanciarlo con `scripts/flutter.sh run -d <id-device>`.

## Eseguire su device fisico

Utile in particolare per testare lo scanner (fotocamera reale, permessi, prestazioni), non riproducibile in modo affidabile su Simulator/emulatore.

### iOS (iPhone fisico)

1. **Xcode signing** — apri `ios/Runner.xcworkspace` in Xcode (o `open ios/Runner.xcworkspace`), seleziona il target `Runner` → tab *Signing & Capabilities* → abilita *Automatically manage signing* e seleziona il tuo Apple ID/team personale (basta un Apple ID gratuito per il debug su device proprio, senza account developer a pagamento).
2. **Collega l'iPhone via USB** (o Wi-Fi, dopo il primo pairing via cavo) e sbloccalo.
3. **Trust del computer** — sull'iPhone conferma il prompt "Trust This Computer?" (serve, se richiesto, anche l'inserimento del passcode del device).
4. Verifica che compaia nella lista device:
   ```bash
   flutter devices
   ```
5. Lancia l'app:
   ```bash
   scripts/flutter.sh run -d <id-device>  # es. l'UDID o il nome mostrato da flutter devices
   ```
6. **Su iOS 26+: crash/schermo bianco in debug** — bug noto del JIT di Flutter su iOS 26 ([flutter/flutter#163984](https://github.com/flutter/flutter/issues/163984), [#176263](https://github.com/flutter/flutter/issues/176263), variante intermittente in [#184533](https://github.com/flutter/flutter/issues/184533)): il sistema revoca i permessi di esecuzione sulle pagine JIT e l'app crasha con `EXC_BAD_ACCESS` al lancio (a volte subito, a volte dopo qualche minuto), indipendentemente dal codice dell'app. Non è un bug del progetto.
   - **Per iterare con hot reload**: usa l'iOS Simulator (funziona regolarmente in debug, vedi sezione sopra), non il device fisico.
   - **Per testare sul device reale** (es. la fotocamera, che sul Simulator non è disponibile): lancia in modalità `--release` o `--profile`, che non usano JIT e non sono soggette al bug:
     ```bash
     scripts/flutter.sh run --release -d <id-device>
     # oppure, per i log di performance senza le ottimizzazioni aggressive del release:
     scripts/flutter.sh run --profile -d <id-device>
     ```
   - Ogni tanto vale la pena rifare `flutter upgrade`: la variante intermittente potrebbe essere risolta in una release più recente di quella attuale (3.38.3).
7. **Primo avvio: "Untrusted Developer"** — se l'app non parte e su iPhone appare un errore, vai su *Impostazioni → Generali → VPN e gestione dispositivo*, seleziona il tuo Apple ID/profilo sviluppatore e tocca *Trust*. Poi riavvia l'app dalla home o rilancia `scripts/flutter.sh run`.
8. **Permesso fotocamera** — al primo utilizzo dello scanner iOS mostra il prompt di sistema (testo da `NSCameraUsageDescription` in `ios/Runner/Info.plist`); se negato per errore, va riabilitato da *Impostazioni → Privacy e sicurezza → Fotocamera → MyComicBrain*.

### Android (device fisico)

1. **Abilita le Opzioni sviluppatore** sul device: *Impostazioni → Informazioni sul telefono*, tocca 7 volte su *Numero build* finché non appare "Sei ora uno sviluppatore!".
2. **Attiva il debug USB**: *Impostazioni → Sistema → Opzioni sviluppatore → Debug USB* (ON).
3. **Collega il device via USB** e, se richiesto sullo schermo del device, conferma *Consenti debug USB* (puoi spuntare "Consenti sempre da questo computer" per non ripetere il prompt).
4. Verifica che compaia nella lista device:
   ```bash
   flutter devices
   adb devices                         # in alternativa, per conferma a basso livello
   ```
5. Lancia l'app:
   ```bash
   scripts/flutter.sh run -d <id-device>
   ```
6. **Debug via Wi-Fi (opzionale, senza cavo dopo il pairing iniziale)**:
   ```bash
   adb tcpip 5555
   adb connect <ip-device>:5555        # IP del device, visibile in Impostazioni → Wi-Fi
   flutter devices                     # il device dovrebbe comparire via rete
   ```
7. **Permesso fotocamera** — `image_picker`/`camera` richiedono il permesso runtime al primo utilizzo dello scanner; se negato per errore, va riabilitato da *Impostazioni → App → MyComicBrain → Autorizzazioni → Fotocamera*.

## Comandi utili durante `flutter run`

- `r` — hot reload
- `R` — hot restart
- `q` — termina l'app e il processo

## Test e analisi statica

```bash
flutter analyze
flutter test
```

Il database Drift/SQLite parte sempre vuoto (nessun seed demo): al primo avvio la Dashboard mostra lo stato vuoto finché non si aggiunge almeno una copia.
