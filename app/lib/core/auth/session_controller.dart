import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mycomicbrain/core/auth/auth_config.dart';
import 'package:mycomicbrain/core/auth/auth_gateway.dart';
import 'package:mycomicbrain/core/data/preferences.dart';

/// Dove atterra l'app.
enum Ingresso {
  /// Primo avvio: benvenuto con "Crea un account", "Accedi", "Usa senza
  /// account" (variante C del prototipo #170).
  benvenuto,

  /// Modalità locale esaurita e nessuna sessione: benvenuto con le sole
  /// opzioni di accesso (#170, ADR-0005).
  soloAccesso,

  /// Dentro l'app — in Modalità locale o con un Profilo autenticato.
  app,

  /// Profilo autenticato senza rete: blocco a schermo intero con "Riprova"
  /// (variante A del prototipo #170) — online-only, nessuna cache.
  offline,
}

class SessionState {
  const SessionState({
    required this.profilo,
    required this.benvenutoSuperato,
    required this.modalitaLocaleEsaurita,
    required this.emailInAttesa,
    this.offline = false,
  });

  /// `null` = Modalità locale.
  final Profilo? profilo;
  final bool benvenutoSuperato;
  final bool modalitaLocaleEsaurita;

  /// Registrazione via email in attesa del link di conferma.
  final String? emailInAttesa;

  /// Supabase non raggiungibile all'ultima verifica. Conta solo con un
  /// Profilo autenticato: la Modalità locale funziona senza rete.
  final bool offline;

  /// Profilo autenticato su un device con dati in Modalità locale non
  /// ancora importati né rifiutati (ADR-0005): il prompt di importazione
  /// arriva con #173.
  bool get importazioneInSospeso => profilo != null && !modalitaLocaleEsaurita;

  Ingresso get ingresso {
    if (profilo != null) return offline ? Ingresso.offline : Ingresso.app;
    if (modalitaLocaleEsaurita) return Ingresso.soloAccesso;
    if (benvenutoSuperato) return Ingresso.app;
    return Ingresso.benvenuto;
  }
}

final authGatewayProvider = Provider<AuthGateway>(
  (ref) => throw UnimplementedError('authGatewayProvider non sostituito'),
);

final accountPreferencesProvider = Provider<Preferences>(
  (ref) =>
      throw UnimplementedError('accountPreferencesProvider non sostituito'),
);

/// "Ci sono dati in Modalità locale su questo device?" — decide se la
/// Modalità locale si esaurisce subito al login (drift vuoto) o resta in
/// sospeso per l'importazione (ADR-0005).
final haDatiLocaliProvider = Provider<Future<bool> Function()>(
  (ref) => throw UnimplementedError('haDatiLocaliProvider non sostituito'),
);

// Chiavi persistite su device (non nella sessione: logout ed eliminazione
// dell'account non le azzerano, ADR-0005).
const _chiaveBenvenutoSuperato = 'account.benvenutoSuperato';
const _chiaveModalitaLocaleEsaurita = 'account.modalitaLocaleEsaurita';
const _chiaveEmailInAttesa = 'account.emailInAttesa';

class SessionController extends Notifier<SessionState> {
  Preferences get _preferences => ref.read(accountPreferencesProvider);
  AuthGateway get _gateway => ref.read(authGatewayProvider);

  @override
  SessionState build() {
    final gateway = ref.watch(authGatewayProvider);
    final preferences = ref.watch(accountPreferencesProvider);
    final sottoscrizione = gateway.cambiamenti.listen(_suProfilo);
    ref.onDispose(sottoscrizione.cancel);
    if (gateway.profiloCorrente != null) {
      // Dopo il primo `state`: `build` deve restituire prima di poterlo
      // aggiornare.
      Future.microtask(riprovaConnessione);
    }
    return SessionState(
      profilo: gateway.profiloCorrente,
      benvenutoSuperato:
          preferences.getString(_chiaveBenvenutoSuperato) == 'true',
      modalitaLocaleEsaurita:
          preferences.getString(_chiaveModalitaLocaleEsaurita) == 'true',
      emailInAttesa: _nonVuota(preferences.getString(_chiaveEmailInAttesa)),
    );
  }

