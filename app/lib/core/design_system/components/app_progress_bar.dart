import 'package:flutter/material.dart';

import 'package:mycomicbrain/core/design_system/tokens.dart';

/// Barra di progresso lineare: traccia hairline + riempimento pieno.
/// Usata per l'avanzamento di una serie (numeri posseduti / totale).
class AppProgressBar extends StatelessWidget {
  const AppProgressBar({
    required this.value,
    this.color = AppColors.accent,
    this.height = 6,
    super.key,
  }) : assert(value >= 0 && value <= 1, 'value deve essere in [0, 1]');

  /// Frazione completata, in [0, 1].
  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(height / 2);

    return ClipRRect(
      borderRadius: radius,
      child: Container(
        height: height,
        color: AppColors.borderDefault,
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: value,
          child: Container(color: color),
        ),
      ),
    );
  }
}
