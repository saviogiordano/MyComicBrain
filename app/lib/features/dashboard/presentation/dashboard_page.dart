import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/core/domain/dashboard_kpis.dart';
import 'package:mycomicbrain/features/dashboard/application/dashboard_providers.dart';

const _mesiItaliani = [
  'gennaio',
  'febbraio',
  'marzo',
  'aprile',
  'maggio',
  'giugno',
  'luglio',
  'agosto',
  'settembre',
  'ottobre',
  'novembre',
  'dicembre',
];

/// Testata (§4.1) — etichetta, totale, griglia KPI e CTA di scansione,
/// su dati reali da [dashboardKpisProvider]. Regole di stato vuoto da #8:
/// a collezione zero l'intera schermata collassa a intestazione + CTA
/// ingrandita, niente griglia.
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kpisAsync = ref.watch(dashboardKpisProvider);

    return Scaffold(
      body: SafeArea(
        child: kpisAsync.when(
          data: (kpis) => kpis.totaleCopie == 0
              ? const _EmptyCollection()
              : _Collection(kpis: kpis),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(
                'Non è stato possibile caricare la collezione.',
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

class _Collection extends ConsumerWidget {
  const _Collection({required this.kpis});

  final DashboardKpis kpis;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Errore o caricamento delle due sezioni secondarie non blocca il resto
    // della Dashboard, già renderizzata dai KPI: si comportano come vuote
    // (nascoste, regola #8) finché non arriva un dato.
    final recenti =
        ref.watch(aggiuntiDiRecenteProvider).valueOrNull ?? const [];
    final serieIncomplete =
        ref.watch(serieIncompleteProvider).valueOrNull ?? const [];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(content: _CollectionTotal(total: kpis.totaleCopie)),
          const SizedBox(height: AppSpacing.lg),
          _KpiGrid(kpis: kpis),
          const SizedBox(height: AppSpacing.md),
          const _ScanCta(),
          if (recenti.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            _AggiuntiRecenteSection(items: recenti),
          ],
          if (serieIncomplete.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            _SerieIncompleteSection(items: serieIncomplete),
          ],
        ],
      ),
    );
  }
}

class _EmptyCollection extends StatelessWidget {
  const _EmptyCollection();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(content: _EmptyCollectionMessage()),
          SizedBox(height: AppSpacing.xxl),
          _ScanCta(emphasized: true),
        ],
      ),
    );
  }
}

/// Etichetta "LA TUA COLLEZIONE" + [content] (totale o messaggio a
/// seconda dello stato) a sinistra, pulsante AI a destra.
class _Header extends StatelessWidget {
  const _Header({required this.content});

  final Widget content;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(label: 'la tua collezione'),
              const SizedBox(height: AppSpacing.xs),
              content,
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        _AiButton(onTap: () => context.push('/assistente')),
      ],
    );
  }
}

class _CollectionTotal extends StatelessWidget {
  const _CollectionTotal({required this.total});

  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          _formatItalianInt(total),
          style: AppTypography.heroNumber.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          'fumetti',
          style: AppTypography.bodyLarge.copyWith(
            color: AppColors.textTertiary,
          ),
        ),
      ],
    );
  }
}

class _EmptyCollectionMessage extends StatelessWidget {
  const _EmptyCollectionMessage();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xxs),
      child: Text(
        'È vuota — comincia dalla prima copertina',
        style: AppTypography.bodyLarge.copyWith(color: AppColors.textTertiary),
      ),
    );
  }
}

class _AiButton extends StatelessWidget {
  const _AiButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.mdRadius,
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.borderDefault),
            borderRadius: AppRadii.mdRadius,
          ),
          child: Text(
            'AI',
            style: AppTypography.monoLabel.copyWith(color: AppColors.accent),
          ),
        ),
      ),
    );
  }
}

