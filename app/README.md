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
flutter run -d "iPhone 16"            # o l'id del device mostrato da `flutter devices`
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
flutter run -d emulator-5554          # o l'id mostrato da `flutter devices`
```

In alternativa, con un device fisico Android collegato via USB (debug USB attivo), `flutter devices` lo elenca allo stesso modo e puoi lanciarlo con `flutter run -d <id-device>`.

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
