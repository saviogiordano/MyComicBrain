// PROTOTIPO USA E GETTA — Mappa "Tutorial di inserimento di un nuovo
// fumetto", ticket "Tutorial: formato (slide a schermo intero, coach-mark o
// misto)" (#239). Vive solo sul branch `prototype/tutorial-formato`, mai su
// main.
//
// Tre varianti sovrapposte alla shell vera dell'app, switchabili dalla
// pillola in alto (solo debug): A slide a schermo intero, B coach-mark sulle
// schermate reali, C misto (scheda introduttiva + suggerimenti in contesto).
// Nessuna persistenza: "↻" fa ripartire il tutorial della variante corrente.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mycomicbrain/core/design_system/tokens.dart';

/// Chiavi appese ai widget reali da evidenziare (solo su questo branch).
abstract final class TutorialPrototypeKeys {
  static final scan = GlobalKey(debugLabel: 'tutorial.scan');
  static final fotocamera = GlobalKey(debugLabel: 'tutorial.fotocamera');
  static final galleria = GlobalKey(debugLabel: 'tutorial.galleria');
  static final fine = GlobalKey(debugLabel: 'tutorial.fine');
}

enum _Variante {
  a('A', 'Slide a schermo intero'),
  b('B', 'Coach-mark sulle schermate reali'),
  c('C', 'Misto: scheda + suggerimenti');

  const _Variante(this.chiave, this.nome);
  final String chiave;
  final String nome;
}

