// PROTOTIPO throwaway — ticket #164 (child della Mappa #163).
//
// Domanda: come devono apparire e comportarsi il meccanismo di selezione
// multipla nella vista Collezione (§9, oggi inesistente) e l'azione in
// blocco "Segna come in vendita" che ne dipende.
//
// Tre varianti radicalmente diverse, montate sulla rotta reale `/collezione`
// (dati veri, griglia vera) e selezionabili con `?variant=a|b|c` — vedi la
// skill `/prototype` (sub-shape A). Lo stato "in vendita" è mockato in
// memoria (nessuna persistenza, nessuna scrittura sul repository reale): il
// campo `inVendita` non esiste ancora su Copia, è esattamente ciò che questo
// prototipo anticipa in UI prima che esista il backend.
//
// Da NON promuovere così com'è: niente test, niente gestione errori,
// mutazione finta. Una volta scelta una variante, riscrivere per bene e
// spostare l'intero file su un branch throwaway (vedi SKILL.md).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/core/domain/edizione_collezione.dart';
import 'package:mycomicbrain/features/collezione/application/collezione_providers.dart';

enum VariantePrototipo {
  a('A', 'Long-press + barra flottante'),
  b('B', 'Pulsante toolbar + FAB menu'),
  c('C', 'Modifica/Fatto + foglio riepilogo');

  const VariantePrototipo(this.chiave, this.nome);

  final String chiave;
  final String nome;

  static VariantePrototipo? fromParam(String? valore) {
    for (final v in VariantePrototipo.values) {
      if (v.chiave.toLowerCase() == valore?.toLowerCase()) return v;
    }
    return null;
  }
}

/// Mock condiviso dalle tre varianti dello stato "in vendita" — solo in
/// memoria, seminato all'apertura così qualche card parte già marcata e le
/// varianti possono mostrare subito il badge "fuori selezione".
class _InVenditaMock extends ChangeNotifier {
  final Set<int> _edizioni = {};
  bool _seminato = false;

  bool contiene(int edizioneId) => _edizioni.contains(edizioneId);

  void seminaSeNecessario(List<EdizioneCollezioneFinestra> edizioni) {
    if (_seminato || edizioni.isEmpty) return;
    _seminato = true;
    for (var i = 0; i < edizioni.length; i++) {
      if (i % 4 == 1) _edizioni.add(edizioni[i].edizioneId);
    }
  }

  /// Applica l'azione in blocco: marca le edizioni selezionate. Ritorna il
  /// numero di copie possedute coinvolte, per il feedback — regola di
  /// cascata decisa in fase di destinazione: selezionare un'edizione marca
  /// tutte le sue copie possedute.
  int applica(Iterable<EdizioneCollezioneFinestra> selezionate) {
    var copie = 0;
    for (final e in selezionate) {
      _edizioni.add(e.edizioneId);
      copie += e.numeroCopie;
    }
    notifyListeners();
    return copie;
  }
}

final _inVenditaMockProvider = ChangeNotifierProvider<_InVenditaMock>(
  (ref) => _InVenditaMock(),
);

/// Punto di montaggio sulla rotta reale: legge i dati della Collezione dagli
/// stessi provider di produzione (`edizioniFinestraCollezioneProvider`) —
/// solo il render della griglia/toolbar/azioni cambia per variante.
class SelezioneMultiplaPrototype extends ConsumerWidget {
  const SelezioneMultiplaPrototype({required this.variante, super.key});

  final VariantePrototipo variante;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final finestra =
        ref.watch(edizioniFinestraCollezioneProvider).valueOrNull ?? const [];
    final mock = ref.watch(_inVenditaMockProvider);
    mock.seminaSeNecessario(finestra);

    if (finestra.isEmpty) {
      return Center(
        child: Text(
          'Nessuna edizione da mostrare per il prototipo.',
          style: TextStyle(color: AppColors.textMuted),
        ),
      );
    }

    return switch (variante) {
      VariantePrototipo.a => _VarianteA(edizioni: finestra),
      VariantePrototipo.b => _VarianteB(edizioni: finestra),
      VariantePrototipo.c => _VarianteC(edizioni: finestra),
    };
  }
}

/// Barra flottante in basso a centro schermo per passare da una variante
/// all'altra — visivamente estranea al design reale apposta (skill
/// `/prototype`, "hidden in production": qui non c'è un flag di build, il
/// file intero è throwaway e non arriva su main).
class PrototypeSwitcher extends StatelessWidget {
  const PrototypeSwitcher({
    required this.corrente,
    required this.onCambia,
    super.key,
  });

