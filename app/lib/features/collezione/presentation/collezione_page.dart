import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/core/domain/edizione_collezione.dart';
import 'package:mycomicbrain/features/collezione/application/collezione_providers.dart';
import 'package:mycomicbrain/features/collezione/application/filtri_collezione_logic.dart';
import 'package:mycomicbrain/features/serie/presentation/serie_page.dart';

/// Schermo Collezione (§9, deciso su #90, prototipo visivo validato su #96):
/// griglia a copertine di tutte le Edizioni possedute, filtrabile sui 12
/// assi e ordinabile, con due stati vuoti distinti, caricata a finestra con
/// scroll infinito (§9, deciso su #112/#115). Dalla Dashboard, il KPI
/// "aggiunti nel mese corrente" apre lo schermo pre-filtrato (deciso su
/// #91) — [soloAggiuntiMeseCorrente] porta quell'intento; non è uno dei 12
/// assi del pannello Filtri, è un pre-filtro d'ingresso a sé, rimovibile
/// dalla sua stessa chip.
class CollezionePage extends ConsumerStatefulWidget {
  const CollezionePage({this.soloAggiuntiMeseCorrente = false, super.key});

  final bool soloAggiuntiMeseCorrente;

  @override
  ConsumerState<CollezionePage> createState() => _CollezionePageState();
}

class _CollezionePageState extends ConsumerState<CollezionePage> {
  @override
  void initState() {
    super.initState();
    // Sincronizza il pre-filtro (provider, deciso su #115) con l'intento di
    // navigazione di questa istanza — sempre, non solo quando `true`,
    // altrimenti un rientro in Collezione dalla bottom nav erediterebbe lo
    // stato lasciato da una precedente visita dalla Dashboard. Rimandato a
    // dopo il primo build (Riverpod non permette di modificare un provider
    // durante il ciclo di vita del widget che lo osserva).
    Future(
      () => ref
          .read(soloAggiuntiMeseCorrenteProvider.notifier)
          .imposta(valore: widget.soloAggiuntiMeseCorrente),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vista = ref.watch(vistaCollezioneProvider);
    final modalitaSelezione = ref.watch(modalitaSelezioneProvider);
    final selezionati = ref.watch(edizioniSelezionateProvider);

    return Scaffold(
      floatingActionButton: modalitaSelezione && selezionati.isNotEmpty
          ? FloatingActionButton(
              onPressed: () => _apriAzioneSelezione(context),
              backgroundColor: AppColors.accent,
              child: const Icon(Icons.sell_outlined, color: AppColors.onAccent),
            )
          : null,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                ),
                child: modalitaSelezione
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${selezionati.length} selezionati',
                            style: AppTypography.headline.copyWith(
                              color: AppColors.textPrimary,
                            ),
                          ),
                          TextButton(
                            onPressed: () => ref
                                .read(modalitaSelezioneProvider.notifier)
                                .disattiva(),
                            child: Text(
                              'Annulla',
                              style: AppTypography.labelMedium.copyWith(
                                color: AppColors.accent,
                              ),
                            ),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const _Titolo(),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _VistaToggle(vista: vista),
                              if (vista == VistaCollezione.singoli) ...[
                                const SizedBox(width: AppSpacing.xs),
                                const _SelezionaButton(),
                              ],
                            ],
                          ),
                        ],
                      ),
              ),
              Expanded(
                // La modalità selezione (§9, variante B decisa su #164) ha
                // senso solo sulla griglia "Fumetti", non sulla vista Serie:
                // forza quella vista mentre è attiva, indipendentemente da
                // [vista].
                child: !modalitaSelezione && vista == VistaCollezione.serie
                    ? const SerieListaBody()
                    : const _ContenutoSingoli(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Apre il foglio dell'azione in blocco "Segna come in vendita" (§9,
  /// variante B decisa su #164) e, alla conferma, mostra il banner di
  /// esito in cima alla griglia.
  Future<void> _apriAzioneSelezione(BuildContext context) async {
    final edizioneIds = ref.read(edizioniSelezionateProvider);
    if (edizioneIds.isEmpty) return;

    final indice = ref.read(indiceCollezioneProvider).valueOrNull ?? const [];
    final numeroCopie = indice
        .where((e) => edizioneIds.contains(e.edizioneId))
        .fold<int>(0, (tot, e) => tot + e.copiePossedute.length);

    final scritte = await showModalBottomSheet<int?>(
      context: context,
      backgroundColor: AppColors.surfaceRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _AzioneSelezioneSheet(
        numeroEdizioni: edizioneIds.length,
        numeroCopie: numeroCopie,
        onConferma: () => ref
            .read(comicsRepositoryProvider)
            .segnaEdizioniInVendita(edizioneIds.toList()),
      ),
    );
    if (scritte == null) return;

    ref.read(modalitaSelezioneProvider.notifier).disattiva();
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.clearMaterialBanners();
    messenger.showMaterialBanner(
      MaterialBanner(
        backgroundColor: AppColors.surfaceRaised,
        content: Text(
          '${edizioneIds.length} edizioni ($scritte copie) segnate come '
          'in vendita',
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: messenger.hideCurrentMaterialBanner,
            child: Text(
              'Chiudi',
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.accent,
              ),
            ),
          ),
        ],
      ),
    );
    Future.delayed(const Duration(seconds: 4), () {
      if (context.mounted) messenger.hideCurrentMaterialBanner();
    });
  }
}

