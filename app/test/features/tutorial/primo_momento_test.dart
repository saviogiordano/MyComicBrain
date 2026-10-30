import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mycomicbrain/core/auth/session_controller.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/core/routing/router.dart';
import 'package:mycomicbrain/features/tutorial/presentation/spotlight.dart';

import '../../core/auth/fake_auth_gateway.dart';

/// La Scansione vera richiede scanner e permessi: qui bastano i suoi tre
/// elementi illuminati, con le stesse chiavi.
class _ScansioneFinta extends StatelessWidget {
  const _ScansioneFinta();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const Text('Scansione'),
          FilledButton(
            key: TutorialInserimentoKeys.fine,
            onPressed: () {},
            child: const Text('Fine'),
          ),
          const Spacer(),
          Row(
            children: [
              SizedBox(
                key: TutorialInserimentoKeys.galleria,
                width: 48,
                height: 48,
              ),
              FilledButton(
                key: TutorialInserimentoKeys.fotocamera,
                onPressed: () {},
                child: const Text('Fotocamera'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

void main() {
  late PreferencesInMemoria preferenze;

  setUp(() => preferenze = PreferencesInMemoria());

  String? fase() => preferenze.valori['tutorial.inserimento.fase'];

  Future<void> pumpShell(
    WidgetTester tester, {
    String? faseIniziale,
    String initialLocation = '/dashboard',
  }) async {
    if (faseIniziale != null) {
      preferenze.valori['tutorial.inserimento.fase'] = faseIniziale;
    }
    GoRoute pagina(String path, Widget child) =>
        GoRoute(path: path, builder: (context, state) => child);
    final router = GoRouter(
      initialLocation: initialLocation,
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              AppShell(navigationShell: navigationShell),
          branches: [
            for (final rotta in [
              pagina('/dashboard', const Text('Dashboard')),
              pagina('/collezione', const Text('Collezione')),
              pagina('/scansione', const _ScansioneFinta()),
              pagina('/ricerca', const Text('Ricerca')),
              pagina('/impostazioni', const Text('Impostazioni')),
            ])
              StatefulShellBranch(routes: [rotta]),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [accountPreferencesProvider.overrideWithValue(preferenze)],
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('al primo ingresso nella Dashboard compare la scheda, e conta '
      'già come visto', (tester) async {
    await pumpShell(tester, faseIniziale: 'daMostrare');

    expect(find.text('Aggiungi il tuo primo fumetto'), findsOneWidget);
    expect(fase(), 'visto');
  });

  testWidgets('"Mostrami" illumina barra, Fotocamera, Galleria e "Fine", '
      'poi arma il secondo momento', (tester) async {
    await pumpShell(tester, faseIniziale: 'daMostrare');

    await tester.tap(find.text('Mostrami'));
    await tester.pumpAndSettle();
    expect(find.text('Da qui aggiungi un fumetto'), findsOneWidget);

    await tester.tap(find.text('Avanti'));
    await tester.pumpAndSettle();
    expect(
      find.text('Scansione'),
      findsOneWidget,
      reason: '"Avanti" apre la Scansione da solo',
    );
    expect(
      find.text('Scatta la cover, puoi ritagliarla e raddrizzarla subito dopo'),
      findsOneWidget,
    );

    await tester.tap(find.text('Avanti'));
    await tester.pumpAndSettle();
    expect(find.text('Oppure scegli una foto che hai già'), findsOneWidget);

    await tester.tap(find.text('Avanti'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        "Scatta tutte le cover che vuoi, poi tocca Fine. Ti mostro l'avanzamento",
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Ho capito'));
    await tester.pumpAndSettle();
    expect(find.text('Ho capito'), findsNothing);
    expect(fase(), 'inAttesaPrimaScansione');
  });

  testWidgets('"Salta" sulla scheda chiude tutto', (tester) async {
    await pumpShell(tester, faseIniziale: 'daMostrare');

    await tester.tap(find.text('Salta'));
    await tester.pumpAndSettle();

    expect(find.text('Aggiungi il tuo primo fumetto'), findsNothing);
    expect(fase(), 'visto');
  });

  testWidgets('"Salta" durante gli spotlight chiude tutto', (tester) async {
    await pumpShell(tester, faseIniziale: 'daMostrare');
    await tester.tap(find.text('Mostrami'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Salta'));
    await tester.pumpAndSettle();

    expect(find.text('Da qui aggiungi un fumetto'), findsNothing);
    expect(fase(), 'visto');
  });

  testWidgets('non parte fuori dalla Dashboard', (tester) async {
    await pumpShell(
      tester,
      faseIniziale: 'daMostrare',
      initialLocation: '/collezione',
    );

    expect(find.text('Aggiungi il tuo primo fumetto'), findsNothing);
    expect(fase(), 'daMostrare');
  });

  testWidgets('a tutorial visto non compare', (tester) async {
    await pumpShell(tester, faseIniziale: 'visto');

    expect(find.text('Aggiungi il tuo primo fumetto'), findsNothing);
  });
}
