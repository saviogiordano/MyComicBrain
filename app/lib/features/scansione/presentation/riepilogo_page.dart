import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/core/domain/analisi_copertina.dart';

/// Schermata `/scansione/riepilogo` (S-B — Lista con stato, deciso su #20):
/// una riga per Scansione appena confermata, con thumbnail e chip di stato
/// collegata allo stato reale dell'Analisi Copertina (`watchStatoAnalisiCopertina`,
/// "In sospeso"/"In corso"/"Completata"/"Fallita" — il riconoscimento AI,
/// §6.3, è fuori scope di questa mappa, vedi `CONTEXT.md`). Schermata a sé, due azioni:
/// "Aggiungi altre" torna allo scanner con il batch preservato (pop, nessun
/// valore); "Fine" avvia la pipeline di analisi copertina (§6.1, §6.2, #32,
/// #49) per l'intero batch — senza attendere il risultato, vedi
/// `AnalisiCopertinaPipeline` — e naviga davvero a `/dashboard`, non un
/// placeholder.
class RiepilogoPage extends ConsumerWidget {
  const RiepilogoPage({required this.scansioni, super.key});

  final List<XFile> scansioni;

  void _fine(BuildContext context, WidgetRef ref) {
    unawaited(
      ref.read(analisiCopertinaPipelineProvider).avviaBatch([
        for (final s in scansioni) s.path,
      ]),
    );
    context.go('/dashboard');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.surfaceDeepest,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.xs,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Riepilogo batch',
                    style: AppTypography.titleLarge.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    '${scansioni.length} ${scansioni.length == 1 ? 'scansione pronta' : 'scansioni pronte'} '
                    'per il riconoscimento AI',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                itemCount: scansioni.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.xs),
                itemBuilder: (context, i) =>
                    _RigaScansione(indice: i, scansione: scansioni[i]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.lg,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => context.pop(),
                      child: const Text('Aggiungi altre'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _fine(context, ref),
                      child: const Text('Fine'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RigaScansione extends ConsumerWidget {
  const _RigaScansione({required this.indice, required this.scansione});

  final int indice;
  final XFile scansione;

  /// Apre lo schermo di conferma candidato (§6.3, #59) per questa Scansione
  /// — raggiungibile una volta che l'Analisi Copertina è `completata`
  /// (l'Identificazione, agganciata in automatico su #58, è quindi già
  /// stata avviata; lo schermo gestisce da sé l'attesa se non è ancora
  /// `completata`).
  Future<void> _apriConfermaCandidato(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final scansioneId = await ref
        .read(comicsRepositoryProvider)
        .idScansionePerImmagine(scansione.path);
    if (!context.mounted) return;
    unawaited(
      context.push('/scansione/conferma-candidato', extra: scansioneId),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stato = ref
        .watch(statoAnalisiCopertinaProvider(scansione.path))
        .valueOrNull;
    final pronta = stato?.stato == StatoAnalisiCopertina.completata;

    return AppCard(
      onTap: pronta ? () => _apriConfermaCandidato(context, ref) : null,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: AppRadii.smRadius,
            child: Image.file(
              File(scansione.path),
              width: 48,
              height: 48,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Scansione ${indice + 1}',
              style: AppTypography.titleMedium.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
          _ChipStatoAnalisi(
            stato: stato?.stato,
            errorMessage: stato?.errorMessage,
            onRiprova: () => ref
                .read(analisiCopertinaPipelineProvider)
                .riprova(scansione.path),
          ),
        ],
      ),
    );
  }
}

/// La chip di stato del riepilogo, collegata allo stato reale della riga
/// `AnalisiCopertinaTable` (prima era testo statico "In sospeso" a
/// prescindere dall'esito, vedi indagine su segnalazione utente): `null`
/// finché lo stream non ha ancora emesso il primo valore. Da `fallita`, la
/// chip stessa è il tasto di retry manuale (nessun retry automatico, #27) —
/// `errorMessage` compare al tocco prolungato.
class _ChipStatoAnalisi extends StatelessWidget {
  const _ChipStatoAnalisi({
    required this.stato,
    required this.errorMessage,
    required this.onRiprova,
  });

  final StatoAnalisiCopertina? stato;
  final String? errorMessage;
  final VoidCallback onRiprova;

  @override
  Widget build(BuildContext context) {
    final (String label, Color colore) = switch (stato) {
      null || StatoAnalisiCopertina.pending => ('In sospeso', AppColors.amber),
      StatoAnalisiCopertina.inCorso => ('In corso', AppColors.amber),
      StatoAnalisiCopertina.completata => ('Completata', AppColors.accent),
      StatoAnalisiCopertina.fallita => (
        'Fallita · Riprova',
        AppColors.textMuted,
      ),
    };

    final chip = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: colore.withValues(alpha: 0.14),
        borderRadius: AppRadii.pillRadius,
        border: Border.all(color: colore),
      ),
      child: Text(
        label,
        style: AppTypography.labelMedium.copyWith(color: colore),
      ),
    );

    if (stato != StatoAnalisiCopertina.fallita) return chip;

    return Tooltip(
      message: errorMessage ?? 'Motivo del fallimento non disponibile',
      child: InkWell(
        borderRadius: AppRadii.pillRadius,
        onTap: onRiprova,
        child: chip,
      ),
    );
  }
}