/// Griglia 3×2 sempre fissa a 6 celle (decisione #8) — ordine e rotte dal
/// prototipo (`kpiDef`, righe 810-819): serie/serie complete/numeri
/// mancanti → `/serie`, duplicati → `/duplicati`, speso finora →
/// `/statistiche`, aggiunti nel mese → `/collezione`.
class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.kpis});

  final DashboardKpis kpis;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      mainAxisSpacing: AppSpacing.xs,
      crossAxisSpacing: AppSpacing.xs,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.1,
      children: _kpiCards(context, kpis),
    );
  }
}

List<Widget> _kpiCards(BuildContext context, DashboardKpis kpis) {
  final meseCorrente = _mesiItaliani[DateTime.now().month - 1];
  final spesoZero = kpis.spesoFinora == 0;

  return [
    _kpiCard(
      value: kpis.numeroSerie,
      label: 'serie',
      tone: _KpiTone.neutral,
      onTap: () => context.push('/serie'),
    ),
    _kpiCard(
      value: kpis.serieComplete,
      label: 'serie complete',
      tone: _KpiTone.neutral,
      onTap: () => context.push('/serie'),
    ),
    _kpiCard(
      value: kpis.duplicati,
      label: 'duplicati',
      tone: _KpiTone.alert,
      onTap: () => context.push('/duplicati'),
    ),
    _kpiCard(
      value: kpis.numeriMancanti,
      label: 'numeri mancanti',
      tone: _KpiTone.alert,
      onTap: () => context.push('/serie'),
    ),
    KpiCard(
      value: spesoZero
          ? '—'
          : '€${_formatItalianInt(kpis.spesoFinora.round())}',
      label: 'speso finora',
      valueColor: _kpiColor(_KpiTone.neutral, spesoZero),
      onTap: () => context.go('/statistiche'),
    ),
    _kpiCard(
      value: kpis.aggiuntiMeseCorrente,
      label: 'aggiunti a $meseCorrente',
      tone: _KpiTone.accent,
      // Intento esplicito → Collezione pre-filtrata (§9, deciso su #91).
      onTap: () => context.go('/collezione', extra: true),
    ),
  ];
}

Widget _kpiCard({
  required int value,
  required String label,
  required _KpiTone tone,
  required VoidCallback onTap,
}) {
  final isZero = value == 0;
  return KpiCard(
    value: isZero ? '—' : _formatItalianInt(value),
    label: label,
    valueColor: _kpiColor(tone, isZero),
    onTap: onTap,
  );
}

enum _KpiTone { neutral, alert, accent }

/// A zero il colore è sempre muto (decisione #8) — anche per le celle
/// non-di-allerta — indipendentemente dal tono che avrebbe a valore reale.
Color _kpiColor(_KpiTone tone, bool isZero) {
  if (isZero) return AppColors.textMuted;
  return switch (tone) {
    _KpiTone.neutral => AppColors.textPrimary,
    _KpiTone.alert => AppColors.amber,
    _KpiTone.accent => AppColors.accent,
  };
}

