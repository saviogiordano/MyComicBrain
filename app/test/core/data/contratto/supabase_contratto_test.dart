import 'package:flutter_test/flutter_test.dart';

import '../cover_repository_test.dart';
import 'adapter_supabase_locale.dart';

/// La suite di contratto su `SupabaseComicsRepository`, contro lo stack
/// locale: `scripts/test-contratto-supabase.sh`. Senza stack configurato è
/// saltata, così `flutter test` resta indipendente da Docker.
///
/// Ogni fetta di porting (mappa #165) aggiunge qui le aree che porta; il
/// flag del login si toglie quando ci sono tutte (ADR-0007).
void main() {
  final crea = creaAdapterSupabaseLocale();
  group(
    'su Supabase locale',
    () {
      contrattoCover(
        crea ?? () => throw StateError('stack locale non configurato'),
      );
    },
    skip: crea == null
        ? 'Stack Supabase locale non configurato: '
              'scripts/test-contratto-supabase.sh'
        : false,
  );
}
