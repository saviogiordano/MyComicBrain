# Pubblicare l'app su TestFlight, App Store e Play Store

Come costruire e pubblicare la **build senza cloud** (`CLOUD_ENABLED=false`).
In questa build l'app vive solo in Modalità locale: niente account e niente
Sincronizzazione, e Supabase non viene mai inizializzato. Il flag è definito
in `app/lib/core/config/funzionalita.dart`.

> **Regola d'oro:** costruisci sempre con `scripts/build-store.sh`, mai con
> Product → Archive di Xcode o con un `flutter build` senza flag.
> Xcode riprende i `dart-define` dell'ultima build Flutter lanciata, quindi
> rischi di pubblicare la versione con il cloud acceso.

Dati dell'app:

| | |
|---|---|
| Bundle ID / applicationId | `com.saviogiordano.mycomicbrain.mycomicbrain` |
| Team Apple | `5Y43GX53B5` (firma automatica) |
| Versione | `version:` in `app/pubspec.yaml` (`1.0.0+1` = versione `1.0.0`, build `1`) |

---

## Versione e numero di build

Ogni upload, su entrambi gli store, vuole un **numero di build più alto**
del precedente. Puoi:

- passarlo allo script: `scripts/build-store.sh ios --build-number=3`;
- oppure cambiare `version:` in `pubspec.yaml`, ad esempio `1.0.0+3`, e
  committare. Così la storia delle release resta nel repo.

Per una nuova versione visibile agli utenti cambia la prima parte
(`1.0.1+4`), oppure passa `--build-name=1.0.1`.

---

## iOS

### Una volta sola

1. **Registra il bundle ID**, se non c'è già: developer.apple.com →
   Certificates, Identifiers & Profiles → Identifiers → "+" → App IDs. Spunta
   la capability *Sign in with Apple*: l'entitlement è nel progetto anche se
   la build locale non la usa.
2. **Crea l'app su App Store Connect**: appstoreconnect.apple.com → App →
   "+" → Nuova app, piattaforma iOS, quel bundle ID, una SKU a piacere (ad
   esempio `mycomicbrain`).
3. **Domanda sulla crittografia**: per non doverla compilare a ogni build,
   aggiungi a `app/ios/Runner/Info.plist`:
   ```xml
   <key>ITSAppUsesNonExemptEncryption</key>
   <false/>
   ```
   L'app usa solo HTTPS standard, quindi "nessuna crittografia non esente".
4. Su Xcode → Settings → Accounts deve esserci il tuo Apple ID con il team.
   Xcode crea da solo certificato e profilo di distribuzione.

### A ogni release

1. Parti da `main` aggiornato, con l'albero pulito:
   ```bash
   git checkout main && git pull
   ```
2. Costruisci l'archive firmato:
   ```bash
   scripts/build-store.sh ios --build-number=<N>
   ```
   Lo script produce:
   - `app/build/ios/archive/MyComicBrain.xcarchive`, l'archive;
   - `app/build/ios/ipa/*.ipa`, il file da caricare.
3. Carica la build in uno di questi modi:
   - **Xcode Organizer** (il più semplice):
     ```bash
     open app/build/ios/archive/MyComicBrain.xcarchive
     ```
     poi Distribute App → App Store Connect → Upload.
   - **Transporter** (app gratuita del Mac App Store): trascini dentro il
     file `.ipa` e premi Consegna.
   - **Da terminale**, con una chiave API di App Store Connect (Utenti e
     accessi → Integrazioni → chiavi API; il file `.p8` va in
     `~/.appstoreconnect/private_keys/`):
     ```bash
     xcrun altool --upload-app -t ios -f app/build/ios/ipa/*.ipa \
       --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>
     ```

### TestFlight

1. Dopo 10–30 minuti di elaborazione la build compare in App Store Connect →
   la tua app → **TestFlight** (arriva anche una mail).
2. **Tester interni** (fino a 100 membri del team): crea un gruppo, aggiungi
   le persone e la build. È subito disponibile nell'app TestFlight.
3. **Tester esterni** (fino a 10.000, tramite email o link pubblico): crea un
   gruppo esterno. La prima build passa una breve revisione Beta di Apple
   (di solito meno di 24 ore).

### Pubblicazione sull'App Store

In App Store Connect → la tua app → **Distribuzione**:

1. **Informazioni sull'app**: nome, sottotitolo, categoria (ad esempio
   Libri o Produttività), classificazione per età.
