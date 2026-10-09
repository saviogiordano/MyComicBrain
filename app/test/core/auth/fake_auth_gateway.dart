import 'dart:async';

import 'package:mycomicbrain/core/auth/auth_gateway.dart';
import 'package:mycomicbrain/core/data/preferences.dart';

/// [AuthGateway] in memoria: simula Supabase Auth (account registrati,
/// conferma email, sessione persistita) senza rete né plugin nativi.
class FakeAuthGateway implements AuthGateway {
  FakeAuthGateway({Profilo? sessioneSalvata}) : _profilo = sessioneSalvata;

  Profilo? _profilo;
  final _cambiamenti = StreamController<Profilo?>.broadcast(sync: true);

  /// email → (password, confermato)
  final account = <String, ({String password, bool confermato})>{};

  /// Se impostato, il prossimo login lancia questa eccezione.
  AuthException? prossimoErrore;

  int confermeInviate = 0;

  /// Supabase raggiungibile? Simula il device offline.
  bool online = true;

  void _emetti(Profilo? profilo) {
    _profilo = profilo;
    _cambiamenti.add(profilo);
  }

  void _lanciaSeImpostato() {
    final errore = prossimoErrore;
    prossimoErrore = null;
    if (errore != null) throw errore;
  }

  final _erroriLink = StreamController<AuthErrore>.broadcast(sync: true);

  /// L'utente tocca un link di conferma scaduto o già usato.
  void linkNonValido() => _erroriLink.add(AuthErrore.linkNonValido);

  @override
  Stream<AuthErrore> get erroriLink => _erroriLink.stream;

  /// L'utente tocca il link di conferma nella mail (deep link PKCE).
  void confermaEmailDaLink(String email) {
    account[email] = (password: account[email]!.password, confermato: true);
    _emetti(Profilo(email: email, metodo: MetodoAccesso.email));
  }

  @override
  Profilo? get profiloCorrente => _profilo;

  @override
  Stream<Profilo?> get cambiamenti => _cambiamenti.stream;

  @override
  Future<void> accediConApple() async {
    _lanciaSeImpostato();
    _emetti(
      const Profilo(
        email: 'x7k2m9@privaterelay.appleid.com',
        metodo: MetodoAccesso.apple,
      ),
    );
  }

  @override
  Future<void> accediConGoogle() async {
    _lanciaSeImpostato();
    _emetti(
      const Profilo(
        email: 'mario.rossi@gmail.com',
        metodo: MetodoAccesso.google,
      ),
    );
  }

  @override
  Future<void> accediConEmail(String email, String password) async {
    _lanciaSeImpostato();
    final a = account[email];
    if (a == null || a.password != password) {
      throw const AuthException(AuthErrore.credenzialiErrate);
    }
    if (!a.confermato) {
      throw const AuthException(AuthErrore.emailNonConfermata);
    }
    _emetti(Profilo(email: email, metodo: MetodoAccesso.email));
  }

  @override
  Future<bool> registratiConEmail(String email, String password) async {
    _lanciaSeImpostato();
    if (account[email]?.confermato ?? false) {
      throw const AuthException(AuthErrore.emailGiaRegistrata);
    }
    account[email] = (password: password, confermato: false);
    confermeInviate++;
    return true;
  }

  @override
  Future<void> reinviaConferma(String email) async => confermeInviate++;

  @override
  Future<void> esci() async => _emetti(null);

  @override
  Future<bool> raggiungibile() async => online;
}

/// [Preferences] in memoria.
class PreferencesInMemoria implements Preferences {
  final valori = <String, String>{};

  @override
  String? getString(String key) => valori[key];

  @override
  Future<void> setString(String key, String value) async => valori[key] = value;
}
