/// Seam sull'autenticazione (Supabase Auth + SDK nativi Apple/Google, deciso
/// su #166/#168): isola `SessionController` dai plugin concreti così i test
/// possono usare un fake in memoria. L'implementazione reale è
/// `SupabaseAuthGateway` (`supabase_auth_gateway.dart`).
///
/// Ogni cambio di sessione — login riuscito, conferma email via deep link,
/// logout, sessione scaduta — arriva **solo** da [cambiamenti]: i metodi di
/// accesso non restituiscono il Profilo, così c'è un unico percorso per
/// aggiornare lo stato.
abstract interface class AuthGateway {
  /// La sessione ripristinata all'avvio (già letta dallo storage sicuro),
  /// `null` se nessuno è autenticato.
  Profilo? get profiloCorrente;

  Stream<Profilo?> get cambiamenti;

  Future<void> accediConApple();
  Future<void> accediConGoogle();
  Future<void> accediConEmail(String email, String password);

  /// Restituisce `true` se Supabase richiede la conferma dell'email (nessuna
  /// sessione finché l'utente non tocca il link), `false` se la sessione
  /// arriva subito su [cambiamenti].
  Future<bool> registratiConEmail(String email, String password);

  Future<void> reinviaConferma(String email);
  Future<void> esci();

  /// Supabase è raggiungibile? Un Profilo autenticato lavora online-only
  /// (ADR-0005): senza rete l'app mostra il blocco offline (#170).
  Future<bool> raggiungibile();
}

enum MetodoAccesso { apple, google, email }

/// Il Profilo autenticato (§17.1, glossario in `CONTEXT.md`) — solo ciò che
/// serve alla UI di account.
class Profilo {
  const Profilo({required this.email, required this.metodo});

  final String email;
  final MetodoAccesso metodo;
}

enum AuthErrore {
  /// L'utente ha chiuso il foglio di Apple/Google: non è un errore da mostrare.
  annullato,
  credenzialiErrate,
  emailNonConfermata,
  emailGiaRegistrata,
  passwordDebole,
  rete,
  sconosciuto,
}

class AuthException implements Exception {
  const AuthException(this.errore, [this.dettaglio]);

  final AuthErrore errore;
  final String? dettaglio;

  @override
  String toString() =>
      'AuthException($errore${dettaglio == null ? '' : ': $dettaglio'})';
}