  static String? _nonVuota(String? valore) =>
      valore == null || valore.isEmpty ? null : valore;

  Future<void> accediConApple() => _gateway.accediConApple();

  Future<void> accediConGoogle() => _gateway.accediConGoogle();

  Future<void> accediConEmail(String email, String password) =>
      _gateway.accediConEmail(email, password);

  /// Con la conferma email attiva (default di Supabase hosted) non nasce
  /// una sessione: l'utente continua in Modalità locale con un avviso
  /// finché non tocca il link (variante B del prototipo #170).
  Future<void> registratiConEmail(String email, String password) async {
    final confermaRichiesta = await _gateway.registratiConEmail(
      email,
      password,
    );
    if (!confermaRichiesta) return;
    await _preferences.setString(_chiaveBenvenutoSuperato, 'true');
    await _impostaEmailInAttesa(email);
    state = _copia(benvenutoSuperato: true);
  }

  Future<void> reinviaConferma() async {
    final email = state.emailInAttesa;
    if (email != null) await _gateway.reinviaConferma(email);
  }

  Future<void> annullaEmailInAttesa() => _impostaEmailInAttesa(null);

  Future<void> esci() => _gateway.esci();

  /// Verifica la rete per il Profilo autenticato: all'avvio, a ogni login
  /// e dal pulsante "Riprova" del blocco offline.
  Future<void> riprovaConnessione() async {
    if (state.profilo == null) return;
    final offline = !await _gateway.raggiungibile();
    if (state.profilo != null) state = _copia(offline: offline);
  }

  Future<void> _impostaEmailInAttesa(String? email) async {
    await _preferences.setString(_chiaveEmailInAttesa, email ?? '');
    state = _copia(emailInAttesa: () => email);
  }

  /// Unico punto in cui cambia il Profilo (vedi [AuthGateway]).
  Future<void> _suProfilo(Profilo? profilo) async {
    state = _copia(profilo: () => profilo, offline: false);
    if (profilo == null) return;
    await riprovaConnessione();
    if (state.emailInAttesa != null) await _impostaEmailInAttesa(null);
    if (!state.benvenutoSuperato) {
      await _preferences.setString(_chiaveBenvenutoSuperato, 'true');
      state = _copia(benvenutoSuperato: true);
    }
    if (!state.modalitaLocaleEsaurita &&
        !await ref.read(haDatiLocaliProvider)()) {
      await _preferences.setString(_chiaveModalitaLocaleEsaurita, 'true');
      state = _copia(modalitaLocaleEsaurita: true);
    }
  }

  Future<void> continuaSenzaAccount() async {
    await _preferences.setString(_chiaveBenvenutoSuperato, 'true');
    state = _copia(benvenutoSuperato: true);
  }

  SessionState _copia({
    Profilo? Function()? profilo,
    bool? benvenutoSuperato,
    bool? modalitaLocaleEsaurita,
    String? Function()? emailInAttesa,
    bool? offline,
  }) => SessionState(
    profilo: profilo != null ? profilo() : state.profilo,
    benvenutoSuperato: benvenutoSuperato ?? state.benvenutoSuperato,
    modalitaLocaleEsaurita:
        modalitaLocaleEsaurita ?? state.modalitaLocaleEsaurita,
    emailInAttesa: emailInAttesa != null
        ? emailInAttesa()
        : state.emailInAttesa,
    offline: offline ?? state.offline,
  );
}

final sessionControllerProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);

/// Lo stato dell'account per le schermate dell'app (pillola e banner della
/// Dashboard): `null` finché il login reale è dietro flag e spento, così
/// l'app senza flag resta identica a prima.
final statoAccountProvider = Provider<SessionState?>(
  (ref) =>
      AuthConfig.loginAbilitato ? ref.watch(sessionControllerProvider) : null,
);
