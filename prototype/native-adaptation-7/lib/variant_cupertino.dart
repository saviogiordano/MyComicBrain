/// PROTOTYPE — throwaway, ticket #7.
///
/// Same Dashboard fragment, built with Cupertino idioms: opacity-fade touch
/// feedback (à la CupertinoButton — no ripple exists on this platform) and
/// CupertinoTextThemeData-driven text, per the `cupertinoOverrideTheme`
/// pattern surfaced in the research on ticket #5
/// (docs/research/adattamento-nativo.md, §5.2). There is no CupertinoCard,
/// no Cupertino grid primitive, no Cupertino KPI-tile equivalent — those
/// pieces are the same custom `Container`s as the Material variant either
/// way; only the *tap feedback* mechanism is platform-idiomatic here.
library;

import 'package:flutter/cupertino.dart';
import 'tokens.dart';

class CupertinoDashboardFragment extends StatelessWidget {
  const CupertinoDashboardFragment({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(),
        const SizedBox(height: 20),
        _KpiGrid(),
        const SizedBox(height: 20),
        _ScanCard(),
      ],
    );
  }
}

/// Opacity-fade tap feedback — what `CupertinoButton` does internally
/// (`AnimatedOpacity` to ~0.4 on press). Reimplemented by hand here because
/// `CupertinoButton` carries its own padding/sizing opinions that would
/// fight the design's own box model — exactly the "no Cupertino<Component>
/// Theme, customize at the call site" cost the research flagged (§5.3).
class _CupertinoTappable extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;
  const _CupertinoTappable({required this.onTap, required this.child});

  @override
  State<_CupertinoTappable> createState() => _CupertinoTappableState();
}

class _CupertinoTappableState extends State<_CupertinoTappable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedOpacity(
        opacity: _pressed ? 0.4 : 1,
        duration: const Duration(milliseconds: 120),
        child: widget.child,
      ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('LA TUA COLLEZIONE', style: Tokens.label),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: const [
                Text('1.248', style: Tokens.heroNumber),
                SizedBox(width: 8),
                Text('fumetti', style: Tokens.heroUnit),
              ],
            ),
          ],
        ),
        _CupertinoTappable(
          onTap: () {},
          child: Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Tokens.hairline),
            ),
            child: const Text(
              'AI',
              style: TextStyle(
                fontFamily: 'IBM Plex Mono',
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Tokens.accent,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _KpiGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      // Cupertino's ScrollBehavior forces BouncingScrollPhysics everywhere
      // (research §2.3) — irrelevant here since the grid never scrolls, but
      // real scrollable regions of this screen would inherit that bounce
      // automatically, at zero cost, once the app root uses the shared
      // ScrollBehavior. Nothing to write by hand.
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.15,
      children: kpiFixtures.map((k) {
        return _CupertinoTappable(
          onTap: () {},
          child: Container(
            padding: const EdgeInsets.all(12),
            alignment: Alignment.topLeft,
            decoration: BoxDecoration(
              border: Border.all(color: Tokens.hairline),
              borderRadius: BorderRadius.circular(Tokens.rCard),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(k.value, style: Tokens.kpiValue.copyWith(color: k.color)),
                const SizedBox(height: 6),
                Text(k.label, style: Tokens.kpiLabel),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ScanCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _CupertinoTappable(
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Tokens.accent.withValues(alpha: .16),
              Tokens.accent.withValues(alpha: .04),
            ],
          ),
          border: Border.all(color: Tokens.accent.withValues(alpha: .28)),
          borderRadius: BorderRadius.circular(Tokens.rHero),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Tokens.accent,
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Text(
                '◉',
                style: TextStyle(
                  fontFamily: 'Space Grotesk',
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Tokens.bg,
                ),
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Scansiona una cover', style: Tokens.scanTitle),
                  SizedBox(height: 2),
                  Text('Fotografa → riconosci → conferma', style: Tokens.scanSubtitle),
                ],
              ),
            ),
            const Text('›', style: TextStyle(fontSize: 18, color: Color(0x66F2F4F5))),
          ],
        ),
      ),
    );
  }
}
