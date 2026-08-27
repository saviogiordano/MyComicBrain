import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/core/domain/serie_dettaglio.dart';
import 'package:mycomicbrain/features/serie/presentation/modifica_serie_sheet.dart';

/// Dettaglio `/serie/:id` (§11, deciso su #97): header con statistiche
/// derivate, griglia dei numeri posseduti/mancanti (se il numero totale è
/// impostato) o solo l'elenco dei numeri posseduti con un invito a
/// impostarlo (deciso su #99). Modifica di nome/numero totale/issn tramite
/// bottom sheet (`ModificaSerieSheet`, variante B scelta su #99).
class SerieDettaglioPage extends ConsumerWidget {
  const SerieDettaglioPage({required this.serieId, super.key});

  final int serieId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dettaglioAsync = ref.watch(serieDettaglioProvider(serieId));

    return Scaffold(
      backgroundColor: AppColors.surfaceDeepest,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceDeepest,
        title: const Text('Serie'),
        actions: [
          dettaglioAsync.maybeWhen(
            data: (s) => s == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.xs),
                    child: TextButton.icon(
                      onPressed: () =>
                          mostraModificaSerieSheet(context, serie: s),
                      icon: const Icon(
                        Icons.edit_outlined,
                        color: AppColors.accent,
                        size: 18,
                      ),
                      label: Text(
                        'Modifica',
                        style: AppTypography.labelMedium.copyWith(
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: SafeArea(
        child: dettaglioAsync.when(
          data: (s) {
            if (s == null) {
              return Center(
                child: Text(
                  'Serie non trovata',
                  style: AppTypography.bodyLarge.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
              );
            }
            return _Corpo(serie: s);
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(
                'Non è stato possibile caricare la serie.',
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

class _Corpo extends StatelessWidget {
  const _Corpo({required this.serie});

  final SerieDettaglio serie;

  @override
  Widget build(BuildContext context) {
    final pct = serie.numeriTotali == null
        ? null
        : serie.numeriPosseduti.length / serie.numeriTotali!;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.xxl,
      ),
      children: [
        Text(
          serie.nome,
          style: AppTypography.headline.copyWith(
            color: AppColors.textPrimary,
            fontSize: 24,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          [
            if (serie.publisher != null) serie.publisher!,
            if (serie.annoInizio != null) 'dal ${serie.annoInizio}',
            if (serie.numeriTotali != null)
              '${serie.numeriTotali} numeri usciti',
          ].join(' · '),
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textTertiary,
          ),
        ),
        if (serie.issn != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'ISSN ${serie.issn}',
            style: AppTypography.monoLabel.copyWith(
              color: AppColors.textMuted,
            ),
          ),
        ],
        if (pct != null) ...[
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: AppProgressBar(
                  value: pct,
                  color: serie.completa
                      ? AppColors.accentLight
                      : AppColors.accent,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '${(pct * 100).round()}%',
                style: AppTypography.titleMedium.copyWith(
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: _StatTile(
                value: '${serie.numeriPosseduti.length}',
                label: 'posseduti',
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: _StatTile(
                value: serie.numeriTotali == null
                    ? '—'
                    : '${serie.numeriMancanti.length}',
                label: 'mancanti',
                valueColor: serie.numeriTotali == null
                    ? AppColors.textMuted
                    : AppColors.amber,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: _StatTile(value: '${serie.duplicati}', label: 'duplicati'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (serie.numeriTotali == null)
          _SenzaTotale(serie: serie)
        else
          _ConTotale(serie: serie),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.value,
    required this.label,
    this.valueColor = AppColors.textPrimary,
  });

  final String value;
  final String label;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: AppTypography.kpiValue.copyWith(color: valueColor)),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            label,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Il caso che motiva #99: senza numero totale non esiste una griglia
/// possibile — solo l'elenco dei numeri posseduti e un invito a impostarlo.
class _SenzaTotale extends StatelessWidget {
  const _SenzaTotale({required this.serie});

  final SerieDettaglio serie;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(label: 'numeri posseduti'),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final n in serie.numeriPosseduti)
              AppChip(label: '#$n', selected: true),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm + 2),
          decoration: BoxDecoration(
            color: AppColors.amberAlpha(0.1),
            border: Border.all(color: AppColors.amberAlpha(0.4)),
            borderRadius: AppRadii.lgRadius,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Numero totale non impostato',
                style: AppTypography.titleMedium.copyWith(
                  color: AppColors.amber,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'Senza il numero totale questa serie non può risultare '
                'completa né mostrare i numeri mancanti — imposta il totale '
                'per attivarli.',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              OutlinedButton(
                onPressed: () => mostraModificaSerieSheet(context, serie: serie),
                child: const Text('Imposta numero totale'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ConTotale extends StatelessWidget {
  const _ConTotale({required this.serie});

  final SerieDettaglio serie;

  @override
  Widget build(BuildContext context) {
    final posseduti = serie.numeriPosseduti.toSet();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SectionHeader(label: 'numeri'),
            Row(
              children: [
                _Legenda(color: AppColors.accent, label: 'posseduto'),
                SizedBox(width: AppSpacing.sm),
                _Legenda(color: AppColors.amber, label: 'mancante'),
              ],
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        GridView.count(
          crossAxisCount: 7,
          mainAxisSpacing: AppSpacing.xxs,
          crossAxisSpacing: AppSpacing.xxs,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (var n = 1; n <= serie.numeriTotali!; n++)
              _NumeroCell(numero: n, posseduto: posseduti.contains(n)),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (serie.completa)
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm + 2),
            decoration: BoxDecoration(
              color: AppColors.accentAlpha(0.08),
              border: Border.all(color: AppColors.accentAlpha(0.3)),
              borderRadius: AppRadii.lgRadius,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, color: AppColors.accentLight, size: 18),
                const SizedBox(width: AppSpacing.xxs),
                Text(
                  'Serie completa',
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.accentLight,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm + 2),
            decoration: BoxDecoration(
              color: AppColors.amberAlpha(0.07),
              border: Border.all(color: AppColors.amberAlpha(0.28)),
              borderRadius: AppRadii.lgRadius,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ti mancano ${serie.numeriMancanti.length} numeri',
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.amber,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  _missingLabel(serie.numeriMancanti),
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Legenda extends StatelessWidget {
  const _Legenda({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _NumeroCell extends StatelessWidget {
  const _NumeroCell({required this.numero, required this.posseduto});

  final int numero;
  final bool posseduto;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: posseduto
            ? AppColors.accentAlpha(0.16)
            : AppColors.amberAlpha(0.1),
        border: Border.all(
          color: posseduto
              ? AppColors.accentAlpha(0.3)
              : AppColors.amberAlpha(0.4),
        ),
        borderRadius: AppRadii.xsRadius,
      ),
      child: Text(
        '$numero',
        style: AppTypography.monoLabel.copyWith(
          color: posseduto ? AppColors.accentLight : AppColors.amber,
          fontSize: 11,
        ),
      ),
    );
  }
}

/// Elenca fino a 3 numeri mancanti; oltre, tronca con "e altri N" — stessa
/// regola della sezione "Serie incomplete" della Dashboard (#14).
String _missingLabel(List<int> numeri) {
  const soglia = 3;
  final visibili = numeri.take(soglia).map((n) => '#$n').join(', ');
  if (numeri.length <= soglia) return visibili;
  return '$visibili e altri ${numeri.length - soglia}';
}
