import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mycomicbrain/core/auth/auth_config.dart';
import 'package:mycomicbrain/core/auth/secure_session_storage.dart';
import 'package:mycomicbrain/core/auth/session_controller.dart';
import 'package:mycomicbrain/core/auth/supabase_auth_gateway.dart';
import 'package:mycomicbrain/core/data/preferences_shared_preferences_adapter.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/data/secure_storage_flutter_adapter.dart';
import 'package:mycomicbrain/core/data/supabase/importazione_modalita_locale.dart';
import 'package:mycomicbrain/core/design_system/app_theme.dart';
import 'package:mycomicbrain/core/routing/router.dart';
import 'package:mycomicbrain/features/importazione/application/importazione_controller.dart';
import 'package:mycomicbrain/features/login/presentation/avviso_accesso.dart';
import 'package:mycomicbrain/features/sincronizzazione/presentation/avviso_modifiche_rifiutate.dart';
import 'package:mycomicbrain/features/sincronizzazione/presentation/avviso_modifiche_scartate.dart';
import 'package:mycomicbrain/features/sincronizzazione/presentation/stato_sincronizzazione.dart';
import 'package:mycomicbrain/features/tutorial/application/tutorial_inserimento.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final sharedPreferences = await SharedPreferences.getInstance();
  final account = await _overridesAccount(sharedPreferences);
  // Prima che l'utente possa superare il benvenuto: la regola per gli
  // utenti esistenti guarda `benvenutoSuperato` com'era all'avvio (#238).
  await TutorialInserimentoController.allAvvio(
    SharedPreferencesAdapter(sharedPreferences),
  );

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),
        ...account,
      ],
      child: const MyComicBrainApp(),
    ),
  );
}

/// Account (#171, ADR-0008): inizializza Supabase con la sessione nello
/// storage sicuro, che `initialize` ripristina prima di restituire — così
/// `SessionController` parte già dal Profilo salvato.
Future<List<Override>> _overridesAccount(
  SharedPreferences sharedPreferences,
) async {
  // La Replica del Profilo (ADR-0008) è un secondo `AppDatabase`, aperto
  // insieme a quello della Modalità locale su un file diverso.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final supabase = await Supabase.initialize(
    url: AuthConfig.supabaseUrl,
    publishableKey: AuthConfig.supabasePublishableKey,
    authOptions: const FlutterAuthClientOptions(
      localStorage: SecureSessionStorage(FlutterSecureStorageAdapter()),
    ),
  );
  return [
    supabaseClientProvider.overrideWithValue(supabase.client),
    authGatewayProvider.overrideWithValue(
      SupabaseAuthGateway(supabase.client),
    ),
    accountPreferencesProvider.overrideWithValue(
      SharedPreferencesAdapter(sharedPreferences),
    ),
    haDatiLocaliProvider.overrideWith(
      (ref) => ref.watch(driftComicsRepositoryProvider).haDatiDaImportare,
    ),
    cancellazioneProfiloProvider.overrideWith((ref) {
      final userId = ref.watch(idUtenteSupabaseProvider);
      if (userId == null) return null;
      final repliche = ref.watch(replicheProfiloProvider);
      final motore = ref.watch(motoreSincronizzazioneProvider);
      return () async {
        // Nessun ciclo deve scrivere sulla Replica mentre si cancella.
        await motore?.chiudi();
        await repliche.cancella(userId);
      };
    }),
    importatoreModalitaLocaleProvider.overrideWith(
      (ref) => ImportazioneModalitaLocale(
        db: ref.watch(appDatabaseProvider),
        client: supabase.client,
        userId: ref.watch(idUtenteSupabaseProvider)!,
        baseDirectory: ref.watch(copertinaDownloaderProvider).baseDirectory,
      ),
    ),
  ];
}

class MyComicBrainApp extends ConsumerWidget {
  const MyComicBrainApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    // La Sincronizzazione gira finché c'è un Profilo (ADR-0008), e con lei
    // l'avvio delle Scansioni accodate senza rete (#210).
    ref
      ..watch(motoreSincronizzazioneProvider)
      ..watch(avvioScansioniInAttesaProvider);
    return MaterialApp.router(
      title: 'MyComicBrain',
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: router,
      builder: (context, child) => AvvisoAccesso(
        vaiAllaDashboard: () => router.go('/dashboard'),
        child: AvvisoModificheScartate(
          child: AvvisoModificheRifiutate(
            apriDettagli: () {
              final navigatore = router.routerDelegate.navigatorKey;
              final context = navigatore.currentContext;
              if (context != null) {
                unawaited(mostraSheetSincronizzazione(context));
              }
            },
            child: child!,
          ),
        ),
      ),
    );
  }
}
