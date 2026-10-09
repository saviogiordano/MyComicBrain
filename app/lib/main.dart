import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mycomicbrain/core/auth/auth_config.dart';
import 'package:mycomicbrain/core/auth/secure_session_storage.dart';
import 'package:mycomicbrain/core/auth/session_controller.dart';
import 'package:mycomicbrain/core/auth/supabase_auth_gateway.dart';
import 'package:mycomicbrain/core/data/preferences_shared_preferences_adapter.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/data/secure_storage_flutter_adapter.dart';
import 'package:mycomicbrain/core/design_system/app_theme.dart';
import 'package:mycomicbrain/core/routing/router.dart';
import 'package:mycomicbrain/features/login/presentation/avviso_accesso.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final sharedPreferences = await SharedPreferences.getInstance();
  final account = AuthConfig.loginAbilitato
      ? await _overridesAccount(sharedPreferences)
      : const <Override>[];

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

/// Login reale dietro flag (#171, ADR-0007): inizializza Supabase con la
/// sessione nello storage sicuro, che `initialize` ripristina prima di
/// restituire — così `SessionController` parte già dal Profilo salvato.
Future<List<Override>> _overridesAccount(
  SharedPreferences sharedPreferences,
) async {
  assert(
    AuthConfig.supabasePublishableKey.isNotEmpty,
    'Manca --dart-define=SUPABASE_PUBLISHABLE_KEY (vedi app/README.md)',
  );
  final supabase = await Supabase.initialize(
    url: AuthConfig.supabaseUrl,
    publishableKey: AuthConfig.supabasePublishableKey,
    authOptions: const FlutterAuthClientOptions(
      localStorage: SecureSessionStorage(FlutterSecureStorageAdapter()),
    ),
  );
  return [
    authGatewayProvider.overrideWithValue(
      SupabaseAuthGateway(supabase.client),
    ),
    accountPreferencesProvider.overrideWithValue(
      SharedPreferencesAdapter(sharedPreferences),
    ),
    haDatiLocaliProvider.overrideWith(
      (ref) => ref.watch(comicsRepositoryProvider).haDatiDaImportare,
    ),
  ];
}

class MyComicBrainApp extends ConsumerWidget {
  const MyComicBrainApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'MyComicBrain',
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: router,
      builder: AuthConfig.loginAbilitato
          ? (context, child) => AvvisoAccesso(
              vaiAllaDashboard: () => router.go('/dashboard'),
              child: child!,
            )
          : null,
    );
  }
}
