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
  int _indice = 0;
  final _confermate = <XFile>[];

  @override
  void initState() {
    super.initState();
    unawaited(_processaProssima());
  }

  Future<void> _processaProssima() async {
    if (_indice >= widget.percorsiGrezzi.length) {
      if (mounted) context.pop(_confermate);
      return;
    }

    final grezzo = widget.percorsiGrezzi[_indice];
    final ritagliato = await ref.read(imageCropServiceProvider).ritagliaFoto(grezzo);

    if (ritagliato != null) {
      final salvato = await ref.read(scansioneStorageProvider).salva(File(ritagliato));
      await ref.read(comicsRepositoryProvider).aggiungiScansione(image: salvato.path);
      _confermate.add(XFile(salvato.path));
    }
    await _eliminaGrezzoBestEffort(grezzo);

    if (!mounted) return;
    setState(() => _indice++);
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
    return Scaffold(
      backgroundColor: AppColors.surfaceDeepest,
      body: Center(
        child: Column(
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
