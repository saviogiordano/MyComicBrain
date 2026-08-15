import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mycomicbrain/core/routing/app_bottom_nav.dart';
import 'package:mycomicbrain/core/routing/session.dart';
import 'package:mycomicbrain/features/assistente/presentation/assistente_page.dart';
import 'package:mycomicbrain/features/collezione/presentation/collezione_page.dart';
import 'package:mycomicbrain/features/dashboard/presentation/dashboard_page.dart';
import 'package:mycomicbrain/features/duplicati/presentation/duplicati_page.dart';
import 'package:mycomicbrain/features/login/presentation/login_page.dart';
import 'package:mycomicbrain/features/ricerca/presentation/ricerca_page.dart';
import 'package:mycomicbrain/features/scansione/presentation/scansione_page.dart';
import 'package:mycomicbrain/features/scheda/presentation/scheda_page.dart';
import 'package:mycomicbrain/features/serie/presentation/serie_page.dart';
import 'package:mycomicbrain/features/statistiche/presentation/statistiche_page.dart';

/// Notifica il router quando [sessionProvider] cambia, così `redirect`
/// viene rivalutato senza dover ricreare il [GoRouter] (che perderebbe
/// la sua history interna).
class _SessionRefresh extends ChangeNotifier {
  _SessionRefresh(Ref ref) {
    ref.listen<bool>(sessionProvider, (_, _) => notifyListeners());
  }
}

/// Router unico dell'app. Costruito come provider così la gate di sessione
/// (Login → shell) è gestita con Riverpod invece che con stato locale.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _SessionRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: refresh,
    redirect: (context, state) {
      final inApp = ref.read(sessionProvider);
      final onLogin = state.matchedLocation == '/login';
      if (!inApp) return onLogin ? null : '/login';
      if (onLogin) return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginPage(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/dashboard',
                builder: (context, state) => const DashboardPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/collezione',
                builder: (context, state) => const CollezionePage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/scansione',
                builder: (context, state) => const ScansionePage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/ricerca',
                builder: (context, state) => const RicercaPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/statistiche',
                builder: (context, state) => const StatistichePage(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/scheda/:id',
        builder: (context, state) => const SchedaPage(),
      ),
      GoRoute(
        path: '/serie/:id',
        builder: (context, state) => const SeriePage(),
      ),
      GoRoute(
        path: '/duplicati',
        builder: (context, state) => const DuplicatiPage(),
      ),
      GoRoute(
        path: '/assistente',
        builder: (context, state) => const AssistentePage(),
      ),
    ],
  );
});

class AppShell extends StatelessWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: AppBottomNav(
        currentIndex: navigationShell.currentIndex,
        onDestinationSelected: navigationShell.goBranch,
      ),
    );
  }
}
