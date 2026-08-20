import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';

/// Schermata `/scansione/revisione` (R-A, deciso su #20): processa in coda i
/// percorsi grezzi appena scattati/selezionati, uno alla volta, aprendo per
/// ognuno l'editor di ritaglio/rotazione nativo di `image_cropper` (#17) —
/// riquadro ad angoli trascinabili direttamente sopra la foto, nessuna
/// anteprima separata, rotazione nella UI nativa stessa.
///
/// "Conferma" nell'editor crea la Scansione (persistenza da #21) e passa
/// alla foto successiva; annullare l'editor equivale a "Riscatta" — nessuna
/// Scansione creata (Q6 del grilling su #15) — e si passa comunque alla
/// successiva. Con la coda esaurita, torna allo scanner con le foto
/// confermate.
class RevisionePage extends ConsumerStatefulWidget {
  const RevisionePage({required this.percorsiGrezzi, super.key});

  final List<String> percorsiGrezzi;

  @override
  ConsumerState<RevisionePage> createState() => _RevisionePageState();
}

class _RevisionePageState extends ConsumerState<RevisionePage> {
  // L'editor di ritaglio è un'interazione nativa a tutto schermo (#20): il
  // timeout resta generoso per non interrompere l'utente mentre decide,
  // ed è solo una rete di sicurezza per il caso in cui il platform channel
  // non risponda più. Salvataggio e persistenza sono I/O locale, quindi un
  // blocco lì indica un problema reale, non un utente lento.
  static const _timeoutRitaglio = Duration(minutes: 5);
  static const _timeoutOperazione = Duration(seconds: 15);

  int _indice = 0;
  final _confermate = <XFile>[];
  Object? _errore;

  @override
  void initState() {
    super.initState();
    unawaited(_processaProssima());
  }

  /// #36: le chiamate awaited (editor di ritaglio, salvataggio, persistenza)
  /// erano prive di try/catch — un'eccezione qui lasciava lo spinner bloccato
  /// per sempre, senza UI di errore né timeout. Ora un fallimento espone uno
  /// stato di errore visibile (build) con "Riprova"/"Salta questa foto".
  Future<void> _processaProssima() async {
    if (_indice >= widget.percorsiGrezzi.length) {
      if (mounted) context.pop(_confermate);
      return;
    }

    if (mounted) setState(() => _errore = null);

    final grezzo = widget.percorsiGrezzi[_indice];
    try {
      final ritagliato = await ref
          .read(imageCropServiceProvider)
          .ritagliaFoto(grezzo)
          .timeout(_timeoutRitaglio);

      if (ritagliato != null) {
        final salvato = await ref
            .read(scansioneStorageProvider)
            .salva(File(ritagliato))
            .timeout(_timeoutOperazione);
        await ref
            .read(comicsRepositoryProvider)
            .aggiungiScansione(image: salvato.path)
            .timeout(_timeoutOperazione);
        _confermate.add(XFile(salvato.path));
      }
    } on Exception catch (e) {
      if (mounted) setState(() => _errore = e);
      return;
    }

    await _eliminaGrezzoBestEffort(grezzo);

    if (!mounted) return;
    setState(() => _indice++);
    await _processaProssima();
  }

  /// Abbandona la foto corrente dopo un errore (#36) e passa alla successiva,
  /// ripulendo il grezzo come nel percorso senza errori.
  Future<void> _saltaCorrente() async {
    await _eliminaGrezzoBestEffort(widget.percorsiGrezzi[_indice]);
    if (!mounted) return;
    setState(() {
      _errore = null;
      _indice++;
    });
    await _processaProssima();
  }

  Future<void> _eliminaGrezzoBestEffort(String path) async {
    try {
      await File(path).delete();
    } on FileSystemException {
      // Best-effort: il grezzo pre-ritaglio non ripulito non blocca il flusso.
    }
  }

  @override
  Widget build(BuildContext context) {
    final totale = widget.percorsiGrezzi.length;
    final errore = _errore;
    return Scaffold(
      backgroundColor: AppColors.surfaceDeepest,
      body: Center(
        child: errore != null
            ? _ErroreRevisione(onRiprova: _processaProssima, onSalta: _saltaCorrente)
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: AppColors.accent),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    totale > 1 ? 'Foto ${(_indice + 1).clamp(1, totale)} di $totale' : 'Apertura editor…',
                    style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ErroreRevisione extends StatelessWidget {
  const _ErroreRevisione({required this.onRiprova, required this.onSalta});

  final VoidCallback onRiprova;
  final VoidCallback onSalta;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 32, color: AppColors.textDisabled),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Elaborazione non riuscita',
            style: AppTypography.bodyMedium.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 2),
          Text(
            'Puoi riprovare o saltare questa foto',
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(onPressed: onRiprova, child: const Text('Riprova')),
          const SizedBox(height: AppSpacing.xs),
          TextButton(onPressed: onSalta, child: const Text('Salta questa foto')),
        ],
      ),
    );
  }
}
