import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:mycomicbrain/core/auth/auth_config.dart';
import 'package:mycomicbrain/core/auth/auth_gateway.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// [AuthGateway] su Supabase Auth, secondo la ricerca #168:
/// - Apple: nativo su iOS (`signInWithIdToken` con nonce), OAuth via browser
///   su Android con ritorno via deep link;
/// - Google: nativo su entrambe (`google_sign_in` 7.x → `signInWithIdToken`);
/// - email+password: conferma via deep link PKCE.
///
/// Non coperto da test automatici: verificato su device (#171).
class SupabaseAuthGateway implements AuthGateway {
  SupabaseAuthGateway(this._client);

  final sb.SupabaseClient _client;
  bool _googleInizializzato = false;

  sb.GoTrueClient get _auth => _client.auth;

  @override
  Profilo? get profiloCorrente => _profilo(_auth.currentUser);

  // Gli errori dei deep link arrivano su `onAuthStateChange`
  // (`GoTrueClient.notifyException`): qui li si scarta, li espone
  // [erroriLink].
  @override
  Stream<Profilo?> get cambiamenti => _auth.onAuthStateChange
      .handleError((Object _) {})
      .map((evento) => _profilo(evento.session?.user))
      .distinct((a, b) => a?.email == b?.email && a?.metodo == b?.metodo);

  @override
  Stream<AuthErrore> get erroriLink => _auth.onAuthStateChange.transform(
    StreamTransformer<sb.AuthState, AuthErrore>.fromHandlers(
      handleData: (_, _) {},
      handleError: (errore, _, sink) => sink.add(
        errore is sb.AuthException && errore.statusCode == 'otp_expired'
            ? AuthErrore.linkNonValido
            : AuthErrore.sconosciuto,
      ),
    ),
  );

  static Profilo? _profilo(sb.User? utente) {
    if (utente == null) return null;
    final provider = utente.appMetadata['provider'] as String?;
    return Profilo(
      email: utente.email ?? '',
      metodo: switch (provider) {
        'apple' => MetodoAccesso.apple,
        'google' => MetodoAccesso.google,
        _ => MetodoAccesso.email,
      },
    );
  }

