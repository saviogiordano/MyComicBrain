import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mycomicbrain/core/data/numero_pulito.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/core/domain/edizione_catalogo.dart';
import 'package:mycomicbrain/core/domain/serie_dettaglio.dart';
import 'package:mycomicbrain/features/serie/application/serie_providers.dart';
import 'package:mycomicbrain/features/serie/presentation/modifica_serie_sheet.dart';

/// Dettaglio `/serie/:id` (§11, deciso su #97): header con cover,
/// statistiche derivate, griglia dei numeri posseduti/mancanti (se il
/// numero totale è impostato) o solo l'elenco dei numeri posseduti con un
/// invito a impostarlo (deciso su #99). Modifica di nome/numero totale/
/// issn/cover tramite bottom sheet (`ModificaSerieSheet`, variante B scelta
/// su #99). Toccare un numero posseduto naviga alla Scheda dell'Edizione
/// corrispondente — se più Edizioni condividono lo stesso numero (variant),
/// mostra prima un selettore invece di scegliere in automatico.
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
            return _Corpo(
              serie: s,
              onNumero: (numero) =>
                  _apriNumero(context, ref, s.serieId, numero),
            );
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

class _Corpo extends ConsumerWidget {
  const _Corpo({required this.serie, required this.onNumero});

  final SerieDettaglio serie;
  final void Function(int numero) onNumero;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vistaNumeri = ref.watch(vistaNumeriSerieProvider);
    final edizioniPossedute =
        ref.watch(edizioniPosseduteDiSerieProvider(serie.serieId)).valueOrNull ??
        const [];
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
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 72,
              height: 108,
              child: ComicCoverImage(
                coverImage: serie.coverImage,
                titolo: serie.nome,
                numero: serie.serieId,
                etichetta: '',
                compatto: true,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                ],
              ),
            ),
          ],
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
          _SenzaTotale(
            serie: serie,
            onNumero: onNumero,
            vista: vistaNumeri,
            edizioniPossedute: edizioniPossedute,
          )
        else
          _ConTotale(
            serie: serie,
            onNumero: onNumero,
            vista: vistaNumeri,
            edizioniPossedute: edizioniPossedute,
          ),
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
          Text(
            value,
            style: AppTypography.kpiValue.copyWith(color: valueColor),
          ),
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
  const _SenzaTotale({
    required this.serie,
    required this.onNumero,
    required this.vista,
    required this.edizioniPossedute,
  });

  final SerieDettaglio serie;
  final void Function(int numero) onNumero;
  final VistaNumeriSerie vista;
  final List<EdizioneCatalogo> edizioniPossedute;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          label: 'numeri posseduti',
          trailing: _VistaNumeriToggle(),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (vista == VistaNumeriSerie.numero)
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final cella in _celleGriglia(
                numeri: serie.numeriPosseduti,
                edizioni: edizioniPossedute,
              ))
                if (cella.numero case final n?)
                  AppChip(label: '#$n', selected: true, onTap: () => onNumero(n))
                else
                  AppChip(
                    label: '#${cella.edizioneDecimale!.issueNumberLabel}',
                    selected: true,
                    onTap: () =>
                        _apriEdizione(context, cella.edizioneDecimale!.edizioneId),
                  ),
            ],
          )
        else
          _CoverGrid(
            nomeSerie: serie.nome,
            numeri: serie.numeriPosseduti,
            posseduti: serie.numeriPosseduti.toSet(),
            edizioniPossedute: edizioniPossedute,
            onNumero: onNumero,
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
                onPressed: () =>
                    mostraModificaSerieSheet(context, serie: serie),
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
  const _ConTotale({
    required this.serie,
    required this.onNumero,
    required this.vista,
    required this.edizioniPossedute,
  });

  final SerieDettaglio serie;
  final void Function(int numero) onNumero;
  final VistaNumeriSerie vista;
  final List<EdizioneCatalogo> edizioniPossedute;

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
                SizedBox(width: AppSpacing.sm),
                _VistaNumeriToggle(),
              ],
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (vista == VistaNumeriSerie.numero)
          GridView.count(
            crossAxisCount: 7,
            mainAxisSpacing: AppSpacing.xxs,
            crossAxisSpacing: AppSpacing.xxs,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final cella in _celleGriglia(
                numeri: [for (var n = 1; n <= serie.numeriTotali!; n++) n],
                edizioni: edizioniPossedute,
              ))
                if (cella.numero case final n?)
                  _NumeroCell(
                    numero: n,
                    posseduto: posseduti.contains(n),
                    onTap: posseduti.contains(n) ? () => onNumero(n) : null,
                  )
                else
                  _NumeroCell(
                    numero: cella.edizioneDecimale!.issueNumber ?? 0,
                    etichetta: cella.edizioneDecimale!.issueNumberLabel,
                    posseduto: true,
                    onTap: () => _apriEdizione(
                      context,
                      cella.edizioneDecimale!.edizioneId,
                    ),
                  ),
            ],
          )
        else
          _CoverGrid(
            nomeSerie: serie.nome,
            numeri: [for (var n = 1; n <= serie.numeriTotali!; n++) n],
            posseduti: posseduti,
            edizioniPossedute: edizioniPossedute,
            onNumero: onNumero,
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
                const Icon(
                  Icons.check_circle,
                  color: AppColors.accentLight,
                  size: 18,
                ),
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
  const _NumeroCell({
    required this.numero,
    required this.posseduto,
    required this.onTap,
    String? etichetta,
  }) : etichetta = etichetta ?? '$numero';

  final int numero;
  final bool posseduto;

  /// L'etichetta mostrata nella cella — `'$numero'` di default, oppure
  /// l'etichetta completa (es. `"699.1"`) per la cella propria di
  /// un'Edizione con numero decimale (vedi [_celleGriglia]).
  final String etichetta;

  /// Null per i numeri mancanti — nessuna Edizione a cui navigare.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.xsRadius,
        child: Container(
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
            etichetta,
            style: AppTypography.monoLabel.copyWith(
              color: posseduto ? AppColors.accentLight : AppColors.amber,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }
}

/// Il pill-toggle "solo numero" (default) / "cover con numero sotto" dei
/// numeri posseduti nel dettaglio Serie.
class _VistaNumeriToggle extends ConsumerWidget {
  const _VistaNumeriToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vista = ref.watch(vistaNumeriSerieProvider);
    final notifier = ref.read(vistaNumeriSerieProvider.notifier);

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.overlayCard,
        borderRadius: AppRadii.pillRadius,
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _VistaNumeriSegment(
            icon: Icons.tag,
            selected: vista == VistaNumeriSerie.numero,
            onTap: () => notifier.imposta(VistaNumeriSerie.numero),
          ),
          _VistaNumeriSegment(
            icon: Icons.grid_view_rounded,
            selected: vista == VistaNumeriSerie.cover,
            onTap: () => notifier.imposta(VistaNumeriSerie.cover),
          ),
        ],
      ),
    );
  }
}

