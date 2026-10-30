import 'package:flutter/material.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';

/// Elementi reali che il Tutorial di inserimento illumina (PRD #242). Ognuno
/// è montato in un solo punto alla volta.
abstract final class TutorialInserimentoKeys {
  static final GlobalKey pulsanteScansione = GlobalKey(
    debugLabel: 'pulsanteScansione',
  );
  static final GlobalKey fotocamera = GlobalKey(debugLabel: 'fotocamera');
  static final GlobalKey galleria = GlobalKey(debugLabel: 'galleria');
  static final GlobalKey fine = GlobalKey(debugLabel: 'fine');
  static final GlobalKey chipRiepilogo = GlobalKey(debugLabel: 'chipRiepilogo');
  static final GlobalKey primoCandidato = GlobalKey(
    debugLabel: 'primoCandidato',
  );
  static final GlobalKey inserisciManualmente = GlobalKey(
    debugLabel: 'inserisciManualmente',
  );
}

class PassoSpotlight {
  const PassoSpotlight({required this.bersaglio, required this.testo});

  final GlobalKey bersaglio;
  final String testo;
}

/// Spotlight bloccante sugli elementi reali (variante C con gli spotlight
/// di B del prototipo, deciso su #239): si avanza con "Avanti", "Salta"
/// chiude tutto il tutorial. Va messo sopra la schermata in uno [Stack]
/// a tutto schermo.
class Spotlight extends StatefulWidget {
  const Spotlight({
    required this.passi,
    required this.onSalta,
    required this.onFine,
    this.primaDelPasso,
    super.key,
  });

  final List<PassoSpotlight> passi;
  final VoidCallback onSalta;
  final VoidCallback onFine;

  /// Chiamata prima di mostrare il passo all'indice dato, per portare a
  /// schermo il suo bersaglio (es. cambiare tab).
  final void Function(int indice)? primaDelPasso;

  @override
  State<Spotlight> createState() => _SpotlightState();
}

class _SpotlightState extends State<Spotlight> {
  var _indice = 0;

  /// Il bersaglio del passo corrente, misurato dopo ogni frame: durante il
  /// build il suo elemento può non essere ancora attivo.
  Rect? _buco;

  /// Frame già attesi per il bersaglio del passo corrente: oltre
  /// [_tentativiMassimi] il fumetto si mostra comunque, al centro.
  var _tentativi = 0;
  static const _tentativiMassimi = 10;

  @override
  void initState() {
    super.initState();
    widget.primaDelPasso?.call(0);
  }

  void _avanti() {
    if (_indice == widget.passi.length - 1) {
      widget.onFine();
      return;
    }
    widget.primaDelPasso?.call(_indice + 1);
    setState(() {
      _indice++;
      _buco = null;
      _tentativi = 0;
    });
  }

  void _misuraDopoIlFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final buco = _rettangolo(widget.passi[_indice].bersaglio);
      if (buco == null) {
        // Il bersaglio compare solo dopo il frame che monta la sua
        // schermata.
        if (_tentativi < _tentativiMassimi) setState(() => _tentativi++);
      } else if (buco != _buco) {
        setState(() => _buco = buco);
      }
    });
  }

  Rect? _rettangolo(GlobalKey chiave) {
    final target = chiave.currentContext?.findRenderObject() as RenderBox?;
    final overlay = context.findRenderObject() as RenderBox?;
    if (target == null ||
        overlay == null ||
        !target.attached ||
        !target.hasSize ||
        !overlay.hasSize) {
      return null;
    }
    final origine = overlay.globalToLocal(target.localToGlobal(Offset.zero));
    return (origine & target.size).inflate(8);
  }

  @override
  Widget build(BuildContext context) {
    final passo = widget.passi[_indice];
    final buco = _buco;
    final inAttesa = buco == null && _tentativi < _tentativiMassimi;
    _misuraDopoIlFrame();
    final ultimo = _indice == widget.passi.length - 1;
    return LayoutBuilder(
      builder: (context, vincoli) {
        final fumetto = _Fumetto(
          testo: passo.testo,
          posizione: widget.passi.length > 1
              ? '${_indice + 1}/${widget.passi.length}'
              : null,
          etichettaAvanti: ultimo ? 'Ho capito' : 'Avanti',
          onAvanti: _avanti,
          onSalta: widget.onSalta,
        );
        final sopra = buco != null && buco.center.dy > vincoli.maxHeight / 2;
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: CustomPaint(painter: _SpotlightPainter(buco)),
              ),
            ),
            if (buco == null && !inAttesa)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: fumetto,
                ),
              )
            else if (buco != null)
              Positioned(
                left: AppSpacing.lg,
                right: AppSpacing.lg,
                top: sopra ? null : buco.bottom + AppSpacing.sm,
                bottom: sopra
                    ? vincoli.maxHeight - buco.top + AppSpacing.sm
                    : null,
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
            Path()..addRRect(
              RRect.fromRectAndRadius(buco, const Radius.circular(AppRadii.lg)),
            ),
          );
    canvas.drawPath(
      path,
      Paint()..color = Colors.black.withValues(alpha: 0.72),
    );
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
  });

  final String testo;
  final String? posizione;
  final String etichettaAvanti;
  final VoidCallback onAvanti;
  final VoidCallback onSalta;

  @override
  Widget build(BuildContext context) {
    final posizione = this.posizione;
    return Material(
      color: AppColors.surfaceRaised,
      borderRadius: AppRadii.lgRadius,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              testo,
              style: AppTypography.bodyLarge.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                if (posizione != null)
                  Text(
                    posizione,
                    style: AppTypography.monoLabel.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                const Spacer(),
                TextButton(onPressed: onSalta, child: const Text('Salta')),
                const SizedBox(width: AppSpacing.xs),
                FilledButton(
                  // Il tema dà ai FilledButton solo padding verticale:
                  // pensato per i pulsanti a tutta larghezza.
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xs,
                    ),
                  ),
                  onPressed: onAvanti,
                  child: Text(etichettaAvanti),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
