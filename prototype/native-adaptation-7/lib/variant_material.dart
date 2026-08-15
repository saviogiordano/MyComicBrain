/// PROTOTYPE — throwaway, ticket #7.
///
/// Dashboard fragment (header + KPI grid + "Scansiona una cover") built with
/// Material idioms: InkWell ripple feedback on every tappable surface,
/// Material's default touch/scroll behaviour.
library;

import 'package:flutter/material.dart';
import 'tokens.dart';

class MaterialDashboardFragment extends StatelessWidget {
  const MaterialDashboardFragment({super.key});

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
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {},
            borderRadius: BorderRadius.circular(12),
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
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.15,
      children: kpiFixtures.map((k) {
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {},
            borderRadius: BorderRadius.circular(Tokens.rCard),
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
          ),
        );
      }).toList(),
    );
  }
}

class _ScanCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(Tokens.rHero),
        child: Ink(
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
      ),
    );
  }
}