class TutorialPrototypeOverlay extends StatefulWidget {
  const TutorialPrototypeOverlay({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  State<TutorialPrototypeOverlay> createState() => _TutorialPrototypeOverlayState();
}

class _TutorialPrototypeOverlayState extends State<TutorialPrototypeOverlay> {
  var _variante = _Variante.a;
  var _attivo = true;
  // Cambiato a ogni riavvio così le varianti ripartono dal primo passo.
  var _generazione = 0;

  void _ricomincia() {
    widget.navigationShell.goBranch(0);
    setState(() {
      _attivo = true;
      _generazione++;
    });
  }

  void _cambia(int delta) {
    final valori = _Variante.values;
    _variante = valori[(_variante.index + delta) % valori.length];
    _ricomincia();
  }

  void _chiudi() => setState(() => _attivo = false);

  @override
  Widget build(BuildContext context) {
    final shell = widget.navigationShell;
    return Stack(
      children: [
        if (_attivo)
          Positioned.fill(
            child: KeyedSubtree(
              key: ValueKey('${_variante.chiave}-$_generazione'),
              child: switch (_variante) {
                _Variante.a => _VarianteSlide(shell: shell, onChiudi: _chiudi),
                _Variante.b => _VarianteCoachMark(shell: shell, onChiudi: _chiudi),
                _Variante.c => _VarianteMisto(shell: shell, onChiudi: _chiudi),
              },
            ),
          ),
        if (kDebugMode)
          _Switcher(
            variante: _variante,
            onPrecedente: () => _cambia(-1),
            onSuccessiva: () => _cambia(1),
            onRicomincia: _ricomincia,
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Pillola di switch (non fa parte del design valutato)
// ---------------------------------------------------------------------------

class _Switcher extends StatelessWidget {
  const _Switcher({
    required this.variante,
    required this.onPrecedente,
    required this.onSuccessiva,
    required this.onRicomincia,
  });

  final _Variante variante;
  final VoidCallback onPrecedente;
  final VoidCallback onSuccessiva;
  final VoidCallback onRicomincia;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(
        child: Material(
          color: Colors.white,
          elevation: 8,
          borderRadius: BorderRadius.circular(999),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(onPressed: onPrecedente, icon: const Icon(Icons.chevron_left, color: Colors.black)),
              Text(
                '${variante.chiave} (${variante.nome})',
                style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w600),
              ),
              IconButton(onPressed: onSuccessiva, icon: const Icon(Icons.chevron_right, color: Colors.black)),
              IconButton(onPressed: onRicomincia, icon: const Icon(Icons.refresh, color: Colors.black)),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// A — Slide a schermo intero
// ---------------------------------------------------------------------------

class _Slide {
  const _Slide(this.icona, this.titolo, this.testo, {this.illustrazione});
  final IconData icona;
  final String titolo;
  final String testo;
  final Widget? illustrazione;
}

final _slides = [
  const _Slide(
    Icons.document_scanner_outlined,
    'Aggiungi un fumetto fotografando la cover',
    'Tocca il pulsante centrale della barra in basso: da lì parte ogni nuovo inserimento.',
  ),
  const _Slide(
    Icons.photo_library_outlined,
    'Fotocamera o galleria, anche più cover di fila',
    'Scatta o scegli dalla galleria quante cover vuoi. Quando hai finito tocca "Fine": le cover partono tutte insieme.',
  ),
  const _Slide(
    Icons.auto_awesome_outlined,
    "L'AI legge la cover e ti propone i Candidati",
    'Per ogni cover vedi le edizioni più probabili, con il punteggio di confidenza.',
    illustrazione: _MockCandidati(),
  ),
  const _Slide(
    Icons.check_circle_outline,
    'Conferma quello giusto',
    'Tocca il Candidato corretto: la Copia entra nella tua collezione.',
  ),
  const _Slide(
    Icons.edit_note_outlined,
    'Nessuno è giusto? Inseriscilo a mano',
    'Dal riepilogo scegli "Inserisci manualmente" e compila i campi: la foto della cover resta collegata.',
  ),
];

class _VarianteSlide extends StatefulWidget {
  const _VarianteSlide({required this.shell, required this.onChiudi});
  final StatefulNavigationShell shell;
  final VoidCallback onChiudi;

  @override
  State<_VarianteSlide> createState() => _VarianteSlideState();
}

class _VarianteSlideState extends State<_VarianteSlide> {
  final _controller = PageController();
  var _pagina = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ultima = _pagina == _slides.length - 1;
    return Material(
      color: AppColors.surfaceDeepest,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 56, AppSpacing.xl, AppSpacing.xl),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: widget.onChiudi, child: const Text('Salta')),
              ),
              Expanded(
                child: PageView(
                  controller: _controller,
                  onPageChanged: (p) => setState(() => _pagina = p),
                  children: [
                    for (final s in _slides)
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              color: AppColors.accentAlpha(0.12),
                              borderRadius: BorderRadius.circular(AppRadii.xl),
                            ),
                            child: Icon(s.icona, color: AppColors.accent, size: 44),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          Text(s.titolo, textAlign: TextAlign.center, style: AppTypography.headline),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            s.testo,
                            textAlign: TextAlign.center,
                            style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
                          ),
                          if (s.illustrazione != null) ...[
                            const SizedBox(height: AppSpacing.xl),
                            s.illustrazione!,
                          ],
                        ],
                      ),
                  ],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _slides.length; i++)
                    Container(
                      margin: const EdgeInsets.all(3),
                      width: i == _pagina ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == _pagina ? AppColors.accent : AppColors.borderStrong,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: ultima
                      ? () {
                          widget.onChiudi();
                          widget.shell.goBranch(2);
                        }
                      : () => _controller.nextPage(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                        ),
                  child: Text(ultima ? 'Aggiungi il primo fumetto' : 'Avanti'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// B — Coach-mark sulle schermate reali
// ---------------------------------------------------------------------------

class _Passo {
  const _Passo({required this.ramo, required this.testo, this.bersaglio, this.illustrazione});

  /// Ramo della shell da mostrare sotto lo spotlight.
  final int ramo;
  final GlobalKey? bersaglio;
  final String testo;
  final Widget? illustrazione;
}

final _passiCoachMark = [
  _Passo(
    ramo: 0,
    bersaglio: TutorialPrototypeKeys.scan,
    testo: 'Ogni nuovo fumetto parte da qui: tocca il pulsante centrale.',
  ),
  _Passo(
    ramo: 2,
    bersaglio: TutorialPrototypeKeys.fotocamera,
    testo: 'Fotografa la cover. Puoi scattarne quante vuoi, una dopo l\'altra.',
  ),
  _Passo(
    ramo: 2,
    bersaglio: TutorialPrototypeKeys.galleria,
    testo: 'Oppure scegli le foto dalla galleria.',
  ),
  _Passo(
    ramo: 2,
    bersaglio: TutorialPrototypeKeys.fine,
    testo: 'Quando hai finito tocca "Fine": le cover vengono analizzate tutte insieme.',
  ),
  const _Passo(
    ramo: 2,
    testo: 'Nel riepilogo, per ogni cover, l\'AI ti propone i Candidati. Tocca quello giusto per aggiungerlo alla collezione.',
    illustrazione: _MockCandidati(),
  ),
  const _Passo(
    ramo: 2,
    testo: 'Se nessun Candidato è giusto, scegli "Inserisci manualmente".',
    illustrazione: _MockManuale(),
  ),
];

class _VarianteCoachMark extends StatefulWidget {
  const _VarianteCoachMark({required this.shell, required this.onChiudi, this.passi, this.etichettaFine});

  final StatefulNavigationShell shell;
  final VoidCallback onChiudi;
  final List<_Passo>? passi;
  final String? etichettaFine;

  @override
  State<_VarianteCoachMark> createState() => _VarianteCoachMarkState();
}

class _VarianteCoachMarkState extends State<_VarianteCoachMark> {
  var _indice = 0;

  List<_Passo> get _passi => widget.passi ?? _passiCoachMark;

  @override
  void initState() {
    super.initState();
    _vaiAlRamo();
  }

  void _vaiAlRamo() {
    widget.shell.goBranch(_passi[_indice].ramo);
    // Il bersaglio esiste solo dopo il frame che monta il ramo.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  void _avanti() {
    if (_indice == _passi.length - 1) {
      widget.onChiudi();
      return;
    }
    setState(() => _indice++);
    _vaiAlRamo();
  }

  Rect? _rettangolo(GlobalKey? chiave) {
    final target = chiave?.currentContext?.findRenderObject() as RenderBox?;
    final overlay = context.findRenderObject() as RenderBox?;
    if (target == null || overlay == null || !target.attached || !target.hasSize) return null;
    final origine = overlay.globalToLocal(target.localToGlobal(Offset.zero));
    return (origine & target.size).inflate(8);
  }

  @override
  Widget build(BuildContext context) {
    final passo = _passi[_indice];
    final buco = _rettangolo(passo.bersaglio);
    return LayoutBuilder(
      builder: (context, vincoli) {
        final sopra = buco != null && buco.center.dy > vincoli.maxHeight / 2;
        final fumetto = _Fumetto(
          testo: passo.testo,
          illustrazione: passo.illustrazione,
          posizione: '${_indice + 1}/${_passi.length}',
          etichettaAvanti: _indice == _passi.length - 1 ? (widget.etichettaFine ?? 'Ho capito') : 'Avanti',
          onAvanti: _avanti,
          onSalta: widget.onChiudi,
        );
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: CustomPaint(painter: _SpotlightPainter(buco)),
              ),
            ),
            if (buco == null)
              Center(child: Padding(padding: const EdgeInsets.all(AppSpacing.xl), child: fumetto))
            else
              Positioned(
                left: AppSpacing.lg,
                right: AppSpacing.lg,
                top: sopra ? null : buco.bottom + AppSpacing.sm,
                bottom: sopra ? vincoli.maxHeight - buco.top + AppSpacing.sm : null,
                child: fumetto,
              ),
          ],
        );
      },
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter(this.buco);
  final Rect? buco;

  @override
  void paint(Canvas canvas, Size size) {
    final sfondo = Path()..addRect(Offset.zero & size);
    final buco = this.buco;
    final path = buco == null
        ? sfondo
        : Path.combine(
            PathOperation.difference,
            sfondo,
            Path()..addRRect(RRect.fromRectAndRadius(buco, const Radius.circular(AppRadii.lg))),
          );
    canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: 0.72));
    if (buco != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(buco, const Radius.circular(AppRadii.lg)),
        Paint()
          ..color = AppColors.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) => old.buco != buco;
}

class _Fumetto extends StatelessWidget {
  const _Fumetto({
    required this.testo,
    required this.posizione,
    required this.etichettaAvanti,
    required this.onAvanti,
    required this.onSalta,
    this.illustrazione,
  });

  final String testo;
  final String posizione;
  final String etichettaAvanti;
  final VoidCallback onAvanti;
  final VoidCallback onSalta;
  final Widget? illustrazione;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceRaised,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(testo, style: AppTypography.bodyLarge),
            if (illustrazione != null) ...[
              const SizedBox(height: AppSpacing.md),
              Center(child: illustrazione),
            ],
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Text(posizione, style: AppTypography.monoLabel.copyWith(color: AppColors.textMuted)),
                const Spacer(),
                TextButton(onPressed: onSalta, child: const Text('Salta')),
                const SizedBox(width: AppSpacing.xs),
                FilledButton(onPressed: onAvanti, child: Text(etichettaAvanti)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// C — Misto: scheda introduttiva sulla Dashboard, poi suggerimenti in contesto
// ---------------------------------------------------------------------------

enum _FaseMisto { scheda, coachScan, suggerimentoScansione, anteprimaRiepilogo }

class _VarianteMisto extends StatefulWidget {
  const _VarianteMisto({required this.shell, required this.onChiudi});
  final StatefulNavigationShell shell;
  final VoidCallback onChiudi;

  @override
  State<_VarianteMisto> createState() => _VarianteMistoState();
}

class _VarianteMistoState extends State<_VarianteMisto> {
  var _fase = _FaseMisto.scheda;

  @override
  Widget build(BuildContext context) {
    switch (_fase) {
      case _FaseMisto.scheda:
        return _SchedaIntroduttiva(
          onMostrami: () => setState(() => _fase = _FaseMisto.coachScan),
          onSalta: widget.onChiudi,
        );
      case _FaseMisto.coachScan:
        return _VarianteCoachMark(
          shell: widget.shell,
          onChiudi: () {
            widget.shell.goBranch(2);
            setState(() => _fase = _FaseMisto.suggerimentoScansione);
          },
          passi: [
            _Passo(
              ramo: 0,
              bersaglio: TutorialPrototypeKeys.scan,
              testo: 'Proviamo: tocca il pulsante centrale per aggiungere il tuo primo fumetto.',
            ),
          ],
          etichettaFine: 'Vai',
        );
      case _FaseMisto.suggerimentoScansione:
        return _SuggerimentoInContesto(
          testo: 'Scatta o scegli dalla galleria una o più cover, poi tocca "Fine".',
          nota: 'Suggerimento in contesto: compare la prima volta che apri la Scansione e non blocca lo schermo.',
          onAvanti: () => setState(() => _fase = _FaseMisto.anteprimaRiepilogo),
          onChiudi: widget.onChiudi,
        );
      case _FaseMisto.anteprimaRiepilogo:
        return _SuggerimentoInContesto(
          testo: 'Tocca il Candidato giusto per aggiungerlo. Nessuno va bene? "Inserisci manualmente".',
          nota: 'Anteprima: nell\'app vera questo compare la prima volta che apri il riepilogo con dei Candidati.',
          illustrazione: const _MockCandidati(),
          onAvanti: widget.onChiudi,
          onChiudi: widget.onChiudi,
        );
    }
  }
}

class _SchedaIntroduttiva extends StatelessWidget {
  const _SchedaIntroduttiva({required this.onMostrami, required this.onSalta});
  final VoidCallback onMostrami;
  final VoidCallback onSalta;

  @override
  Widget build(BuildContext context) {
    Widget riga(IconData icona, String titolo, String testo) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icona, color: AppColors.accent),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titolo, style: AppTypography.titleMedium),
                Text(testo, style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );

    return Stack(
      children: [
        Positioned.fill(child: ColoredBox(color: Colors.black.withValues(alpha: 0.55))),
        Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            color: AppColors.surfaceRaised,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadii.xl)),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Come aggiungere un fumetto', style: AppTypography.headline),
                    const SizedBox(height: AppSpacing.lg),
                    riga(Icons.document_scanner_outlined, 'Fotografa la cover',
                        "L'AI la riconosce e ti propone i Candidati: confermi quello giusto."),
                    riga(Icons.burst_mode_outlined, 'Più cover di fila',
                        'Scatta o scegli dalla galleria quante cover vuoi, poi "Fine".'),
                    riga(Icons.edit_note_outlined, 'A mano',
                        'Se nessun Candidato è giusto, inserisci tu i dati.'),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        TextButton(onPressed: onSalta, child: const Text('Salta')),
                        const Spacer(),
                        FilledButton(onPressed: onMostrami, child: const Text('Mostrami')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SuggerimentoInContesto extends StatelessWidget {
  const _SuggerimentoInContesto({
    required this.testo,
    required this.nota,
    required this.onAvanti,
    required this.onChiudi,
    this.illustrazione,
  });

  final String testo;
  final String nota;
  final VoidCallback onAvanti;
  final VoidCallback onChiudi;
  final Widget? illustrazione;

  @override
  Widget build(BuildContext context) {
    // Non blocca: niente velo, solo un banner sotto la pillola di switch.
    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, 56, AppSpacing.md, 0),
          child: Material(
            color: AppColors.surfaceRaised,
            elevation: 6,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.lightbulb_outline, color: AppColors.amber),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: Text(testo, style: AppTypography.bodyMedium)),
                      IconButton(onPressed: onChiudi, icon: const Icon(Icons.close, size: 18)),
                    ],
                  ),
                  if (illustrazione != null) Center(child: illustrazione),
                  Text(nota, style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted)),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(onPressed: onAvanti, child: const Text('Avanti')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Illustrazioni finte condivise
// ---------------------------------------------------------------------------

class _MockCandidati extends StatelessWidget {
  const _MockCandidati();

  @override
  Widget build(BuildContext context) {
    Widget candidato(String titolo, int punteggio, {bool evidenziato = false}) => Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.overlayCardHover,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: evidenziato ? AppColors.accent : AppColors.borderDefault),
      ),
      child: Row(
        children: [
          Container(width: 28, height: 40, color: AppColors.borderStrong),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(titolo, style: AppTypography.bodySmall)),
          Text('$punteggio%', style: AppTypography.monoLabel.copyWith(color: AppColors.accent)),
        ],
      ),
    );
    return SizedBox(
      width: 260,
      child: Column(
        children: [
          candidato('Tex n. 1 — Bonelli', 92, evidenziato: true),
          candidato('Tex Gigante n. 1', 61),
        ],
      ),
    );
  }
}

class _MockManuale extends StatelessWidget {
  const _MockManuale();

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () {},
      icon: const Icon(Icons.edit_note_outlined),
      label: const Text('Inserisci manualmente'),
    );
  }
}
