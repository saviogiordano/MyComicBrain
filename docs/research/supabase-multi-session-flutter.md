# Ricerca — `supabase_flutter` e sessioni multiple concorrenti nello stesso processo app

> Risposta al ticket Wayfinder [#150](https://github.com/saviogiordano/MyComicBrain/issues/150), propedeutica al ticket figlio [#151](https://github.com/saviogiordano/MyComicBrain/issues/151) ("Decisione — mapping profili locali (§17.1) su modello di sessione/account Supabase Auth"). Contesto più ampio nel ticket [#148](https://github.com/saviogiordano/MyComicBrain/issues/148) e nella ricerca comparativa BaaS a `docs/research/baas-auth-backend.md` (branch `research/baas-auth-backend`).
>
> Questo documento è **solo ricerca**: raccoglie fatti da fonti primarie per il ticket #151, che prenderà la decisione vera e propria in una sessione successiva. Non modifica codice applicativo né gli issue #149/#151.

Contesto: requisito §17.1 (`docs/requisiti.md`) richiede profili multipli indipendenti sullo stesso dispositivo, con switch rapido, dati/impostazioni completamente separati, e senza che il logout di un profilo cancelli i dati locali degli altri. La domanda fattuale da chiarire prima della decisione #151: **`supabase_flutter` (e il modello sottostante di GoTrue/Supabase Auth) supporta più sessioni autenticate concorrenti nello stesso processo app**, o è un singleton con una sola sessione attiva alla volta?

## Il wrapper `Supabase` di `supabase_flutter` è un singleton enforced

La classe `Supabase` (non `SupabaseClient`) usata da `Supabase.initialize()` / `Supabase.instance.client` è esplicitamente un singleton nel codice sorgente:

```dart
class Supabase {
  Supabase._();
  static Supabase get instance { ... }
  static Future<Supabase> initialize({ ... }) async {
    if (_instance._isInitialized) {
      flutterLogger.info('Supabase is already initialized. Skipping reinitialization.');
      return _instance;
    }
    ...
  }
}
```
Fonte: [`packages/supabase_flutter/lib/src/supabase.dart`](https://github.com/supabase/supabase-flutter/blob/main/packages/supabase_flutter/lib/src/supabase.dart) (repo monorepo `supabase/supabase-flutter`, branch `main`).

Chiamare `Supabase.initialize()` una seconda volta **non crea una seconda istanza**: viene loggato un messaggio informativo e restituita l'istanza già esistente. Questo comportamento (idempotenza) è stato introdotto deliberatamente con la feature [#1194](https://github.com/supabase/supabase-flutter/issues/1194) ("Make `Supabase.initialize()` idempotent", PR mergiata, chiude l'issue [#1163](https://github.com/supabase/supabase-flutter/issues/1163)): prima di questa modifica, una seconda chiamata lanciava un `AssertionError` (`assert(!_instance._initialized)`), come riscontrato da un utente in produzione nella discussione citata più sotto. Il pacchetto è oggi in versione `3.0.0-dev.2` (da `packages/supabase_flutter/pubspec.yaml` sul branch `main`).

**Conclusione parziale**: l'entry point "comodo" (`Supabase.initialize()`/`Supabase.instance.client`) che gestisce anche deep link OAuth/magic link e ciclo di vita Flutter è **volutamente vincolato a una sola istanza per processo**, e i maintainer non intendono cambiarlo — vedi sotto l'issue #345 chiusa "not planned".

## `SupabaseClient` (il livello sotto il wrapper) non è un singleton

`SupabaseClient`, la classe di basso livello da cui `Supabase.instance.client` è costruito (pacchetto `supabase`, dipendenza di `supabase_flutter`), ha un **costruttore pubblico senza alcuna restrizione singleton**:

```dart
class SupabaseClient {
  SupabaseClient(
    String supabaseUrl,
    String supabaseKey, {
    PostgrestClientOptions postgrestOptions = const PostgrestClientOptions(),
    AuthClientOptions authOptions = const AuthClientOptions(),
    ...
  }) : ...
}
```
Fonte: [`packages/supabase/lib/src/supabase_client.dart`](https://github.com/supabase/supabase-flutter/blob/main/packages/supabase/lib/src/supabase_client.dart).

Si possono quindi istanziare **più `SupabaseClient` indipendenti** nello stesso processo, bypassando `Supabase.initialize()`. Il costo è perdere l'integrazione automatica di `supabase_flutter` (gestione deep link per OAuth/magic link, hook al ciclo di vita Flutter, `Supabase.instance.client` come accesso globale comodo): vanno gestiti manualmente per ogni istanza.

## Una sessione per `AuthClient`, non per account

Ogni `SupabaseClient` possiede internamente un solo `AuthClient` (la classe che implementa il client di Supabase Auth — erede diretta di quello che nel pacchetto storico `gotrue-dart`, ora confluito nel monorepo come `packages/supabase_auth`, si chiamava `GoTrueClient`). L'`AuthClient` tiene **una sola sessione corrente** e **un solo timer di auto-refresh** per istanza:

```dart
class AuthClient {
  ...
  Session? get _currentSession => _sessionState.session;
  set _currentSession(Session? value) => _sessionState.session = value;
  ...
  Timer? _autoRefreshTicker;
  ...
  _autoRefreshTicker = Timer.periodic(
    AuthConstants.autoRefreshTickDuration,
    (Timer t) => _autoRefreshTokenTick(),
  );
}
```
Fonte: [`packages/supabase_auth/lib/src/auth_client.dart`](https://github.com/supabase/supabase-flutter/blob/main/packages/supabase_auth/lib/src/auth_client.dart).

Ne consegue che:
- **un singolo `SupabaseClient`/`AuthClient` non può tenere due sessioni "vive" contemporaneamente**: `recoverSession()`/`setSession()`/login sovrascrivono `_currentSession` dell'istanza;
- per avere N sessioni realmente concorrenti (ciascuna con il proprio auto-refresh attivo in background) servono **N istanze indipendenti di `SupabaseClient`**, ciascuna con la propria configurazione di storage — non un singolo client che "ricorda" più sessioni.

## Persistenza della sessione lato client

Lo storage di default per `supabase_flutter` è `SharedPreferencesLocalStorage`, basato su `SharedPreferencesAsync`, con la sessione salvata sotto un'unica chiave stringa (`persistSessionKey`, di default derivata dall'URL del progetto via `defaultPersistSessionKey(url)`); su web la persistenza passa per un percorso dedicato (`local_storage_web.dart`, storage del browser). Fonte: [`packages/supabase_flutter/lib/src/local_storage.dart`](https://github.com/supabase/supabase-flutter/blob/main/packages/supabase_flutter/lib/src/local_storage.dart).

`LocalStorage` è una interfaccia astratta sostituibile (`abstract class LocalStorage { initialize(); hasAccessToken(); accessToken(); removePersistedSession(); persistSession(String); }`), passabile a `Supabase.initialize(authOptions: FlutterAuthClientOptions(localStorage: ...))`. Questo è esattamente il meccanismo che un membro del team Supabase (DevRel, `dshukertjr`) ha indicato come via ufficiale per gestire più utenti in [Discussion #13983](https://github.com/orgs/supabase/discussions/13983):

> "supabase_flutter allows you to define your own custom storage to store and retrieve session data, so you could probably create your own that takes care of switching between users."
> — [dshukertjr, supabase org discussion #13983](https://github.com/orgs/supabase/discussions/13983)

Nella stessa discussione, un altro utente (`GaryAustin1`) propone in alternativa client separati per utente:

> "You can also have separate clients per user (set unique storage key name in createClient. Then the session data is stored separately for you."
> — [GaryAustin1, supabase org discussion #13983](https://github.com/orgs/supabase/discussions/13983)

Ma quando l'autore del thread ha provato a farlo chiamando `Supabase.initialize()` una seconda volta con uno storage diverso, ha ottenuto (nella versione del pacchetto disponibile all'epoca):

```
Unhandled Exception: 'package:supabase_flutter/src/supabase.dart': Failed assertion: line 76 pos 7: '!_instance._initialized': This instance is already initialized
```
— [Gerald-Gmainer, supabase org discussion #13983](https://github.com/orgs/supabase/discussions/13983)

confermando che il pattern "client multipli" richiede di **non passare da `Supabase.initialize()`** ma istanziare `SupabaseClient` direttamente (vedi sezione precedente); non risultano, nella doc ufficiale o nel repo, opzioni per passare una storage key a `Supabase.initialize()` stesso.

## Refresh token: comportamento per sessioni non "attive"

Per capire cosa succede a una sessione parcheggiata (non nell'`AuthClient` correntemente in uso), la guida ufficiale spiega il modello dei refresh token:

- l'access token è un JWT a vita breve (tipicamente 5 minuti–1 ora); il refresh token è una stringa che non scade di per sé ma è **utilizzabile una sola volta** — ogni refresh scambia il token per una nuova coppia access+refresh e invalida quello precedente;
- sono previste due eccezioni al blocco "single-use": riuso entro una finestra di 10 secondi (per scenari tipo SSR dove client e server processano lo stesso token) e "replay del token genitore" per problemi di rete;
- fuori da queste eccezioni, un riuso di refresh token già consumato fa terminare **l'intera sessione**, con tutti i refresh token di quella sessione marcati come revocati (protezione anti-furto token).

Fonte: [Supabase Docs — Managing user sessions](https://supabase.com/docs/guides/auth/sessions).

Questo spiega il comportamento incontrato nella già citata Discussion #13983: l'autore salvava una singola istantanea di sessione (`persistSessionString`) e la riusava più volte per fare login rapido; dopo il primo `recoverSession()` andato a buon fine il refresh token contenuto in quella istantanea era già stato consumato/ruotato, quindi i tentativi successivi con la stessa stringa fallivano con `Invalid Refresh Token: Refresh Token Not Found`. Nel codice sorgente attuale, `AuthClient.recoverSession()` gestisce esplicitamente il caso "sessione scaduta ma già rinnovata altrove" (`Session was already refreshed elsewhere, skipping recovery`), ma resta vero che una sessione "congelata" in uno storage esterno e non aggiornata ad ogni rotazione del token diventa **stale** e può fallire il recovery. Fonte: [`packages/supabase_auth/lib/src/auth_client.dart`](https://github.com/supabase/supabase-flutter/blob/main/packages/supabase_auth/lib/src/auth_client.dart) (metodo `recoverSession`).

Al contrario, se si usano **istanze `SupabaseClient` separate e mantenute vive** (ciascuna con il proprio `AuthClient` e la propria storage key, come descritto sopra), ciascuna istanza continua a fare l'auto-refresh della propria sessione indipendentemente — non c'è un concetto di sessione "secondaria" che smette di essere rinnovata, perché ogni istanza ha il proprio ciclo di refresh autonomo.

## Il server GoTrue non limita le sessioni concorrenti per default

Lato server, GoTrue (il servizio Auth di Supabase) non impedisce di per sé sessioni multiple: per default un utente può avere "un numero illimitato di sessioni attive su altrettanti dispositivi." Esiste una feature opt-in a pagamento (piano Pro e superiori) chiamata **"Single session per user"**, che se abilitata mantiene attiva solo la sessione dell'accesso più recente terminando le altre — applicazione non immediata ma al successivo refresh/scadenza del JWT. Fonte: [Supabase Docs — Managing user sessions, sezione "Limiting session lifetime and number of allowed sessions"](https://supabase.com/docs/guides/auth/sessions#limiting-session-lifetime-and-number-of-allowed-sessions).

Questo vincolo (se attivato) è **per singolo account utente attraverso più dispositivi**, non per processo app: non impedisce che due account Supabase diversi abbiano ciascuno una propria sessione valida sullo stesso dispositivo/processo — è comunque disattivato di default, e rilevante solo come nota a margine se in futuro si volesse limitare le sessioni multi-dispositivo di un singolo account condiviso.

## Nessun supporto/roadmap ufficiale per istanze multiple del wrapper

Una richiesta esplicita di supporto nativo a istanze parallele di `Supabase` (il wrapper `supabase_flutter`, per isolare sessioni utente nei test di integrazione) è stata aperta e **chiusa come "not planned"**:

> Issue [#345](https://github.com/supabase/supabase-flutter/issues/345), "Support multiple, separate, instances of `Supabase` in a single application" (aperta 2023-02-04, `state: CLOSED`, `stateReason: NOT_PLANNED`).

Un collaboratore del repo (`Vinzent03`) ha risposto oltre un anno dopo mettendo in dubbio anche l'utilità della richiesta per il caso d'uso originale (test paralleli), senza però negare esplicitamente la fattibilità tecnica di più istanze — la issue resta comunque chiusa senza intervento di prodotto. Fonte: [commenti issue #345](https://github.com/supabase/supabase-flutter/issues/345).

Non risultano guide ufficiali Supabase (per Flutter o altri SDK client — JS incluso) dedicate esplicitamente a "multi-account switching" nello stesso processo; i pattern trovati sono tutti di provenienza community/DevRel nelle discussioni citate sopra, non guide ufficiali pubblicate su supabase.com/docs.

### Fonti primarie consultate

- Codice sorgente (repo monorepo `supabase/supabase-flutter`, branch `main`):
  - [`packages/supabase_flutter/lib/src/supabase.dart`](https://github.com/supabase/supabase-flutter/blob/main/packages/supabase_flutter/lib/src/supabase.dart) — singleton `Supabase`, `initialize()` idempotente
  - [`packages/supabase_flutter/lib/src/local_storage.dart`](https://github.com/supabase/supabase-flutter/blob/main/packages/supabase_flutter/lib/src/local_storage.dart) — interfaccia `LocalStorage`, `SharedPreferencesLocalStorage`
  - [`packages/supabase/lib/src/supabase_client.dart`](https://github.com/supabase/supabase-flutter/blob/main/packages/supabase/lib/src/supabase_client.dart) — costruttore pubblico non-singleton di `SupabaseClient`
  - [`packages/supabase_auth/lib/src/auth_client.dart`](https://github.com/supabase/supabase-flutter/blob/main/packages/supabase_auth/lib/src/auth_client.dart) — `AuthClient` (ex `GoTrueClient`), una sessione + un timer di refresh per istanza, `recoverSession()`
  - [`packages/supabase_flutter/pubspec.yaml`](https://github.com/supabase/supabase-flutter/blob/main/packages/supabase_flutter/pubspec.yaml) — versione corrente `3.0.0-dev.2`
  - [`packages/supabase_flutter/CHANGELOG.md`](https://github.com/supabase/supabase-flutter/blob/main/packages/supabase_flutter/CHANGELOG.md) — voce "Make `Supabase.initialize()` idempotent"
- Issue/discussion GitHub (org/repo `supabase`):
  - [Issue #345 — Support multiple, separate, instances of `Supabase`](https://github.com/supabase/supabase-flutter/issues/345) (chiusa, not planned)
  - [Issue #1194 — Make `Supabase.initialize()` idempotent](https://github.com/supabase/supabase-flutter/issues/1194) / chiude [#1163](https://github.com/supabase/supabase-flutter/issues/1163)
  - [Discussion #13983 — \[flutter\] multiple user login and store session](https://github.com/orgs/supabase/discussions/13983)
- Documentazione ufficiale:
  - [Supabase Docs — Managing user sessions](https://supabase.com/docs/guides/auth/sessions) (persistenza, rotazione refresh token, reuse detection, "Single session per user")
  - [Supabase Docs — Flutter: Initializing](https://supabase.com/docs/reference/dart/initializing)

## Conclusione

**Non esiste, nell'SDK ufficiale `supabase_flutter` (né nel modello sottostante GoTrue/Supabase Auth), un concetto nativo di "più account Supabase loggati contemporaneamente" gestito da un singolo client/sessione.** Il wrapper comodo `Supabase.instance.client` è un singleton per processo, con una sola sessione attiva e un login/logout la sovrascrive; una richiesta esplicita di istanze multiple del wrapper è stata chiusa dai maintainer come "not planned".

Ciò che è tecnicamente disponibile, verificato nel codice sorgente e nei thread ufficiali, sono due pattern alternativi, nessuno dei quali è "sessioni multiple native":

1. **Un solo `SupabaseClient`/`AuthClient`, con storage sostituibile**: si tiene un solo client, e si implementa uno storage custom che sa "ricordare" più sessioni serializzate (una per profilo) e le scambia (`recoverSession()`/`setSession()`) allo switch. In questo modello **una sola sessione alla volta è "viva"** (auto-refresh attivo); le altre sono congelate come dati salvati e vanno ri-agganciate al cambio profilo, con il rischio — osservato in pratica nella Discussion #13983 — che un refresh token salvato e non aggiornato nel frattempo diventi stale per via della rotazione single-use dei token.
2. **Più istanze indipendenti di `SupabaseClient`** (bypassando `Supabase.initialize()`), ciascuna con la propria storage key: qui sì si ottengono sessioni realmente concorrenti, ognuna con il proprio timer di auto-refresh attivo in background — ma è un pattern non wrappato da `supabase_flutter` (si perde la gestione automatica di deep link OAuth/magic link e altre integrazioni Flutter del wrapper), non documentato ufficialmente per Flutter, e comporta gestire a mano N client vivi in memoria.

Non è emerso, in nessuna fonte primaria, un modo per avere `Supabase.instance.client` stesso a rappresentare più sessioni contemporaneamente con switch istantaneo senza round-trip di rete: qualunque implementazione di §17.1 dovrà scegliere tra questi due pattern (o modellare i "profili" come costrutto applicativo sopra un unico account Supabase condiviso) — la scelta del pattern specifico è compito del ticket #151, non di questo documento.
