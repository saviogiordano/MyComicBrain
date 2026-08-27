import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/analisi_copertina_pipeline.dart';
import 'package:mycomicbrain/core/data/comic_vine_client.dart';
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/data/cover_analysis_client.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/data/identificazione_pipeline.dart';
import 'package:mycomicbrain/core/domain/analisi_copertina.dart';
import 'package:mycomicbrain/core/domain/identificazione.dart';
import 'package:path/path.dart' as p;

/// [ComicVineClient] finto per l'Identificazione agganciata a fine pipeline:
/// nessuna chiamata di rete, registra solo se interpellato.
class _FakeComicVineClient implements ComicVineClient {
  bool chiamato = false;

  @override
  Future<List<ComicVineIssueMatch>> cercaIssue({
    required String? title,
    required String? seriesName,
    required String? issueNumberLabel,
    required String? publisher,
  }) async {
    chiamato = true;
    return const [];
  }

  @override
  Future<void> verificaConnessione() async {}
}

/// [CoverAnalysisClient] finto: restituisce [risultato] o solleva
/// [eccezione] senza mai chiamare la rete — usato per isolare la pipeline
/// dal provider AI reale (Claude/OpenAI).
class _FakeCoverAnalysisClient implements CoverAnalysisClient {
  _FakeCoverAnalysisClient({this.risultato, this.eccezione});

  final CoverAnalysisResult? risultato;
  final Exception? eccezione;

  @override
  Future<CoverAnalysisResult> estraiCopertina(Uint8List immagineJpeg) async {
    final eccezione = this.eccezione;
    if (eccezione != null) throw eccezione;
    return risultato!;
  }

  @override
  Future<void> verificaConnessione() async {}
}

const _risultatoCompleto = CoverAnalysisResult(
  title: 'Amazing Spider-Man',
  issueNumberLabel: '300',
  publisher: 'Marvel',
  seriesName: 'The Amazing Spider-Man',
  isbn: null,
  barcode: '076194130132500111',
  price: '€ 1,50',
  releaseDate: 'giugno 1988',
  year: 1988,
  pageCount: 32,
  language: 'inglese',
  color: 'a colori',
  issn: null,
  characters: ['Spider-Man', 'Venom'],
  coverStyleTags: ['stile realistico'],
  visualElementTags: ['sfondo con esplosione'],
  recognizedPublisherLogo: 'Marvel',
  recognizedSeriesLogo: null,
  printingType: 'Direct Edition',
  classificazione: 'Rated T+',
  description: 'Peter Parker affronta Venom in un confronto decisivo.',
  raw: {
    'authors': ['David Michelinie'],
  },
);

