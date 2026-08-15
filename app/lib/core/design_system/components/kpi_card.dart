import 'package:flutter/material.dart';

import 'package:mycomicbrain/core/design_system/components/app_card.dart';
import 'package:mycomicbrain/core/design_system/tokens.dart';

/// Card KPI: un valore in grande evidenza e la sua etichetta. Il colore
/// del valore è il canale semantico — testo primario per un conteggio
/// neutro, [AppColors.amber] per richiamare attenzione (es. duplicati,
/// numeri mancanti), [AppColors.accent] per una variazione positiva.
class KpiCard extends StatelessWidget {
  const KpiCard({
    required this.value,
    required this.label,
    this.valueColor = AppColors.textPrimary,
    this.onTap,
    super.key,
  });

  final String value;
  final String label;
  final Color valueColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: AppTypography.kpiValue.copyWith(color: valueColor)),
          const SizedBox(height: 6),
          Text(
            label,
            style: AppTypography.bodySmall.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}
