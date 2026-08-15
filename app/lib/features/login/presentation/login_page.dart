import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/core/routing/session.dart';

/// Schermata di ingresso — sola UI, nessuna autenticazione: entrambi i
/// pulsanti fanno passare la sessione a "dentro l'app" (vedi
/// [SessionNotifier.enter]). Content e gerarchia dal prototipo
/// (`app-design/Catalogo Fumetti.dc.html`, righe 47-75).
class LoginPage extends ConsumerWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void enter() => ref.read(sessionProvider.notifier).enter();

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: AppColors.accent, borderRadius: AppRadii.xsRadius),
                        child: Text(
                          'S',
                          style: AppTypography.labelLarge.copyWith(fontSize: 13, color: AppColors.onAccent),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs + 2),
                      Text('Scaffale', style: AppTypography.titleMedium.copyWith(color: AppColors.textPrimary)),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl + 2),
                  Text(
                    "Fotografa la\ncopertina.\nAl resto pensa l'app.",
                    style: AppTypography.headline.copyWith(color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Riconoscimento della cover, metadati dai database, copie fisiche '
                    'e numeri mancanti — in un unico posto.',
                    style: AppTypography.bodyMedium.copyWith(color: AppColors.textTertiary),
                  ),
                  const SizedBox(height: AppSpacing.lg + 2),
                  const Row(
                    children: [
                      Expanded(child: _StatBox(value: '~12s', label: 'per albo catalogato')),
                      SizedBox(width: AppSpacing.xs),
                      Expanded(child: _StatBox(value: '1 tap', label: 'per confermare il match')),
                    ],
                  ),
                ],
              ),
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: enter,
                      style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: AppRadii.lgRadius)),
                      child: const Text('Entra nella collezione'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs + 2),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton(
                      onPressed: enter,
                      style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: AppRadii.lgRadius)),
                      child: const Text('Crea un account'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs + 2),
                  Text(
                    'Le foto vengono analizzate solo dopo il tuo consenso e puoi '
                    'eliminarle in qualsiasi momento.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySmall.copyWith(color: AppColors.textDisabled),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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
          Text(value, style: AppTypography.titleLarge.copyWith(color: AppColors.accent)),
          const SizedBox(height: 3),
          Text(label, style: AppTypography.bodySmall.copyWith(color: AppColors.textTertiary)),
        ],
      ),
    );
  }
}
