import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/features/tutorial/application/tutorial_inserimento.dart';
import 'package:mycomicbrain/features/tutorial/presentation/spotlight.dart';

/// Ramo della shell con la Scansione (vedi `router.dart`).
const _ramoScansione = 2;

enum _Fase { nessuna, scheda, spotlight }

/// Primo momento del Tutorial di inserimento (PRD #242): al primo ingresso
/// nella Dashboard una scheda introduttiva e, con "Mostrami", gli spotlight
/// sul pulsante centrale della barra e poi su Fotocamera, Galleria e "Fine"
/// della Scansione. Sta sopra la shell, quindi mai sopra benvenuto,
/// importazione e primo download, che ne sono fuori.
class PrimoMomentoTutorial extends ConsumerStatefulWidget {
  const PrimoMomentoTutorial({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<PrimoMomentoTutorial> createState() =>
      _PrimoMomentoTutorialState();
}

class _PrimoMomentoTutorialState extends ConsumerState<PrimoMomentoTutorial> {
  _Fase _fase = _Fase.nessuna;

  TutorialInserimentoController get _controller =>
      ref.read(tutorialInserimentoProvider.notifier);

  @override
  void initState() {
    super.initState();
    // Anche dopo la riapertura da Impostazioni, che riporta alla Dashboard.
    ref.listenManual(
      tutorialInserimentoProvider,
      (_, _) => _valutaDopoIlFrame(),
      fireImmediately: true,
    );
  }

  @override
  void didUpdateWidget(PrimoMomentoTutorial oldWidget) {
    super.didUpdateWidget(oldWidget);
    _valutaDopoIlFrame();
  }

  // Non durante build: avviare il primo momento scrive sul provider.
  void _valutaDopoIlFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _fase != _Fase.nessuna) return;
      if (!ref.read(tutorialInserimentoProvider).mostraPrimoMomento) return;
      if (widget.navigationShell.currentIndex != 0) return;
      setState(() => _fase = _Fase.scheda);
      unawaited(_controller.avviaPrimoMomento());
    });
  }

  void _chiudi() => setState(() => _fase = _Fase.nessuna);

  @override
  Widget build(BuildContext context) {
    return switch (_fase) {
      _Fase.nessuna => const SizedBox.shrink(),
      _Fase.scheda => _SchedaIntroduttiva(
        onMostrami: () => setState(() => _fase = _Fase.spotlight),
        onSalta: () {
          unawaited(_controller.salta());
          _chiudi();
        },
      ),
      _Fase.spotlight => Spotlight(
        passi: [
          PassoSpotlight(
            bersaglio: TutorialInserimentoKeys.pulsanteScansione,
            testo: 'Da qui aggiungi un fumetto',
          ),
          PassoSpotlight(
            bersaglio: TutorialInserimentoKeys.fotocamera,
            testo:
                'Scatta la cover, puoi ritagliarla e raddrizzarla subito dopo',
          ),
          PassoSpotlight(
            bersaglio: TutorialInserimentoKeys.galleria,
            testo: 'Oppure scegli una foto che hai già',
          ),
          PassoSpotlight(
            bersaglio: TutorialInserimentoKeys.fine,
            testo:
                'Scatta tutte le cover che vuoi, poi tocca Fine. '
                "Ti mostro l'avanzamento",
          ),
        ],
        // "Avanti" sul pulsante della barra apre la Scansione da solo.
        primaDelPasso: (indice) {
          if (indice == 1) widget.navigationShell.goBranch(_ramoScansione);
        },
        onSalta: () {
          unawaited(_controller.salta());
          _chiudi();
        },
        onFine: () {
          unawaited(_controller.completaPrimoMomento());
          _chiudi();
        },
      ),
    };
  }
}

class _SchedaIntroduttiva extends StatelessWidget {
  const _SchedaIntroduttiva({required this.onMostrami, required this.onSalta});

  final VoidCallback onMostrami;
  final VoidCallback onSalta;

  @override
  Widget build(BuildContext context) {
    Widget riga(String emoji, String testo) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: AppTypography.bodyLarge),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              testo,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.55)),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            color: AppColors.surfaceRaised,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppRadii.xl),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Aggiungi il tuo primo fumetto',
                      style: AppTypography.titleLarge.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    riga(
                      '📷',
                      'Fotografa la cover: riconosco io il fumetto e ti '
                          'propongo le corrispondenze.',
                    ),
                    riga(
                      '📚',
                      'Ne hai tanti? Scatta più cover di fila, poi tocca '
                          '"Fine".',
                    ),
                    riga('✍️', 'Non trovo quello giusto? Lo inserisci a mano.'),
                    const SizedBox(height: AppSpacing.sm),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: onMostrami,
                        child: const Text('Mostrami'),
                      ),
                    ),
                    Center(
                      child: TextButton(
                        onPressed: onSalta,
                        child: const Text('Salta'),
                      ),
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
