import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/domain/copia.dart';
import 'package:mycomicbrain/core/domain/valore_stimato.dart';

import 'contratto/adapter_sotto_contratto.dart';

void main() => contrattoValoreStimato(creaAdapterDriftInMemoria);

/// Area ValoreStimato della suite di contratto di `ComicsRepository` (ADR-0007).
void contrattoValoreStimato(CreaAdapter crea) {
  late AdapterSottoContratto adapter;
  late ComicsRepository repo;

  setUp(() async {
    adapter = await crea();
    repo = adapter.repo;
  });

  tearDown(() => adapter.chiudi());

  Future<int> copia({CondizioneCopia? condition}) async {
    final operaId = await repo.aggiungiOpera(title: 'Amazing Spider-Man');
    final edizioneId = await repo.aggiungiEdizione(
      operaId: operaId,
      publisher: 'Marvel',
      issueNumberLabel: '1',
    );
    return repo.aggiungiCopia(
      edizioneId: edizioneId,
      status: StatoCopia.posseduta,
      condition: condition,
    );
  }

  test(
    'avviaOrRiavviaValoreStimato crea la riga in stato inCorso al primo calcolo',
    () async {
      final copiaId = await copia();

      final id = await repo.avviaOrRiavviaValoreStimato(copiaId: copiaId);

      final riga = await (adapter.drift.select(
        adapter.drift.valoreStimatoTable,
      )..where((v) => v.id.equals(id))).getSingle();
      expect(riga.copiaId, copiaId);
      expect(riga.status, StatoValoreStimato.inCorso);
      expect(riga.value, isNull);
      expect(riga.completedAt, isNull);
    },
  );

  test(
    'avviaOrRiavviaValoreStimato su una Copia già calcolata riusa la stessa riga',
    () async {
      final copiaId = await copia();
      final id = await repo.avviaOrRiavviaValoreStimato(copiaId: copiaId);
      await repo.completaValoreStimato(id: id, value: 42.5);

      final secondoId = await repo.avviaOrRiavviaValoreStimato(
        copiaId: copiaId,
      );

      expect(secondoId, id);
      final righe = await (adapter.drift.select(
        adapter.drift.valoreStimatoTable,
      )..where((v) => v.copiaId.equals(copiaId))).get();
      expect(righe, hasLength(1));
      expect(righe.single.status, StatoValoreStimato.inCorso);
    },
  );

  test(
    'completaValoreStimato registra il valore in EUR e lo stato completata',
    () async {
      final copiaId = await copia();
      final id = await repo.avviaOrRiavviaValoreStimato(copiaId: copiaId);

      await repo.completaValoreStimato(id: id, value: 12.3);

      final riga = await (adapter.drift.select(
        adapter.drift.valoreStimatoTable,
      )..where((v) => v.id.equals(id))).getSingle();
      expect(riga.status, StatoValoreStimato.completata);
      expect(riga.value, 12.3);
      expect(riga.completedAt, isNotNull);
    },
  );

  test(
    'segnaValoreStimatoNonDisponibile azzera il valore ed è permanente finché non si ritenta',
    () async {
      final copiaId = await copia();
      final id = await repo.avviaOrRiavviaValoreStimato(copiaId: copiaId);

      await repo.segnaValoreStimatoNonDisponibile(id: id);

      final riga = await (adapter.drift.select(
        adapter.drift.valoreStimatoTable,
      )..where((v) => v.id.equals(id))).getSingle();
      expect(riga.status, StatoValoreStimato.nonDisponibile);
      expect(riga.value, isNull);
      expect(riga.completedAt, isNotNull);
    },
  );

  test(
    'fallisciValoreStimato non cancella un valore calcolato in precedenza (#161)',
    () async {
      final copiaId = await copia();
      final id = await repo.avviaOrRiavviaValoreStimato(copiaId: copiaId);
      await repo.completaValoreStimato(id: id, value: 30);
      await repo.avviaOrRiavviaValoreStimato(copiaId: copiaId);

      await repo.fallisciValoreStimato(id: id, errorMessage: 'timeout');

      final riga = await (adapter.drift.select(
        adapter.drift.valoreStimatoTable,
      )..where((v) => v.id.equals(id))).getSingle();
      expect(riga.status, StatoValoreStimato.fallita);
      expect(riga.errorMessage, 'timeout');
      expect(riga.value, 30);
    },
  );

  test(
    'copiaConEdizionePerId risolve titolo, numero, editore e condizione',
    () async {
      final copiaId = await copia(condition: CondizioneCopia.veryFine);

      final dati = await repo.copiaConEdizionePerId(copiaId);

      expect(dati.title, 'Amazing Spider-Man');
      expect(dati.issueNumberLabel, '1');
      expect(dati.publisher, 'Marvel');
      expect(dati.condition, CondizioneCopia.veryFine);
    },
  );
}
