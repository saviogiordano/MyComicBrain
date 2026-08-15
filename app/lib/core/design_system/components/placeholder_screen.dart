import 'package:flutter/material.dart';

import 'package:mycomicbrain/core/design_system/tokens.dart';

/// Schermata non ancora implementata, dichiarata come tale — non un
/// dimenticato. Usata dalle rotte della shell di navigazione che non
/// hanno ancora una schermata reale dietro (Collezione, Scansione,
/// Cerca, Statistiche in questa mappa).
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({required this.title, required this.icon, super.key});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: AppColors.textDisabled),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'In arrivo',
                style: AppTypography.titleMedium.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                '$title non è ancora implementata in questa versione.',
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
