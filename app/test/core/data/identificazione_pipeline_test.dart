import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/comic_vine_client.dart';
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/data/identificazione_pipeline.dart';
import 'package:mycomicbrain/core/domain/identificazione.dart';

/// [ComicVineClient] finto: restituisce [risultati] o solleva [eccezione]
/// senza mai chiamare la rete, e registra se è stato interpellato — usato
/// per verificare che il fallback su ComicVine scatti solo quando il
/// catalogo interno non produce candidati sopra soglia.
class _FakeComicVineClient implements ComicVineClient {
  _FakeComicVineClient({this.risultati = const [], this.eccezione});

  final List<ComicVineIssueMatch> risultati;
  final ComicVineException? eccezione;
  bool chiamato = false;

  @override
  Future<List<ComicVineIssueMatch>> cercaIssue({
    required String? title,
    required String? seriesName,
    required String? issueNumberLabel,
    required String? publisher,
  }) async {
    chiamato = true;
    final eccezione = this.eccezione;
    if (eccezione != null) throw eccezione;
    return risultati;
  }
}

const _issueSpiderMan = ComicVineIssueMatch(
  id: 111,
  name: 'Amazing Fantasy',
  issueNumber: '15',
  volumeName: 'Amazing Fantasy',
  coverImageUrl: 'https://comicvine.example/15.jpg',
  siteDetailUrl: 'https://comicvine.example/15',
);

void main() {
  late AppDatabase db;
  late ComicsRepository repo;

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
    );
    repo = ComicsRepository(db);
  });

  tearDown(() => db.close());

  Future<int> scansioneConAnalisiCompletata({
    String? title,
    String? seriesName,
    String? issueNumberLabel,
    String? publisher,
  }) async {
    final scansioneId = await repo.aggiungiScansione(image: '/scansioni/1.jpg');
    final analisiId = await repo.avviaAnalisiCopertina(scansioneId: scansioneId);
    await repo.completaAnalisiCopertina(
      id: analisiId,
      rawResponse: '{}',
      title: title,
      seriesName: seriesName,
      issueNumberLabel: issueNumberLabel,
      publisher: publisher,
    );
    return scansioneId;
  }

  Future<IdentificazioneTableData> unicaIdentificazione() =>
      db.select(db.identificazioneTable).getSingle();

  test('candidato interno sopra soglia: nessuna chiamata a ComicVine', () async {
    final operaId = await repo.aggiungiOpera(title: 'Batman');
    await repo.aggiungiEdizione(operaId: operaId, publisher: 'DC Comics', issueNumberLabel: '42');
    final scansioneId = await scansioneConAnalisiCompletata(
      title: 'Batman',
      publisher: 'DC Comics',
      issueNumberLabel: '42',
    );
    final comicVine = _FakeComicVineClient();
    final pipeline = IdentificazionePipeline(repository: repo, comicVineClient: comicVine);

    await pipeline.identifica(scansioneId: scansioneId);

    expect(comicVine.chiamato, isFalse);
    final identificazione = await unicaIdentificazione();
    expect(identificazione.status, StatoIdentificazione.completata);
    final candidati = await (db.select(
      db.candidatiTable,
    )..where((c) => c.identificazioneId.equals(identificazione.id))).get();
    expect(candidati, hasLength(1));
    expect(candidati.single.source, FonteCandidato.interno);
    expect(candidati.single.edizioneId, isNotNull);
  });

  test('nessun candidato interno sopra soglia: fallback su ComicVine, candidato esterno persistito', () async {
    final scansioneId = await scansioneConAnalisiCompletata(
      title: 'Amazing Fantasy',
      seriesName: 'Amazing Fantasy',
    );
    final comicVine = _FakeComicVineClient(risultati: const [_issueSpiderMan]);
    final pipeline = IdentificazionePipeline(repository: repo, comicVineClient: comicVine);

    await pipeline.identifica(scansioneId: scansioneId);

    expect(comicVine.chiamato, isTrue);
    final identificazione = await unicaIdentificazione();
    expect(identificazione.status, StatoIdentificazione.completata);
    final candidati = await (db.select(
      db.candidatiTable,
    )..where((c) => c.identificazioneId.equals(identificazione.id))).get();
    expect(candidati, hasLength(1));
    expect(candidati.single.source, FonteCandidato.esterno);
    expect(candidati.single.edizioneId, isNull);
    expect(candidati.single.title, 'Amazing Fantasy');
  });

  test('zero candidati (interno vuoto, ComicVine senza risultati): completata senza righe', () async {
    final scansioneId = await scansioneConAnalisiCompletata(title: 'Un fumetto mai visto');
    final comicVine = _FakeComicVineClient();
    final pipeline = IdentificazionePipeline(repository: repo, comicVineClient: comicVine);

    await pipeline.identifica(scansioneId: scansioneId);

    expect(comicVine.chiamato, isTrue);
    final identificazione = await unicaIdentificazione();
    expect(identificazione.status, StatoIdentificazione.completata);
    final candidati = await (db.select(
      db.candidatiTable,
    )..where((c) => c.identificazioneId.equals(identificazione.id))).get();
    expect(candidati, isEmpty);
  });

  test('un fallimento tecnico di ComicVine porta lo stato a fallita, nessuna eccezione propagata', () async {
    final scansioneId = await scansioneConAnalisiCompletata(title: 'Un fumetto mai visto');
    final comicVine = _FakeComicVineClient(
      eccezione: ComicVineException('rate limit superato'),
    );
    final pipeline = IdentificazionePipeline(repository: repo, comicVineClient: comicVine);

    await pipeline.identifica(scansioneId: scansioneId);

    final identificazione = await unicaIdentificazione();
    expect(identificazione.status, StatoIdentificazione.fallita);
    expect(identificazione.errorMessage, contains('rate limit superato'));
    final candidati = await (db.select(
      db.candidatiTable,
    )..where((c) => c.identificazioneId.equals(identificazione.id))).get();
    expect(candidati, isEmpty);
  });
}