void main() {
  late Directory tempDir;
  late AppDatabase db;
  late ComicsRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'analisi_copertina_pipeline_test_',
    );
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    repo = ComicsRepository(db);
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  Future<String> scansioneConImmagine(String nome) async {
    final path = p.join(tempDir.path, nome);
    await File(path).writeAsBytes(<int>[1, 2, 3]);
    await repo.aggiungiScansione(image: path);
    return path;
  }

  Future<AnalisiCopertinaTableData> unicaAnalisi() =>
      db.select(db.analisiCopertinaTable).getSingle();

  test('successo: persiste i campi grezzi e lo stato completata', () async {
    final path = await scansioneConImmagine('cover.jpg');
    final pipeline = AnalisiCopertinaPipeline(
      repository: repo,
      client: _FakeCoverAnalysisClient(risultato: _risultatoCompleto),
    );

    await pipeline.avviaBatch([path]);

    final analisi = await unicaAnalisi();
    expect(analisi.status, StatoAnalisiCopertina.completata);
    expect(analisi.title, 'Amazing Spider-Man');
    expect(analisi.issueNumberLabel, '300');
    expect(analisi.publisher, 'Marvel');
    expect(analisi.seriesName, 'The Amazing Spider-Man');
    expect(analisi.isbn, isNull);
    expect(analisi.barcode, '076194130132500111');
    expect(analisi.price, '€ 1,50');
    expect(analisi.releaseDate, 'giugno 1988');
    expect(analisi.year, 1988);
    expect(analisi.pageCount, 32);
    expect(analisi.language, 'inglese');
    expect(analisi.color, 'a colori');
    expect(analisi.issn, isNull);
    expect(analisi.characters, ['Spider-Man', 'Venom']);
    expect(analisi.coverStyleTags, ['stile realistico']);
    expect(analisi.visualElementTags, ['sfondo con esplosione']);
    expect(analisi.recognizedPublisherLogo, 'Marvel');
    expect(analisi.recognizedSeriesLogo, isNull);
    expect(analisi.printingType, 'Direct Edition');
    expect(analisi.classificazione, 'Rated T+');
    expect(
      analisi.description,
      'Peter Parker affronta Venom in un confronto decisivo.',
    );
    expect(analisi.rawResponse, contains('David Michelinie'));
    expect(analisi.errorMessage, isNull);
    expect(analisi.completedAt, isNotNull);
  });

  test(
    'fallimento: nessuna eccezione propagata, stato fallita con errorMessage',
    () async {
      final path = await scansioneConImmagine('cover.jpg');
      final pipeline = AnalisiCopertinaPipeline(
        repository: repo,
        client: _FakeCoverAnalysisClient(
          eccezione: CoverAnalysisException('rete assente'),
        ),
      );

      await pipeline.avviaBatch([path]);

      final analisi = await unicaAnalisi();
      expect(analisi.status, StatoAnalisiCopertina.fallita);
      expect(analisi.errorMessage, contains('rete assente'));
      expect(analisi.title, isNull);
      expect(analisi.characters, isEmpty);
    },
  );

  test('riprova: riusa la riga esistente e la porta a completata', () async {
    final path = await scansioneConImmagine('cover.jpg');
    final pipelineFallita = AnalisiCopertinaPipeline(
      repository: repo,
      client: _FakeCoverAnalysisClient(
        eccezione: CoverAnalysisException('timeout'),
      ),
    );
    await pipelineFallita.avviaBatch([path]);
    final analisiFallita = await unicaAnalisi();
    expect(analisiFallita.status, StatoAnalisiCopertina.fallita);

    final pipelineRiprova = AnalisiCopertinaPipeline(
      repository: repo,
      client: _FakeCoverAnalysisClient(risultato: _risultatoCompleto),
    );
    await pipelineRiprova.riprova(path);

    final righe = await db.select(db.analisiCopertinaTable).get();
    expect(
      righe,
      hasLength(1),
      reason: 'il retry non deve creare una seconda riga',
    );
    expect(righe.single.id, analisiFallita.id);
    expect(righe.single.status, StatoAnalisiCopertina.completata);
    expect(righe.single.errorMessage, isNull);
    expect(righe.single.title, 'Amazing Spider-Man');
  });

  test(
    'riprova: un secondo fallimento aggiorna errorMessage sulla stessa riga',
    () async {
      final path = await scansioneConImmagine('cover.jpg');
      final pipeline = AnalisiCopertinaPipeline(
        repository: repo,
        client: _FakeCoverAnalysisClient(
          eccezione: CoverAnalysisException('timeout'),
        ),
      );
      await pipeline.avviaBatch([path]);
      final primoId = (await unicaAnalisi()).id;

      await pipeline.riprova(path);

      final analisi = await unicaAnalisi();
      expect(analisi.id, primoId);
      expect(analisi.status, StatoAnalisiCopertina.fallita);
      expect(analisi.errorMessage, contains('timeout'));
    },
  );

  test(
    "successo: aggancia subito l'Identificazione della stessa Scansione",
    () async {
      final path = await scansioneConImmagine('cover.jpg');
      final comicVine = _FakeComicVineClient();
      final pipeline = AnalisiCopertinaPipeline(
        repository: repo,
        client: _FakeCoverAnalysisClient(risultato: _risultatoCompleto),
        identificazionePipeline: IdentificazionePipeline(
          repository: repo,
          comicVineClient: comicVine,
        ),
      );

      await pipeline.avviaBatch([path]);

      expect(comicVine.chiamato, isTrue);
      final identificazione = await db
          .select(db.identificazioneTable)
          .getSingle();
      expect(identificazione.status, StatoIdentificazione.completata);
    },
  );

  test('fallimento: nessuna Identificazione viene avviata', () async {
    final path = await scansioneConImmagine('cover.jpg');
    final comicVine = _FakeComicVineClient();
    final pipeline = AnalisiCopertinaPipeline(
      repository: repo,
      client: _FakeCoverAnalysisClient(
        eccezione: CoverAnalysisException('rete assente'),
      ),
      identificazionePipeline: IdentificazionePipeline(
        repository: repo,
        comicVineClient: comicVine,
      ),
    );

    await pipeline.avviaBatch([path]);

    expect(comicVine.chiamato, isFalse);
    final righe = await db.select(db.identificazioneTable).get();
    expect(righe, isEmpty);
  });

  test(
    "riprova andato a buon fine: aggancia anche lì l'Identificazione",
    () async {
      final path = await scansioneConImmagine('cover.jpg');
      final pipelineFallita = AnalisiCopertinaPipeline(
        repository: repo,
        client: _FakeCoverAnalysisClient(
          eccezione: CoverAnalysisException('timeout'),
        ),
      );
      await pipelineFallita.avviaBatch([path]);

      final comicVine = _FakeComicVineClient();
      final pipelineRiprova = AnalisiCopertinaPipeline(
        repository: repo,
        client: _FakeCoverAnalysisClient(risultato: _risultatoCompleto),
        identificazionePipeline: IdentificazionePipeline(
          repository: repo,
          comicVineClient: comicVine,
        ),
      );
      await pipelineRiprova.riprova(path);

      expect(comicVine.chiamato, isTrue);
      final identificazione = await db
          .select(db.identificazioneTable)
          .getSingle();
      expect(identificazione.status, StatoIdentificazione.completata);
    },
  );

  test(
    'il fallimento di una Scansione non blocca le successive del batch',
    () async {
      final ok = await scansioneConImmagine('ok.jpg');
      final path1 = await scansioneConImmagine('ko.jpg');
      var chiamate = 0;
      final client = _CoverAnalysisClientAlternante(
        risposte: [
          () => throw CoverAnalysisException('fallita'),
          () => _risultatoCompleto,
        ],
        onChiamata: () => chiamate++,
      );
      final pipeline = AnalisiCopertinaPipeline(
        repository: repo,
        client: client,
      );

      await pipeline.avviaBatch([path1, ok]);

      expect(chiamate, 2);
      final analisi = await (db.select(
        db.analisiCopertinaTable,
      )..orderBy([(a) => OrderingTerm.asc(a.id)])).get();
      expect(analisi, hasLength(2));
      expect(analisi[0].status, StatoAnalisiCopertina.fallita);
      expect(analisi[1].status, StatoAnalisiCopertina.completata);
    },
  );

  test(
    'la rielaborazione di una Scansione già completata non blocca le Scansioni successive del batch (bug #86)',
    () async {
      // Riproduce il bug segnalato da utente: `ScansionePage` teneva nel
      // filmstrip una Scansione già inviata a una pipeline precedente (fix
      // in `ScansionePage._fine`, #86) — quando rientrava in un batch
      // successivo, `avviaAnalisiCopertina` creava una seconda riga
      // `AnalisiCopertina` per lo stesso scansioneId, e `identifica()` (via
      // `analisiCopertinaPerScansione`, che usa `getSingle()`) andava in
      // errore trovandone due. Senza il try/catch attorno a `identifica()`
      // in `_eseguiAnalisi`, quell'eccezione risaliva fuori dal `for` di
      // `avviaBatch`, e la Scansione successiva del batch non veniva mai
      // nemmeno presa in carico.
      final vecchia = await scansioneConImmagine('vecchia.jpg');
      final nuova = await scansioneConImmagine('nuova.jpg');

      final pipelinePrimoGiro = AnalisiCopertinaPipeline(
        repository: repo,
        client: _FakeCoverAnalysisClient(risultato: _risultatoCompleto),
      );
      await pipelinePrimoGiro.avviaBatch([vecchia]);
      expect((await unicaAnalisi()).status, StatoAnalisiCopertina.completata);

      final pipelineSecondoGiro = AnalisiCopertinaPipeline(
        repository: repo,
        client: _FakeCoverAnalysisClient(risultato: _risultatoCompleto),
      );
      await pipelineSecondoGiro.avviaBatch([vecchia, nuova]);

      final scansioneIdNuova = await repo.idScansionePerImmagine(nuova);
      final analisiNuova = await (db.select(
        db.analisiCopertinaTable,
      )..where((a) => a.scansioneId.equals(scansioneIdNuova))).getSingle();
      expect(
        analisiNuova.status,
        StatoAnalisiCopertina.completata,
        reason:
            'la Scansione davvero nuova deve essere processata anche se '
            'quella duplicata prima nel batch fa fallire la sua Identificazione',
      );
    },
  );
}

class _CoverAnalysisClientAlternante implements CoverAnalysisClient {
  _CoverAnalysisClientAlternante({
    required this.risposte,
    required this.onChiamata,
  });

  final List<CoverAnalysisResult Function()> risposte;
  final void Function() onChiamata;
  var _indice = 0;

  @override
  Future<CoverAnalysisResult> estraiCopertina(Uint8List immagineJpeg) async {
    onChiamata();
    return risposte[_indice++]();
  }

  @override
  Future<void> verificaConnessione() async {}
}
