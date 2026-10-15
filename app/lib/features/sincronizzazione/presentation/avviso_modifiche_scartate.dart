import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/data/sincronizzazione/motore_sincronizzazione.dart';
import 'package:mycomicbrain/features/sincronizzazione/application/avviso_scartate.dart';

/// Avvisa quando la Sincronizzazione toglie dalla Replica righe con
/// Modifiche in sospeso perché eliminate su un altro dispositivo (prototipo
/// #201, punto 7). Sta alla radice dell'app, come `AvvisoAccesso`, così
/// l'avviso arriva in qualunque schermata.
class AvvisoModificheScartate extends ConsumerStatefulWidget {
  const AvvisoModificheScartate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AvvisoModificheScartate> createState() =>
      _AvvisoModificheScartateState();
}

class _AvvisoModificheScartateState
    extends ConsumerState<AvvisoModificheScartate> {
  StreamSubscription<List<ModificaScartata>>? _scartate;

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
    unawaited(_scartate?.cancel());
    _scartate = motore?.scartate.listen((scartate) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(avvisoScartate(scartate)),
            duration: const Duration(seconds: 6),
          ),
        );
    });
  }

  @override
  void dispose() {
    unawaited(_scartate?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