  @override
  Future<void> accediConApple() => _traduci(() async {
    if (!Platform.isIOS) {
      await _auth.signInWithOAuth(
        sb.OAuthProvider.apple,
        redirectTo: AuthConfig.redirectUrl,
        authScreenLaunchMode: sb.LaunchMode.externalApplication,
      );
      return;
    }
    final rawNonce = _auth.generateRawNonce();
    final credenziale = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: sha256.convert(utf8.encode(rawNonce)).toString(),
    );
    final idToken = credenziale.identityToken;
    if (idToken == null) {
      throw const AuthException(
        AuthErrore.sconosciuto,
        'identityToken assente',
      );
    }
    await _auth.signInWithIdToken(
      provider: sb.OAuthProvider.apple,
      idToken: idToken,
      nonce: rawNonce,
    );
    // Apple fornisce il nome solo al primo accesso e non è nell'ID token.
    final nome = [
      credenziale.givenName,
      credenziale.familyName,
    ].whereType<String>().join(' ');
    if (nome.isNotEmpty) {
      await _auth.updateUser(
        sb.UserAttributes(
          data: {
            'full_name': nome,
            'given_name': credenziale.givenName,
            'family_name': credenziale.familyName,
          },
        ),
      );
    }
  });

  @override
  Future<void> accediConGoogle() => _traduci(() async {
    final google = GoogleSignIn.instance;
    if (!_googleInizializzato) {
      await google.initialize(
        clientId: Platform.isIOS ? AuthConfig.googleIosClientId : null,
        serverClientId: AuthConfig.googleWebClientId,
      );
      _googleInizializzato = true;
    }
    final account = await google.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw const AuthException(AuthErrore.sconosciuto, 'idToken assente');
    }
    await _auth.signInWithIdToken(
      provider: sb.OAuthProvider.google,
      idToken: idToken,
    );
  });

  @override
  Future<void> accediConEmail(String email, String password) => _traduci(
    () => _auth.signInWithPassword(email: email, password: password),
  );

  @override
  Future<bool> registratiConEmail(String email, String password) =>
      _traduci(() async {
        final risposta = await _auth.signUp(
          email: email,
          password: password,
          emailRedirectTo: AuthConfig.redirectUrl,
        );
        // Con "Confirm email" attivo Supabase non restituisce una sessione
        // e, per non rivelare quali email esistono, risponde con un utente
        // senza identità se l'email è già registrata.
        if (risposta.user?.identities?.isEmpty ?? false) {
          throw const AuthException(AuthErrore.emailGiaRegistrata);
        }
        return risposta.session == null;
      });

  @override
  Future<void> reinviaConferma(String email) => _traduci(
    () => _auth.resend(
      type: sb.OtpType.signup,
      email: email,
      emailRedirectTo: AuthConfig.redirectUrl,
    ),
  );

  @override
  Future<void> esci() => _traduci(() async {
    await _auth.signOut();
    if (_googleInizializzato) await GoogleSignIn.instance.signOut();
  });

  @override
  Future<void> eliminaAccount() => _traduci(() async {
    String? appleCode;
    if (Platform.isIOS && profiloCorrente?.metodo == MetodoAccesso.apple) {
      final credenziale = await SignInWithApple.getAppleIDCredential(
        scopes: const [],
      );
      appleCode = credenziale.authorizationCode;
    }
    try {
      await _client.functions.invoke(
        'elimina-account',
        body: {'appleAuthorizationCode': ?appleCode},
      );
    } on sb.FunctionException catch (e) {
      throw AuthException(
        e.status == 409
            ? AuthErrore.proprietarioConCollaboratori
            : AuthErrore.sconosciuto,
        '${e.status}: ${e.details}',
      );
    }
    // L'utente non esiste più: `signOut` ignora il 404 del server e
    // chiude comunque la sessione sul device.
    await _auth.signOut();
    if (_googleInizializzato) await GoogleSignIn.instance.signOut();
  });

  @override
  Future<bool> raggiungibile() async {
    try {
      final risposta = await http
          .get(
            Uri.parse('${AuthConfig.supabaseUrl}/auth/v1/health'),
            headers: {'apikey': AuthConfig.supabasePublishableKey},
          )
          .timeout(const Duration(seconds: 8));
      return risposta.statusCode < 500;
    } on Exception {
      return false;
    }
  }

  static Future<T> _traduci<T>(Future<T> Function() azione) async {
    try {
      return await azione();
    } on AuthException {
      rethrow;
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        throw const AuthException(AuthErrore.annullato);
      }
      throw AuthException(AuthErrore.sconosciuto, e.message);
    } on GoogleSignInException catch (e) {
      // Su Android un errore di configurazione (SHA-1, serverClientId) può
      // presentarsi come "canceled" (#168 §1).
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const AuthException(AuthErrore.annullato);
      }
      throw AuthException(AuthErrore.sconosciuto, e.description);
    } on sb.AuthRetryableFetchException catch (e) {
      throw AuthException(AuthErrore.rete, e.message);
    } on sb.AuthWeakPasswordException catch (e) {
      throw AuthException(AuthErrore.passwordDebole, e.message);
    } on sb.AuthApiException catch (e) {
      throw AuthException(switch (e.code) {
        'invalid_credentials' => AuthErrore.credenzialiErrate,
        'email_not_confirmed' => AuthErrore.emailNonConfermata,
        'user_already_exists' ||
        'email_exists' => AuthErrore.emailGiaRegistrata,
        'weak_password' => AuthErrore.passwordDebole,
        _ => AuthErrore.sconosciuto,
      }, e.message);
    } on SocketException catch (e) {
      throw AuthException(AuthErrore.rete, e.message);
    } on http.ClientException catch (e) {
      throw AuthException(AuthErrore.rete, e.message);
    }
  }
}