/// La vista "fumetti singoli" della Collezione (§9) — griglia a copertine
/// con filtri/ordinamento, invariata rispetto a prima dell'introduzione del
/// toggle Fumetti/Serie: solo il titolo si è spostato nel widget padre,
/// condiviso con la vista Serie.
class _ContenutoSingoli extends ConsumerWidget {
  const _ContenutoSingoli();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final indiceAsync = ref.watch(indiceCollezioneProvider);
    final filtri = ref.watch(filtriCollezioneProvider);
    final soloAggiuntiMeseCorrente = ref.watch(soloAggiuntiMeseCorrenteProvider);

    return indiceAsync.when(
      data: (tutte) => _Collezione(
        totale: tutte.length,
        filtri: filtri,
        soloAggiuntiMeseCorrente: soloAggiuntiMeseCorrente,
        onRimuoviAggiuntiMeseCorrente: () => ref
            .read(soloAggiuntiMeseCorrenteProvider.notifier)
            .imposta(valore: false),
      ),
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
    );
  }
}

/// Il pill-toggle Fumetti/Serie (§9): default "Fumetti" ad ogni apertura
/// dello schermo, come [FiltriCollezioneState] — non è uno dei 12 assi né
/// va ricordato fra le sessioni.
class _VistaToggle extends ConsumerWidget {
  const _VistaToggle({required this.vista});

  final VistaCollezione vista;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(vistaCollezioneProvider.notifier);

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
          _VistaSegment(
            label: 'Fumetti',
            selected: vista == VistaCollezione.singoli,
            onTap: () => notifier.imposta(VistaCollezione.singoli),
          ),
          _VistaSegment(
            label: 'Serie',
            selected: vista == VistaCollezione.serie,
            onTap: () => notifier.imposta(VistaCollezione.serie),
          ),
        ],
      ),
    );
  }
}

class _VistaSegment extends StatelessWidget {
  const _VistaSegment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
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
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xxs + 2,
          ),
          decoration: BoxDecoration(
            color: selected ? AppColors.accent : Colors.transparent,
            borderRadius: AppRadii.pillRadius,
          ),
          child: Text(
            label,
            style: AppTypography.labelMedium.copyWith(
              color: selected ? AppColors.onAccent : AppColors.textMuted,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

/// Pulsante dedicato che entra in modalità selezione (§9, variante B decisa
/// su #164) — l'uscita passa dal pulsante "Annulla" mostrato nell'header al
/// suo posto mentre la modalità è attiva, non da questo stesso pulsante.
class _SelezionaButton extends ConsumerWidget {
  const _SelezionaButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () => ref.read(modalitaSelezioneProvider.notifier).attiva(),
        borderRadius: AppRadii.pillRadius,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xxs + 2,
          ),
          decoration: BoxDecoration(
            color: AppColors.overlayCard,
            borderRadius: AppRadii.pillRadius,
            border: Border.all(color: AppColors.borderDefault),
          ),
          child: Text(
            'Seleziona',
            style: AppTypography.labelMedium.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _Collezione extends ConsumerWidget {
  const _Collezione({
    required this.totale,
    required this.filtri,
    required this.soloAggiuntiMeseCorrente,
    required this.onRimuoviAggiuntiMeseCorrente,
  });

  final int totale;
  final FiltriCollezioneState filtri;
  final bool soloAggiuntiMeseCorrente;
  final VoidCallback onRimuoviAggiuntiMeseCorrente;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (totale == 0) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: _EmptyCatalogo(),
      );
    }

    final visibili = ref.watch(edizioniVisibiliProvider).valueOrNull ?? const [];
    final finestra =
        ref.watch(edizioniFinestraCollezioneProvider).valueOrNull ?? const [];
    final haFiltriAttivi = filtri.haFiltriAttivi || soloAggiuntiMeseCorrente;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ContaLinea(
          totale: totale,
          visibili: visibili.length,
          filtrato: haFiltriAttivi,
        ),
        if (haFiltriAttivi)
          _ChipRow(
            filtri: filtri,
            soloAggiuntiMeseCorrente: soloAggiuntiMeseCorrente,
            onRimuoviAggiuntiMeseCorrente: onRimuoviAggiuntiMeseCorrente,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            AppSpacing.xxs,
          ),
          child: Align(
            alignment: Alignment.centerRight,
            child: _FiltriButton(numeroAssiAttivi: filtri.numeroAssiAttivi),
          ),
        ),
        Expanded(
          child: visibili.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: _EmptyRisultati(),
                )
              : _Griglia(
                  edizioni: finestra,
                  haAltriRisultati: finestra.length < visibili.length,
                ),
        ),
      ],
    );
  }
}

