import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/data/sincronizzazione/motore_sincronizzazione.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/features/sincronizzazione/application/indicatore_sincronizzazione.dart';
import 'package:mycomicbrain/features/sincronizzazione/application/sincronizzazione_providers.dart';

/// Il colore di ogni stato dell'indicatore.
Color coloreIndicatore(TonoIndicatore tono) => switch (tono) {
  TonoIndicatore.offline => AppColors.amber,
  TonoIndicatore.errore => AppColors.dangerLight,
  TonoIndicatore.inCorso || TonoIndicatore.cover => AppColors.accent,
  TonoIndicatore.sincronizzato => AppColors.success,
};

/// La pillola di stato della Sincronizzazione in Dashboard (prototipo #201,
/// variante A): non sparisce mai, e toccandola apre lo sheet.
class PillolaSincronizzazione extends StatelessWidget {
  const PillolaSincronizzazione({required this.indicatore, super.key});

  final IndicatoreSincronizzazione indicatore;

  @override
  Widget build(BuildContext context) {
    final colore = coloreIndicatore(indicatore.tono);
    final ok = indicatore.tono == TonoIndicatore.sincronizzato;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () => mostraSheetSincronizzazione(context),
        borderRadius: AppRadii.pillRadius,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 7,
          ),
          decoration: BoxDecoration(
            color: ok ? Colors.transparent : colore.withValues(alpha: 0.12),
            borderRadius: AppRadii.pillRadius,
            border: Border.all(
              color: ok
                  ? AppColors.borderStrong
                  : colore.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconaIndicatore(indicatore: indicatore, dimensione: 14),
              const SizedBox(width: 6),
              Text(
                indicatore.breve,
                style: AppTypography.labelMedium.copyWith(
                  color: ok ? AppColors.textSecondary : colore,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// L'icona di uno stato: un pallino verde quando è tutto a posto, la
/// freccia che gira durante la sincronizzazione.
class IconaIndicatore extends StatelessWidget {
  const IconaIndicatore({
    required this.indicatore,
    required this.dimensione,
    super.key,
  });

  final IndicatoreSincronizzazione indicatore;
  final double dimensione;

  @override
  Widget build(BuildContext context) {
    final colore = coloreIndicatore(indicatore.tono);
    final icona = switch (indicatore.tono) {
      TonoIndicatore.offline => Icons.cloud_off_outlined,
      TonoIndicatore.errore => Icons.error_outline,
      TonoIndicatore.inCorso => Icons.sync,
      TonoIndicatore.cover => Icons.downloading_outlined,
      TonoIndicatore.sincronizzato => null,
    };
    if (icona == null) {
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: colore, shape: BoxShape.circle),
      );
    }
    final widget = Icon(icona, size: dimensione, color: colore);
    return indicatore.gira ? _CheGira(child: widget) : widget;
  }
}

class _CheGira extends StatefulWidget {
  const _CheGira({required this.child});

  final Widget child;

  @override
  State<_CheGira> createState() => _CheGiraState();
}

class _CheGiraState extends State<_CheGira>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Con le animazioni ridotte l'icona resta ferma.
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      RotationTransition(turns: _controller, child: widget.child);
}

/// Lo sheet "Sincronizzazione" che si apre dalla pillola.
Future<void> mostraSheetSincronizzazione(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceRaised,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.8,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Sincronizzazione',
                  style: AppTypography.titleLarge.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                const DettaglioSincronizzazione(),
                const SizedBox(height: AppSpacing.xs),
                TextButton(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    context.go('/impostazioni');
                  },
                  child: const Text('Apri Impostazioni'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

/// Sezione "Sincronizzazione" di Impostazioni, subito dopo Account
/// (prototipo #201, punto 2); vuota in Modalità locale.
class SezioneSincronizzazione extends ConsumerWidget {
  const SezioneSincronizzazione({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(indicatoreSincronizzazioneProvider) == null) {
      return const SizedBox.shrink();
    }
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(label: 'Sincronizzazione'),
        SizedBox(height: AppSpacing.sm),
        AppCard(
          padding: EdgeInsets.all(AppSpacing.md),
          child: DettaglioSincronizzazione(),
        ),
        SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

/// Stato, ultima sincronizzazione, Modifiche in sospeso con l'elenco, cover
/// in arrivo, spiegazione e "Sincronizza ora": lo stesso contenuto nello
/// sheet e in Impostazioni.
class DettaglioSincronizzazione extends ConsumerWidget {
  const DettaglioSincronizzazione({super.key});

  /// Oltre questo numero l'elenco si chiude con "e altre N".
  static const massimoElenco = 30;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final indicatore = ref.watch(indicatoreSincronizzazioneProvider);
    final stato = ref.watch(statoSincronizzazioneProvider).valueOrNull;
    if (indicatore == null || stato == null) return const SizedBox.shrink();
    final inSospeso = ref.watch(modificheInSospesoProvider).valueOrNull ?? 0;
    final elenco = inSospeso == 0
        ? const <String>[]
        : ref.watch(elencoModificheProvider).valueOrNull ?? const <String>[];
    final ora = ref.watch(oraProvider).valueOrNull ?? DateTime.now();
    final offline = stato.fase == FaseSincronizzazione.offline;
    final inCorso = stato.fase == FaseSincronizzazione.inCorso;
    final cover = stato.cover;
    final testo = AppTypography.bodyMedium.copyWith(
      color: AppColors.textTertiary,
    );

    Widget riga(String etichetta, Widget valore) => Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          Expanded(child: Text(etichetta, style: testo)),
          valore,
        ],
      ),
    );
    Text valore(String v, {Color? colore}) => Text(
      v,
      style: AppTypography.labelLarge.copyWith(
        color: colore ?? AppColors.textPrimary,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        riga(
          'Stato',
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconaIndicatore(indicatore: indicatore, dimensione: 14),
              const SizedBox(width: 6),
              valore(
                indicatore.breve,
                colore: coloreIndicatore(indicatore.tono),
              ),
            ],
          ),
        ),
        riga(
          'Ultima sincronizzazione',
          valore(ultimaSincronizzazione(stato.ultima, ora)),
        ),
        riga('Modifiche in attesa', valore('$inSospeso')),
        if (cover != null)
          riga(
            'Cover scaricate',
            valore('${cover.scaricate} di ${cover.totale}'),
          ),
        if (elenco.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          for (final voce in elenco.take(massimoElenco))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '• $voce',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          if (elenco.length > massimoElenco)
            Text(
              '… e altre ${elenco.length - massimoElenco}',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Text(
          indicatore.spiegazione,
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: offline || inCorso
              ? null
              : () => unawaited(
                  ref.read(motoreSincronizzazioneProvider)?.sincronizzaOra(),
                ),
          icon: Icon(inCorso ? Icons.sync : Icons.sync_outlined, size: 18),
          label: Text(inCorso ? 'Sincronizzo…' : 'Sincronizza ora'),
        ),
        if (offline) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Serve una connessione a Internet: la sincronizzazione riparte da '
            'sola al ritorno della rete.',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ],
    );
  }
}