2. **Privacy dell'app**: URL della privacy policy (obbligatorio) e
   dichiarazione dei dati raccolti. Senza cloud i dati restano sul
   dispositivo. Ricorda però le chiamate esterne: ComicVine, PriceCharting e
   i provider AI configurati dall'utente con le sue chiavi.
3. **Versione**:
   - screenshot (obbligatori quelli iPhone 6,9", ad esempio un iPhone 17 Pro
     Max in Simulator);
   - descrizione, parole chiave, URL di supporto;
   - sezione **Build**: scegli quella caricata.
4. **Note per la revisione**: spiega che l'app funziona senza account e che
   le funzioni AI richiedono una chiave API dell'utente. Se servono per
   provarle, dai al revisore indicazioni o una chiave di test.
5. **Aggiungi per la revisione → Invia**. Di solito Apple risponde in 1–2
   giorni. Puoi scegliere la pubblicazione automatica o manuale
   all'approvazione.

---

## Android

### Una volta sola

1. **Crea la chiave di upload.** Conservala fuori dal repo: `keys/` e
   `*.jks` sono già in `.gitignore`. Salva anche una copia di backup sicura,
   perché senza chiave non puoi più aggiornare l'app finché non chiedi a
   Google di reimpostarla.
   ```bash
   keytool -genkey -v -keystore keys/upload-keystore.jks \
     -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
2. **Crea `app/android/key.properties`** (anche questo è ignorato da git):
   ```properties
   storePassword=<password>
   keyPassword=<password>
   keyAlias=upload
   storeFile=../../../keys/upload-keystore.jks
   ```
   `app/android/app/build.gradle.kts` lo legge e firma il release con la
   chiave di upload. Senza il file firma con la chiave di debug, che va bene
   per `flutter run --release` ma che Play Console rifiuta: per questo
   `scripts/build-store.sh android` si ferma se il file manca.
3. **Crea l'app su Play Console** (play.google.com/console, account
   sviluppatore da 25 $ una tantum): Crea app → nome, lingua, app gratuita.
   Accetta la **Firma dell'app di Google Play**: Google tiene la chiave di
   firma, tu usi solo quella di upload.

### A ogni release

1. ```bash
   scripts/build-store.sh android --build-number=<N>
   ```
   Lo script produce `app/build/app/outputs/bundle/release/app-release.aab`.
2. Play Console → la tua app → **Test → Test interno** → Crea nuova
   release → carica il file `.aab` → note di rilascio → Salva → Rivedi e
   implementa.

### Pubblicazione su Play Store

1. Prima di poter andare in produzione, compila in **Dashboard** tutte le
   voci di "Configura la tua app":
   - privacy policy;
   - accesso all'app (nessun login necessario);
   - annunci;
   - classificazione dei contenuti (questionario);
   - target di età;
   - **Sicurezza dei dati** (vale quanto detto per la privacy iOS).
2. **Scheda dello Store**: icona 512×512, grafica in evidenza 1024×500,
   almeno 2 screenshot del telefono, descrizione breve e completa.
3. ⚠️ Gli **account sviluppatore personali creati dopo novembre 2023** devono
   fare un **test chiuso con almeno 12 tester per 14 giorni consecutivi**
   prima di poter chiedere l'accesso alla produzione.
4. **Produzione** → Crea nuova release → aggiungi la build dalla libreria
   (lo stesso `.aab` del test) → Invia per la revisione. Di solito servono
   da poche ore a qualche giorno.

---

## Checklist rapida per ogni release

- [ ] `main` aggiornato e test verdi
- [ ] numero di build aumentato
- [ ] `scripts/build-store.sh ios|android|tutti` (mai Xcode Archive)
- [ ] provata la build su TestFlight o nel test interno: niente "Crea un
      account" nel benvenuto, niente sezione Account in Impostazioni
- [ ] upload, note di rilascio, invio per la revisione

## Quando accenderemo il cloud

Basta costruire senza `--dart-define=CLOUD_ENABLED=false`, oppure con
`=true`, e aggiornare lo script. Al primo accesso, chi ha la build solo
locale riceverà la proposta di importare i propri dati (ADR-0005). Prima
di pubblicare bisognerà aggiornare le dichiarazioni privacy (account, email,
dati su Supabase) e verificare che l'eliminazione dell'account sia
raggiungibile (App Store 5.1.1(v)).
