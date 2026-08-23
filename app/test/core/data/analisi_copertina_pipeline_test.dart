import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/analisi_copertina_pipeline.dart';
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/data/cover_analysis_client.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/domain/analisi_copertina.dart';
import 'package:path/path.dart' as p;

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
}

const _risultatoCompleto = CoverAnalysisResult(
  title: 'Amazing Spider-Man',
  issueNumberLabel: '300',
  publisher: 'Marvel',
  seriesName: 'The Amazing Spider-Man',
  isbn: null,
  barcode: '076194130132500111',
  price: '€ 1,50',
  characters: ['Spider-Man', 'Venom'],
  coverStyleTags: ['stile realistico'],
  visualElementTags: ['sfondo con esplosione'],
  recognizedPublisherLogo: 'Marvel',
  recognizedSeriesLogo: null,
  raw: {'authors': ['David Michelinie']},
);

void main() {
  late Directory tempDir;
  late AppDatabase db;
  late ComicsRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('analisi_copertina_pipeline_test_');
    db = AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
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
    expect(analisi.characters, ['Spider-Man', 'Venom']);
    expect(analisi.coverStyleTags, ['stile realistico']);
    expect(analisi.visualElementTags, ['sfondo con esplosione']);
    expect(analisi.recognizedPublisherLogo, 'Marvel');
    expect(analisi.recognizedSeriesLogo, isNull);
    expect(analisi.rawResponse, contains('David Michelinie'));
    expect(analisi.errorMessage, isNull);
    expect(analisi.completedAt, isNotNull);
  });

  test('fallimento: nessuna eccezione propagata, stato fallita con errorMessage', () async {
    final path = await scansioneConImmagine('cover.jpg');
    final pipeline = AnalisiCopertinaPipeline(
      repository: repo,
      client: _FakeCoverAnalysisClient(eccezione: CoverAnalysisException('rete assente')),
    );

    await pipeline.avviaBatch([path]);

    final analisi = await unicaAnalisi();
    expect(analisi.status, StatoAnalisiCopertina.fallita);
    expect(analisi.errorMessage, contains('rete assente'));
    expect(analisi.title, isNull);
    expect(analisi.characters, isEmpty);
  });

  test('il fallimento di una Scansione non blocca le successive del batch', () async {
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
    final pipeline = AnalisiCopertinaPipeline(repository: repo, client: client);

    await pipeline.avviaBatch([path1, ok]);

    expect(chiamate, 2);
    final analisi = await (db.select(db.analisiCopertinaTable)
          ..orderBy([(a) => OrderingTerm.asc(a.id)]))
        .get();
    expect(analisi, hasLength(2));
    expect(analisi[0].status, StatoAnalisiCopertina.fallita);
    expect(analisi[1].status, StatoAnalisiCopertina.completata);
  });
}

class _CoverAnalysisClientAlternante implements CoverAnalysisClient {
  _CoverAnalysisClientAlternante({required this.risposte, required this.onChiamata});

  final List<CoverAnalysisResult Function()> risposte;
  final void Function() onChiamata;
  var _indice = 0;

  @override
  Future<CoverAnalysisResult> estraiCopertina(Uint8List immagineJpeg) async {
    onChiamata();
    return risposte[_indice++]();
  }
}
