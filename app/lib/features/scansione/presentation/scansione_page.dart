import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';

/// I 5 suggerimenti statici (deciso su #22): ordine per fasi logiche
/// (distanza → allineamento → illuminazione → riflessi → messa a fuoco),
/// nessun feedback in tempo reale — solo testo fisso, avanzamento al tocco.
class _GuideHint {
  const _GuideHint(this.icon, this.label);

  final IconData icon;
  final String label;
}

const _guideHints = <_GuideHint>[
  _GuideHint(Icons.social_distance_outlined, 'Inquadra tutta la copertina'),
  _GuideHint(Icons.crop_free, 'Allinea la copertina dritta'),
  _GuideHint(Icons.wb_sunny_outlined, 'Cerca più luce'),
  _GuideHint(Icons.flare_outlined, 'Evita i riflessi'),
  _GuideHint(Icons.center_focus_strong_outlined, 'Tieni ferma la fotocamera'),
];

/// Schermata `/scansione` (requisito 5.1, Variante B — Corner brackets,
/// decisa su #19): fotocamera live con overlay a 4 angoli, pillola di
/// suggerimento, filmstrip del batch in corso, Galleria e "Fine".
///
/// Al tocco su una foto scattata/selezionata naviga alla revisione
/// ritaglio/rotazione; "Fine" naviga al riepilogo di fine batch — entrambe
/// definite su #20 ma non ancora implementate (stub, vedi #24).
class ScansionePage extends StatefulWidget {
  const ScansionePage({super.key});

  @override
  State<ScansionePage> createState() => _ScansionePageState();
}

class _ScansionePageState extends State<ScansionePage> with WidgetsBindingObserver {
  CameraController? _controller;
  bool _cameraNonDisponibile = false;
  bool _scattando = false;
  int _hintIndex = 0;
  final _captures = <XFile>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initCamera());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      unawaited(controller.dispose());
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_initCamera());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_controller?.dispose());
    super.dispose();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    // Nessuna fotocamera (es. iOS Simulator, vedi docs/research/camera-package-flutter.md
    // §6): mostra un fallback statico invece di bloccare la schermata.
    if (cameras.isEmpty) {
      if (mounted) setState(() => _cameraNonDisponibile = true);
      return;
    }

    final camera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    final controller = CameraController(camera, ResolutionPreset.high, enableAudio: false);

    try {
      await controller.initialize();
    } on CameraException {
      if (mounted) setState(() => _cameraNonDisponibile = true);
      return;
    }

    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() {
      _controller = controller;
      _cameraNonDisponibile = false;
    });
  }

  Future<void> _scatta() async {
    final controller = _controller;
    if (controller == null || _scattando) return;

    setState(() => _scattando = true);
    try {
      final foto = await controller.takePicture();
      if (!mounted) return;
      setState(() => _captures.add(foto));
      unawaited(context.push('/scansione/revisione'));
    } on CameraException {
      // Gestione errori di scatto: fuori scope (vedi "Not yet specified" su #15).
    } finally {
      if (mounted) setState(() => _scattando = false);
    }
  }

  Future<void> _aggiungiDaGalleria() async {
    final foto = await ImagePicker().pickMultiImage();
    if (foto.isEmpty || !mounted) return;
    setState(() => _captures.addAll(foto));
    unawaited(context.push('/scansione/revisione'));
  }

  void _prossimoSuggerimento() => setState(() => _hintIndex = (_hintIndex + 1) % _guideHints.length);

  void _fine() => context.push('/scansione/riepilogo');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceDeepest,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _CameraBackground(controller: _controller, nonDisponibile: _cameraNonDisponibile),
          if (_controller != null)
            const Center(
              child: AspectRatio(
                aspectRatio: 0.68,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
                  child: CustomPaint(painter: _CornerBracketsPainter()),
                ),
              ),
            ),
          SafeArea(
            child: Column(
              children: [
                _Filmstrip(captures: _captures, onFine: _fine),
                const Spacer(),
                _HintPill(hint: _guideHints[_hintIndex], index: _hintIndex, onTap: _prossimoSuggerimento),
                const SizedBox(height: AppSpacing.md),
                _BottomBar(
                  lastCapture: _captures.isEmpty ? null : _captures.last,
                  scattoAbilitato: _controller != null && !_scattando,
                  onScatta: _scatta,
                  onGalleria: _aggiungiDaGalleria,
                ),
                const SizedBox(height: AppSpacing.md),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraBackground extends StatelessWidget {
  const _CameraBackground({required this.controller, required this.nonDisponibile});

  final CameraController? controller;
  final bool nonDisponibile;

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;
    if (controller != null && controller.value.isInitialized) {
      return ColoredBox(color: Colors.black, child: Center(child: CameraPreview(controller)));
    }

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          radius: 1.1,
          colors: [AppColors.surfaceRaised, AppColors.surfaceDeepest],
        ),
      ),
      child: nonDisponibile
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.videocam_off_outlined, size: 32, color: AppColors.textDisabled),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Fotocamera non disponibile',
                    style: AppTypography.bodyMedium.copyWith(color: AppColors.textMuted),
                  ),
                ],
              ),
            )
          : const Center(child: CircularProgressIndicator(color: AppColors.accent)),
    );
  }
}