class _Titolo extends StatelessWidget {
  const _Titolo();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Collezione',
      style: AppTypography.headline.copyWith(color: AppColors.textPrimary),
    );
  }
}

class _ContaLinea extends StatelessWidget {
  const _ContaLinea({
    required this.totale,
    required this.visibili,
    required this.filtrato,
  });

  final int totale;
  final int visibili;
  final bool filtrato;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xxs,
        AppSpacing.md,
        0,
      ),
      child: filtrato
          ? Text.rich(
              TextSpan(
                style: AppTypography.monoLabel.copyWith(
                  color: AppColors.textMuted,
                ),
                children: [
                  TextSpan(
                    text: '$visibili',
                    style: const TextStyle(color: AppColors.accentLight),
                  ),
                  TextSpan(text: ' di $totale fumetti'),
                ],
              ),
            )
          : Text(
              '$totale fumetti',
              style: AppTypography.monoLabel.copyWith(
                color: AppColors.textMuted,
              ),
            ),
    );
  }
}

class _ChipRow extends ConsumerWidget {
  const _ChipRow({
    required this.filtri,
    required this.soloAggiuntiMeseCorrente,
    required this.onRimuoviAggiuntiMeseCorrente,
  });

  final FiltriCollezioneState filtri;
  final bool soloAggiuntiMeseCorrente;
  final VoidCallback onRimuoviAggiuntiMeseCorrente;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(filtriCollezioneProvider.notifier);
    final chips = <Widget>[
      if (soloAggiuntiMeseCorrente)
        _RemovableChip(
          label: 'Aggiunti nel mese corrente',
          onRemove: onRimuoviAggiuntiMeseCorrente,
        ),
      if (filtri.soloInVendita)
        _RemovableChip(
          label: 'In vendita',
          onRemove: () => notifier.impostaSoloInVendita(false),
        ),
      for (final asse in AsseCollezione.values)
        for (final valore in filtri.valoriSelezionati(asse))
          _RemovableChip(
            label: '${asse.label}: ${etichettaValoreAsse(asse, valore)}',
            onRemove: () => notifier.toggleValore(asse, valore),
          ),
    ];

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xxs,
        ),
        children: [
          for (var i = 0; i < chips.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.xxs + 2),
            chips[i],
          ],
          if (chips.length > 1) ...[
            const SizedBox(width: AppSpacing.xs),
            GestureDetector(
              onTap: () {
                notifier.azzeraTutti();
                if (soloAggiuntiMeseCorrente) onRimuoviAggiuntiMeseCorrente();
              },
              child: Center(
                child: Text(
                  'Cancella tutto',
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.textMuted,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RemovableChip extends StatelessWidget {
  const _RemovableChip({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.xxs,
        AppSpacing.xxs,
        AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: AppColors.accentAlpha(0.12),
        borderRadius: AppRadii.pillRadius,
        border: Border.all(color: AppColors.accentAlpha(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTypography.labelMedium.copyWith(
              color: AppColors.accentLight,
            ),
          ),
          const SizedBox(width: AppSpacing.xxs),
          GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 16,
              height: 16,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.accentAlpha(0.22),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close,
                size: 11,
                color: AppColors.accentLight,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FiltriButton extends StatelessWidget {
  const _FiltriButton({required this.numeroAssiAttivi});

  final int numeroAssiAttivi;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () => _apriFiltriSheet(context),
        borderRadius: AppRadii.pillRadius,
        child: Container(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.xs,
            AppSpacing.sm + 2,
            AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: AppColors.overlayCard,
            borderRadius: AppRadii.pillRadius,
            border: Border.all(color: AppColors.borderDefault),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.tune, size: 17, color: AppColors.textPrimary),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                'Filtri e ordina',
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              if (numeroAssiAttivi > 0) ...[
                const SizedBox(width: AppSpacing.xxs),
                Container(
                  constraints: const BoxConstraints(minWidth: 16),
                  height: 16,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$numeroAssiAttivi',
                    style: AppTypography.monoLabel.copyWith(
                      color: AppColors.onAccent,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// La griglia della finestra caricata — richiede lo step successivo (§9,
/// deciso su #112/#115) quando lo scroll costruisce una card a meno di 15
/// elementi dalla fine, senza alcuno stato di caricamento a fondo griglia
/// dedicato (deciso su #115: l'indice è già tutto in memoria, l'unica
/// latenza è la cover per-card).
class _Griglia extends ConsumerStatefulWidget {
  const _Griglia({required this.edizioni, required this.haAltriRisultati});

  final List<EdizioneCollezioneFinestra> edizioni;
  final bool haAltriRisultati;

  @override
  ConsumerState<_Griglia> createState() => _GrigliaState();
}

class _GrigliaState extends ConsumerState<_Griglia> {
  bool _richiestaInviata = false;

  @override
  void didUpdateWidget(covariant _Griglia oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.edizioni.length != oldWidget.edizioni.length) {
      _richiestaInviata = false;
    }
  }

  /// Tra 12 e 18 elementi dalla fine (§9, deciso su #112) — un valore
  /// intermedio fisso.
  static const _sogliaPrefetch = 15;

  void _eventualeCaricaAltro(int index) {
    if (_richiestaInviata || !widget.haAltriRisultati) return;
    if (index < widget.edizioni.length - _sogliaPrefetch) return;
    _richiestaInviata = true;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(numeroCaricatiCollezioneProvider.notifier).caricaAltro(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.xxl,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: AppSpacing.xs + 2,
        mainAxisSpacing: AppSpacing.xs + 2,
        childAspectRatio: 0.6,
      ),
      itemCount: widget.edizioni.length,
      itemBuilder: (context, index) {
        _eventualeCaricaAltro(index);
        return _CardEdizione(edizione: widget.edizioni[index]);
      },
    );
  }
}

class _CardEdizione extends ConsumerWidget {
  const _CardEdizione({required this.edizione});

  final EdizioneCollezioneFinestra edizione;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modalitaSelezione = ref.watch(modalitaSelezioneProvider);
    final selezionata = ref
        .watch(edizioniSelezionateProvider)
        .contains(edizione.edizioneId);
    final sottotitolo = edizione.serieName ?? edizione.publisher ?? '';
    final numero = edizione.numeroVisualizzato;

    return GestureDetector(
      onTap: modalitaSelezione
          ? () => ref
              .read(edizioniSelezionateProvider.notifier)
              .toggle(edizione.edizioneId)
          : () => context.push('/scheda/${edizione.edizioneId}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: AppRadii.smRadius,
                      border: modalitaSelezione && selezionata
                          ? Border.all(color: AppColors.accent, width: 2)
                          : null,
                    ),
                    child: ComicCoverImage(
                      coverImage: edizione.coverImage,
                      titolo: edizione.titolo,
                      numero: edizione.issueNumber ?? 0,
                      etichetta: edizione.numeroVisualizzato,
                    ),
                  ),
                ),
                if (modalitaSelezione && !selezionata)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.45),
                    ),
                  ),
                if (!modalitaSelezione && edizione.inVendita)
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _InVenditaBand(),
                  ),
                // In modalità selezione lo spunta occupa l'angolo in alto a
                // destra già usato dal badge duplicati (§9, deciso su #93):
                // durante la selezione il numero di copie non è
                // l'informazione prioritaria (il foglio dell'azione lo
                // riepiloga a parte), quindi il badge duplicati è sostituito
                // dallo spunta invece di essere spostato altrove.
                if (modalitaSelezione)
                  Positioned(
                    top: 5,
                    right: 5,
                    child: _SelezioneCheck(selezionata: selezionata),
                  )
                else if (edizione.numeroCopie > 1)
                  Positioned(
                    top: 5,
                    right: 5,
                    child: _DupBadge(numero: edizione.numeroCopie),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            edizione.titolo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelMedium.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          if (sottotitolo.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              sottotitolo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.monoLabel.copyWith(
                color: AppColors.textMuted,
                fontSize: 10,
              ),
            ),
          ],
          if (numero.isNotEmpty) ...[
            const SizedBox(height: 1),
            Text(
              numero,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.monoLabel.copyWith(
                color: AppColors.textMuted,
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DupBadge extends StatelessWidget {
  const _DupBadge({required this.numero});

  final int numero;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surfaceDeepest,
        borderRadius: AppRadii.pillRadius,
        border: Border.all(color: AppColors.borderStrong),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.content_copy, size: 10, color: AppColors.amber),
          const SizedBox(width: 2),
          Text(
            '×$numero',
            style: AppTypography.monoLabel.copyWith(
              color: AppColors.amber,
              fontSize: 9.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Lo spunta in alto a destra di una card in modalità selezione (§9,
/// variante B decisa su #164).
class _SelezioneCheck extends StatelessWidget {
  const _SelezioneCheck({required this.selezionata});

  final bool selezionata;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selezionata ? AppColors.accent : AppColors.overlayCardHover,
        border: Border.all(
          color: selezionata ? AppColors.accent : AppColors.borderStrong,
          width: 1.5,
        ),
      ),
      child: selezionata
          ? const Icon(Icons.check, size: 14, color: AppColors.onAccent)
          : null,
    );
  }
}

/// Fascia "IN VENDITA" sulla card fuori dalla modalità selezione (§9,
/// deciso su #163/#164) — colore ambra come gli altri segnali di attenzione
/// della Collezione (badge duplicati), non un colore nuovo.
class _InVenditaBand extends StatelessWidget {
  const _InVenditaBand();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 3),
      color: AppColors.amberAlpha(0.92),
      alignment: Alignment.center,
      child: Text(
        'IN VENDITA',
        style: AppTypography.monoLabel.copyWith(
          color: AppColors.surfaceDeepest,
          fontSize: 8.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _EmptyCatalogo extends StatelessWidget {
  const _EmptyCatalogo();

  @override
  Widget build(BuildContext context) {
    return _EmptyState(
      icon: Icons.auto_stories_outlined,
      titolo: 'Nessun fumetto in collezione',
      messaggio:
          'Scansiona la copertina di un fumetto per iniziare a costruire il tuo catalogo.',
      azione: 'Scansiona il primo fumetto',
      onAzione: () => context.go('/scansione'),
    );
  }
}

class _EmptyRisultati extends ConsumerWidget {
  const _EmptyRisultati();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _EmptyState(
      icon: Icons.filter_alt_off_outlined,
      titolo: 'Nessun fumetto corrisponde ai filtri',
      messaggio: 'Prova a rimuovere uno o più filtri per allargare la ricerca.',
      azione: 'Rimuovi filtri',
      onAzione: () => ref.read(filtriCollezioneProvider.notifier).azzeraTutti(),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.titolo,
    required this.messaggio,
    required this.azione,
    required this.onAzione,
  });

  final IconData icon;
  final String titolo;
  final String messaggio;
  final String azione;
  final VoidCallback onAzione;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: AppColors.textDisabled),
          const SizedBox(height: AppSpacing.sm),
          Text(
            titolo,
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            messaggio,
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onAzione,
              borderRadius: AppRadii.pillRadius,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: AppRadii.pillRadius,
                ),
                child: Text(
                  azione,
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.onAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void _apriFiltriSheet(BuildContext context) {
  unawaited(
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => const _FiltriSheet(),
    ),
  );
}

class _FiltriSheet extends ConsumerWidget {
  const _FiltriSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visibili =
        ref.watch(edizioniVisibiliProvider).valueOrNull?.length ?? 0;

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.borderStrong,
                borderRadius: AppRadii.pillRadius,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.xs,
                AppSpacing.sm,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Filtri e ordina',
                    style: AppTypography.titleMedium.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.borderSubtle),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                children: [
                  const _InVenditaToggleRow(),
                  for (final asse in AsseCollezione.values)
                    _AxisBlock(asse: asse),
                  const _SortBlock(),
                  const _RicordaToggleRow(),
                  const SizedBox(height: AppSpacing.md),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.borderSubtle),
            Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.sm + MediaQuery.of(context).padding.bottom,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => ref
                          .read(filtriCollezioneProvider.notifier)
                          .azzeraTutti(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        side: const BorderSide(color: AppColors.borderDefault),
                        shape: RoundedRectangleBorder(
                          borderRadius: AppRadii.pillRadius,
                        ),
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.sm + 1,
                        ),
                      ),
                      child: const Text('Cancella tutto'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: AppColors.onAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: AppRadii.pillRadius,
                        ),
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.sm + 1,
                        ),
                      ),
                      child: Text('Mostra $visibili risultati'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AxisBlock extends ConsumerWidget {
  const _AxisBlock({required this.asse});

  final AsseCollezione asse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final valori = ref.watch(valoriAsseProvider(asse));
    final selezionati = ref
        .watch(filtriCollezioneProvider)
        .valoriSelezionati(asse);
    final notifier = ref.read(filtriCollezioneProvider.notifier);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm + 2),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                asse.label,
                style: AppTypography.titleMedium.copyWith(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                ),
              ),
              Text(
                asse.tipo == TipoAsse.autocomplete
                    ? 'testo libero'
                    : 'pochi valori',
                style: AppTypography.monoLabel.copyWith(
                  color: AppColors.textMuted,
                  fontSize: 9.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          if (valori.isEmpty)
            Text(
              'Nessun valore in collezione',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textDisabled,
              ),
            )
          else if (asse.tipo == TipoAsse.chip)
            Wrap(
              spacing: AppSpacing.xxs + 2,
              runSpacing: AppSpacing.xxs + 2,
              children: [
                for (final valore in valori)
                  AppChip(
                    label: etichettaValoreAsse(asse, valore),
                    selected: selezionati.contains(valore),
                    onTap: () => notifier.toggleValore(asse, valore),
                  ),
              ],
            )
          else
            _AxisAutocomplete(
              asse: asse,
              valori: valori,
              selezionati: selezionati,
              notifier: notifier,
            ),
        ],
      ),
    );
  }
}

class _AxisAutocomplete extends StatefulWidget {
  const _AxisAutocomplete({
    required this.asse,
    required this.valori,
    required this.selezionati,
    required this.notifier,
  });

  final AsseCollezione asse;
  final List<String> valori;
  final Set<String> selezionati;
  final FiltriCollezioneNotifier notifier;

  @override
  State<_AxisAutocomplete> createState() => _AxisAutocompleteState();
}

class _AxisAutocompleteState extends State<_AxisAutocomplete> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _aperto = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() => setState(() => _aperto = _focusNode.hasFocus));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim().toLowerCase();
    final opzioni = widget.valori
        .where((v) => !widget.selezionati.contains(v))
        .where(
          (v) =>
              etichettaValoreAsse(widget.asse, v).toLowerCase().contains(query),
        )
        .take(8)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          onChanged: (_) => setState(() {}),
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textPrimary,
          ),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Cerca ${widget.asse.label.toLowerCase()}…',
            hintStyle: AppTypography.bodyMedium.copyWith(
              color: AppColors.textDisabled,
            ),
            filled: true,
            fillColor: AppColors.overlayCard,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs + 1,
            ),
            border: OutlineInputBorder(
              borderRadius: AppRadii.smRadius,
              borderSide: const BorderSide(color: AppColors.borderDefault),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: AppRadii.smRadius,
              borderSide: const BorderSide(color: AppColors.borderDefault),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: AppRadii.smRadius,
              borderSide: const BorderSide(color: AppColors.accent),
            ),
          ),
        ),
        if (_aperto && opzioni.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 160),
            decoration: BoxDecoration(
              color: AppColors.surfaceBase,
              borderRadius: AppRadii.smRadius,
              border: Border.all(color: AppColors.borderStrong),
            ),
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                for (final opzione in opzioni)
                  ListTile(
                    dense: true,
                    title: Text(
                      etichettaValoreAsse(widget.asse, opzione),
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    onTap: () {
                      widget.notifier.toggleValore(widget.asse, opzione);
                      _controller.clear();
                      setState(() {});
                    },
                  ),
              ],
            ),
          ),
        if (widget.selezionati.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xxs + 2,
            runSpacing: AppSpacing.xxs + 2,
            children: [
              for (final valore in widget.selezionati)
                _RemovableChip(
                  label: etichettaValoreAsse(widget.asse, valore),
                  onRemove: () =>
                      widget.notifier.toggleValore(widget.asse, valore),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SortBlock extends ConsumerWidget {
  const _SortBlock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordinamento = ref.watch(filtriCollezioneProvider).ordinamento;
    final notifier = ref.read(filtriCollezioneProvider.notifier);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ordina per',
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.textPrimary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _SortRow(
            etichetta: 'Primario',
            criterio: ordinamento.primario,
            direzione: ordinamento.direzionePrimario,
            onCriterio: (criterio) => notifier.impostaOrdinamento(
              ordinamento.copyWith(
                primario: criterio,
                direzionePrimario: DirezioneOrdinamento.crescente,
              ),
            ),
            onDirezione: () => notifier.impostaOrdinamento(
              ordinamento.copyWith(
                direzionePrimario:
                    ordinamento.direzionePrimario ==
                        DirezioneOrdinamento.crescente
                    ? DirezioneOrdinamento.decrescente
                    : DirezioneOrdinamento.crescente,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          _SortRow(
            etichetta: 'Secondario',
            criterio: ordinamento.secondario,
            direzione: ordinamento.direzioneSecondario,
            nessunoConsentito: true,
            criterioEscluso: ordinamento.primario,
            onCriterio: (criterio) => notifier.impostaOrdinamento(
              criterio == null
                  ? ordinamento.copyWith(azzeraSecondario: true)
                  : ordinamento.copyWith(
                      secondario: criterio,
                      direzioneSecondario: DirezioneOrdinamento.crescente,
                    ),
            ),
            onDirezione: ordinamento.secondario == null
                ? null
                : () => notifier.impostaOrdinamento(
                    ordinamento.copyWith(
                      direzioneSecondario:
                          ordinamento.direzioneSecondario ==
                              DirezioneOrdinamento.crescente
                          ? DirezioneOrdinamento.decrescente
                          : DirezioneOrdinamento.crescente,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SortRow extends StatelessWidget {
  const _SortRow({
    required this.etichetta,
    required this.criterio,
    required this.direzione,
    required this.onCriterio,
    required this.onDirezione,
    this.nessunoConsentito = false,
    this.criterioEscluso,
  });

  final String etichetta;
  final CriterioOrdinamento? criterio;
  final DirezioneOrdinamento direzione;
  final bool nessunoConsentito;
  final CriterioOrdinamento? criterioEscluso;
  final ValueChanged<CriterioOrdinamento?> onCriterio;
  final VoidCallback? onDirezione;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 68,
          child: Text(
            etichetta,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textMuted,
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.overlayCard,
              borderRadius: AppRadii.smRadius,
              border: Border.all(color: AppColors.borderDefault),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<CriterioOrdinamento?>(
                value: criterio,
                isExpanded: true,
                isDense: true,
                dropdownColor: AppColors.surfaceBase,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textPrimary,
                ),
                icon: Icon(
                  Icons.expand_more,
                  color: AppColors.textMuted,
                  size: 18,
                ),
                items: [
                  if (nessunoConsentito)
                    const DropdownMenuItem(child: Text('— nessuno —')),
                  for (final c in CriterioOrdinamento.values)
                    if (c != criterioEscluso)
                      DropdownMenuItem(value: c, child: Text(c.label)),
                ],
                onChanged: onCriterio,
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onDirezione,
            borderRadius: AppRadii.smRadius,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs + 2,
                vertical: AppSpacing.xs + 1,
              ),
              decoration: BoxDecoration(
                color: AppColors.overlayCard,
                borderRadius: AppRadii.smRadius,
                border: Border.all(color: AppColors.borderDefault),
              ),
              child: Text(
                direzione == DirezioneOrdinamento.crescente ? '↑ A→Z' : '↓ Z→A',
                style: AppTypography.bodyMedium.copyWith(
                  color: onDirezione == null
                      ? AppColors.textDisabled
                      : AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RicordaToggleRow extends ConsumerWidget {
  const _RicordaToggleRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ricorda = ref.watch(ricordaFiltriProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Ricorda filtri e ordinamento',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Switch(
            value: ricorda,
            activeThumbColor: AppColors.accent,
            onChanged: (valore) => ref
                .read(ricordaFiltriProvider.notifier)
                .imposta(valore: valore),
          ),
        ],
      ),
    );
  }
}

/// Il toggle "In vendita" del pannello Filtri (§9, deciso su #163/#164) —
/// separato visivamente dal loop dei 12 assi in [_FiltriSheet]: non è uno
/// di loro, è un filtro on/off a sé (stesso trattamento del pre-filtro
/// "aggiunti nel mese corrente", ma persistito insieme al resto dei
/// filtri/ordinamento).
class _InVenditaToggleRow extends ConsumerWidget {
  const _InVenditaToggleRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final soloInVendita = ref.watch(filtriCollezioneProvider).soloInVendita;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm + 2),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'In vendita',
              style: AppTypography.titleMedium.copyWith(
                color: AppColors.textPrimary,
                fontSize: 13,
              ),
            ),
          ),
          Switch(
            value: soloInVendita,
            activeThumbColor: AppColors.accent,
            onChanged: (valore) => ref
                .read(filtriCollezioneProvider.notifier)
                .impostaSoloInVendita(valore),
          ),
        ],
      ),
    );
  }
}

/// Il foglio dell'azione in blocco "Segna come in vendita" (§9, variante B
/// decisa su #164): mostra prima il menu delle azioni disponibili, poi
/// espande la conferma nello stesso foglio (non un dialog separato) —
/// [onConferma] esegue la scrittura e ritorna quante Copie sono state
/// effettivamente marcate, propagato a [Navigator.pop] come risultato del
/// foglio.
class _AzioneSelezioneSheet extends StatefulWidget {
  const _AzioneSelezioneSheet({
    required this.numeroEdizioni,
    required this.numeroCopie,
    required this.onConferma,
  });

  final int numeroEdizioni;
  final int numeroCopie;
  final Future<int> Function() onConferma;

  @override
  State<_AzioneSelezioneSheet> createState() => _AzioneSelezioneSheetState();
}

class _AzioneSelezioneSheetState extends State<_AzioneSelezioneSheet> {
  bool _mostraConferma = false;
  bool _confermaInCorso = false;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _mostraConferma ? _conferma() : _menu(),
        ),
      ),
    );
  }

  List<Widget> _menu() {
    return [
      ListTile(
        leading: const Icon(Icons.sell_outlined, color: AppColors.accent),
        title: Text(
          'Segna come in vendita',
          style: AppTypography.bodyLarge.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
        onTap: () => setState(() => _mostraConferma = true),
      ),
      // Deliberatamente disabilitata (§9, deciso su #164): l'azione inversa
      // non è implementata in questo giro, ma resta visibile per segnalare
      // che è prevista.
      ListTile(
        enabled: false,
        leading: Icon(
          Icons.remove_shopping_cart_outlined,
          color: AppColors.textDisabled,
        ),
        title: Text(
          'Rimuovi da in vendita',
          style: AppTypography.bodyLarge.copyWith(
            color: AppColors.textDisabled,
          ),
        ),
      ),
    ];
  }

  List<Widget> _conferma() {
    final edizioniLabel = widget.numeroEdizioni == 1
        ? '1 edizione'
        : '${widget.numeroEdizioni} edizioni';
    final copieLabel = widget.numeroCopie == 1
        ? '1 copia posseduta'
        : '${widget.numeroCopie} copie possedute';

    return [
      Text(
        'Segnare come "In vendita" $edizioniLabel ($copieLabel coinvolte)?',
        style: AppTypography.bodyLarge.copyWith(color: AppColors.textPrimary),
      ),
      const SizedBox(height: AppSpacing.md),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _confermaInCorso
                  ? null
                  : () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                side: const BorderSide(color: AppColors.borderDefault),
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadii.pillRadius,
                ),
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.sm + 1,
                ),
              ),
              child: const Text('Annulla'),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: FilledButton(
              onPressed: _confermaInCorso
                  ? null
                  : () async {
                      setState(() => _confermaInCorso = true);
                      final scritte = await widget.onConferma();
                      if (mounted) Navigator.of(context).pop(scritte);
                    },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.onAccent,
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadii.pillRadius,
                ),
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.sm + 1,
                ),
              ),
              child: const Text('Confermo'),
            ),
          ),
        ],
      ),
    ];
  }
}
