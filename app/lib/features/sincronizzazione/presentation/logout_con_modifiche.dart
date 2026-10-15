import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/data/registro_modifiche.dart';
import 'package:mycomicbrain/core/data/sincronizzazione/motore_sincronizzazione.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/features/sincronizzazione/application/sincronizzazione_providers.dart';

/// Chiede conferma del logout (prototipo #201, punto 6, variante A): il
/// dialog semplice senza Modifiche in sospeso, altrimenti "Modifiche non
/// sincronizzate" con "Sincronizza e esci", "Esci comunque" (con una
/// seconda conferma) e "Annulla". Restituisce true se si può uscire.
Future<bool> confermaLogout(BuildContext context, WidgetRef ref) async {
  final inSospeso = await ref.read(modificheInSospesoProvider.future);
  if (!context.mounted) return false;
  if (inSospeso == 0) {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text("Uscire dall'account?"),
            content: const Text(
              'La collezione resta nel tuo account. Da questo telefono verrà '
              'tolta e la ritroverai al prossimo accesso.',
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
        ) ??
        false;
  }
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const DialogModificheNonSincronizzate(),
      ) ??
      false;
}

/// "Modifiche non sincronizzate": la collezione viene tolta dal telefono
/// al logout, quindi le Modifiche in sospeso (Scansioni in attesa di rete
/// comprese) andrebbero perse.
class DialogModificheNonSincronizzate extends ConsumerStatefulWidget {
  const DialogModificheNonSincronizzate({super.key});

  @override
  ConsumerState<DialogModificheNonSincronizzate> createState() =>
      _DialogModificheNonSincronizzateState();
}

class _DialogModificheNonSincronizzateState
    extends ConsumerState<DialogModificheNonSincronizzate> {
  var _sincronizzo = false;
  var _fallita = false;

  Future<void> _sincronizzaEEsci() async {
    final motore = ref.read(motoreSincronizzazioneProvider);
    if (motore == null) return;
    setState(() {
      _sincronizzo = true;
      _fallita = false;
    });
    final esito = await motore.sincronizzaOra();
    if (!mounted) return;
    // Esce solo se sul telefono non resta nulla: una scrittura fatta
    // durante il ciclo, o un'operazione rifiutata, resterebbe in sospeso.
    final db = ref.read(replicaDelProfiloProvider);
    final restano = db == null ? 0 : await RegistroModifiche(db).conteggio();
    if (!mounted) return;
    if (esito is SincronizzazioneRiuscita && restano == 0) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _sincronizzo = false;
      _fallita = true;
    });
  }

  Future<void> _esciComunque(int inSospeso, int scansioni) async {
    final conferma = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.error_outline, color: AppColors.dangerLight),
        title: Text(
          inSospeso == 1
              ? 'Eliminare 1 modifica?'
              : 'Eliminare $inSospeso modifiche?',
        ),
        content: Text(
          'Non sono ancora nel tuo account e non si possono recuperare.'
          '${scansioni > 0 ? ' Anche le scansioni in attesa di rete '
                    'andranno perse.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: AppColors.textPrimary,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Esci e perdi le modifiche'),
          ),
        ],
      ),
    );
    if (conferma == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final inSospeso = ref.watch(modificheInSospesoProvider).valueOrNull ?? 0;
    final scansioni = ref.watch(scansioniInAttesaProvider).valueOrNull?.length;
    final offline =
        ref.watch(statoSincronizzazioneProvider).valueOrNull?.fase ==
        FaseSincronizzazione.offline;
    final nota = AppTypography.bodySmall.copyWith(
      color: AppColors.textTertiary,
    );

    return AlertDialog(
      title: const Text('Modifiche non sincronizzate'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            inSospeso == 1
                ? '1 modifica non è ancora stata sincronizzata. Uscendo '
                      'verrebbe persa, perché la collezione viene tolta da '
                      'questo telefono.'
                : '$inSospeso modifiche non sono ancora state sincronizzate. '
                      'Uscendo verrebbero perse, perché la collezione viene '
                      'tolta da questo telefono.',
          ),
          if (_fallita) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.12),
                borderRadius: AppRadii.smRadius,
              ),
              child: Text(
                'La sincronizzazione non è riuscita. Le modifiche sono ancora '
                'su questo telefono.',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.dangerLight,
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: offline || _sincronizzo ? null : _sincronizzaEEsci,
            child: Text(_sincronizzo ? 'Sincronizzo…' : 'Sincronizza e esci'),
          ),
          if (offline) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text('Sei offline: collegati per sincronizzare.', style: nota),
          ],
          const SizedBox(height: AppSpacing.xs),
          OutlinedButton(
            onPressed: _sincronizzo
                ? null
                : () => _esciComunque(inSospeso, scansioni ?? 0),
            child: const Text('Esci comunque'),
          ),
          const SizedBox(height: AppSpacing.xs),
          TextButton(
            onPressed: _sincronizzo
                ? null
                : () => Navigator.of(context).pop(false),
            child: const Text('Annulla'),
          ),
        ],
      ),
    );
  }
}
