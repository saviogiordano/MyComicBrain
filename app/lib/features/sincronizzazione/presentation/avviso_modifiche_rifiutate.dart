import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/data/sincronizzazione/descrizione_modifiche.dart';
import 'package:mycomicbrain/core/data/sincronizzazione/motore_sincronizzazione.dart';
import 'package:mycomicbrain/features/sincronizzazione/application/avviso_rifiuti.dart';

/// Avvisa una volta sola per ogni nuovo rifiuto del server (#225), con
/// "Dettagli" che apre lo sheet della Sincronizzazione. Sta alla radice
/// dell'app come `AvvisoModificheScartate`, sopra il Navigator: lo sheet lo
/// apre [apriDettagli].
class AvvisoModificheRifiutate extends ConsumerStatefulWidget {
  const AvvisoModificheRifiutate({
    required this.apriDettagli,
    required this.child,
    super.key,
  });

  final VoidCallback apriDettagli;
  final Widget child;

  @override
  ConsumerState<AvvisoModificheRifiutate> createState() =>
      _AvvisoModificheRifiutateState();
}

class _AvvisoModificheRifiutateState
    extends ConsumerState<AvvisoModificheRifiutate> {
  StreamSubscription<List<ModificaRifiutata>>? _rifiuti;

  @override
  void initState() {
    super.initState();
    // Il motore cambia a ogni login e logout.
    ref.listenManual(
      motoreSincronizzazioneProvider,
      (_, motore) => _ascolta(motore),
      fireImmediately: true,
    );
  }

  void _ascolta(MotoreSincronizzazione? motore) {
    unawaited(_rifiuti?.cancel());
    _rifiuti = motore?.rifiuti.listen((rifiutate) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(avvisoRifiuti(rifiutate)),
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: 'Dettagli',
              onPressed: widget.apriDettagli,
            ),
          ),
        );
    });
  }

  @override
  void dispose() {
    unawaited(_rifiuti?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
