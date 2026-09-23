# Ricerca — login Apple, Google ed email con `supabase_flutter` su iOS e Android

> Risposta al ticket Wayfinder [#168](https://github.com/saviogiordano/MyComicBrain/issues/168), parte della mappa [#165](https://github.com/saviogiordano/MyComicBrain/issues/165) ("Account singolo end-to-end"). Sblocca [#171](https://github.com/saviogiordano/MyComicBrain/issues/171).
>
> Questo documento è **solo ricerca**: fatti da fonti primarie (docs Supabase, codice sorgente di `supabase-flutter`, pub.dev, docs Apple/Google), verificati il 2026-09-23. Non modifica codice applicativo. Dove un punto è una deduzione e non un fatto citato, è marcato come **(deduzione)**.

Contesto noto: progetto Supabase `ojfwicezfctlwpouudsa`; provider Apple già configurato su Supabase con Services ID `com.saviogiordano.mycomicbrain.mycomicbrain.signin` (#156); bundle id / applicationId `com.saviogiordano.mycomicbrain.mycomicbrain`; stack Flutter 3.38.3 / Dart 3.10.1; iOS deployment target 15.0; Android `MainActivity` già con `launchMode="singleTop"`. In `app/pubspec.yaml` oggi non c'è nessuna dipendenza Supabase/Apple/Google; `flutter_secure_storage: ^11.0.0` e `shared_preferences: ^2.5.5` sono già presenti.

---

## 1. Versioni dei pacchetti e compatibilità con Flutter 3.38.3

Dati letti dall'API di pub.dev (`https://pub.dev/api/packages/<nome>`, campo `environment` di ogni versione).

| Pacchetto | Ultima versione | Vincolo SDK dell'ultima | **Versione massima compatibile con Flutter 3.38.3 / Dart 3.10.1** |
|---|---|---|---|
| [`supabase_flutter`](https://pub.dev/packages/supabase_flutter) | 2.17.2 (2026-08-14); 3.0.0-dev.6 in pre-release | Flutter ≥3.35, Dart ≥3.9 | **2.17.2** ✓ |
| [`sign_in_with_apple`](https://pub.dev/packages/sign_in_with_apple/versions) | 8.2.0 (2026-08-27) | Flutter ≥3.44, Dart ^3.12 | **7.0.1** (8.0.0 richiede già Flutter ≥3.41) |
| [`google_sign_in`](https://pub.dev/packages/google_sign_in/versions) | 7.2.0 (2025-09-17) | Flutter ≥3.29, Dart ^3.7 | **7.2.0** ✓ |
| ↳ `google_sign_in_android` (transitiva) | 7.2.17 | Flutter ≥3.44 da 7.2.12 | **7.2.11** (il resolver la sceglie da solo) |
| ↳ `google_sign_in_ios` (transitiva) | 6.3.5 | Flutter ≥3.38 | **6.3.5** ✓ |
| ↳ `app_links` (transitiva di `supabase_flutter`, range `>=6.4.1 <8.0.0`) | 7.2.1 | Flutter ≥3.44 da 7.1.0 | **7.0.0** (richiede Flutter ≥3.38.1) |
| [`crypto`](https://pub.dev/packages/crypto) (SHA-256 del nonce) | 3.0.7 | Dart ^3.4 | **3.0.7** ✓ (già transitiva via `gotrue`) |
| [`flutter_secure_storage`](https://pub.dev/packages/flutter_secure_storage) | 11.2.0 | Flutter ≥3.19 | **11.2.0** ✓ (già in uso) |

Punti da notare:

- **`sign_in_with_apple` va fissato a `^7.0.1`**, come già fatto per `speech_to_text`: la 8.x non è risolvibile sullo stack del progetto.
- **Attenzione alla toolchain locale**: sulla macchina di sviluppo `flutter --version` riporta oggi **Flutter 3.47.1 / Dart 3.13.1**, non 3.38.3. Con quella toolchain `pub get` sceglierebbe `sign_in_with_apple` 8.2.0, `app_links` 7.2.1 e `google_sign_in_android` 7.2.17, cioè versioni che poi non girano su 3.38.3. Se lo stack di riferimento resta 3.38.3, i pin espliciti servono, oppure va allineata la toolchain.
- **`supabase_flutter` 3.0.0 è in `-dev`** e ha molte breaking change che toccano l'auth: `AuthState` diventa una sealed class ([#1846](https://github.com/supabase/supabase-flutter/issues/1846)), i metodi auth restituiscono `Session` ([#1845](https://github.com/supabase/supabase-flutter/issues/1845)), `AuthClient` gestisce la persistenza tramite un unico storage ([#1805](https://github.com/supabase/supabase-flutter/issues/1805)), la sessione viene salvata con `SharedPreferencesAsync` ([#1680](https://github.com/supabase/supabase-flutter/issues/1680)) e `gotrue` è rinominato `supabase_auth` ([#1697](https://github.com/supabase/supabase-flutter/issues/1697)). Fonte: [CHANGELOG su `main`](https://github.com/supabase/supabase-flutter/blob/main/packages/supabase_flutter/CHANGELOG.md). **Conviene usare 2.17.x stabile** e rimandare la migrazione a v3.
- In 2.17.x `Supabase.initialize` accetta `publishableKey`, mentre `anonKey` è `@Deprecated('Use publishableKey instead…')` ([`supabase.dart` @ v2.17.2](https://github.com/supabase/supabase-flutter/blob/supabase_flutter-v2.17.2/packages/supabase_flutter/lib/src/supabase.dart)).

### Breaking change di `google_sign_in` 7.x (rispetto alla 6.x)

Fonte: [CHANGELOG di google_sign_in](https://pub.dev/packages/google_sign_in/changelog) e [API `initialize`](https://pub.dev/documentation/google_sign_in/latest/google_sign_in/GoogleSignIn/initialize.html).

- `GoogleSignIn` è un **singleton** (`GoogleSignIn.instance`) e non si costruisce più con `GoogleSignIn(...)`.
- Va chiamato e atteso **una sola volta** `initialize({String? clientId, String? serverClientId, String? nonce, String? hostedDomain})` prima di qualunque altro metodo (7.1.1 ne documenta l'obbligo).
- **Autenticazione e autorizzazione sono passi separati.** `authenticate()` (se `supportsAuthenticate()` è true, cioè su iOS e Android) o `attemptLightweightAuthentication()` restituiscono l'account, con l'`idToken` in `account.authentication.idToken`. L'access token OAuth si ottiene a parte con `account.authorizationClient.authorizeScopes([...])` / `authorizationForScopes`. `signIn()` e il vecchio bundle di token non esistono più.
- La 7.1.0 esporta `GoogleSignInExceptionCode` e la 7.2.0 aggiunge `clearAuthorizationToken`.
- Su Android il plugin usa Credential Manager. Gli errori di configurazione (SHA-1 sbagliato, package name errato, `serverClientId` mancante) possono presentarsi come un **"canceled" indistinguibile da un annullamento dell'utente** ([README google_sign_in_android](https://pub.dev/packages/google_sign_in_android)).

---

## 2. Flusso nativo vs OAuth via browser, per piattaforma

### Sign in with Apple

Fonte: [Supabase — Login with Apple (Flutter)](https://supabase.com/docs/guides/auth/social-login/auth-apple?platform=flutter).

| Piattaforma | Flusso raccomandato da Supabase |
|---|---|
| iOS / macOS | **Nativo**: `sign_in_with_apple` → `supabase.auth.signInWithIdToken(provider: OAuthProvider.apple, idToken:, nonce:)` |
| Android (e web/desktop) | **OAuth via browser**: `supabase.auth.signInWithOAuth(OAuthProvider.apple, redirectTo: 'schema://host', authScreenLaunchMode: LaunchMode.externalApplication)`, con ritorno all'app tramite deep link |

- Le docs Supabase dicono testualmente: *"Do **NOT** follow the Android or Web setup instructions on sign_in_with_apple package README for these platforms."* Su Android quindi `sign_in_with_apple` **non si usa**: niente callback server, niente `intent://…signinwithapple` e niente `webAuthenticationOptions`.
- **Nonce (iOS)**: `final rawNonce = supabase.auth.generateRawNonce();` produce 16 byte casuali in base64url ([`supabase_auth.dart` @ v2.17.2](https://github.com/supabase/supabase-flutter/blob/supabase_flutter-v2.17.2/packages/supabase_flutter/lib/src/supabase_auth.dart)). Ad Apple si passa `sha256(rawNonce)` in esadecimale (`SignInWithApple.getAppleIDCredential(scopes: [email, fullName], nonce: hashedNonce)`), mentre a `signInWithIdToken` si passa il **rawNonce**. Supabase ricalcola l'hash e lo confronta con il claim `nonce` dell'ID token.
- **Nome utente**: *"Apple only provides the user's full name on the first sign-in."* Va salvato subito con `supabase.auth.updateUser(UserAttributes(data: {'full_name': …, 'given_name': …, 'family_name': …}))`, perché non è nell'ID token.
- **Configurazione su Supabase**, Authentication → Providers → Apple → *Client IDs*:
  - flusso nativo iOS: va inserito il **bundle id** `com.saviogiordano.mycomicbrain.mycomicbrain`;
  - flusso OAuth (Android): serve il **Services ID** `com.saviogiordano.mycomicbrain.mycomicbrain.signin` e, usando entrambi i flussi, le docs indicano di metterlo **per primo** nella lista. Il flusso OAuth richiede anche la **secret key** (JWT firmato con la chiave `.p8`), che *"You will have to generate a new secret key … every 6 months"*. Se scade, il login Apple su Android smette di funzionare, mentre quello nativo su iOS no **(deduzione dalle docs: il nativo usa solo Client IDs)**.
  - Da verificare rispetto a #156: nella lista devono esserci **sia** il bundle id **sia** il Services ID, e il Services ID deve avere come Return URL `https://ojfwicezfctlwpouudsa.supabase.co/auth/v1/callback`.
- **iOS, Xcode**: capability **Sign in with Apple** sul target Runner (Signing & Capabilities), che genera `Runner.entitlements` con `com.apple.developer.applesignin = [Default]`. Oggi `app/ios/Runner/` non ha alcun file `.entitlements`. Fonte: [README sign_in_with_apple 7.0.1](https://pub.dev/packages/sign_in_with_apple/versions/7.0.1).

### Google

Fonte: [Supabase — Login with Google (Flutter)](https://supabase.com/docs/guides/auth/social-login/auth-google?platform=flutter).

| Piattaforma | Flusso raccomandato da Supabase |
|---|---|
| iOS e Android | **Nativo**: `google_sign_in` 7.x → `signInWithIdToken(provider: OAuthProvider.google, idToken:, accessToken:)` |

Esempio ufficiale Supabase, riassunto:

```dart
await GoogleSignIn.instance.initialize(
  serverClientId: webClientId, // client "Web application"
  clientId: iosClientId,       // client "iOS" (ignorato su Android)
);
final googleUser = await GoogleSignIn.instance.attemptLightweightAuthentication();
final authorization = await googleUser.authorizationClient.authorizeScopes(['email', 'profile']);
await supabase.auth.signInWithIdToken(
  provider: OAuthProvider.google,
  idToken: googleUser.authentication.idToken,
  accessToken: authorization.accessToken,
);
```

- Nota **(deduzione)**: `attemptLightweightAuthentication()` può restituire `null` quando non c'è una sessione Google precedente. Per un pulsante "Accedi con Google" va usato `authenticate()`, eventualmente dopo un tentativo lightweight ([README google_sign_in](https://pub.dev/packages/google_sign_in)). `accessToken` in `signInWithIdToken` è **opzionale** ([`gotrue_client.dart` @ v2.17.2](https://github.com/supabase/supabase-flutter/blob/supabase_flutter-v2.17.2/packages/gotrue/lib/src/gotrue_client.dart)), quindi il passo di autorizzazione si può omettere se servono solo i claim dell'ID token.
- **Client ID Google** (Google Cloud Console → Credentials):
  - **Web application**: va passato come `serverClientId` ed è l'audience dell'ID token che Supabase verifica. È **obbligatorio su Android** senza `google-services.json` ([README google_sign_in_android](https://pub.dev/packages/google_sign_in_android)).
  - **iOS**: bundle id `com.saviogiordano.mycomicbrain.mycomicbrain`. Va passato come `clientId` oppure messo in Info.plist come `GIDClientID`.
  - **Android**: package `com.saviogiordano.mycomicbrain.mycomicbrain` + **SHA-1** del certificato di firma. Serve un client **per ogni keystore** (debug, release, ed eventuale Play App Signing). Non va passato nel codice.
- **Su Supabase**, Authentication → Providers → Google → *Client IDs*: lista separata da virgole con il **client Web per primo**, seguito dal client iOS (e dagli Android). Il *Client Secret* è quello del client Web.
- **Nonce**:
  - La docs Supabase dice di attivare **"Skip nonce check"** per iOS, perché l'SDK Google iOS di default non include il nonce e Supabase rifiuta i token con nonce incoerente (*"Passed nonce and nonce in id_token should either both exist or not"*). Vedi anche [discussione supabase #33057](https://github.com/orgs/supabase/discussions/33057). L'opzione vale per l'intero provider, quindi anche per Android.
  - Alternativa tecnicamente possibile ma **non documentata da Supabase**: `google_sign_in` 7.x accetta `initialize(nonce:)`. `google_sign_in_android` lo inoltra a Credential Manager e `google_sign_in_ios` lo supporta dalla 6.1.0 (*"Adds support for the `nonce` parameter"*, SDK GoogleSignIn 9.0, [CHANGELOG](https://github.com/flutter/packages/blob/main/packages/google_sign_in/google_sign_in_ios/CHANGELOG.md)). Però `initialize` si chiama una volta sola, quindi il nonce sarebbe fisso per tutta la durata del processo **(deduzione)**, e va verificato sul campo.
- **iOS, Info.plist**: `CFBundleURLTypes` con lo schema **reversed client ID** (`com.googleusercontent.apps.<id>`). `GIDClientID`/`GIDServerClientID` sono opzionali se passati in `initialize` ([README google_sign_in_ios](https://pub.dev/packages/google_sign_in_ios)).
- **Android**: nessuna modifica al Manifest per Google. Basta il client Android con lo SHA-1 corretto su Google Cloud.

### Obblighi App Store collegati

- [Guideline 4.8](https://developer.apple.com/app-store/review/guidelines/#login-services): se si offre Google Sign-In per l'account primario, serve un login equivalente che limiti i dati a nome ed email e permetta di nascondere l'email. Sign in with Apple soddisfa il requisito.
- [Guideline 5.1.1(v)](https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage): se l'app permette di creare un account, deve permettere di **cancellarlo dall'app**. È già nella destinazione della mappa #165.

---

## 3. Deep link / URL scheme

Fonte: [Supabase — Native mobile deep linking (Flutter)](https://supabase.com/docs/guides/auth/native-mobile-deep-linking?platform=flutter) e [Redirect URLs](https://supabase.com/docs/guides/auth/redirect-urls).

Un deep link verso l'app serve per **Apple su Android** (ritorno da `signInWithOAuth`) e per il **link di conferma email** (e reset password) su entrambe le piattaforme. Per Apple nativo iOS e per Google nativo non serve.

- **Schema proposto**: `com.saviogiordano.mycomicbrain://login-callback`. Sulle docs è un esempio, non un vincolo: basta uno schema custom univoco.
- **Supabase** → Authentication → URL Configuration: aggiungere lo schema in *Additional Redirect URLs*, eventualmente con wildcard (`com.saviogiordano.mycomicbrain://**`). Se `redirectTo`/`emailRedirectTo` non è in lista si ricade sulla **Site URL**, che di default è `localhost:3000`.
- **iOS `Info.plist`**: `CFBundleURLTypes` → `CFBundleURLSchemes` = `com.saviogiordano.mycomicbrain`. È un'entry in più rispetto al reversed client ID di Google.
- **Android `AndroidManifest.xml`**, dentro la `<activity>` di `MainActivity`:
  ```xml
  <intent-filter>
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="com.saviogiordano.mycomicbrain" android:host="login-callback" />
  </intent-filter>
  ```
- **Come lo gestisce `supabase_flutter`**: usa `app_links` internamente (`uriLinkStream` + `getInitialLink`). Con `detectSessionInUri: true` (default) intercetta i link che contengono `code`, `access_token`, `error`, `error_code` o `error_description` e chiama `getSessionFromUrl` ([`supabase_auth.dart`](https://github.com/supabase/supabase-flutter/blob/supabase_flutter-v2.17.2/packages/supabase_flutter/lib/src/supabase_auth.dart), [`flutter_go_true_client_options.dart`](https://github.com/supabase/supabase-flutter/blob/supabase_flutter-v2.17.2/packages/supabase_flutter/lib/src/flutter_go_true_client_options.dart)). Il risultato arriva su `onAuthStateChange`, perché `signInWithOAuth` restituisce solo `bool`. Se `go_router` intercetta lo stesso link, lo può filtrare con `detectSessionInUriPredicate` (2.17.0+).

---

## 4. Persistenza della sessione e refresh

Fonte: codice di `supabase_flutter` 2.17.2 ([`supabase.dart`](https://github.com/supabase/supabase-flutter/blob/supabase_flutter-v2.17.2/packages/supabase_flutter/lib/src/supabase.dart), [`local_storage.dart`](https://github.com/supabase/supabase-flutter/blob/supabase_flutter-v2.17.2/packages/supabase_flutter/lib/src/local_storage.dart), [`supabase_client_options.dart`](https://github.com/supabase/supabase-flutter/blob/supabase_flutter-v2.17.2/packages/supabase/lib/src/supabase_client_options.dart), [`constants.dart` di gotrue](https://github.com/supabase/supabase-flutter/blob/supabase_flutter-v2.17.2/packages/gotrue/lib/src/constants.dart)) e [Supabase — User sessions](https://supabase.com/docs/guides/auth/sessions).

- **Default**: `FlutterAuthClientOptions(authFlowType: AuthFlowType.pkce, autoRefreshToken: true, persistSession: true, detectSessionInUri: true)`.
  - Se `localStorage` non è passato, la sessione (JSON con access e refresh token) va in **`SharedPreferencesLocalStorage`**, cioè in chiaro in `NSUserDefaults` / `SharedPreferences`.
  - Il code verifier PKCE va in `SharedPreferencesGotrueAsyncStorage`.
- **Secure storage**: si passa `authOptions: FlutterAuthClientOptions(localStorage: MySecureLocalStorage())`, una classe che implementa `LocalStorage` (`initialize`, `hasAccessToken`, `accessToken`, `persistSession`, `removePersistedSession`) sopra `flutter_secure_storage`. Il README di `supabase_flutter` prevede esplicitamente questo caso. Il progetto ha già un adapter (`app/lib/core/data/secure_storage.dart`, `secure_storage_flutter_adapter.dart`) riusabile.
- **Refresh**: `autoRefreshToken` controlla la sessione ogni 10 s e rinnova 3 tick (circa 30 s) prima della scadenza. `SupabaseAuth` implementa `WidgetsBindingObserver`: su `resumed` chiama `startAutoRefresh()`, su `paused`/`detached` chiama `stopAutoRefresh()`. All'avvio `recoverSession()` legge la sessione persistita e la rinnova se scaduta.
- **Lato server**: access token JWT di **1 ora** di default. Refresh token *"never expire but can only be used once"*, con un intervallo di riuso di **10 s**. Sessioni con scadenza forzata o per inattività sono solo sul piano Pro.
- **Caveat `flutter_secure_storage`** ([README](https://pub.dev/packages/flutter_secure_storage)):
  - il backup automatico Android su Google Drive può causare `InvalidKeyException` al ripristino, quindi va disattivato `allowBackup` o vanno escluse le preferenze. Oggi il Manifest non lo imposta, quindi vale il default `true`;
  - dalla v10 serve minSdk 23;
  - per il keychain iOS conviene `accessibility: first_unlock`, così il token è leggibile anche con l'app in background dopo il primo sblocco.

---

## 5. Conferma email alla registrazione (email+password)

Fonti: [Supabase — Password-based Auth](https://supabase.com/docs/guides/auth/passwords), [PKCE flow](https://supabase.com/docs/guides/auth/sessions/pkce-flow), [Custom SMTP](https://supabase.com/docs/guides/auth/auth-smtp), [Redirect URLs](https://supabase.com/docs/guides/auth/redirect-urls).

- **Default**: sui progetti **hosted** "Confirm email" è **attivo di default** (su local/self-hosted è disattivo). Con la conferma attiva, `signUp` restituisce `AuthResponse` con **`session == null`** finché l'utente non clicca il link. L'app deve mostrare lo stato "controlla la tua email", non considerare l'utente loggato.
- **`emailRedirectTo`**: `signUp(email:, password:, emailRedirectTo: 'com.saviogiordano.mycomicbrain://login-callback')`. Deve stare nelle Redirect URLs, altrimenti si usa la Site URL (default `localhost:3000`, che su mobile non funziona).
- **Con PKCE (default in supabase_flutter)**:
  1. `signUp` invia un `code_challenge` e salva il verifier sul device (confermato nel [codice di `signUp`](https://github.com/supabase/supabase-flutter/blob/supabase_flutter-v2.17.2/packages/gotrue/lib/src/gotrue_client.dart)).
  2. Il link nell'email passa da Supabase e rimanda all'app con `?code=…`.
  3. `supabase_flutter` lo intercetta e scambia il code per una sessione.
  4. Vincoli: *"The code exchange must be initiated on the same browser and device where the flow was started"*, e il code è valido **5 minuti** e utilizzabile **una volta**.
  5. Se l'utente apre l'email su un altro dispositivo, per esempio il PC, il deep link non arriva all'app. **(deduzione)** L'email risulta comunque verificata lato server, ma non nasce una sessione: l'app deve prevedere "email confermata? accedi con la password".
- **Alternativa senza deep link**: modificare il template "Confirm signup" per mostrare il codice `{{ .Token }}` e verificarlo in app con `verifyOTP(type: OtpType.signup, email:, token:)`. Funziona da qualunque dispositivo. In alternativa si può disattivare "Confirm email", al costo di accettare email non verificate.
- **SMTP**: il servizio email integrato invia *"2 messages per hour"*, solo a indirizzi *pre-authorized* (membri del team), senza SLA ed è *"best-effort only"*. **Prima di utenti reali serve un SMTP custom**, altrimenti conferme e reset password non arrivano.

---

## 6. Raccomandazione per metodo di login

| Metodo | iOS | Android | Configurazione da fare |
|---|---|---|---|
| **Apple** | Nativo: `sign_in_with_apple ^7.0.1` + `signInWithIdToken` con nonce (raw a Supabase, SHA-256 ad Apple). Salvare il nome al primo accesso con `updateUser`. | `signInWithOAuth(OAuthProvider.apple, redirectTo: 'com.saviogiordano.mycomicbrain://login-callback', authScreenLaunchMode: LaunchMode.externalApplication)`. Non usare `sign_in_with_apple` su Android. | Capability "Sign in with Apple" in Xcode (`Runner.entitlements`). Su Supabase: Client IDs = Services ID (per primo) + bundle id, Return URL del Services ID = callback Supabase. Promemoria di rotazione della secret key ogni 6 mesi. Intent-filter Android e redirect URL in allowlist. |
| **Google** | Nativo: `google_sign_in 7.2.0`, `initialize(clientId: iOS, serverClientId: Web)` → `authenticate()` → `signInWithIdToken(idToken:)`. | Nativo: stesso codice (`clientId` ignorato; `serverClientId` = Web obbligatorio). | Google Cloud: client Web, iOS e Android (SHA-1 di debug e release, più Play App Signing se usato). Supabase: Client IDs "web,ios,android…" con web per primo, secret del client Web, **"Skip nonce check" attivo** come da docs. iOS: reversed client ID in `CFBundleURLTypes`. |
| **Email+password** | `signUp(emailRedirectTo: schema app)` → UI "controlla l'email" (sessione null); `signInWithPassword`. | Idem. | Tenere "Confirm email" attivo, deep link iOS/Android per lo schema dell'app, Redirect URLs, **SMTP custom** prima del rilascio. Valutare il codice OTP (`{{ .Token }}` + `verifyOTP`) se la conferma da altro dispositivo è un caso frequente. |
| **Trasversale** | `supabase_flutter 2.17.2` (non 3.0.0-dev), `publishableKey`, flusso PKCE di default, `LocalStorage` custom su `flutter_secure_storage` al posto di SharedPreferences. | Idem. Rivedere `allowBackup` nel Manifest. | Fissare le versioni (`sign_in_with_apple 7.0.1`) o allineare la toolchain: la macchina locale oggi ha Flutter 3.47.1. |

### Punti da verificare sul campo (non risolvibili con le sole docs)

1. Configurazione #156: il bundle id è già nei Client IDs Apple accanto al Services ID? La Return URL è la callback Supabase?
2. Il comportamento reale del link di conferma aperto su un altro dispositivo (la sessione non nasce, l'email risulta confermata?).
3. Se si vuole evitare "Skip nonce check": test di `initialize(nonce:)` su iOS e Android con `google_sign_in_ios` ≥6.1.0.
