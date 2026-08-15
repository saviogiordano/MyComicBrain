/// PROTOTYPE — throwaway. Answers ticket #7 ("Quanto in profondità va
/// l'adattamento nativo?"). Not the real app's design system — just enough
/// of it, copied from `app-design/Catalogo Fumetti.dc.html`, to theme both
/// variants identically.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

abstract final class Tokens {
  static const bg = Color(0xFF08090A);
  static const surface = Color(0xFF0E1113);
  static const ink = Color(0xFFF2F4F5);
  static const inkDim = Color(0x8AF2F4F5); // rgba(242,244,245,.54)-ish
  static const inkFaint = Color(0x6BF2F4F5); // rgba(242,244,245,.42)
  static const accent = Color(0xFF22B8CF);
  static const amber = Color(0xFFE9A23B);
  static const violet = Color(0xFFB07CE8); // 3rd KPI color, guessed from design family
  static const hairline = Color(0x14FFFFFF); // rgba(255,255,255,.08)
  static const cardFill = Color(0x05FFFFFF); // rgba(255,255,255,.02)

  static const rCard = 14.0;
  static const rHero = 18.0;

  // The design's mono label style ("LA TUA COLLEZIONE", KPI captions).
  static const label = TextStyle(
    fontFamily: 'IBM Plex Mono',
    fontSize: 10.5,
    height: 1,
    letterSpacing: 1.6,
    fontWeight: FontWeight.w500,
    color: inkFaint,
  );

  static const heroNumber = TextStyle(
    fontFamily: 'Space Grotesk',
    fontSize: 40,
    height: 1,
    letterSpacing: -1.2,
    fontWeight: FontWeight.w600,
    color: ink,
  );

  static const heroUnit = TextStyle(
    fontFamily: 'Space Grotesk',
    fontSize: 14,
    color: inkDim,
  );

  static const kpiValue = TextStyle(
    fontFamily: 'Space Grotesk',
    fontSize: 21,
    height: 1,
    fontWeight: FontWeight.w600,
  );

  static const kpiLabel = TextStyle(
    fontFamily: 'Space Grotesk',
    fontSize: 10.5,
    height: 1.3,
    color: inkDim,
  );

  static const scanTitle = TextStyle(
    fontFamily: 'Space Grotesk',
    fontSize: 14.5,
    fontWeight: FontWeight.w600,
    color: ink,
  );

  static const scanSubtitle = TextStyle(
    fontFamily: 'Space Grotesk',
    fontSize: 11.5,
    height: 1.4,
    color: Color(0x8CF2F4F5),
  );
}

/// The Dashboard KPI fixtures used by both variants — lifted from the
/// `{{ kpis }}` binding in the design HTML, hardcoded here since the
/// question is presentational, not data.
class KpiFixture {
  final String value;
  final String label;
  final Color color;
  const KpiFixture(this.value, this.label, this.color);
}

const kpiFixtures = [
  KpiFixture('1.248', 'fumetti', Tokens.ink),
  KpiFixture('312', 'edizioni', Tokens.accent),
  KpiFixture('18', 'duplicati', Tokens.amber),
  KpiFixture('4', 'serie complete', Tokens.violet),
  KpiFixture('27', 'numeri mancanti', Tokens.amber),
  KpiFixture('€2.340', 'speso finora', Tokens.ink),
];
