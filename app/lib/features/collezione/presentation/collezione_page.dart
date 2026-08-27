import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/core/domain/edizione_collezione.dart';
import 'package:mycomicbrain/features/collezione/application/collezione_providers.dart';
import 'package:mycomicbrain/features/collezione/application/filtri_collezione_logic.dart';

/// Schermo Collezione (§9, deciso su #90, prototipo visivo validato su #96):
/// griglia a copertine di tutte le Edizioni possedute, filtrabile sui 12
/// assi e ordinabile, con due stati vuoti distinti. Dalla Dashboard, il KPI
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
  late bool _soloAggiuntiMeseCorrente = widget.soloAggiuntiMeseCorrente;

  @override
  Widget build(BuildContext context) {
    final edizioniAsync = ref.watch(collezioneEdizioniProvider);
    final filtri = ref.watch(filtriCollezioneProvider);

    return Scaffold(
      body: SafeArea(
        child: edizioniAsync.when(
          data: (tutte) => _Collezione(
            tutte: tutte,
            filtri: filtri,
            soloAggiuntiMeseCorrente: _soloAggiuntiMeseCorrente,
            onRimuoviAggiuntiMeseCorrente: () =>
                setState(() => _soloAggiuntiMeseCorrente = false),
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
        ),
      ),
    );
  }
}

bool _aggiuntaMeseCorrente(EdizioneCollezione edizione, DateTime ora) {
  final inizioMese = DateTime(ora.year, ora.month);
  final inizioMeseProssimo = DateTime(ora.year, ora.month + 1);
  return edizione.copiePossedute.any(
    (c) =>
        !c.createdAt.isBefore(inizioMese) &&
        c.createdAt.isBefore(inizioMeseProssimo),
  );
}

class _Collezione extends ConsumerWidget {
  const _Collezione({
    required this.tutte,
    required this.filtri,
    required this.soloAggiuntiMeseCorrente,
    required this.onRimuoviAggiuntiMeseCorrente,
  });

  final List<EdizioneCollezione> tutte;
  final FiltriCollezioneState filtri;
  final bool soloAggiuntiMeseCorrente;
  final VoidCallback onRimuoviAggiuntiMeseCorrente;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tutte.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Titolo(),
            Expanded(child: _EmptyCatalogo()),
          ],
        ),
      );
    }

    var visibili = edizioniVisibili(tutte, filtri);
    if (soloAggiuntiMeseCorrente) {
      final ora = DateTime.now();
      visibili = visibili
          .where((ed) => _aggiuntaMeseCorrente(ed, ora))
          .toList();
    }
    final haFiltriAttivi = filtri.haFiltriAttivi || soloAggiuntiMeseCorrente;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: _Titolo(),
          ),
          _ContaLinea(
            totale: tutte.length,
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
                : _Griglia(edizioni: visibili),
          ),
        ],
      ),
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

class _Griglia extends StatelessWidget {
  const _Griglia({required this.edizioni});

  final List<EdizioneCollezione> edizioni;

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
      itemCount: edizioni.length,
      itemBuilder: (context, index) => _CardEdizione(edizione: edizioni[index]),
    );
  }
}

class _CardEdizione extends StatelessWidget {
  const _CardEdizione({required this.edizione});

  final EdizioneCollezione edizione;

  @override
  Widget build(BuildContext context) {
    final sottotitolo = [
      edizione.serieName ?? edizione.publisher ?? '',
      if (edizione.numeroVisualizzato.isNotEmpty) edizione.numeroVisualizzato,
    ].where((s) => s.isNotEmpty).join(' · ');

    return GestureDetector(
      onTap: () => context.push('/scheda/${edizione.edizioneId}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: ComicCoverImage(
                    coverImage: edizione.coverImage,
                    titolo: edizione.titolo,
                    numero: edizione.issueNumber ?? 0,
                    etichetta: edizione.numeroVisualizzato,
                  ),
                ),
                if (edizione.numeroCopie > 1)
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
