import 'package:drift/drift.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/domain/analisi_copertina.dart';
import 'package:mycomicbrain/core/domain/copia.dart';
import 'package:mycomicbrain/core/domain/dashboard_kpis.dart';

/// Espone il dominio del catalogo (opera/edizione/copia, §36) all'UI senza
/// farle vedere Drift: prende e restituisce tipi di dominio, mai i tipi
/// generati (`OpereData`, `CopieData`, ...).
class ComicsRepository {
  ComicsRepository(this._db);

  final AppDatabase _db;

  // --- Scrittura (usata dai test per costruire fixture; superficie minima
  // per il catalogo — nessuna schermata di questa mappa scrive dati). ---

  Future<int> aggiungiOpera({required String title, DateTime? createdAt}) {
    return _db
        .into(_db.opere)
        .insert(
          OpereCompanion.insert(
            title: title,
            createdAt: createdAt ?? DateTime.now(),
          ),
        );
  }

  Future<int> aggiungiSerie({required String name, int? totalIssues}) {
    return _db
        .into(_db.serieTable)
        .insert(
          SerieTableCompanion.insert(
            name: name,
            totalIssues: Value(totalIssues),
          ),
        );
  }

  Future<int> aggiungiEdizione({
    required int operaId,
    int? serieId,
    String? publisher,
    int? issueNumber,
    String? issueNumberLabel,
    String? coverImage,
    DateTime? createdAt,
  }) {
    return _db
        .into(_db.edizioni)
        .insert(
          EdizioniCompanion.insert(
            operaId: operaId,
            serieId: Value(serieId),
            publisher: Value(publisher),
            issueNumber: Value(issueNumber),
            issueNumberLabel: Value(issueNumberLabel),
            coverImage: Value(coverImage),
            createdAt: createdAt ?? DateTime.now(),
          ),
        );
  }

