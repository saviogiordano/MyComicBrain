import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/data/drift_comics_repository.dart';
import 'package:mycomicbrain/core/data/registro_modifiche.dart';
import 'package:mycomicbrain/core/data/sincronizzazione/descrizione_modifiche.dart';
import 'package:mycomicbrain/core/domain/copia.dart';
import 'package:mycomicbrain/core/domain/creator.dart';

/// L'elenco leggibile delle Modifiche in sospeso (prototipo #201, punto 1)
/// e il titolo per l'avviso "modifica non salvata" (punto 7).
void main() {
  late AppDatabase db;
  late DriftComicsRepository repo;
  late RegistroModifiche registro;
  late DescrizioneModifiche descrizione;

  setUp(() {
    db = AppDatabase.replica(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    repo = DriftComicsRepository(db);
    registro = RegistroModifiche(db);
    descrizione = DescrizioneModifiche(db);
  });

  tearDown(() => db.close());

  /// Un fumetto già sincronizzato: niente nel registro.
  Future<({String edizione, String copia})> fumettoSincronizzato() async {
    final operaId = await repo.aggiungiOpera(title: 'Dylan Dog');
    final edizione = await repo.aggiungiEdizione(
      operaId: operaId,
      issueNumberLabel: '41',
    );
    final copia = await repo.aggiungiCopia(
      edizioneId: edizione,
      status: StatoCopia.posseduta,
    );
    await registro.rimuovi((await registro.voci()).map((v) => v.id));
    return (edizione: edizione, copia: copia);
  }

  test('una riga per riga modificata, con il titolo del fumetto', () async {
    final f = await fumettoSincronizzato();
    await repo.aggiornaCopia(id: f.copia, seller: 'Fumetteria');
    await repo.aggiornaCopia(id: f.copia, seller: 'Mercatino');

    expect(await descrizione.elenco(), ['Copia modificata: Dylan Dog 41']);
  });

  test(
    "aggiunte ed eliminazioni, nell'ordine in cui sono state fatte",
    () async {
      final f = await fumettoSincronizzato();
      final operaId = await repo.aggiungiOpera(title: 'Tex');
      await repo.aggiungiEdizione(operaId: operaId, issueNumberLabel: '712');
      await repo.rimuoviCopia(f.copia);

      expect(await descrizione.elenco(), [
        'Opera aggiunta: Tex',
        'Fumetto aggiunto: Tex 712',
        'Copia eliminata',
        // Era l'ultima Copia: se ne va anche l'Edizione.
        'Fumetto eliminato',
      ]);
    },
  );

  test('una riga aggiunta e poi modificata conta come aggiunta', () async {
    final operaId = await repo.aggiungiOpera(title: 'Zagor');
    await repo.aggiornaTitoloOpera(operaId: operaId, title: 'Zagor Classic');

    expect(await descrizione.elenco(), ['Opera aggiunta: Zagor Classic']);
  });

  test('le righe uguali si raccolgono con il conteggio', () async {
    final f = await fumettoSincronizzato();
    final a = await repo.aggiungiCreator('Tiziano Sclavi');
    final b = await repo.aggiungiCreator('Angelo Stano');
    await registro.rimuovi((await registro.voci()).map((v) => v.id));
    await repo.collegaCreatorAEdizione(
      edizioneId: f.edizione,
      creatorId: a,
      ruolo: RuoloCreator.sceneggiatore,
    );
    await repo.collegaCreatorAEdizione(
      edizioneId: f.edizione,
      creatorId: b,
      ruolo: RuoloCreator.disegnatore,
    );

    expect(await descrizione.elenco(), [
      'Autore del fumetto aggiunto: Dylan Dog 41 (×2)',
    ]);
  });

  test('il titolo di una riga per l\'avviso "modifica non salvata"', () async {
    final f = await fumettoSincronizzato();

    expect(
      await descrizione.titoli([
        (tabella: 'copie', id: f.copia),
        (tabella: 'edizioni', id: f.edizione),
        (tabella: 'copie', id: 'non-esiste'),
      ]),
      {
        (tabella: 'copie', id: f.copia): 'Dylan Dog 41',
        (tabella: 'edizioni', id: f.edizione): 'Dylan Dog 41',
      },
    );
  });
}
