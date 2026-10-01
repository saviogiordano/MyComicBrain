import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/core/routing/session.dart';
import 'package:mycomicbrain/features/login/presentation/login_hero.dart';

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
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const LoginHero(),
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: enter,
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: AppRadii.lgRadius,
                        ),
                      ),
                      child: const Text('Entra nella collezione'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs + 2),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton(
                      onPressed: enter,
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: AppRadii.lgRadius,
                        ),
                      ),
                      child: const Text('Crea un account'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs + 2),
                  Text(
                    'Le foto vengono analizzate solo dopo il tuo consenso e puoi '
                    'eliminarle in qualsiasi momento.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textDisabled,
                    ),
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
