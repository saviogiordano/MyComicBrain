import 'package:flutter/material.dart';

import 'package:mycomicbrain/core/design_system/tokens.dart';

/// Intestazione di sezione: mono, maiuscolo, spaziato — il pattern usato
/// per introdurre un blocco della schermata (es. "LA TUA COLLEZIONE",
/// "SCANSIONI IN CODA"). [label] non va passato già maiuscolo: lo stile
/// applica `.toUpperCase()`.
class SectionHeader extends StatelessWidget {
  const SectionHeader({required this.label, this.trailing, super.key});

  final String label;

  /// Contenuto opzionale allineato a destra (es. "2 in elaborazione").
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final title = Text(
      label.toUpperCase(),
      style: AppTypography.sectionHeader.copyWith(color: AppColors.textMuted),
    );

    if (trailing == null) return title;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [title, trailing!],
    );
  }
}
