import 'package:drift/drift.dart';
import 'package:mycomicbrain/core/data/copertina_downloader.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/domain/analisi_copertina.dart';
import 'package:mycomicbrain/core/domain/copia.dart';
import 'package:mycomicbrain/core/domain/dashboard_kpis.dart';
import 'package:mycomicbrain/core/domain/edizione_catalogo.dart';
import 'package:mycomicbrain/core/domain/identificazione.dart';

/// Espone il dominio del catalogo (opera/edizione/copia, §36) all'UI senza
/// farle vedere Drift: prende e restituisce tipi di dominio, mai i tipi
/// generati (`OpereData`, `CopieData`, ...).
class ComicsRepository {
  ComicsRepository(this._db, {CopertinaDownloader? copertinaDownloader})
    : _copertinaDownloader = copertinaDownloader ?? CopertinaDownloader();

  final AppDatabase _db;
  final CopertinaDownloader _copertinaDownloader;

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
    int? scansioneId,
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
            scansioneId: Value(scansioneId),
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

  /// Rimuove una Scansione non ancora inviata alla pipeline (swipe-to-delete
  /// nel riepilogo, prima di "Fine") — solo la riga `Scansioni`: a questo
  /// punto del flusso non esiste ancora nessuna `AnalisiCopertina` collegata
  /// da ripulire. Il file immagine salvato va eliminato a parte con
  /// `ScansioneStorage.elimina`, non è responsabilità del repository.
  Future<void> eliminaScansione({required int id}) {
    return (_db.delete(_db.scansioni)..where((s) => s.id.equals(id))).go();
  }

