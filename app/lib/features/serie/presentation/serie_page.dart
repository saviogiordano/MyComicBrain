import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/core/domain/serie_lista.dart';

/// Elenco `/serie` (§11, deciso su #97/#98): tre sezioni — Incomplete (per
/// percentuale di completamento crescente), Complete (alfabetico), Senza
/// numero totale (alfabetico) — ciascuna nascosta del tutto se vuota.
/// Righe in densità compatta (titolo + frazione + barra sottile, nessuna
/// riga di didascalia, deciso su #98). Stato vuoto a schermo intero se la
/// collezione non ha nessuna serie (riuso della regola #8/#14).
class SeriePage extends ConsumerWidget {
  const SeriePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listaAsync = ref.watch(serieListaProvider);

    return Scaffold(
      backgroundColor: AppColors.surfaceDeepest,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceDeepest,
        title: const Text('Serie'),
      ),
      body: SafeArea(
        child: listaAsync.when(
          data: (lista) =>
              lista.isEmpty ? const _SerieVuota() : _SerieElenco(lista: lista),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(
                'Non è stato possibile caricare le serie.',
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SerieElenco extends StatelessWidget {
  const _SerieElenco({required this.lista});

  final SerieLista lista;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xxl,
      ),
      children: [
        if (lista.incomplete.isNotEmpty)
          _Sezione(label: 'incomplete', items: lista.incomplete),
        if (lista.complete.isNotEmpty)
          _Sezione(label: 'complete', items: lista.complete),
        if (lista.senzaTotale.isNotEmpty)
          _Sezione(label: 'senza numero totale', items: lista.senzaTotale),
      ],
    );
  }
}

class _Sezione extends StatelessWidget {
  const _Sezione({required this.label, required this.items});

  final String label;
  final List<SerieRiga> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(label: '$label · ${items.length}'),
          const SizedBox(height: AppSpacing.sm),
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.xs),
            _SerieRigaCard(item: items[i]),
          ],
        ],
      ),
    );
  }
}

class _SerieRigaCard extends StatelessWidget {
  const _SerieRigaCard({required this.item});

  final SerieRiga item;

  @override
  Widget build(BuildContext context) {
    final pct = item.percentualeCompletamento;
    return AppCard(
      onTap: () => context.push('/serie/${item.serieId}'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 2,
        vertical: AppSpacing.sm - 3,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            height: 44,
            child: ComicCoverImage(
              coverImage: item.coverImage,
              titolo: item.nome,
              numero: item.serieId,
              etichetta: '',
              compatto: true,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.nome,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                  ),
                ),
                if (pct != null) ...[
                  const SizedBox(height: AppSpacing.xxs + 2),
                  AppProgressBar(
                    value: pct,
                    height: 3,
                    color: pct >= 1 ? AppColors.accentLight : AppColors.accent,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            pct == null
                ? '${item.numeriPosseduti}'
                : '${item.numeriPosseduti}/${item.numeriTotali}',
            style: AppTypography.monoLabel.copyWith(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _SerieVuota extends StatelessWidget {
  const _SerieVuota();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_stories_outlined,
              size: 40,
              color: AppColors.textDisabled,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Nessuna serie in collezione',
              style: AppTypography.titleMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Scansiona la copertina di un fumetto per iniziare a costruire '
              'le tue serie.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: () => context.go('/scansione'),
              child: const Text('Scansiona la prima cover'),
            ),
          ],
        ),
      ),
    );
  }
}
