import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/data/drift_comics_repository.dart';
import 'package:mycomicbrain/core/data/registro_modifiche.dart';
import 'package:mycomicbrain/core/domain/conversazione.dart';
import 'package:mycomicbrain/core/domain/copia.dart';
import 'package:mycomicbrain/core/domain/identificazione.dart';
import 'package:path/path.dart' as p;

/// Il registro delle Modifiche in sospeso della Replica (ADR-0008): i
/// trigger SQLite catturano ogni scrittura sulle tabelle replicate.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final formatoHlc = RegExp(
    r'^\d{13}-\d{4}-[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );
  final formatoUuidV7 = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  AppDatabase memoria({bool replica = true}) {
    final connessione = DatabaseConnection(
      NativeDatabase.memory(),
      closeStreamsSynchronously: true,
    );
    return replica
        ? AppDatabase.replica(connessione)
        : AppDatabase(connessione);
  }

  late AppDatabase db;
  late DriftComicsRepository repo;
  late RegistroModifiche registro;

  setUp(() {
    db = memoria();
    repo = DriftComicsRepository(db);
    registro = RegistroModifiche(db);
  });

  tearDown(() => db.close());

  Map<String, Object?> valori(VoceRegistro voce) =>
      jsonDecode(voce.valori!) as Map<String, Object?>;

  test('un inserimento registra la riga intera, senza id', () async {
    final operaId = await repo.aggiungiOpera(
      title: 'Dylan Dog',
      createdAt: DateTime.utc(2026, 10, 15),
    );

    final voce = (await registro.voci()).single;
    expect(voce.tabella, 'opere');
    expect(voce.riga, operaId);
    expect(voce.tipo, TipoVoceRegistro.inserimento);
    expect(voce.id, matches(formatoUuidV7));
    expect(voce.hlc, matches(formatoHlc));
    expect(valori(voce), {
      'title': 'Dylan Dog',
      'created_at': isA<String>(),
    });
  });

  test('una modifica registra solo i campi cambiati', () async {
    final operaId = await repo.aggiungiOpera(title: 'Dylan Dog');
    final edizioneId = await repo.aggiungiEdizione(operaId: operaId);
    final copiaId = await repo.aggiungiCopia(
      edizioneId: edizioneId,
      status: StatoCopia.posseduta,
      notes: 'prima',
    );
    final prima = (await registro.voci()).length;

    await repo.aggiornaCopia(id: copiaId, notes: 'dopo', seller: 'Edicola');

    final voci = await registro.voci();
    expect(voci, hasLength(prima + 1));
    final voce = voci.last;
    expect(voce.tabella, 'copie');
    expect(voce.riga, copiaId);
    expect(voce.tipo, TipoVoceRegistro.modifica);
    expect(valori(voce), containsPair('notes', 'dopo'));
    expect(valori(voce), containsPair('seller', 'Edicola'));
    expect(valori(voce), isNot(contains('status')));
    expect(valori(voce), isNot(contains('edizione_id')));
  });

  test('una modifica che non cambia nulla non registra niente', () async {
    final operaId = await repo.aggiungiOpera(title: 'Dylan Dog');
    final prima = (await registro.voci()).length;

    await (db.update(db.opere)..where((o) => o.id.equals(operaId))).write(
      const OpereCompanion(title: Value('Dylan Dog')),
    );

    expect(await registro.voci(), hasLength(prima));
  });

  test('un campo che torna a null è registrato come null', () async {
    final operaId = await repo.aggiungiOpera(title: 'Dylan Dog');
    final edizioneId = await repo.aggiungiEdizione(operaId: operaId);
    final copiaId = await repo.aggiungiCopia(
      edizioneId: edizioneId,
      status: StatoCopia.posseduta,
      notes: 'una nota',
    );

    await (db.update(db.copie)..where((c) => c.id.equals(copiaId))).write(
      const CopieCompanion(notes: Value(null)),
    );

    final voce = (await registro.voci()).last;
    expect(valori(voce), {'notes': null});
  });

  test("un'eliminazione registra la riga senza valori", () async {
    final operaId = await repo.aggiungiOpera(title: 'Dylan Dog');
    final edizioneId = await repo.aggiungiEdizione(operaId: operaId);
    final copiaId = await repo.aggiungiCopia(
      edizioneId: edizioneId,
      status: StatoCopia.posseduta,
    );

    await repo.rimuoviCopia(copiaId);

    final eliminazioni = (await registro.voci())
        .where((v) => v.tipo == TipoVoceRegistro.eliminazione)
        .toList();
    expect(
      eliminazioni.map((v) => (v.tabella, v.riga)),
      contains(('copie', copiaId)),
    );
    expect(eliminazioni.every((v) => v.valori == null), isTrue);
  });

  test('i timestamp HLC crescono strettamente, anche nella stessa '
      'istruzione, e portano tutti lo stesso id del device', () async {
    final operaId = await repo.aggiungiOpera(title: 'Dylan Dog');
    for (var i = 0; i < 5; i++) {
      await repo.aggiungiEdizione(operaId: operaId, issueNumber: i);
    }
    // Una sola UPDATE su più righe: stesso istante, il contatore avanza.
    await db
        .update(db.edizioni)
        .write(const EdizioniCompanion(language: Value('it')));

    final hlc = (await registro.voci()).map((v) => v.hlc).toList();
    expect(hlc, hasLength(11));
    for (var i = 1; i < hlc.length; i++) {
      expect(hlc[i].compareTo(hlc[i - 1]), greaterThan(0), reason: hlc[i]);
    }
    final dispositivo = await registro.dispositivo();
    expect(dispositivo, matches(formatoUuidV7));
    expect(hlc.every((h) => h.endsWith('-$dispositivo')), isTrue);
  });

  test('dopo un timestamp ricevuto da un altro device, il prossimo locale '
      'viene dopo', () async {
    final futuro =
        '${DateTime.now().millisecondsSinceEpoch + 3600000}'
        '-0007-0199f0c0-0000-7000-8000-000000000001';

    await registro.ricevi(futuro);
    await repo.aggiungiOpera(title: 'Dylan Dog');

    final hlc = (await registro.voci()).single.hlc;
    expect(
      hlc.substring(0, 18).compareTo(futuro.substring(0, 18)),
      greaterThan(0),
    );
  });

  test('un timestamp ricevuto più vecchio non fa tornare indietro '
      "l'orologio", () async {
    await repo.aggiungiOpera(title: 'Dylan Dog');
    final primo = (await registro.voci()).single.hlc;

    await registro.ricevi(
      '0000000001000-0000-0199f0c0-0000-7000-8000-000000000001',
    );
    await repo.aggiungiOpera(title: 'Tex');

    expect((await registro.voci()).last.hlc.compareTo(primo), greaterThan(0));
  });

  test('confermaCandidato registra tutte le righe della transazione', () async {
    final immagini = await Directory.systemTemp.createTemp('registro_');
    addTearDown(() => immagini.delete(recursive: true));
    final immagine = File(p.join(immagini.path, '1.jpg'))
      ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);
    final scansioneId = await repo.aggiungiScansione(image: immagine.path);
    await repo.completaAnalisiCopertina(
      id: await repo.avviaAnalisiCopertina(scansioneId: scansioneId),
      rawResponse: '{}',
      title: 'Batman',
      issueNumberLabel: '42',
    );
    final identificazioneId = await repo.avviaIdentificazione(
      scansioneId: scansioneId,
    );
    await repo.aggiungiCandidato(
      identificazioneId: identificazioneId,
      source: FonteCandidato.esterno,
      punteggio: 80,
      title: 'Batman',
      issueNumberLabel: '42',
    );
    final candidato =
        (await repo.watchIdentificazione(scansioneId).first).candidati.single;
    final prima = (await registro.voci()).length;

    final copiaId = await repo.confermaCandidato(
      candidato: candidato,
      scansioneId: scansioneId,
    );

    final nuove = (await registro.voci()).skip(prima).toList();
    final tabelle = nuove.map((v) => v.tabella).toSet();
    expect(
      tabelle,
      containsAll(['opere', 'edizioni', 'copie', 'candidati']),
    );
    expect(
      nuove.where((v) => v.tabella == 'copie').map((v) => v.riga),
      contains(copiaId),
    );
  });

  test('la Modalità locale non registra nulla', () async {
    final locale = memoria(replica: false);
    addTearDown(locale.close);

    await DriftComicsRepository(locale).aggiungiOpera(title: 'Dylan Dog');

    expect(await RegistroModifiche(locale).voci(), isEmpty);
  });

  test('la Conversazione non è replicata e non registra nulla', () async {
    await repo.aggiungiMessaggio(
      conversazioneId: await repo.getOrCreaConversazione(),
      ruolo: RuoloMessaggio.utente,
      testo: 'Quanti Dylan Dog ho?',
    );

    expect(await registro.voci(), isEmpty);
  });

  test('le scritture dentro senzaRegistro non registrano nulla (il pull '
      'del motore di Sincronizzazione)', () async {
    await registro.senzaRegistro(() async {
      final operaId = await repo.aggiungiOpera(title: 'Dylan Dog');
      await (db.delete(db.opere)..where((o) => o.id.equals(operaId))).go();
    });
    await repo.aggiungiOpera(title: 'Tex');

    expect((await registro.voci()).map((v) => v.tabella), ['opere']);
  });

  test('il conteggio delle Modifiche in sospeso conta le righe toccate, '
      'e si aggiorna a ogni scrittura', () async {
    final conteggi = <int>[];
    final sub = registro.watchConteggio().listen(conteggi.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();

    final operaId = await repo.aggiungiOpera(title: 'Dylan Dog');
    await pumpEventQueue();
    await (db.update(db.opere)..where((o) => o.id.equals(operaId))).write(
      const OpereCompanion(title: Value('Dylan Dog Color')),
    );
    await pumpEventQueue();
    await repo.aggiungiOpera(title: 'Tex');
    await pumpEventQueue();

    expect(await registro.conteggio(), 2);
    expect(conteggi.first, 0);
    expect(conteggi.last, 2);
  });

  test('rimuovi toglie dal registro le voci accolte da Supabase', () async {
    await repo.aggiungiOpera(title: 'Dylan Dog');
    await repo.aggiungiOpera(title: 'Tex');
    final voci = await registro.voci();

    await registro.rimuovi([voci.first.id]);

    expect((await registro.voci()).map((v) => v.id), [voci.last.id]);
  });

  test("l'id del device e l'orologio sopravvivono alla riapertura", () async {
    final cartella = await Directory.systemTemp.createTemp('registro_file_');
    addTearDown(() => cartella.delete(recursive: true));
    final file = File(p.join(cartella.path, 'replica.sqlite'));

    final primo = AppDatabase.replica(NativeDatabase(file));
    await DriftComicsRepository(primo).aggiungiOpera(title: 'Dylan Dog');
    final dispositivo = await RegistroModifiche(primo).dispositivo();
    final hlcPrimo = (await RegistroModifiche(primo).voci()).single.hlc;
    await primo.close();

    final secondo = AppDatabase.replica(NativeDatabase(file));
    addTearDown(secondo.close);
    await DriftComicsRepository(secondo).aggiungiOpera(title: 'Tex');
    final voci = await RegistroModifiche(secondo).voci();

    expect(await RegistroModifiche(secondo).dispositivo(), dispositivo);
    expect(voci, hasLength(2));
    expect(voci.last.hlc.compareTo(hlcPrimo), greaterThan(0));
  });
}