/// L'invito alla prima scansione (righe 104-111 del prototipo).
/// [emphasized] ingrandisce icona e tipografia per lo stato a zero,
/// dove è l'unica azione disponibile sulla Dashboard.
class _ScanCta extends StatelessWidget {
  const _ScanCta({this.emphasized = false});

  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final iconSize = emphasized ? 52.0 : 44.0;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () => context.go('/scansione'),
        borderRadius: AppRadii.xlRadius,
        child: Container(
          padding: EdgeInsets.all(emphasized ? AppSpacing.lg : AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: AppRadii.xlRadius,
            border: Border.all(color: AppColors.accentAlpha(0.28)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.accentAlpha(0.16),
                AppColors.accentAlpha(0.04),
              ],
            ),
          ),
          child: Row(
            children: [
              Container(
                width: iconSize,
                height: iconSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: AppRadii.lgRadius,
                ),
                child: Icon(
                  Icons.camera_alt_outlined,
                  color: AppColors.onAccent,
                  size: emphasized ? 26 : 22,
                ),
              ),
              const SizedBox(width: AppSpacing.sm + 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      emphasized
                          ? 'Scansiona la prima cover'
                          : 'Scansiona una cover',
                      style: AppTypography.titleMedium.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Fotografa → riconosci → conferma',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Carosello orizzontale delle ultime copie possedute aggiunte al catalogo
/// (§4.1, righe 129-141 del prototipo). Mostra la cover reale se nota,
/// altrimenti una copertina procedurale generata da titolo e numero — vedi
/// `ComicCoverImage`. Nascosta del tutto se vuota (#8).
class _AggiuntiRecenteSection extends StatelessWidget {
  const _AggiuntiRecenteSection({required this.items});

  final List<ComicRecente> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          label: 'aggiunti di recente',
          trailing: GestureDetector(
            onTap: () => context.go('/collezione'),
            child: Text(
              'Tutti',
              style: AppTypography.bodyMedium.copyWith(color: AppColors.accent),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.xs + 2),
                _RecentCard(item: items[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _RecentCard extends StatelessWidget {
  const _RecentCard({required this.item});

  final ComicRecente item;

  @override
  Widget build(BuildContext context) {
    // Sottotitolo: nome serie (o editore come ripiego), poi il numero su una
    // riga propria sotto — stessa convenzione della Collezione
    // (`_CardEdizione`), separata per non finire in ellissi col nome serie.
    final sottotitolo = item.serieName ?? item.editore ?? '';
    final numero = item.numeroVisualizzato;

    return GestureDetector(
      onTap: () => context.push('/scheda/${item.edizioneId}'),
      child: SizedBox(
        width: 96,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 96,
              height: 128,
              child: ComicCoverImage(
                coverImage: item.coverImage,
                titolo: item.titolo,
                numero: item.numero ?? 0,
                etichetta: item.numeroVisualizzato,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              item.titolo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            // Sottotitolo assente: riga omessa, non "—" — quel simbolo è la
            // convenzione per "valore zero" (#8), un significato diverso da
            // "campo non compilato".
            if (sottotitolo.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                sottotitolo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
            ],
            if (numero.isNotEmpty) ...[
              const SizedBox(height: 1),
              Text(
                numero,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Righe delle serie incomplete (§17, righe 143-163 del prototipo): nome,
/// frazione posseduti/totale, barra di completamento, riepilogo dei numeri
/// mancanti. Nascosta del tutto se vuota (#8).
class _SerieIncompleteSection extends StatelessWidget {
  const _SerieIncompleteSection({required this.items});

  final List<SerieIncompleta> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(label: 'serie incomplete'),
        const SizedBox(height: AppSpacing.sm),
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.xs),
          _SerieIncompletaRow(item: items[i]),
        ],
      ],
    );
  }
}

class _SerieIncompletaRow extends StatelessWidget {
  const _SerieIncompletaRow({required this.item});

  final SerieIncompleta item;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: () => context.push('/serie/${item.serieId}'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 2,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  item.nome,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.titleMedium.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '${item.numeriPosseduti}/${item.numeriTotali}',
                style: AppTypography.monoLabel.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs + 1),
          AppProgressBar(value: item.percentualeCompletamento),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Mancano ${_missingLabel(item.numeriMancanti)}',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Elenca fino a 3 numeri mancanti; oltre, tronca con "e altri N". Il
/// prototipo non definisce una regola (dati statici) — decisa qui in
/// risoluzione di #14.
String _missingLabel(List<int> numeri) {
  const soglia = 3;
  final visibili = numeri.take(soglia).map((n) => '#$n').join(', ');
  if (numeri.length <= soglia) return visibili;
  return '$visibili e altri ${numeri.length - soglia}';
}

/// Migliaia separate da punto, stile italiano (`1248` → `"1.248"`) — nessuna
/// dipendenza `intl` per questo solo formato.
String _formatItalianInt(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return (value < 0 ? '-' : '') + buffer.toString();
}