  /// Crea la riga `AnalisiCopertina` di una Scansione, in stato `inCorso` —
  /// la pipeline (#32) la crea appena prende in carico la Scansione, prima
  /// di chiamare Claude.
  Future<int> avviaAnalisiCopertina({
    required int scansioneId,
    DateTime? createdAt,
  }) {
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
    return (_db.update(
      _db.analisiCopertinaTable,
    )..where((a) => a.id.equals(id))).write(
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
    return (_db.update(
      _db.analisiCopertinaTable,
    )..where((a) => a.id.equals(id))).write(
      AnalisiCopertinaTableCompanion(
        status: const Value(StatoAnalisiCopertina.fallita),
        errorMessage: Value(errorMessage),
        completedAt: Value(completedAt ?? DateTime.now()),
      ),
    );
  }

  /// L'id della riga `AnalisiCopertina` già creata per questa Scansione —
  /// usato dal retry manuale (riepilogo) per riprendere la riga esistente
  /// invece di crearne una seconda, che romperebbe la relazione 1:1 con la
  /// Scansione.
  Future<int> idAnalisiCopertinaPerScansione(int scansioneId) async {
    final riga = await (_db.select(
      _db.analisiCopertinaTable,
    )..where((a) => a.scansioneId.equals(scansioneId))).getSingle();
    return riga.id;
  }

  /// Riporta un'Analisi Copertina `fallita` in stato `inCorso` per un nuovo
  /// tentativo — retry manuale dall'utente (nessun retry automatico, #27):
  /// azzera `errorMessage`/`completedAt` della riga esistente.
  Future<void> riavviaAnalisiCopertina({required int id}) {
    return (_db.update(
      _db.analisiCopertinaTable,
    )..where((a) => a.id.equals(id))).write(
      const AnalisiCopertinaTableCompanion(
        status: Value(StatoAnalisiCopertina.inCorso),
        errorMessage: Value(null),
        completedAt: Value(null),
      ),
    );
  }

  /// Lo stato osservabile dell'Analisi Copertina per la Scansione con questo
  /// percorso immagine — usato dal riepilogo per riflettere lo stato reale
  /// invece di un placeholder statico. `pending` finché la pipeline
  /// sequenziale non ha ancora creato la riga per questa Scansione.
  Stream<StatoAnalisiScansione> watchStatoAnalisiCopertina(String image) {
    final query = _db.select(_db.scansioni).join([
      leftOuterJoin(
        _db.analisiCopertinaTable,
        _db.analisiCopertinaTable.scansioneId.equalsExp(_db.scansioni.id),
      ),
    ])..where(_db.scansioni.image.equals(image));

    return query.watchSingleOrNull().map((row) {
      final analisi = row?.readTableOrNull(_db.analisiCopertinaTable);
      return (
        stato: analisi?.status ?? StatoAnalisiCopertina.pending,
        errorMessage: analisi?.errorMessage,
      );
    });
  }

  /// Crea la riga `Identificazione` di una Scansione, in stato `inCorso` —
  /// la pipeline (§6.3, deciso su #53) la crea appena prende in carico la
  /// Scansione dopo il completamento dell'Analisi Copertina, sul modello di
  /// [avviaAnalisiCopertina].
  Future<int> avviaIdentificazione({
    required int scansioneId,
    DateTime? createdAt,
  }) {
    return _db
        .into(_db.identificazioneTable)
        .insert(
          IdentificazioneTableCompanion.insert(
            scansioneId: scansioneId,
            status: const Value(StatoIdentificazione.inCorso),
            createdAt: createdAt ?? DateTime.now(),
          ),
        );
  }

  /// Persiste un Candidato proposto per un'Identificazione — una riga per
  /// candidato, non appena proposto (deciso su #53), indipendentemente da
  /// quale verrà poi confermato con [marcaCandidatoScelto].
  Future<int> aggiungiCandidato({
    required int identificazioneId,
    required FonteCandidato source,
    required double punteggio,
    int? edizioneId,
    String? title,
    String? seriesName,
    String? issueNumberLabel,
    String? publisher,
    int? year,
    String? coverImageUrl,
  }) {
    return _db
        .into(_db.candidatiTable)
        .insert(
          CandidatiTableCompanion.insert(
            identificazioneId: identificazioneId,
            source: source,
            punteggio: punteggio,
            edizioneId: Value(edizioneId),
            title: Value(title),
            seriesName: Value(seriesName),
            issueNumberLabel: Value(issueNumberLabel),
            publisher: Value(publisher),
            year: Value(year),
            coverImageUrl: Value(coverImageUrl),
          ),
        );
  }

  /// Conclude un'Identificazione con successo — anche col caso "zero
  /// Candidati trovati" (nessuno stato speciale, deciso su #53): la tabella
  /// `Candidati` resta semplicemente senza righe per questa Identificazione.
  Future<void> completaIdentificazione({
    required int id,
    DateTime? completedAt,
  }) {
    return (_db.update(
      _db.identificazioneTable,
    )..where((i) => i.id.equals(id))).write(
      IdentificazioneTableCompanion(
        status: const Value(StatoIdentificazione.completata),
        completedAt: Value(completedAt ?? DateTime.now()),
      ),
    );
  }

  /// Registra un fallimento tecnico dell'Identificazione (es. ComicVine
  /// irraggiungibile) — nessun retry automatico, sul modello di
  /// [fallisciAnalisiCopertina].
  Future<void> fallisciIdentificazione({
    required int id,
    required String errorMessage,
    DateTime? completedAt,
  }) {
    return (_db.update(
      _db.identificazioneTable,
    )..where((i) => i.id.equals(id))).write(
      IdentificazioneTableCompanion(
        status: const Value(StatoIdentificazione.fallita),
        errorMessage: Value(errorMessage),
        completedAt: Value(completedAt ?? DateTime.now()),
      ),
    );
  }

  /// Marca il Candidato confermato dall'utente (schermo di conferma, #54) —
  /// la riga scelta fra quelle proposte per la stessa Identificazione.
  Future<void> marcaCandidatoScelto({required int id}) {
    return (_db.update(
      _db.candidatiTable,
    )..where((c) => c.id.equals(id))).write(
      const CandidatiTableCompanion(scelto: Value(true)),
    );
  }

  /// L'esito osservabile dell'Identificazione di una Scansione — stato più
  /// Candidati ordinati per punteggio decrescente (schermo di conferma,
  /// #54/#59). `pending` finché la pipeline (§6.3, agganciata su #58) non ha
  /// ancora creato la riga `Identificazione` per questa Scansione, stesso
  /// significato di `watchStatoAnalisiCopertina`.
  Stream<EsitoIdentificazione> watchIdentificazione(int scansioneId) {
    final query =
        _db.select(_db.identificazioneTable).join([
            leftOuterJoin(
              _db.candidatiTable,
              _db.candidatiTable.identificazioneId.equalsExp(
                _db.identificazioneTable.id,
              ),
            ),
          ])
          ..where(_db.identificazioneTable.scansioneId.equals(scansioneId))
          ..orderBy([OrderingTerm.desc(_db.candidatiTable.punteggio)]);

    return query.watch().map((rows) {
      if (rows.isEmpty) {
        return (
          stato: StatoIdentificazione.pending,
          errorMessage: null,
          candidati: const <Candidato>[],
        );
      }
      final identificazione = rows.first.readTable(_db.identificazioneTable);
      final candidati = [
        for (final row in rows)
          if (row.readTableOrNull(_db.candidatiTable) case final c?)
            _candidatoDaRiga(c),
      ];
      return (
        stato: identificazione.status,
        errorMessage: identificazione.errorMessage,
        candidati: candidati,
      );
    });
  }

  Candidato _candidatoDaRiga(CandidatiTableData riga) {
    return Candidato(
      id: riga.id,
      source: riga.source,
      punteggio: riga.punteggio,
      scelto: riga.scelto,
      edizioneId: riga.edizioneId,
      title: riga.title,
      seriesName: riga.seriesName,
      issueNumberLabel: riga.issueNumberLabel,
      publisher: riga.publisher,
      year: riga.year,
      coverImageUrl: riga.coverImageUrl,
    );
  }

  /// Conferma un Candidato (schermo di conferma, §6.3, deciso su #54/#59):
  /// marca la riga scelta e collega/crea la Copia risultante. Se `interno`
  /// (Edizione già catalogata), aggiunge solo una nuova Copia a
  /// quell'Edizione; se `esterno` (ComicVine, nessuna Edizione propria
  /// ancora), crea Opera/Serie/Edizione da zero a partire dai campi grezzi
  /// del candidato prima di aggiungere la Copia. Ritorna l'id della Copia
  /// creata.
  Future<int> confermaCandidato({
    required Candidato candidato,
    required int scansioneId,
  }) async {
    await marcaCandidatoScelto(id: candidato.id);

    final edizioneId = candidato.source == FonteCandidato.interno
        ? candidato.edizioneId!
        : await _creaEdizioneDaCandidato(candidato);

    return aggiungiCopia(
      edizioneId: edizioneId,
      status: StatoCopia.posseduta,
      scansioneId: scansioneId,
    );
  }

  Future<int> _creaEdizioneDaCandidato(Candidato candidato) async {
    final operaId = await aggiungiOpera(
      title: candidato.title ?? candidato.seriesName ?? 'Senza titolo',
    );

    int? serieId;
    if (candidato.seriesName != null) {
      serieId = await aggiungiSerie(name: candidato.seriesName!);
    }

    return aggiungiEdizione(
      operaId: operaId,
      serieId: serieId,
      publisher: candidato.publisher,
      issueNumber: candidato.issueNumberLabel != null
          ? int.tryParse(candidato.issueNumberLabel!.trim())
          : null,
      issueNumberLabel: candidato.issueNumberLabel,
      coverImage: await _coverImagePerCandidato(candidato),
    );
  }

  /// La cover da salvare sull'Edizione creata da un Candidato esterno: una
  /// copia locale scaricata da ComicVine (vedi [CopertinaDownloader]) invece
  /// dell'URL remoto, così il catalogo non dipende dalla disponibilità
  /// futura di quell'URL. Se il download fallisce (rete, host irraggiungibile)
  /// ricade sull'URL originale invece di lasciare l'Edizione senza cover —
  /// nessun retry, la conferma del Candidato non deve fallire per questo.
  Future<String?> _coverImagePerCandidato(Candidato candidato) async {
    final url = candidato.coverImageUrl;
    if (url == null) return null;
    return await _copertinaDownloader.scarica(url) ?? url;
  }

  /// La riga `AnalisiCopertina` completata di questa Scansione — letta dal
  /// motore di matching (#52/#57) per generare i Candidati di
  /// un'Identificazione. Presuppone che l'Analisi Copertina sia già
  /// `completata`: la pipeline (§6.3) avvia l'Identificazione solo dopo,
  /// stesso ordine del requisito.
  Future<AnalisiCopertinaTableData> analisiCopertinaPerScansione(
    int scansioneId,
  ) {
    return (_db.select(
      _db.analisiCopertinaTable,
    )..where((a) => a.scansioneId.equals(scansioneId))).getSingle();
  }

  /// Il catalogo interno (Opere/Serie/Edizioni) con Opera/Serie già risolte
  /// via join, pronto per il motore di matching (#52/#57) — nessun filtro:
  /// ogni Edizione è un candidato interno potenziale a prescindere da quante
  /// Copie possiede.
  Future<List<EdizioneCatalogo>> catalogoPerMatching() {
    final query = _db.select(_db.edizioni).join([
      innerJoin(_db.opere, _db.opere.id.equalsExp(_db.edizioni.operaId)),
      leftOuterJoin(
        _db.serieTable,
        _db.serieTable.id.equalsExp(_db.edizioni.serieId),
      ),
    ]);
    return query.get().then(
      (rows) => [
        for (final row in rows)
          EdizioneCatalogo(
            edizioneId: row.readTable(_db.edizioni).id,
            title: row.readTable(_db.opere).title,
            serieId: row.readTableOrNull(_db.serieTable)?.id,
            seriesName: row.readTableOrNull(_db.serieTable)?.name,
            publisher: row.readTable(_db.edizioni).publisher,
            issueNumber: row.readTable(_db.edizioni).issueNumber,
            issueNumberLabel: row.readTable(_db.edizioni).issueNumberLabel,
            coverImage: row.readTable(_db.edizioni).coverImage,
          ),
      ],
    );
  }

  /// I numeri posseduti per Serie — stesso filtro "posseduto" del resto del
  /// catalogo (`status IN (posseduta, prestata)`, vedi `watchDashboardKpis`)
  /// — usati dal bonus di contesto del motore di matching (Livello 5,
  /// #52/#57): il numero di una Serie senza `issueNumber` non è comparabile
  /// e viene escluso.
  Future<Map<int, Set<int>>> numeriPossedutiPerSerie() {
    final query =
        _db.select(_db.copie).join([
          innerJoin(
            _db.edizioni,
            _db.edizioni.id.equalsExp(_db.copie.edizioneId),
          ),
        ])..where(
          _db.copie.status.isInValues(const [
            StatoCopia.posseduta,
            StatoCopia.prestata,
          ]),
        );

    return query.get().then((rows) {
      final risultato = <int, Set<int>>{};
      for (final row in rows) {
        final edizione = row.readTable(_db.edizioni);
        final serieId = edizione.serieId;
        final numero = edizione.issueNumber;
        if (serieId == null || numero == null) continue;
        risultato.putIfAbsent(serieId, () => {}).add(numero);
      }
      return risultato;
    });
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
                  for (final row in entry.value)
                    row.read<int>('numero_mancante'),
                ],
                numeriPosseduti:
                    entry.value.first.read<int>('numeri_totali') -
                    entry.value.length,
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
    final query =
        _db.select(_db.copie).join([
            innerJoin(
              _db.edizioni,
              _db.edizioni.id.equalsExp(_db.copie.edizioneId),
            ),
            innerJoin(_db.opere, _db.opere.id.equalsExp(_db.edizioni.operaId)),
          ])
          ..where(
            _db.copie.status.isInValues(const [
              StatoCopia.posseduta,
              StatoCopia.prestata,
            ]),
          )
          ..orderBy([
            OrderingTerm.desc(_db.copie.createdAt),
            OrderingTerm.desc(_db.copie.id),
          ])
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
            coverImage: row.readTable(_db.edizioni).coverImage,
          ),
      ],
    );
  }
}
