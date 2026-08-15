/// PROTOTYPE — throwaway. Answers wayfinder ticket #7,
/// "Quanto in profondità va l'adattamento nativo?", on the map
/// "Mappa — Dashboard su fondamenta Flutter" (issue #1).
///
/// Question: same Dashboard fragment (header + KPI grid + "Scansiona una
/// cover"), built once with Material idioms and once with Cupertino idioms,
/// both themed with the same design tokens (`tokens.dart`, lifted from
/// `app-design/Catalogo Fumetti.dc.html`) — side by side, to see concretely
/// what's shared, what diverges, and how much code the divergence costs.
///
/// Run: `flutter run -d macos` (or `-d chrome`) from this directory.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'variant_cupertino.dart';
import 'variant_material.dart';
import 'tokens.dart';

void main() => runApp(const ProtoApp());

/// Root is `MaterialApp`, on both platforms — per the research on ticket #5:
/// `CupertinoApp` doesn't provide the `Material` ancestor plain-Material
/// widgets assert on, but `MaterialApp` bridges a `CupertinoTheme` to
/// nested Cupertino widgets automatically. `cupertinoOverrideTheme` closes
/// the one gap that bridge leaves open — typography — since Cupertino's
/// default text styles have `inherit: false` and never see our font
/// otherwise (research §5.2).
class ProtoApp extends StatelessWidget {
  const ProtoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Ticket #7 — adattamento nativo',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Tokens.bg,
        fontFamily: 'Space Grotesk',
        colorScheme: const ColorScheme.dark(
          primary: Tokens.accent,
          surface: Tokens.surface,
        ),
        cupertinoOverrideTheme: const CupertinoThemeData(
          brightness: Brightness.dark,
          primaryColor: Tokens.accent,
          scaffoldBackgroundColor: Tokens.bg,
          textTheme: CupertinoTextThemeData(
            textStyle: TextStyle(fontFamily: 'Space Grotesk', color: Tokens.ink),
          ),
        ),
      ),
      home: const ComparisonScreen(),
    );
  }
}

class ComparisonScreen extends StatelessWidget {
  const ComparisonScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Tokens.bg,
      body: SafeArea(
        child: Column(
          children: [
            const _IntroBar(),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    _PhoneColumn(
                      label: 'MATERIAL — InkWell ripple',
                      child: MaterialDashboardFragment(),
                    ),
                    SizedBox(width: 28),
                    _PhoneColumn(
                      label: 'CUPERTINO — opacity fade',
                      child: CupertinoDashboardFragment(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntroBar extends StatelessWidget {
  const _IntroBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Tokens.hairline)),
      ),
      child: const Text(
        'Ticket #7 — stessa porzione di Dashboard, due variante tematizzate. '
        'Tocca le card: la differenza di feedback è l\'unica divergenza reale '
        'in questo frammento (vedi README per l\'analisi completa).',
        style: TextStyle(fontFamily: 'Space Grotesk', fontSize: 12.5, color: Tokens.inkDim),
      ),
    );
  }
}

class _PhoneColumn extends StatelessWidget {
  final String label;
  final Widget child;
  const _PhoneColumn({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'IBM Plex Mono',
            fontSize: 11,
            letterSpacing: 1.2,
            color: Tokens.accent,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: 390,
          padding: const EdgeInsets.fromLTRB(18, 24, 18, 24),
          decoration: BoxDecoration(
            color: Tokens.surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Tokens.hairline, width: 2),
          ),
          child: child,
        ),
      ],
    );
  }
}
