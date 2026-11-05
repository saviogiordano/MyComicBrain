import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mycomicbrain/core/data/providers.dart';

class _AiAbilitataFissa extends AiAbilitataNotifier {
  _AiAbilitataFissa({required this.iniziale});

  final bool iniziale;

  @override
  bool build() => iniziale;

  @override
  Future<void> imposta({required bool abilitata}) async => state = abilitata;
}

/// [aiAbilitataProvider] fissato, senza `SharedPreferences` dietro.
Override aiAbilitata({bool abilitata = true}) =>
    aiAbilitataProvider.overrideWith(
      () => _AiAbilitataFissa(iniziale: abilitata),
    );
