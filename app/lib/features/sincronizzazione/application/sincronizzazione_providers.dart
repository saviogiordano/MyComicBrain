import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/data/registro_modifiche.dart';
import 'package:mycomicbrain/core/data/sincronizzazione/canale_sincronizzazione.dart';
import 'package:mycomicbrain/core/data/sincronizzazione/descrizione_modifiche.dart';
import 'package:mycomicbrain/core/data/sincronizzazione/motore_sincronizzazione.dart';
import 'package:mycomicbrain/features/sincronizzazione/application/indicatore_sincronizzazione.dart';

/// La Replica del Profilo autenticato, `null` in Modalità locale.
final replicaDelProfiloProvider = Provider<AppDatabase?>((ref) {
  final userId = ref.watch(idUtenteSupabaseProvider);
  if (userId == null) return null;
  return ref.watch(replicheProfiloProvider).database(userId);
});

/// Quante righe hanno Modifiche in sospeso (0 in Modalità locale): la
/// pillola, lo sheet e l'avviso al logout (#217).
final modificheInSospesoProvider = StreamProvider<int>((ref) {
  final db = ref.watch(replicaDelProfiloProvider);
  if (db == null) return Stream.value(0);
  return RegistroModifiche(db).watchConteggio();
});

/// L'elenco leggibile delle Modifiche in sospeso, per lo sheet e
/// Impostazioni › Sincronizzazione.
final elencoModificheProvider = StreamProvider<List<String>>((ref) {
  final db = ref.watch(replicaDelProfiloProvider);
  if (db == null) return Stream.value(const []);
  final descrizione = DescrizioneModifiche(db);
  return RegistroModifiche(
    db,
  ).watchConteggio().asyncMap((_) => descrizione.elenco());
});

/// Le Modifiche rifiutate dal server (#225), per la pillola "N da
/// controllare" e la sezione "Non accettate dal server"; vuote in Modalità
/// locale.
final modificheRifiutateProvider = StreamProvider<List<ModificaRifiutata>>((
  ref,
) {
  final motore = ref.watch(motoreSincronizzazioneProvider);
  if (motore == null) return Stream.value(const []);
  return motore.watchRifiutate();
});

/// L'ora, aggiornata ogni 30 secondi: fa scorrere "riprovo tra N min" e
/// "N min fa" anche quando lo stato non cambia.
final oraProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(seconds: 30), (_) => DateTime.now());
});

/// Che cosa dice l'indicatore della Sincronizzazione; `null` in Modalità
/// locale o prima che il motore sia partito.
final indicatoreSincronizzazioneProvider =
    Provider<IndicatoreSincronizzazione?>(
      (ref) {
        final stato = ref.watch(statoSincronizzazioneProvider).valueOrNull;
        if (stato == null) return null;
        return IndicatoreSincronizzazione.da(
          stato,
          inSospeso: ref.watch(modificheInSospesoProvider).valueOrNull ?? 0,
          rifiutate:
              ref.watch(modificheRifiutateProvider).valueOrNull ?? const [],
          ora: ref.watch(oraProvider).valueOrNull ?? DateTime.now(),
        );
      },
    );

/// Quanto è grande la collezione sul server, per l'avanzamento del primo
/// download: le righe che `cambiamenti_da` porterà (tutte le tabelle
/// replicate) e i fumetti (le Copie) da mostrare. `null` se non si riesce a
/// saperlo: il primo download mostra allora un avanzamento senza totale.
final dimensioniCollezioneProvider =
    FutureProvider<({int righe, int fumetti})?>((ref) async {
      final client = ref.watch(supabaseClientProvider);
      final userId = ref.watch(idUtenteSupabaseProvider);
      if (client == null || userId == null) return null;
      // Senza rete non si sa: si riprova quando torna.
      final offline = ref.watch(
        statoSincronizzazioneProvider.select(
          (s) => s.valueOrNull?.fase == FaseSincronizzazione.offline,
        ),
      );
      if (offline) return null;
      try {
        return await CanaleSupabase(client, userId: userId).dimensioni();
      } on Object {
        return null;
      }
    });
