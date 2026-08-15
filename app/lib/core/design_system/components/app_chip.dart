import 'package:flutter/material.dart';

import 'package:mycomicbrain/core/design_system/tokens.dart';

/// Chip selezionabile a pillola: bordo e testo `accent` quando [selected],
/// altrimenti neutro. Usato per filtri, stati e modalità (es. "Tutti / Da
/// leggere / Duplicati").
class AppChip extends StatelessWidget {
  const AppChip({
    required this.label,
    required this.selected,
    this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.accent : AppColors.textSecondary;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.pillRadius,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? AppColors.accentAlpha(0.14) : Colors.transparent,
            borderRadius: AppRadii.pillRadius,
            border: Border.all(color: selected ? AppColors.accent : AppColors.borderStrong),
          ),
          child: Text(label, style: AppTypography.labelMedium.copyWith(color: color)),
        ),
      ),
    );
  }
}
