import 'package:flutter/material.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';

/// Logo, headline e statistiche della schermata di ingresso — condivisi fra
/// `LoginPage` (login fittizio, flag spento) e `BenvenutoPage` (#171).
class LoginHero extends StatelessWidget {
  const LoginHero({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: AppRadii.xsRadius,
              ),
              child: Text(
                'M',
                style: AppTypography.labelLarge.copyWith(
                  fontSize: 13,
                  color: AppColors.onAccent,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs + 2),
            Text(
              'MyComicBrain',
              style: AppTypography.titleMedium.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl + 2),
        Text(
          "Fotografa la\ncopertina.\nAl resto pensa l'app.",
          style: AppTypography.headline.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Riconoscimento della cover, metadati dai database, copie fisiche '
          'e numeri mancanti — in un unico posto.',
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: AppSpacing.lg + 2),
        const Row(
          children: [
            Expanded(
              child: _StatBox(
                value: '~12s',
                label: 'per albo catalogato',
              ),
            ),
            SizedBox(width: AppSpacing.xs),
            Expanded(
              child: _StatBox(
                value: '1 tap',
                label: 'per confermare il match',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.sm + 2),
      borderRadius: AppRadii.lgRadius,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: AppTypography.titleLarge.copyWith(color: AppColors.accent),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}
