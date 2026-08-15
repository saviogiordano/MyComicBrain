import 'package:flutter/widgets.dart';

/// Colore, in tre livelli: fondi (surface), testo a opacità scalare,
/// accent (ciano) e ambra (segnali di attenzione — duplicati, numeri
/// mancanti). Estratti dal prototipo `app-design/Catalogo Fumetti.dc.html`.
abstract final class AppColors {
  // Fondi — scala di elevazione, dal più profondo al più sollevato.
  static const Color surfaceDeepest = Color(0xFF08090A);
  static const Color surfaceBase = Color(0xFF0E1113);
  static const Color surfaceRaised = Color(0xFF141A1D);

  /// Overlay bianco-trasparente da sovrapporre a un fondo per ottenere
  /// una superficie "sollevata" (card, riquadro) senza un colore piatto.
  static const Color overlayCard = Color(0x05FFFFFF); // rgba(255,255,255,.02)
  static const Color overlayCardHover = Color(0x0DFFFFFF); // .05

  // Bordi — hairline bianco-trasparente su fondo scuro.
  static const Color borderSubtle = Color(0x0FFFFFFF); // .06
  static const Color borderDefault = Color(0x14FFFFFF); // .08
  static const Color borderStrong = Color(0x24FFFFFF); // .14

  // Testo — bianco caldo a opacità scalare sopra ai fondi.
  static const Color textBase = Color(0xFFF2F4F5);
  static const double textOpacityPrimary = 1;
  static const double textOpacitySecondary = 0.6;
  static const double textOpacityTertiary = 0.5;
  static const double textOpacityMuted = 0.42;
  static const double textOpacityDisabled = 0.34;

  static Color text(double opacity) => textBase.withValues(alpha: opacity);

  static const Color textPrimary = textBase;
  static final Color textSecondary = text(textOpacitySecondary);
  static final Color textTertiary = text(textOpacityTertiary);
  static final Color textMuted = text(textOpacityMuted);
  static final Color textDisabled = text(textOpacityDisabled);

  // Accent — ciano, colore d'azione primario.
  static const Color accent = Color(0xFF22B8CF);
  static const Color accentLight = Color(0xFF5AD3E4);

  /// Colore del testo/icona sopra a una superficie piena `accent`.
  static const Color onAccent = surfaceDeepest;

  static Color accentAlpha(double opacity) => accent.withValues(alpha: opacity);

  // Ambra — segnali di attenzione (duplicati, numeri mancanti), mai errore.
  static const Color amber = Color(0xFFE9A23B);
  static const Color amberStrong = Color(0xFFC4771B);

  static Color amberAlpha(double opacity) => amber.withValues(alpha: opacity);
}

/// Spaziature su scala 4px, coprendo il range osservato nel prototipo (4–34px).
abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Raggi degli angoli. `pill` è un raggio "infinito" per componenti
/// completamente arrotondati (chip, pillole) indipendentemente dall'altezza.
abstract final class AppRadii {
  static const double xs = 6;
  static const double sm = 9;
  static const double md = 13;
  static const double lg = 14;
  static const double xl = 18;
  static const double pill = 999;

  static BorderRadius get xsRadius => BorderRadius.circular(xs);
  static BorderRadius get smRadius => BorderRadius.circular(sm);
  static BorderRadius get mdRadius => BorderRadius.circular(md);
  static BorderRadius get lgRadius => BorderRadius.circular(lg);
  static BorderRadius get xlRadius => BorderRadius.circular(xl);
  static BorderRadius get pillRadius => BorderRadius.circular(pill);
}

/// Le due famiglie tipografiche del prodotto: Space Grotesk per UI e testo,
/// IBM Plex Mono per etichette tecniche/mono (intestazioni di sezione,
/// badge numerici, valori KPI in evidenza).
abstract final class AppFonts {
  static const String sans = 'Space Grotesk';
  static const String mono = 'IBM Plex Mono';
}

/// Stili di testo con nome, mappati sui ruoli osservati nel prototipo.
/// Nessuno include un colore: applicalo al call site con `.copyWith(color: ...)`
/// o con `AppColors.text*`.
abstract final class AppTypography {
  // Display — numeri e titoli in grande evidenza.
  static const TextStyle heroNumber = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 40,
    fontWeight: FontWeight.w600,
    height: 1,
    letterSpacing: -0.03 * 40,
  );

  static const TextStyle pageTitle = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 34,
    fontWeight: FontWeight.w600,
    height: 1.08,
    letterSpacing: -0.02 * 34,
  );

  static const TextStyle headline = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 30,
    fontWeight: FontWeight.w600,
    height: 1.1,
    letterSpacing: -0.025 * 30,
  );

  // Title — intestazioni di card e schermate.
  static const TextStyle titleLarge = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 20,
    fontWeight: FontWeight.w500,
    height: 1.1,
  );

  static const TextStyle titleMedium = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.01 * 15,
  );

  /// Valore numerico di una card KPI.
  static const TextStyle kpiValue = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 21,
    fontWeight: FontWeight.w600,
    height: 1,
  );

  // Body — testo corrente.
  static const TextStyle bodyLarge = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.6,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 12.5,
    fontWeight: FontWeight.w400,
    height: 1.55,
  );

  static const TextStyle bodySmall = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 11,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  // Label — pulsanti, chip, campi interattivi.
  static const TextStyle labelLarge = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle labelMedium = TextStyle(
    fontFamily: AppFonts.sans,
    fontSize: 11.5,
    fontWeight: FontWeight.w500,
  );

  /// Intestazione di sezione: mono, maiuscolo, spaziato. Applicare
  /// `.toUpperCase()` al testo — lo stile non lo fa da solo.
  static const TextStyle sectionHeader = TextStyle(
    fontFamily: AppFonts.mono,
    fontSize: 10.5,
    fontWeight: FontWeight.w500,
    height: 1,
    letterSpacing: 0.16 * 10.5,
  );

  /// Testo tecnico mono di piccola taglia: badge condizione, celle di
  /// griglia numerica, valori in evidenza su sfondo scuro.
  static const TextStyle monoLabel = TextStyle(
    fontFamily: AppFonts.mono,
    fontSize: 11,
    fontWeight: FontWeight.w500,
  );
}
