import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/auth/auth_gateway.dart';
import 'package:mycomicbrain/core/auth/session_controller.dart';
import 'package:mycomicbrain/core/routing/router.dart';

/// La gate del login reale: con un Profilo autenticato si entra nell'app
/// solo con la Replica scaricata (#217); senza, il primo download.
void main() {
  const profilo = Profilo(
    email: 'mario@example.com',
    metodo: MetodoAccesso.email,
  );

  SessionState sessione({Profilo? profilo, bool esaurita = true}) =>
      SessionState(
        profilo: profilo,
        benvenutoSuperato: true,
        modalitaLocaleEsaurita: esaurita,
        emailInAttesa: null,
      );

  String? vai(
    SessionState s,
    String posizione, {
    bool? replicaScaricata,
  }) => redirectAccount(
    s,
    replicaScaricata: replicaScaricata,
    posizione: posizione,
  );

  test('un Profilo senza Replica va al primo download, anche quando non si '
      'sa ancora', () {
    final s = sessione(profilo: profilo);
    expect(vai(s, '/dashboard', replicaScaricata: false), '/primo-download');
    expect(vai(s, '/benvenuto'), '/primo-download');
    expect(vai(s, '/primo-download', replicaScaricata: false), isNull);
  });

  test('con la Replica scaricata si entra (anche senza rete)', () {
    final s = sessione(profilo: profilo);
    expect(vai(s, '/primo-download', replicaScaricata: true), '/dashboard');
    expect(vai(s, '/collezione', replicaScaricata: true), isNull);
  });

  test("l'importazione viene prima del primo download", () {
    final s = sessione(profilo: profilo, esaurita: false);
    expect(vai(s, '/primo-download'), '/importazione');
  });

  test('la Modalità locale non passa mai dal primo download', () {
    final s = sessione(esaurita: false);
    expect(vai(s, '/primo-download'), '/dashboard');
    expect(vai(s, '/collezione'), isNull);
  });

  group('senza cloud', () {
    String? senzaCloud(SessionState s, String posizione) => redirectAccount(
      s,
      replicaScaricata: null,
      posizione: posizione,
      cloudAbilitato: false,
    );

    SessionState locale({required bool benvenuto, bool esaurita = false}) =>
        SessionState(
          profilo: null,
          benvenutoSuperato: benvenuto,
          modalitaLocaleEsaurita: esaurita,
          emailInAttesa: null,
        );

    test('al primo avvio resta sul benvenuto', () {
      final s = locale(benvenuto: false);
      expect(senzaCloud(s, '/benvenuto'), isNull);
      expect(senzaCloud(s, '/dashboard'), '/benvenuto');
      expect(senzaCloud(s, '/accedi'), '/benvenuto');
    });

    test('superato il benvenuto le schermate del cloud portano alla '
        'Dashboard', () {
      final s = locale(benvenuto: true);
      for (final posizione in [
        '/benvenuto',
        '/accedi',
        '/primo-download',
        '/importazione',
        '/account/elimina',
      ]) {
        expect(senzaCloud(s, posizione), '/dashboard', reason: posizione);
      }
      expect(senzaCloud(s, '/collezione'), isNull);
    });

    test('con la Modalità locale esaurita si entra lo stesso', () {
      final s = locale(benvenuto: true, esaurita: true);
      expect(senzaCloud(s, '/dashboard'), isNull);
    });
  });
}
