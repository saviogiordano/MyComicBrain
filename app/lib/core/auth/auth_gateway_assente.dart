import 'package:mycomicbrain/core/auth/auth_gateway.dart';

/// [AuthGateway] della build senza cloud ([Funzionalita.cloud] spento):
/// nessuno è mai autenticato e nessuna schermata offre l'accesso, quindi
/// i metodi di accesso non vengono mai chiamati.
class AuthGatewayAssente implements AuthGateway {
  const AuthGatewayAssente();

  @override
  Profilo? get profiloCorrente => null;

  @override
  Stream<Profilo?> get cambiamenti => const Stream.empty();

  @override
  Stream<AuthErrore> get erroriLink => const Stream.empty();

  static Never _nonDisponibile() =>
      throw UnsupportedError('Account non disponibile in questa build');

  @override
  Future<void> accediConApple() async => _nonDisponibile();

  @override
  Future<void> accediConGoogle() async => _nonDisponibile();

  @override
  Future<void> accediConEmail(String email, String password) async =>
      _nonDisponibile();

  @override
  Future<bool> registratiConEmail(String email, String password) async =>
      _nonDisponibile();

  @override
  Future<void> reinviaConferma(String email) async => _nonDisponibile();

  @override
  Future<void> esci() async => _nonDisponibile();

  @override
  Future<void> eliminaAccount() async => _nonDisponibile();
}
