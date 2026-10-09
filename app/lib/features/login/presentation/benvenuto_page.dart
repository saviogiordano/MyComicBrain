import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mycomicbrain/core/auth/session_controller.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/features/login/presentation/accesso_ui.dart';
import 'package:mycomicbrain/features/login/presentation/login_hero.dart';

/// Schermata di ingresso con il login reale (#171), variante C del
/// prototipo #170: account in primo piano, "Usa senza account" come link
/// che spiega la Modalità locale prima di confermarla. Con la Modalità
/// locale esaurita (ADR-0005) offre solo le opzioni di accesso.
class BenvenutoPage extends ConsumerWidget {
  const BenvenutoPage({super.key});

  static const List<String> _puntiModalitaLocale = [
    'Puoi fare tutto: scansionare, catalogare, cercare.',
    _puntoSoloDispositivo,
    _puntoAccountDopo,
  ];
  static const _puntoSoloDispositivo =
      'I fumetti restano solo su questo dispositivo: se lo perdi, li perdi.';
  static const _puntoAccountDopo =
      'Puoi creare un account quando vuoi, da Impostazioni, e importarli.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final soloAccesso =
        ref.watch(sessionControllerProvider).ingresso == Ingresso.soloAccesso;
    final controller = ref.read(sessionControllerProvider.notifier);

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, vincoli) => SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: vincoli.maxHeight - AppSpacing.xl * 2,
              ),
              child: IntrinsicHeight(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const LoginHero(),
                        if (soloAccesso) ...[
                          const SizedBox(height: AppSpacing.lg),
                          AppCard(
                            padding: const EdgeInsets.all(AppSpacing.sm + 2),
                            child: Text(
                              'Su questo dispositivo la collezione è già passata a '
                              'un account. Accedi per ritrovarla.',
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (soloAccesso)
                      Column(
                        children: [
                          PulsanteIngresso(
                            etichetta: 'Continua con Apple',
                            stile: StilePulsanteIngresso.apple,
                            icona: const Icon(Icons.apple, size: 20),
                            onPressed: () => eseguiAccesso(
                              context,
                              controller.accediConApple,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs + 2),
                          PulsanteIngresso(
                            etichetta: 'Continua con Google',
                            stile: StilePulsanteIngresso.contorno,
                            onPressed: () => eseguiAccesso(
                              context,
                              controller.accediConGoogle,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs + 2),
                          PulsanteIngresso(
                            etichetta: 'Accedi con email',
                            stile: StilePulsanteIngresso.contorno,
                            onPressed: () =>
                                context.push('/accedi?modo=accedi'),
                          ),
                          PulsanteIngresso(
                            etichetta: 'Crea un account',
                            stile: StilePulsanteIngresso.testo,
                            onPressed: () =>
                                context.push('/accedi?modo=registrati'),
                          ),
                        ],
                      )
                    else
                      Column(
                        children: [
                          PulsanteIngresso(
                            etichetta: 'Crea un account',
                            onPressed: () =>
                                context.push('/accedi?modo=registrati'),
                          ),
                          const SizedBox(height: AppSpacing.xs + 2),
                          PulsanteIngresso(
                            etichetta: 'Accedi',
                            stile: StilePulsanteIngresso.contorno,
                            onPressed: () =>
                                context.push('/accedi?modo=accedi'),
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          TextButton(
                            onPressed: () =>
                                _spiegaModalitaLocale(context, ref),
                            child: const Text('Usa senza account'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _spiegaModalitaLocale(BuildContext context, WidgetRef ref) {
    return showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Usare l'app senza account?",
                style: AppTypography.titleLarge.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final punto in _puntiModalitaLocale)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text(
                    '•  $punto',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              PulsanteIngresso(
                etichetta: 'Continua senza account',
                onPressed: () async {
                  Navigator.of(sheetContext).pop();
                  await ref
                      .read(sessionControllerProvider.notifier)
                      .continuaSenzaAccount();
                },
              ),
              PulsanteIngresso(
                etichetta: 'Indietro',
                stile: StilePulsanteIngresso.testo,
                onPressed: () => Navigator.of(sheetContext).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
