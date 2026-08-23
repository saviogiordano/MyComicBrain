import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';

/// Schermata `/scansione/riepilogo` (S-B — Lista con stato, deciso su #20):
/// una riga per Scansione appena confermata, con thumbnail e chip "In
/// sospeso" esplicito su ognuna (il riconoscimento AI, §6.3, è fuori scope
/// di questa mappa, vedi `CONTEXT.md`). Schermata a sé, due azioni:
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
      ref.read(analisiCopertinaPipelineProvider).avviaBatch([for (final s in scansioni) s.path]),
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
              padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, AppSpacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Riepilogo batch', style: AppTypography.titleLarge.copyWith(color: AppColors.textPrimary)),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    '${scansioni.length} ${scansioni.length == 1 ? 'scansione pronta' : 'scansioni pronte'} '
                    'per il riconoscimento AI',
                    style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                itemCount: scansioni.length,
                separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
                itemBuilder: (context, i) => _RigaScansione(indice: i, scansione: scansioni[i]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.lg),
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

class _RigaScansione extends StatelessWidget {
  const _RigaScansione({required this.indice, required this.scansione});

  final int indice;
  final XFile scansione;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          ClipRRect(
            borderRadius: AppRadii.smRadius,
            child: Image.file(File(scansione.path), width: 48, height: 48, fit: BoxFit.cover),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Scansione ${indice + 1}',
              style: AppTypography.titleMedium.copyWith(color: AppColors.textPrimary),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.amberAlpha(0.14),
              borderRadius: AppRadii.pillRadius,
              border: Border.all(color: AppColors.amber),
            ),
            child: Text('In sospeso', style: AppTypography.labelMedium.copyWith(color: AppColors.amber)),
          ),
        ],
      ),
    );
  }
}