class _VistaNumeriSegment extends StatelessWidget {
  const _VistaNumeriSegment({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.pillRadius,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.xxs + 2),
          decoration: BoxDecoration(
            color: selected ? AppColors.accent : Colors.transparent,
            borderRadius: AppRadii.pillRadius,
          ),
          child: Icon(
            icon,
            size: 15,
            color: selected ? AppColors.onAccent : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}

/// La vista "cover con numero sotto" dei numeri posseduti (§11) — risolve
/// la copertina di ciascun numero dalle Edizioni possedute della serie
/// (passate da [_Corpo] via [edizioniPosseduteDiSerieProvider]); i numeri
/// senza Edizione (mancanti in [_ConTotale]) ricadono sul segnaposto
/// procedurale di [ComicCoverImage], come nel resto dell'app.
class _CoverGrid extends StatelessWidget {
  const _CoverGrid({
    required this.nomeSerie,
    required this.numeri,
    required this.posseduti,
    required this.edizioniPossedute,
    required this.onNumero,
  });

  final String nomeSerie;
  final List<int> numeri;
  final Set<int> posseduti;
  final List<EdizioneCatalogo> edizioniPossedute;
  final void Function(int numero) onNumero;

  @override
  Widget build(BuildContext context) {
    final coverPerNumero = <int, EdizioneCatalogo>{};
    for (final e in edizioniPossedute) {
      final numero = e.issueNumber;
      if (numero != null) coverPerNumero.putIfAbsent(numero, () => e);
    }

    return GridView.count(
      crossAxisCount: 4,
      mainAxisSpacing: AppSpacing.sm,
      crossAxisSpacing: AppSpacing.xs,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 0.62,
      children: [
        for (final cella in _celleGriglia(
          numeri: numeri,
          edizioni: edizioniPossedute,
        ))
          if (cella.numero case final n?)
            _NumeroCoverCell(
              numero: n,
              posseduto: posseduti.contains(n),
              coverImage: coverPerNumero[n]?.coverImage,
              titolo: coverPerNumero[n]?.title ?? nomeSerie,
              onTap: posseduti.contains(n) ? () => onNumero(n) : null,
            )
          else
            _NumeroCoverCell(
              numero: cella.edizioneDecimale!.issueNumber ?? 0,
              etichetta: cella.edizioneDecimale!.issueNumberLabel,
              posseduto: true,
              coverImage: cella.edizioneDecimale!.coverImage,
              titolo: cella.edizioneDecimale!.title,
              onTap: () =>
                  _apriEdizione(context, cella.edizioneDecimale!.edizioneId),
            ),
      ],
    );
  }
}

class _NumeroCoverCell extends StatelessWidget {
  const _NumeroCoverCell({
    required this.numero,
    required this.posseduto,
    required this.coverImage,
    required this.titolo,
    required this.onTap,
    String? etichetta,
  }) : etichetta = etichetta ?? '$numero';

  final int numero;
  final bool posseduto;
  final String? coverImage;
  final String titolo;

  /// L'etichetta mostrata — `'$numero'` di default, oppure l'etichetta
  /// completa (es. `"699.1"`) per la cella propria di un'Edizione con
  /// numero decimale (vedi [_celleGriglia]).
  final String etichetta;

  /// Null per i numeri mancanti — nessuna Edizione a cui navigare.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.xsRadius,
        child: Column(
          children: [
            Expanded(
              child: Opacity(
                opacity: posseduto ? 1 : 0.4,
                child: ComicCoverImage(
                  coverImage: coverImage,
                  titolo: titolo,
                  numero: numero,
                  etichetta: '#$etichetta',
                  compatto: true,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              etichetta,
              style: AppTypography.monoLabel.copyWith(
                color: posseduto ? AppColors.accentLight : AppColors.amber,
                fontSize: 11,
              ),
            ),
          ],
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

/// Tap su una cella decimale (es. "699.1") della griglia — l'Edizione è già
/// risolta da [_celleGriglia], nessun selettore necessario a differenza di
/// [_apriNumero].
void _apriEdizione(BuildContext context, int edizioneId) {
  unawaited(context.push('/scheda/$edizioneId'));
}

/// Una cella della griglia/elenco dei numeri posseduti (§11): un numero
/// intero della sequenza (posseduto o mancante), oppure — per un'Edizione
/// con etichetta decimale come "699.1" — una cella propria inserita fra
/// l'intero precedente e successivo invece di fondersi in quello come una
/// variant di copertina (richiesta utente: un "point one" è un albo a sé,
/// non una variant del numero intero — vedi [numeroDecimale]).
class _CellaGriglia {
  const _CellaGriglia.intera(int numero)
    : numero = numero,
      posizione = numero * 1.0,
      edizioneDecimale = null;

  const _CellaGriglia.decimale(this.posizione, EdizioneCatalogo edizione)
    : numero = null,
      edizioneDecimale = edizione;

  /// La chiave di ordinamento nella sequenza — l'intero stesso per una
  /// cella intera, il numero decimale completo (`699.1`) per una cella
  /// decimale, così finisce sempre subito dopo il suo intero e prima del
  /// successivo.
  final double posizione;

  /// Non null per una cella intera.
  final int? numero;

  /// Non null per una cella decimale.
  final EdizioneCatalogo? edizioneDecimale;
}

/// Costruisce e ordina le celle di [numeri] (la sequenza base di interi,
/// posseduti o mancanti) più una cella propria per ogni Edizione di
/// [edizioni] con un'etichetta decimale (vedi [numeroDecimale]) — usata sia
/// dalla vista "solo numero" sia da quella "cover" del dettaglio Serie.
List<_CellaGriglia> _celleGriglia({
  required List<int> numeri,
  required List<EdizioneCatalogo> edizioni,
}) {
  final celle = [for (final n in numeri) _CellaGriglia.intera(n)];
  for (final edizione in edizioni) {
    final posizione = numeroDecimale(edizione.issueNumberLabel);
    if (posizione != null) {
      celle.add(_CellaGriglia.decimale(posizione, edizione));
    }
  }
  celle.sort((a, b) => a.posizione.compareTo(b.posizione));
  return celle;
}

/// Tap su un numero posseduto: naviga diretto alla Scheda se una sola
/// Edizione lo copre, altrimenti mostra un selettore — più Edizioni possono
/// condividere lo stesso `issueNumber` (variant, es. "4 Variant" copre il
/// buco del numero 4, CONTEXT.md).
Future<void> _apriNumero(
  BuildContext context,
  WidgetRef ref,
  int serieId,
  int numero,
) async {
  final edizioni = await ref
      .read(comicsRepositoryProvider)
      .edizioniPosseduteDiSerie(serieId);
  final corrispondenti = edizioni
      .where((e) => e.issueNumber == numero)
      .toList();
  if (!context.mounted || corrispondenti.isEmpty) return;

  if (corrispondenti.length == 1) {
    unawaited(context.push('/scheda/${corrispondenti.first.edizioneId}'));
    return;
  }

  final scelta = await showModalBottomSheet<EdizioneCatalogo>(
    context: context,
    backgroundColor: AppColors.surfaceRaised,
    builder: (context) => _SceltaEdizioneSheet(edizioni: corrispondenti),
  );
  if (scelta != null && context.mounted) {
    unawaited(context.push('/scheda/${scelta.edizioneId}'));
  }
}

/// Selettore mostrato quando più Edizioni condividono lo stesso numero —
/// vedi [_apriNumero].
class _SceltaEdizioneSheet extends StatelessWidget {
  const _SceltaEdizioneSheet({required this.edizioni});

  final List<EdizioneCatalogo> edizioni;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              label: 'più edizioni per il #${edizioni.first.issueNumber}',
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final e in edizioni)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: AppCard(
                  onTap: () => Navigator.of(context).pop(e),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 40,
                        height: 60,
                        child: ComicCoverImage(
                          coverImage: e.coverImage,
                          titolo: e.title,
                          numero: e.issueNumber ?? 0,
                          etichetta: e.issueNumberLabel ?? '',
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
                              e.issueNumberLabel ?? '#${e.issueNumber}',
                              style: AppTypography.titleMedium.copyWith(
                                color: AppColors.textPrimary,
                              ),
                            ),
                            if (e.publisher != null)
                              Text(
                                e.publisher!,
                                style: AppTypography.bodySmall.copyWith(
                                  color: AppColors.textTertiary,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