  Future<int> aggiungiCopia({
    required int edizioneId,
    required StatoCopia status,
    StatoLettura? readingStatus,
    CondizioneCopia? condition,
    double? purchasePrice,
    DateTime? purchaseDate,
    String? seller,
    String? location,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final now = DateTime.now();
    return _db
        .into(_db.copie)
        .insert(
          CopieCompanion.insert(
            edizioneId: edizioneId,
            status: status,
            readingStatus: Value(readingStatus),
            condition: Value(condition),
            purchasePrice: Value(purchasePrice),
            purchaseDate: Value(purchaseDate),
            seller: Value(seller),
            location: Value(location),
            notes: Value(notes),
            createdAt: createdAt ?? now,
            updatedAt: updatedAt ?? createdAt ?? now,
          ),
        );
  }

  /// Persiste una Scansione confermata (revisione ritaglio/rotazione, #24).
  /// Il riconoscimento (§6.3, collegamento a un'edizione) resta fuori scope
  /// di questa mappa — l'Analisi Copertina (§6.1, §6.2) parte separatamente,
  /// vedi [idScansionePerImmagine]/[avviaAnalisiCopertina].
  Future<int> aggiungiScansione({required String image, DateTime? createdAt}) {
    return _db
        .into(_db.scansioni)
        .insert(
          ScansioniCompanion.insert(
            image: image,
            createdAt: createdAt ?? DateTime.now(),
          ),
        );
  }

  /// L'id della Scansione salvata con questo percorso immagine — usato dalla
  /// pipeline di analisi OCR (#32) per collegare il batch di file in uscita
  /// dal riepilogo alla riga già persistita in `Scansioni` da [aggiungiScansione].
  Future<int> idScansionePerImmagine(String image) async {
    final riga = await (_db.select(
      _db.scansioni,
    )..where((s) => s.image.equals(image))).getSingle();
    return riga.id;
  }

  /// Crea la riga `AnalisiCopertina` di una Scansione, in stato `inCorso` —
  /// la pipeline (#32) la crea appena prende in carico la Scansione, prima
  /// di chiamare Claude.
  Future<int> avviaAnalisiCopertina({required int scansioneId, DateTime? createdAt}) {
    return _db
        .into(_db.analisiCopertinaTable)
        .insert(
          AnalisiCopertinaTableCompanion.insert(
            scansioneId: scansioneId,
            status: const Value(StatoAnalisiCopertina.inCorso),
            createdAt: createdAt ?? DateTime.now(),
          ),
        );
  }

  /// Registra il risultato di un'Analisi Copertina completata con successo —
  /// campi grezzi e non parsati (#31, #48), `rawResponse` preserva l'intera
  /// risposta strutturata di Claude.
  Future<void> completaAnalisiCopertina({
    required int id,
    required String rawResponse,
    String? title,
    String? issueNumberLabel,
    String? publisher,
    String? seriesName,
    String? isbn,
    String? barcode,
    String? price,
    List<String> characters = const [],
    List<String> coverStyleTags = const [],
    List<String> visualElementTags = const [],
    String? recognizedPublisherLogo,
    String? recognizedSeriesLogo,
    DateTime? completedAt,
  }) {
    return (_db.update(_db.analisiCopertinaTable)..where((a) => a.id.equals(id))).write(
      AnalisiCopertinaTableCompanion(
        title: Value(title),
        issueNumberLabel: Value(issueNumberLabel),
        publisher: Value(publisher),
        seriesName: Value(seriesName),
        isbn: Value(isbn),
        barcode: Value(barcode),
        price: Value(price),
        characters: Value(characters),
        coverStyleTags: Value(coverStyleTags),
        visualElementTags: Value(visualElementTags),
        recognizedPublisherLogo: Value(recognizedPublisherLogo),
        recognizedSeriesLogo: Value(recognizedSeriesLogo),
        rawResponse: Value(rawResponse),
        status: const Value(StatoAnalisiCopertina.completata),
        completedAt: Value(completedAt ?? DateTime.now()),
      ),
    );
  }

  /// Registra un fallimento dell'Analisi Copertina — nessun retry automatico
  /// (destinazione della mappa #27): lo stato resta `fallita`, `errorMessage`
  /// cattura il motivo per capirlo a posteriori.
  Future<void> fallisciAnalisiCopertina({
    required int id,
    required String errorMessage,
    DateTime? completedAt,
  }) {
    return (_db.update(_db.analisiCopertinaTable)..where((a) => a.id.equals(id))).write(
      AnalisiCopertinaTableCompanion(
        status: const Value(StatoAnalisiCopertina.fallita),
        errorMessage: Value(errorMessage),
        completedAt: Value(completedAt ?? DateTime.now()),
      ),
    );
  }

  // --- KPI della Dashboard (§4.1, regole fissate su #2). ---

  /// I numeri riassuntivi della Dashboard. Un'unica query: tutti i KPI di
  /// volume condividono lo stesso filtro "posseduto" (`status IN
  /// ('posseduta', 'prestata')` — una copia prestata resta posseduta, solo
  /// venduta/persa escono dai conteggi, vedi `CONTEXT.md`), e i numeri
  /// mancanti/serie complete condividono la stessa CTE ricorsiva 1..totale
  /// per serie (§17, §6 di `docs/research/drift-setup.md`).
  Stream<DashboardKpis> watchDashboardKpis() {
    final ora = DateTime.now();
    final inizioMese = DateTime(ora.year, ora.month);
    final inizioMeseProssimo = DateTime(ora.year, ora.month + 1);

    return _db
        .customSelect(
          '''
WITH RECURSIVE
  serie_valutabile AS (
    SELECT id, total_issues FROM serie WHERE total_issues IS NOT NULL
  ),
  numeri_serie(serie_id, n, total_issues) AS (
    SELECT id, 1, total_issues FROM serie_valutabile
    UNION ALL
    SELECT serie_id, n + 1, total_issues FROM numeri_serie WHERE n < total_issues
  ),
  numeri_posseduti AS (
    SELECT DISTINCT e.serie_id AS serie_id, e.issue_number AS n
    FROM edizioni e
    JOIN copie c ON c.edizione_id = e.id AND c.status IN ('posseduta', 'prestata')
    WHERE e.serie_id IS NOT NULL AND e.issue_number IS NOT NULL
  ),
  mancanti AS (
    SELECT ns.serie_id AS serie_id, ns.n AS n
    FROM numeri_serie ns
    WHERE NOT EXISTS (
      SELECT 1 FROM numeri_posseduti np
      WHERE np.serie_id = ns.serie_id AND np.n = ns.n
    )
  ),
  edizioni_possedute AS (
    SELECT e.id AS edizione_id, e.serie_id AS serie_id, COUNT(*) AS copie_possedute
    FROM edizioni e
    JOIN copie c ON c.edizione_id = e.id AND c.status IN ('posseduta', 'prestata')
    GROUP BY e.id
  )
SELECT
  (SELECT COUNT(*) FROM copie WHERE status IN ('posseduta', 'prestata')) AS totale_copie,
  (SELECT COUNT(DISTINCT serie_id) FROM edizioni_possedute WHERE serie_id IS NOT NULL) AS numero_serie,
  (SELECT COUNT(*) FROM edizioni_possedute WHERE copie_possedute >= 2) AS duplicati,
  (SELECT COUNT(*) FROM mancanti) AS numeri_mancanti,
  (SELECT COUNT(*) FROM serie_valutabile sv
     WHERE NOT EXISTS (SELECT 1 FROM mancanti m WHERE m.serie_id = sv.id)) AS serie_complete,
  COALESCE((SELECT SUM(purchase_price) FROM copie WHERE status IN ('posseduta', 'prestata')), 0.0) AS speso_finora,
  (SELECT COUNT(*) FROM copie
     WHERE status IN ('posseduta', 'prestata') AND created_at >= ?1 AND created_at < ?2) AS aggiunti_mese
''',
          variables: [
            Variable.withDateTime(inizioMese),
            Variable.withDateTime(inizioMeseProssimo),
          ],
          readsFrom: {_db.serieTable, _db.edizioni, _db.copie},
        )
        .watch()
        .map((rows) {
          final r = rows.single;
          return DashboardKpis(
            totaleCopie: r.read<int>('totale_copie'),
            numeroSerie: r.read<int>('numero_serie'),
            serieComplete: r.read<int>('serie_complete'),
            duplicati: r.read<int>('duplicati'),
            numeriMancanti: r.read<int>('numeri_mancanti'),
            spesoFinora: r.read<double>('speso_finora'),
            aggiuntiMeseCorrente: r.read<int>('aggiunti_mese'),
          );
        });
  }

  /// Le serie con "numeri totali" noto e almeno un numero mancante, con la
  /// percentuale di completamento (sezione "Serie incomplete" del
  /// prototipo). Le serie complete e quelle senza "numeri totali" non
  /// compaiono.
  Stream<List<SerieIncompleta>> watchSerieIncomplete() {
    return _db
        .customSelect(
          '''
WITH RECURSIVE
  numeri_serie(serie_id, n, total_issues) AS (
    SELECT id, 1, total_issues FROM serie WHERE total_issues IS NOT NULL
    UNION ALL
    SELECT serie_id, n + 1, total_issues FROM numeri_serie WHERE n < total_issues
  ),
  numeri_posseduti AS (
    SELECT DISTINCT e.serie_id AS serie_id, e.issue_number AS n
    FROM edizioni e
    JOIN copie c ON c.edizione_id = e.id AND c.status IN ('posseduta', 'prestata')
    WHERE e.serie_id IS NOT NULL AND e.issue_number IS NOT NULL
  )
SELECT ns.serie_id AS serie_id, s.name AS nome, ns.total_issues AS numeri_totali, ns.n AS numero_mancante
FROM numeri_serie ns
JOIN serie s ON s.id = ns.serie_id
WHERE NOT EXISTS (
  SELECT 1 FROM numeri_posseduti np WHERE np.serie_id = ns.serie_id AND np.n = ns.n
)
ORDER BY s.name, ns.n
''',
          readsFrom: {_db.serieTable, _db.edizioni, _db.copie},
        )
        .watch()
        .map((rows) {
          final perSerie = <int, List<QueryRow>>{};
          for (final row in rows) {
            perSerie.putIfAbsent(row.read<int>('serie_id'), () => []).add(row);
          }
          return [
            for (final entry in perSerie.entries)
              SerieIncompleta(
                serieId: entry.key,
                nome: entry.value.first.read<String>('nome'),
                numeriTotali: entry.value.first.read<int>('numeri_totali'),
                numeriMancanti: [
                  for (final row in entry.value) row.read<int>('numero_mancante'),
                ],
                numeriPosseduti:
                    entry.value.first.read<int>('numeri_totali') - entry.value.length,
              ),
          ];
        });
  }

  /// Quante copie mostrare nel carosello "Aggiunti di recente" — oltre lo
  /// scroll orizzontale di una Dashboard non aggiunge informazione utile.
  static const _limiteAggiuntiDiRecente = 12;

  /// Le ultime copie possedute aggiunte al catalogo (§4.1, carosello
  /// "Aggiunti di recente"), le più recenti per prime.
  Stream<List<ComicRecente>> watchAggiuntiDiRecente() {
    final query = _db.select(_db.copie).join([
      innerJoin(_db.edizioni, _db.edizioni.id.equalsExp(_db.copie.edizioneId)),
      innerJoin(_db.opere, _db.opere.id.equalsExp(_db.edizioni.operaId)),
    ])
      ..where(_db.copie.status.isInValues(const [StatoCopia.posseduta, StatoCopia.prestata]))
      ..orderBy([OrderingTerm.desc(_db.copie.createdAt), OrderingTerm.desc(_db.copie.id)])
      ..limit(_limiteAggiuntiDiRecente);

    return query.watch().map(
      (rows) => [
        for (final row in rows)
          ComicRecente(
            edizioneId: row.readTable(_db.edizioni).id,
            titolo: row.readTable(_db.opere).title,
            numero: row.readTable(_db.edizioni).issueNumber,
            numeroLabel: row.readTable(_db.edizioni).issueNumberLabel,
            editore: row.readTable(_db.edizioni).publisher,
          ),
      ],
    );
  }
}
