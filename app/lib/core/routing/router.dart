import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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

final router = GoRouter(
  initialLocation: '/login',
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

class AppShell extends StatelessWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: navigationShell.goBranch,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.collections_bookmark_outlined),
            selectedIcon: Icon(Icons.collections_bookmark),
            label: 'Collezione',
          ),
          NavigationDestination(
            icon: Icon(Icons.document_scanner_outlined),
            selectedIcon: Icon(Icons.document_scanner),
            label: 'Scansione',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search),
            label: 'Cerca',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'Statistiche',
          ),
        ],
      ),
    );
  }
}