class _Filmstrip extends StatelessWidget {
  const _Filmstrip({required this.captures, required this.onFine});

  final List<XFile> captures;
  final VoidCallback onFine;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, 0),
      child: Row(
        children: [
          Expanded(
            child: captures.isEmpty
                ? Text('Nessuna scansione ancora', style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted))
                : SizedBox(
                    height: 40,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: captures.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 6),
                      itemBuilder: (context, i) => ClipRRect(
                        borderRadius: AppRadii.xsRadius,
                        child: Container(
                          width: 40,
                          decoration: BoxDecoration(
                            borderRadius: AppRadii.xsRadius,
                            border: Border.all(color: AppColors.borderStrong),
                          ),
                          child: Image.file(File(captures[i].path), fit: BoxFit.cover),
                        ),
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Material(
            color: AppColors.accent,
            borderRadius: AppRadii.pillRadius,
            child: InkWell(
              onTap: onFine,
              borderRadius: AppRadii.pillRadius,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                child: Text('Fine', style: AppTypography.labelLarge.copyWith(color: AppColors.onAccent)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HintPill extends StatelessWidget {
  const _HintPill({required this.hint, required this.index, required this.onTap});

  final _GuideHint hint;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
          decoration: BoxDecoration(
            color: AppColors.surfaceDeepest.withValues(alpha: 0.72),
            borderRadius: AppRadii.pillRadius,
            border: Border.all(color: AppColors.borderDefault),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(hint.icon, size: 15, color: AppColors.accentLight),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  hint.label,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyMedium.copyWith(color: AppColors.textPrimary),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text('${index + 1}/${_guideHints.length}', style: AppTypography.monoLabel.copyWith(color: AppColors.textMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.lastCapture,
    required this.scattoAbilitato,
    required this.onScatta,
    required this.onGalleria,
  });

  final XFile? lastCapture;
  final bool scattoAbilitato;
  final VoidCallback onScatta;
  final VoidCallback onGalleria;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _GalleryThumbButton(lastCapture: lastCapture, onTap: onGalleria),
        _ShutterButton(enabled: scattoAbilitato, onTap: onScatta),
        const SizedBox(width: 48),
      ],
    );
  }
}

class _GalleryThumbButton extends StatelessWidget {
  const _GalleryThumbButton({required this.lastCapture, required this.onTap});

  final XFile? lastCapture;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final lastCapture = this.lastCapture;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.smRadius,
        child: Container(
          width: 48,
          height: 48,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.overlayCardHover,
            borderRadius: AppRadii.smRadius,
            border: Border.all(color: Colors.white70, width: 2),
          ),
          child: lastCapture == null
              ? Icon(Icons.photo_library_outlined, color: AppColors.textSecondary)
              : Image.file(File(lastCapture.path), fit: BoxFit.cover),
        ),
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: enabled ? onTap : null,
        customBorder: const CircleBorder(),
        child: Container(
          width: 76,
          height: 76,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.fromBorderSide(
              BorderSide(color: enabled ? Colors.white : Colors.white38, width: 3),
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(shape: BoxShape.circle, color: enabled ? Colors.white : Colors.white38),
          ),
        ),
      ),
    );
  }
}

class _CornerBracketsPainter extends CustomPainter {
  const _CornerBracketsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.accent
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final len = size.shortestSide * 0.12;

    void bracket(Offset corner, Offset dx, Offset dy) {
      canvas
        ..drawLine(corner, corner + dx * len, paint)
        ..drawLine(corner, corner + dy * len, paint);
    }

    bracket(Offset.zero, const Offset(1, 0), const Offset(0, 1));
    bracket(Offset(size.width, 0), const Offset(-1, 0), const Offset(0, 1));
    bracket(Offset(0, size.height), const Offset(1, 0), const Offset(0, -1));
    bracket(Offset(size.width, size.height), const Offset(-1, 0), const Offset(0, -1));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
