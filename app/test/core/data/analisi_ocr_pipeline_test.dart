import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/analisi_ocr_pipeline.dart';
import 'package:mycomicbrain/core/data/claude_ocr_client.dart';
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/domain/analisi_ocr.dart';
import 'package:path/path.dart' as p;

/// [ClaudeOcrClient] finto: restituisce [risultato] o solleva [eccezione]
/// senza mai chiamare la rete — usato per isolare la pipeline dall'API.
class _FakeClaudeOcrClient implements ClaudeOcrClient {
  _FakeClaudeOcrClient({this.risultato, this.eccezione});

  final ClaudeOcrResult? risultato;
  final Exception? eccezione;

  @override
  Future<ClaudeOcrResult> estraiCopertina(Uint8List immagineJpeg) async {
    final eccezione = this.eccezione;
    if (eccezione != null) throw eccezione;
    return risultato!;
  }
}

const _risultatoCompleto = ClaudeOcrResult(
  title: 'Amazing Spider-Man',
  issueNumberLabel: '300',
  publisher: 'Marvel',
  seriesName: 'The Amazing Spider-Man',
  isbn: null,
  barcode: '076194130132500111',
  price: '€ 1,50',
  raw: {'authors': ['David Michelinie']},
);

void main() {
  late Directory tempDir;
  late AppDatabase db;
  late ComicsRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('analisi_ocr_pipeline_test_');
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

  Future<AnalisiOcrTableData> unicaAnalisi() => db.select(db.analisiOcrTable).getSingle();

  test('successo: persiste i campi grezzi e lo stato completata', () async {
    final path = await scansioneConImmagine('cover.jpg');
    final pipeline = AnalisiOcrPipeline(
      repository: repo,
      client: _FakeClaudeOcrClient(risultato: _risultatoCompleto),
    );

    await pipeline.avviaBatch([path]);

    final analisi = await unicaAnalisi();
    expect(analisi.status, StatoAnalisiOcr.completata);
    expect(analisi.title, 'Amazing Spider-Man');
    expect(analisi.issueNumberLabel, '300');
    expect(analisi.publisher, 'Marvel');
    expect(analisi.seriesName, 'The Amazing Spider-Man');
    expect(analisi.isbn, isNull);
    expect(analisi.barcode, '076194130132500111');
    expect(analisi.price, '€ 1,50');
    expect(analisi.rawResponse, contains('David Michelinie'));
    expect(analisi.errorMessage, isNull);
    expect(analisi.completedAt, isNotNull);
  });

  test('fallimento: nessuna eccezione propagata, stato fallita con errorMessage', () async {
    final path = await scansioneConImmagine('cover.jpg');
    final pipeline = AnalisiOcrPipeline(
      repository: repo,
      client: _FakeClaudeOcrClient(eccezione: ClaudeOcrException('rete assente')),
    );

    await pipeline.avviaBatch([path]);

    final analisi = await unicaAnalisi();
    expect(analisi.status, StatoAnalisiOcr.fallita);
    expect(analisi.errorMessage, contains('rete assente'));
    expect(analisi.title, isNull);
  });

  test('il fallimento di una Scansione non blocca le successive del batch', () async {
    final ok = await scansioneConImmagine('ok.jpg');
    final path1 = await scansioneConImmagine('ko.jpg');
    var chiamate = 0;
    final client = _ClaudeOcrClientAlternante(
      risposte: [
        () => throw ClaudeOcrException('fallita'),
        () => _risultatoCompleto,
      ],
      onChiamata: () => chiamate++,
    );
    final pipeline = AnalisiOcrPipeline(repository: repo, client: client);

    await pipeline.avviaBatch([path1, ok]);

    expect(chiamate, 2);
    final analisi = await (db.select(db.analisiOcrTable)
          ..orderBy([(a) => OrderingTerm.asc(a.id)]))
        .get();
    expect(analisi, hasLength(2));
    expect(analisi[0].status, StatoAnalisiOcr.fallita);
    expect(analisi[1].status, StatoAnalisiOcr.completata);
  });
}

class _ClaudeOcrClientAlternante implements ClaudeOcrClient {
  _ClaudeOcrClientAlternante({required this.risposte, required this.onChiamata});

  final List<ClaudeOcrResult Function()> risposte;
  final void Function() onChiamata;
  var _indice = 0;

  @override
  Future<ClaudeOcrResult> estraiCopertina(Uint8List immagineJpeg) async {
    onChiamata();
    return risposte[_indice++]();
  }
}