  final VariantePrototipo corrente;
  final ValueChanged<VariantePrototipo> onCambia;

  @override
  Widget build(BuildContext context) {
    final valori = VariantePrototipo.values;
    final indice = valori.indexOf(corrente);

    void cicla(int delta) {
      final prossimo = valori[(indice + delta + valori.length) % valori.length];
      onCambia(prossimo);
    }

    return Positioned(
      left: 0,
      right: 0,
      bottom: 8,
      child: Center(
        child: Material(
          color: const Color(0xFFFF00AA),
          borderRadius: BorderRadius.circular(999),
          elevation: 6,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  color: Colors.white,
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => cicla(-1),
                ),
                Text(
                  '${corrente.chiave} — ${corrente.nome}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                IconButton(
                  color: Colors.white,
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => cicla(1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Variante A — long-press per entrare, checkbox top-left, barra flottante.
// ---------------------------------------------------------------------------

class _VarianteA extends ConsumerStatefulWidget {
  const _VarianteA({required this.edizioni});

  final List<EdizioneCollezioneFinestra> edizioni;

  @override
  ConsumerState<_VarianteA> createState() => _VarianteAState();
}

class _VarianteAState extends ConsumerState<_VarianteA> {
  bool _attiva = false;
  final Set<int> _selezionati = {};

  void _entra(int edizioneId) {
    setState(() {
      _attiva = true;
      _selezionati.add(edizioneId);
    });
  }

  void _esci() => setState(() {
    _attiva = false;
    _selezionati.clear();
  });

  void _toggle(int edizioneId) => setState(() {
    if (!_selezionati.remove(edizioneId)) _selezionati.add(edizioneId);
    if (_selezionati.isEmpty) _attiva = false;
  });

  Future<void> _applica() async {
    final mock = ref.read(_inVenditaMockProvider);
    final selezionate = widget.edizioni
        .where((e) => _selezionati.contains(e.edizioneId))
        .toList();
    final copie = selezionate.fold<int>(0, (s, e) => s + e.numeroCopie);

    final conferma = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceRaised,
        title: const Text('Segnare come in vendita?'),
        content: Text(
          '${selezionate.length} '
          '${selezionate.length == 1 ? 'edizione' : 'edizioni'} selezionata'
          '${selezionate.length == 1 ? '' : 'e'} ($copie copie possedute in '
          'totale) verranno segnate come in vendita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Conferma'),
          ),
        ],
      ),
    );
    if (conferma != true || !mounted) return;

    final copieMarcate = mock.applica(selezionate);
    _esci();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Segnate ${selezionate.length} '
          '${selezionate.length == 1 ? 'edizione' : 'edizioni'} come in '
          'vendita ($copieMarcate copie).',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mock = ref.watch(_inVenditaMockProvider);

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              child: _attiva
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${_selezionati.length} selezionat'
                          '${_selezionati.length == 1 ? 'a' : 'e'}',
                          style: AppTypography.titleMedium.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                        TextButton(
                          onPressed: _esci,
                          child: const Text('Annulla'),
                        ),
                      ],
                    )
                  : Text(
                      'Collezione — tieni premuto su una copertina per '
                      'selezionare',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.xs,
                  AppSpacing.md,
                  AppSpacing.xxl + 56,
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: AppSpacing.xs + 2,
                  mainAxisSpacing: AppSpacing.xs + 2,
                  childAspectRatio: 0.6,
                ),
                itemCount: widget.edizioni.length,
                itemBuilder: (context, index) {
                  final e = widget.edizioni[index];
                  final selezionata = _selezionati.contains(e.edizioneId);
                  return GestureDetector(
                    onTap: _attiva
                        ? () => _toggle(e.edizioneId)
                        : () {}, // nella vista reale: apre la scheda edizione
                    onLongPress: _attiva ? null : () => _entra(e.edizioneId),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: Opacity(
                                  opacity: _attiva && !selezionata ? 0.55 : 1,
                                  child: ComicCoverImage(
                                    coverImage: e.coverImage,
                                    titolo: e.titolo,
                                    numero: e.issueNumber ?? 0,
                                    etichetta: e.numeroVisualizzato,
                                  ),
                                ),
                              ),
                              if (!_attiva && mock.contiene(e.edizioneId))
                                const Positioned(
                                  left: 5,
                                  bottom: 5,
                                  child: _TagInVendita(),
                                ),
                              if (_attiva)
                                Positioned(
                                  top: 5,
                                  left: 5,
                                  child: Container(
                                    width: 22,
                                    height: 22,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: selezionata
                                          ? AppColors.accent
                                          : AppColors.surfaceDeepest
                                                .withValues(alpha: 0.7),
                                      border: Border.all(
                                        color: selezionata
                                            ? AppColors.accent
                                            : AppColors.borderStrong,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: selezionata
                                        ? const Icon(
                                            Icons.check,
                                            size: 15,
                                            color: AppColors.onAccent,
                                          )
                                        : null,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          e.titolo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.labelMedium.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        if (_attiva)
          Positioned(
            left: AppSpacing.md,
            right: AppSpacing.md,
            bottom: AppSpacing.xl,
            child: Material(
              color: AppColors.surfaceRaised,
              borderRadius: AppRadii.pillRadius,
              elevation: 8,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_selezionati.length} selezionat'
                      '${_selezionati.length == 1 ? 'a' : 'e'}',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _applica,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: AppColors.onAccent,
                      ),
                      icon: const Icon(Icons.sell_outlined, size: 16),
                      label: const Text('Segna come in vendita'),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TagInVendita extends StatelessWidget {
  const _TagInVendita();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.accentAlpha(0.85),
        borderRadius: AppRadii.pillRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.sell, size: 9, color: AppColors.onAccent),
          const SizedBox(width: 2),
          Text(
            'In vendita',
            style: AppTypography.monoLabel.copyWith(
              color: AppColors.onAccent,
              fontSize: 8.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Variante B — pulsante dedicato in toolbar, FAB con menu azioni, banner
// ribbon per "in vendita".
// ---------------------------------------------------------------------------

class _VarianteB extends ConsumerStatefulWidget {
  const _VarianteB({required this.edizioni});

  final List<EdizioneCollezioneFinestra> edizioni;

  @override
  ConsumerState<_VarianteB> createState() => _VarianteBState();
}

class _VarianteBState extends ConsumerState<_VarianteB> {
  bool _attiva = false;
  final Set<int> _selezionati = {};
  String? _messaggioBanner;
  Timer? _bannerTimer;

  @override
  void dispose() {
    _bannerTimer?.cancel();
    super.dispose();
  }

  void _mostraBanner(String testo) {
    _bannerTimer?.cancel();
    setState(() => _messaggioBanner = testo);
    _bannerTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _messaggioBanner = null);
    });
  }

  void _toggleModalita() => setState(() {
    _attiva = !_attiva;
    if (!_attiva) _selezionati.clear();
  });

  void _toggleSelezione(int edizioneId) => setState(() {
    if (!_selezionati.remove(edizioneId)) _selezionati.add(edizioneId);
  });

  Future<void> _apriMenuAzioni() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        var confermaEspansa = false;
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final selezionate = widget.edizioni
                .where((e) => _selezionati.contains(e.edizioneId))
                .toList();
            final copie = selezionate.fold<int>(0, (s, e) => s + e.numeroCopie);

            return Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.lg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${selezionate.length} selezionate',
                    style: AppTypography.titleMedium.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.sell_outlined,
                      color: AppColors.accent,
                    ),
                    title: const Text('Segna come in vendita'),
                    onTap: () => setSheetState(() => confermaEspansa = true),
                  ),
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    enabled: false,
                    leading: Icon(Icons.remove_shopping_cart_outlined),
                    title: Text('Rimuovi da in vendita'),
                    subtitle: Text('Nessuna selezionata è già in vendita'),
                  ),
                  if (confermaEspansa) ...[
                    const Divider(color: AppColors.borderSubtle),
                    Text(
                      '$copie copie possedute (fra tutte le copie delle '
                      'edizioni selezionate) verranno segnate come in '
                      'vendita.',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: AppColors.onAccent,
                        ),
                        onPressed: () {
                          final copieMarcate = ref
                              .read(_inVenditaMockProvider)
                              .applica(selezionate);
                          Navigator.of(sheetContext).pop();
                          setState(() {
                            _attiva = false;
                            _selezionati.clear();
                          });
                          _mostraBanner(
                            '✓ ${selezionate.length} edizioni ($copieMarcate '
                            'copie) segnate come in vendita',
                          );
                        },
                        child: const Text('Conferma'),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final mock = ref.watch(_inVenditaMockProvider);

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Collezione',
                    style: AppTypography.titleLarge.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                  OutlinedButton(
                    onPressed: _toggleModalita,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _attiva
                          ? AppColors.accent
                          : AppColors.textSecondary,
                      side: BorderSide(
                        color: _attiva
                            ? AppColors.accent
                            : AppColors.borderDefault,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: AppRadii.pillRadius,
                      ),
                    ),
                    child: Text(_attiva ? 'Annulla' : 'Seleziona'),
                  ),
                ],
              ),
            ),
            if (_messaggioBanner != null)
              Container(
                margin: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.xs,
                  AppSpacing.md,
                  0,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accentAlpha(0.12),
                  borderRadius: AppRadii.smRadius,
                  border: Border.all(color: AppColors.accentAlpha(0.35)),
                ),
                child: Text(
                  _messaggioBanner!,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.accentLight,
                  ),
                ),
              ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.xs,
                  AppSpacing.md,
                  AppSpacing.xxl + 56,
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: AppSpacing.xs + 2,
                  mainAxisSpacing: AppSpacing.xs + 2,
                  childAspectRatio: 0.6,
                ),
                itemCount: widget.edizioni.length,
                itemBuilder: (context, index) {
                  final e = widget.edizioni[index];
                  final selezionata = _selezionati.contains(e.edizioneId);
                  return GestureDetector(
                    onTap: _attiva
                        ? () => _toggleSelezione(e.edizioneId)
                        : () {}, // nella vista reale: apre la scheda edizione
                    child: Opacity(
                      opacity: _attiva && !selezionata ? 0.5 : 1,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: AppRadii.xsRadius,
                          border: selezionata
                              ? Border.all(color: AppColors.accent, width: 2)
                              : null,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: ComicCoverImage(
                                      coverImage: e.coverImage,
                                      titolo: e.titolo,
                                      numero: e.issueNumber ?? 0,
                                      etichetta: e.numeroVisualizzato,
                                    ),
                                  ),
                                  if (!_attiva && mock.contiene(e.edizioneId))
                                    const Positioned(
                                      top: 0,
                                      left: 0,
                                      right: 0,
                                      child: _RibbonInVendita(),
                                    ),
                                  if (selezionata)
                                    Positioned(
                                      top: 5,
                                      right: 5,
                                      child: Container(
                                        width: 18,
                                        height: 18,
                                        decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: AppColors.accent,
                                        ),
                                        child: const Icon(
                                          Icons.check,
                                          size: 12,
                                          color: AppColors.onAccent,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              e.titolo,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.labelMedium.copyWith(
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        if (_attiva && _selezionati.isNotEmpty)
          Positioned(
            right: AppSpacing.md,
            bottom: AppSpacing.xl,
            child: FloatingActionButton.extended(
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.onAccent,
              onPressed: _apriMenuAzioni,
              icon: const Icon(Icons.more_horiz),
              label: Text('${_selezionati.length}'),
            ),
          ),
      ],
    );
  }
}

class _RibbonInVendita extends StatelessWidget {
  const _RibbonInVendita();

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 3),
      color: AppColors.amberAlpha(0.88),
      child: Text(
        'IN VENDITA',
        style: AppTypography.monoLabel.copyWith(
          color: AppColors.surfaceDeepest,
          fontSize: 8,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Variante C — "Modifica/Fatto", seleziona-tutti, foglio riepilogo a lista,
// feedback come highlight in-place invece che messaggio.
// ---------------------------------------------------------------------------

class _VarianteC extends ConsumerStatefulWidget {
  const _VarianteC({required this.edizioni});

  final List<EdizioneCollezioneFinestra> edizioni;

  @override
  ConsumerState<_VarianteC> createState() => _VarianteCState();
}

class _VarianteCState extends ConsumerState<_VarianteC> {
  bool _attiva = false;
  final Set<int> _selezionati = {};
  final Set<int> _evidenziati = {};

  void _toggleModalita() => setState(() {
    _attiva = !_attiva;
    if (!_attiva) _selezionati.clear();
  });

  void _toggleSelezione(int edizioneId) => setState(() {
    if (!_selezionati.remove(edizioneId)) _selezionati.add(edizioneId);
  });

  void _selezionaTutti() => setState(() {
    _selezionati
      ..clear()
      ..addAll(widget.edizioni.map((e) => e.edizioneId));
  });

  void _deselezionaTutti() => setState(_selezionati.clear);

  Future<void> _apriRiepilogo() async {
    final selezionate = widget.edizioni
        .where((e) => _selezionati.contains(e.edizioneId))
        .toList();

    final confermato = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.85,
          minChildSize: 0.3,
          expand: false,
          builder: (context, scrollController) {
            final copieTotali = selezionate.fold<int>(
              0,
              (s, e) => s + e.numeroCopie,
            );
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.md,
                    AppSpacing.xs,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Segna come in vendita',
                        style: AppTypography.titleMedium.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${selezionate.length} edizioni · $copieTotali copie '
                        'possedute in totale — ogni edizione con più copie '
                        'viene marcata su tutte le sue copie possedute.',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.borderSubtle),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                    itemCount: selezionate.length,
                    itemBuilder: (context, index) {
                      final e = selezionate[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          e.titolo,
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                        trailing: Text(
                          e.numeroCopie == 1
                              ? '1 copia'
                              : '${e.numeroCopie} copie',
                          style: AppTypography.monoLabel.copyWith(
                            color: AppColors.textMuted,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.md,
                    AppSpacing.sm + MediaQuery.of(context).padding.bottom,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: AppColors.onAccent,
                      ),
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Text('Conferma per $copieTotali copie'),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (confermato != true || !mounted) return;
    ref.read(_inVenditaMockProvider).applica(selezionate);
    final idSelezionati = {..._selezionati};
    setState(() {
      _attiva = false;
      _selezionati.clear();
      _evidenziati.addAll(idSelezionati);
    });
    Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _evidenziati.removeAll(idSelezionati));
    });
  }

  @override
  Widget build(BuildContext context) {
    final mock = ref.watch(_inVenditaMockProvider);

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Collezione',
                    style: AppTypography.titleLarge.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                  TextButton(
                    onPressed: _toggleModalita,
                    child: Text(_attiva ? 'Fatto' : 'Modifica'),
                  ),
                ],
              ),
            ),
            if (_attiva)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Row(
                  children: [
                    Text(
                      '${_selezionati.length} selezionate',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _selezionati.length == widget.edizioni.length
                          ? _deselezionaTutti
                          : _selezionaTutti,
                      child: Text(
                        _selezionati.length == widget.edizioni.length
                            ? 'Deseleziona tutti'
                            : 'Seleziona tutti visibili',
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.xs,
                  AppSpacing.md,
                  AppSpacing.xxl + 56,
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: AppSpacing.xs + 2,
                  mainAxisSpacing: AppSpacing.xs + 2,
                  childAspectRatio: 0.6,
                ),
                itemCount: widget.edizioni.length,
                itemBuilder: (context, index) {
                  final e = widget.edizioni[index];
                  final selezionata = _selezionati.contains(e.edizioneId);
                  final evidenziata = _evidenziati.contains(e.edizioneId);
                  return GestureDetector(
                    onTap: _attiva
                        ? () => _toggleSelezione(e.edizioneId)
                        : () {}, // nella vista reale: apre la scheda edizione
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      decoration: BoxDecoration(
                        borderRadius: AppRadii.smRadius,
                        color: evidenziata
                            ? AppColors.accentAlpha(0.18)
                            : Colors.transparent,
                      ),
                      padding: const EdgeInsets.all(3),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: Opacity(
                                    opacity: _attiva && !selezionata
                                        ? 0.4
                                        : 1,
                                    child: ComicCoverImage(
                                      coverImage: e.coverImage,
                                      titolo: e.titolo,
                                      numero: e.issueNumber ?? 0,
                                      etichetta: e.numeroVisualizzato,
                                    ),
                                  ),
                                ),
                                if (!_attiva && mock.contiene(e.edizioneId))
                                  const Positioned(
                                    top: 5,
                                    right: 5,
                                    child: _IconaInVendita(),
                                  ),
                                if (selezionata)
                                  const Positioned.fill(
                                    child: Center(
                                      child: Icon(
                                        Icons.check_circle,
                                        color: AppColors.accent,
                                        size: 32,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            e.titolo,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.labelMedium.copyWith(
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        if (_attiva)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: AppColors.surfaceRaised,
              padding: EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.sm + MediaQuery.of(context).padding.bottom,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_selezionati.length} selezionate',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  TextButton(
                    onPressed: _selezionati.isEmpty ? null : _apriRiepilogo,
                    child: const Text('Segna come in vendita'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _IconaInVendita extends StatelessWidget {
  const _IconaInVendita();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.surfaceDeepest,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.sell, size: 10, color: AppColors.amber),
    );
  }
}
