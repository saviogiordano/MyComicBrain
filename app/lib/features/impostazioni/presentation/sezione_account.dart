import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mycomicbrain/core/auth/auth_gateway.dart';
import 'package:mycomicbrain/core/auth/session_controller.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/features/login/presentation/accesso_ui.dart';

/// Sezione "Account", prima di Impostazioni (#171, prototipo #170): tre
/// stati — Modalità locale, email in attesa di conferma, Profilo
/// autenticato con "Esci" ed "Elimina account" (#172).
class SezioneAccount extends ConsumerWidget {
  const SezioneAccount({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessione = ref.watch(sessionControllerProvider);
    final profilo = sessione.profilo;
    final emailInAttesa = sessione.emailInAttesa;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(label: 'Account'),
        const SizedBox(height: AppSpacing.sm),
        if (profilo != null)
          _Autenticato(profilo: profilo)
        else if (emailInAttesa != null)
          _EmailInAttesa(email: emailInAttesa)
        else
          const _ModalitaLocale(),
      ],
    );
  }
}

TextStyle get _titolo =>
    AppTypography.titleMedium.copyWith(color: AppColors.textPrimary);
TextStyle get _testo =>
    AppTypography.bodySmall.copyWith(color: AppColors.textTertiary);

class _ModalitaLocale extends StatelessWidget {
  const _ModalitaLocale();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Modalità locale', style: _titolo),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'I tuoi fumetti sono salvati solo su questo dispositivo. Crea un '
            'account per ritrovarli ovunque: al primo accesso ti chiederemo '
            'se importarli.',
            style: _testo,
          ),
          const SizedBox(height: AppSpacing.sm),
          PulsanteIngresso(
            etichetta: 'Crea account o accedi',
            onPressed: () => context.push('/accedi?modo=registrati'),
          ),
        ],
      ),
    );
  }
}

class _EmailInAttesa extends ConsumerWidget {
  const _EmailInAttesa({required this.email});

  final String email;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(sessionControllerProvider.notifier);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Conferma la tua email', style: _titolo),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Abbiamo inviato un link a $email. Aprilo da questo dispositivo; '
            'nel frattempo continui in Modalità locale.',
            style: _testo,
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              OutlinedButton(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final inviato = await eseguiAccesso(
                    context,
                    controller.reinviaConferma,
                  );
                  if (inviato) {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Nuovo link inviato.')),
                    );
                  }
                },
                child: const Text('Reinvia'),
              ),
              const SizedBox(width: AppSpacing.xs),
              TextButton(
                onPressed: controller.annullaEmailInAttesa,
                child: const Text('Cambia email'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Autenticato extends ConsumerWidget {
  const _Autenticato({required this.profilo});

  final Profilo profilo;

  static String _metodo(MetodoAccesso metodo) => switch (metodo) {
    MetodoAccesso.apple => 'Apple',
    MetodoAccesso.google => 'Google',
    MetodoAccesso.email => 'email e password',
  };

  Future<void> _esci(BuildContext context, WidgetRef ref) async {
    final conferma = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Uscire dall'account?"),
        content: const Text(
          'La collezione resta nel tuo account: la ritrovi quando accedi di '
          'nuovo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Esci'),
          ),
        ],
      ),
    );
    if (conferma != true || !context.mounted) return;
    await eseguiAccesso(
      context,
      ref.read(sessionControllerProvider.notifier).esci,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 21,
                  backgroundColor: AppColors.accentAlpha(0.18),
                  child: Text(
                    profilo.email.isEmpty
                        ? '?'
                        : profilo.email[0].toUpperCase(),
                    style: AppTypography.titleMedium.copyWith(
                      color: AppColors.accent,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profilo.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodyLarge.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        'Accesso con ${_metodo(profilo.metodo)}',
                        style: _testo,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.borderSubtle),
          _Riga(
            etichetta: 'Esci',
            colore: AppColors.textPrimary,
            onTap: () => _esci(context, ref),
          ),
          const Divider(height: 1, color: AppColors.borderSubtle),
          _Riga(
            etichetta: 'Elimina account',
            colore: AppColors.amberStrong,
            onTap: () => context.push('/account/elimina'),
          ),
        ],
      ),
    );
  }
}

class _Riga extends StatelessWidget {
  const _Riga({
    required this.etichetta,
    required this.colore,
    required this.onTap,
  });

  final String etichetta;
  final Color colore;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + 2,
        ),
        child: Row(
          children: [
            Text(
              etichetta,
              style: AppTypography.bodyLarge.copyWith(color: colore),
            ),
            const Spacer(),
            Icon(Icons.chevron_right, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}
