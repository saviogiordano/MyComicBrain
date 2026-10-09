import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mycomicbrain/core/auth/auth_gateway.dart';
import 'package:mycomicbrain/core/auth/session_controller.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/features/login/presentation/accesso_ui.dart';

/// Eliminazione dell'account dall'app (App Store 5.1.1(v), #172; schermata
/// decisa sul prototipo #170): conseguenze elencate e spunta "Ho capito"
/// prima che il pulsante si attivi. A eliminazione riuscita il Profilo
/// torna `null` e il router porta al benvenuto.
class EliminaAccountPage extends ConsumerStatefulWidget {
  const EliminaAccountPage({super.key});

  @override
  ConsumerState<EliminaAccountPage> createState() => _EliminaAccountPageState();
}

class _EliminaAccountPageState extends ConsumerState<EliminaAccountPage> {
  bool _capito = false;
  bool _inCorso = false;

  static String _messaggioErrore(AuthErrore errore) => switch (errore) {
    AuthErrore.rete ||
    AuthErrore.proprietarioConCollaboratori => messaggioErroreAccesso(errore),
    _ => "Non è stato possibile eliminare l'account. Riprova.",
  };

  Future<void> _elimina() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _inCorso = true);
    try {
      await ref.read(sessionControllerProvider.notifier).eliminaAccount();
      messenger.showSnackBar(
        const SnackBar(content: Text('Account eliminato')),
      );
    } on AuthException catch (e) {
      if (e.errore != AuthErrore.annullato) {
        messenger.showSnackBar(
          SnackBar(content: Text(_messaggioErrore(e.errore))),
        );
      }
      if (mounted) setState(() => _inCorso = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profilo = ref.watch(sessionControllerProvider).profilo;
    final testo = AppTypography.bodyMedium.copyWith(
      color: AppColors.textTertiary,
    );
    final conseguenze = [
      'La collezione con tutti i fumetti verrà eliminata.',
      'Le scansioni e le immagini delle cover verranno eliminate.',
      "La conversazione con l'Assistente verrà eliminata.",
      if (profilo?.metodo == MetodoAccesso.apple)
        "Revocheremo anche l'accesso con Apple.",
      "L'operazione non si può annullare.",
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Elimina account')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView(
                  children: [
                    Text.rich(
                      TextSpan(
                        text: "Stai per eliminare l'account ",
                        children: [
                          TextSpan(
                            text: profilo?.email ?? '',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const TextSpan(text: '.'),
                        ],
                      ),
                      style: testo,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    for (final conseguenza in conseguenze)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('•  ', style: testo),
                            Expanded(child: Text(conseguenza, style: testo)),
                          ],
                        ),
                      ),
                    const SizedBox(height: AppSpacing.md),
                    CheckboxListTile(
                      value: _capito,
                      onChanged: _inCorso
                          ? null
                          : (valore) => setState(() => _capito = valore!),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Ho capito che la collezione verrà eliminata '
                        'definitivamente.',
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _capito && !_inCorso ? _elimina : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.amberStrong,
                    foregroundColor: AppColors.textPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadii.lgRadius,
                    ),
                  ),
                  child: Text(
                    _inCorso
                        ? 'Eliminazione in corso…'
                        : 'Elimina definitivamente',
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              PulsanteIngresso(
                etichetta: 'Annulla',
                stile: StilePulsanteIngresso.testo,
                onPressed: _inCorso ? null : () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
