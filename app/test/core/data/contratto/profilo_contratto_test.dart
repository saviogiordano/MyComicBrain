import 'package:flutter_test/flutter_test.dart';

import '../conversazione_repository_test.dart';
import 'adapter_profilo_locale.dart';

/// La parte della suite di contratto che cambia per un Profilo autenticato
/// (ADR-0008): la Conversazione, che resta su Supabase. Il resto gira sulla
/// Replica con `DriftComicsRepository`, già coperto dalla suite su drift.
/// Contro lo stack locale: `scripts/test-contratto-supabase.sh`. Senza
/// stack configurato è saltata, così `flutter test` resta indipendente da
/// Docker.
void main() {
  final crea = creaAdapterProfiloLocale();
  group(
    'Profilo su Supabase locale',
    () {
      final factory =
          crea ?? () => throw StateError('stack locale non configurato');
      group('Conversazione', () => contrattoConversazione(factory));
    },
    skip: crea == null
        ? 'Stack Supabase locale non configurato: '
              'scripts/test-contratto-supabase.sh'
        : false,
  );
}
