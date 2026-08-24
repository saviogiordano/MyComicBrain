import 'dart:io';

import 'package:drift/drift.dart';
import 'package:mycomicbrain/core/data/copertina_downloader.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/data/percorso_locale.dart' as percorso_locale;
import 'package:mycomicbrain/core/domain/analisi_copertina.dart';
import 'package:mycomicbrain/core/domain/copia.dart';
import 'package:mycomicbrain/core/domain/creator.dart';
import 'package:mycomicbrain/core/domain/dashboard_kpis.dart';
import 'package:mycomicbrain/core/domain/edizione_catalogo.dart';
import 'package:mycomicbrain/core/domain/edizione_dettaglio.dart';
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

  Future<int> aggiungiSerie({
    required String name,
    int? totalIssues,
    String? issn,
  }) {
    return _db
        .into(_db.serieTable)
        .insert(
          SerieTableCompanion.insert(
            name: name,
            totalIssues: Value(totalIssues),
            issn: Value(issn),
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
    String? releaseDate,
    String? coverPrice,
    int? pageCount,
    String? language,
    String? color,
    String? ean,
    String? volume,
    String? description,
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
            releaseDate: Value(releaseDate),
            coverPrice: Value(coverPrice),
            pageCount: Value(pageCount),
            language: Value(language),
            color: Value(color),
            ean: Value(ean),
            volume: Value(volume),
            description: Value(description),
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

  /// Cerca Creator esistenti per nome (match parziale, per l'autocomplete
  /// della Scheda — vedi "Not yet specified" sulla mappa #63).
  Future<List<CreatorData>> cercaCreator(String query) {
    return (_db.select(
      _db.creator,
    )..where((c) => c.name.like('%$query%'))).get();
  }

  /// Crea un nuovo Creator. Nessun controllo di univocità sul nome (#64).
  Future<int> aggiungiCreator(String name) {
    return _db.into(_db.creator).insert(CreatorCompanion.insert(name: name));
  }

  /// Collega un Creator a un'Edizione con un ruolo. Ammessi più Creator con
  /// lo stesso ruolo sulla stessa Edizione e lo stesso Creator con ruoli
  /// diversi (#64).
  Future<void> collegaCreatorAEdizione({
    required int edizioneId,
    required int creatorId,
    required RuoloCreator ruolo,
  }) {
    return _db
        .into(_db.comicCreator)
        .insert(
          ComicCreatorCompanion.insert(
            edizioneId: edizioneId,
            creatorId: creatorId,
            ruolo: ruolo,
          ),
        );
  }

  /// Rimuove un collegamento Creator↔Edizione (riga ComicCreator).
  Future<void> rimuoviCreatorDaEdizione(int comicCreatorId) {
    return (_db.delete(
      _db.comicCreator,
    )..where((c) => c.id.equals(comicCreatorId))).go();
  }

  /// Legge tutti i Creator collegati a un'Edizione con il relativo ruolo,
  /// per il rendering della Scheda (§8.1).
  Future<List<CreatorConRuolo>> autoriDiEdizione(int edizioneId) {
    final query = _db.select(_db.comicCreator).join([
      innerJoin(
        _db.creator,
        _db.creator.id.equalsExp(_db.comicCreator.creatorId),
      ),
    ])..where(_db.comicCreator.edizioneId.equals(edizioneId));

    return query.get().then(
      (rows) => [
        for (final row in rows)
          (
            comicCreatorId: row.readTable(_db.comicCreator).id,
            creatorId: row.readTable(_db.creator).id,
            name: row.readTable(_db.creator).name,
            ruolo: row.readTable(_db.comicCreator).ruolo,
          ),
      ],
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

  /// Il valore da passare come `coverImage` di [aggiungiEdizione] per usare
  /// la cover scansionata di questa Scansione (§6.3, deciso su #63) —
  /// `InserisciManualmentePage` non ha altrimenti nessuna cover da mostrare,
  /// a differenza di un Candidato che ne porta una propria (ComicVine o
  /// un'Edizione interna già catalogata). Relativizzato alla cartella base
  /// come [_coverImagePerCandidato]: `ScansioneStorage` salva `image` come
  /// percorso *assoluto* (sotto `scansioni/`, riconosciuto comunque da
  /// [percorso_locale.risolvi] anche non relativizzato), ma le nuove righe
  /// devono restare coerenti col formato relativo usato da qui in avanti.
  Future<String> coverImagePerScansione(int scansioneId) async {
    final riga = await (_db.select(
      _db.scansioni,
    )..where((s) => s.id.equals(scansioneId))).getSingle();
    final base = await _copertinaDownloader.baseDirectory();
    return percorso_locale.relativizza(riga.image, base);
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
    String? releaseDate,
    int? pageCount,
    String? language,
    String? color,
    String? issn,
    List<String> characters = const [],
    List<String> coverStyleTags = const [],
    List<String> visualElementTags = const [],
    String? recognizedPublisherLogo,
    String? recognizedSeriesLogo,
    String? printingType,
    String? classificazione,
    String? description,
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
        releaseDate: Value(releaseDate),
        pageCount: Value(pageCount),
        language: Value(language),
        color: Value(color),
        issn: Value(issn),
        characters: Value(characters),
        coverStyleTags: Value(coverStyleTags),
        visualElementTags: Value(visualElementTags),
        recognizedPublisherLogo: Value(recognizedPublisherLogo),
        recognizedSeriesLogo: Value(recognizedSeriesLogo),
        printingType: Value(printingType),
        classificazione: Value(classificazione),
        description: Value(description),
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
    String? description,
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
            description: Value(description),
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

    return query.watch().asyncMap((rows) async {
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
            await _candidatoDaRiga(c),
      ];
      return (
        stato: identificazione.status,
        errorMessage: identificazione.errorMessage,
        candidati: candidati,
      );
    });
  }

  /// Un Candidato `interno` porta la cover già nota dell'Edizione
  /// catalogata (`Edizioni.coverImage`, snapshot preso da `catalogoPerMatching`
  /// al momento dell'Identificazione) — stesso valore soggetto alla
  /// migrazione di container di `watchAggiuntiDiRecente`/
  /// `percorso_locale.dart`, va risolto qui allo stesso modo. Un Candidato
  /// `esterno` porta invece sempre un vero URL remoto ComicVine, passato
  /// invariato da [risolviCoverImage].
  Future<Candidato> _candidatoDaRiga(CandidatiTableData riga) async {
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
      coverImageUrl: await risolviCoverImage(riga.coverImageUrl),
      description: riga.description,
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
        : await _creaEdizioneDaCandidato(candidato, scansioneId);

    return aggiungiCopia(
      edizioneId: edizioneId,
      status: StatoCopia.posseduta,
      scansioneId: scansioneId,
    );
  }

  /// Crea Opera/Serie/Edizione per un Candidato `esterno` (ComicVine). I
  /// campi bibliografici (§8.1) vengono presi dall'Analisi Copertina di
  /// questa Scansione quando disponibili — l'estrazione AI (OCR §6.1 /
  /// computer vision §6.2) legge la copertina scansionata stessa, mentre la
  /// risorsa `issue` di ComicVine non espone quasi nessuno di questi campi
  /// (nemmeno l'editore, vedi commento su `MatchingEngine.candidatiEsterni`)
  /// — usarla come unica fonte lasciava l'Edizione quasi vuota (bug
  /// osservato, deciso su #70). ComicVine resta la fonte per titolo/serie/
  /// numero solo come ripiego quando l'AI non li ha letti, per la cover
  /// (sempre, [_coverImagePerCandidato]) e per la descrizione (unica fonte
  /// disponibile oggi).
  Future<int> _creaEdizioneDaCandidato(
    Candidato candidato,
    int scansioneId,
  ) async {
    final analisi = await analisiCopertinaPerScansione(scansioneId);

    final title =
        _nonVuoto(analisi.title) ??
        candidato.title ??
        candidato.seriesName ??
        'Senza titolo';
    final operaId = await aggiungiOpera(title: title);

    final seriesName = _nonVuoto(analisi.seriesName) ?? candidato.seriesName;
    int? serieId;
    if (seriesName != null) {
      serieId = await aggiungiSerie(name: seriesName);
    }

    final issueNumberLabel =
        _nonVuoto(analisi.issueNumberLabel) ?? candidato.issueNumberLabel;
    // `barcode` prima di `isbn`, stessa priorità di
    // `InserisciManualmentePage._prefill`: sulle edizioni italiane da
    // edicola è quasi sempre l'EAN periodico quello riportato in copertina.
    final ean = _nonVuoto(analisi.barcode) ?? _nonVuoto(analisi.isbn);

    return aggiungiEdizione(
      operaId: operaId,
      serieId: serieId,
      publisher: _nonVuoto(analisi.publisher) ?? candidato.publisher,
      issueNumber: issueNumberLabel != null
          ? int.tryParse(issueNumberLabel.trim())
          : null,
      issueNumberLabel: issueNumberLabel,
      coverImage: await _coverImagePerCandidato(candidato),
      releaseDate: _nonVuoto(analisi.releaseDate),
      coverPrice: _nonVuoto(analisi.price),
      pageCount: analisi.pageCount,
      language: _nonVuoto(analisi.language),
      color: _nonVuoto(analisi.color),
      ean: ean,
      description: candidato.description,
    );
  }

  /// `null`/stringa vuota o di soli spazi normalizzati a `null` — stesso
  /// trattamento di `InserisciManualmentePage._valore`: Claude a volte
  /// restituisce una stringa vuota invece di `null` nonostante il prompt
  /// (osservato empiricamente), che altrimenti scavalcherebbe il ripiego su
  /// ComicVine come se fosse un valore valido.
  String? _nonVuoto(String? v) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  /// La cover da salvare sull'Edizione creata da un Candidato esterno: una
  /// copia locale scaricata da ComicVine (vedi [CopertinaDownloader]) invece
  /// dell'URL remoto, così il catalogo non dipende dalla disponibilità
  /// futura di quell'URL. Se il download fallisce (rete, host irraggiungibile)
  /// ricade sull'URL originale invece di lasciare l'Edizione senza cover —
  /// nessun retry, la conferma del Candidato non deve fallire per questo.
  ///
  /// Il percorso scaricato viene salvato *relativo* alla cartella base
  /// (non l'assoluto di [CopertinaDownloader.scarica]): il container
  /// dell'app cambia UUID a ogni reinstallazione/aggiornamento su iOS, e un
  /// percorso assoluto persistito in DB in una sessione precedente punta a
  /// un container che potrebbe non esistere più (bug osservato: cover
  /// visibile subito dopo la conferma, sparita al riavvio dopo un nuovo
  /// `flutter run`). Vedi `percorso_locale.dart`.
  Future<String?> _coverImagePerCandidato(Candidato candidato) async {
    final url = candidato.coverImageUrl;
    if (url == null) return null;
    final locale = await _copertinaDownloader.scarica(url);
    if (locale == null) return url;
    final base = await _copertinaDownloader.baseDirectory();
    return percorso_locale.relativizza(locale, base);
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

    return query.watch().asyncMap((rows) async {
      final risultati = <ComicRecente>[];
      for (final row in rows) {
        risultati.add(
          ComicRecente(
            edizioneId: row.readTable(_db.edizioni).id,
            titolo: row.readTable(_db.opere).title,
            numero: row.readTable(_db.edizioni).issueNumber,
            numeroLabel: row.readTable(_db.edizioni).issueNumberLabel,
            editore: row.readTable(_db.edizioni).publisher,
            coverImage: await risolviCoverImage(
              row.readTable(_db.edizioni).coverImage,
            ),
          ),
        );
      }
      return risultati;
    });
  }

  /// Il valore di `Edizioni.coverImage` così com'è per un URL remoto
  /// (fallback ComicVine di [_coverImagePerCandidato]); per un percorso
  /// locale, ricostruito assoluto sulla cartella base *corrente* — vedi
  /// `percorso_locale.dart` sul perché non basta usare il valore in DB
  /// così com'è. `baseDirectory` è lazy (vedi [percorso_locale.risolvi]):
  /// non tocca `path_provider` per un URL remoto o un percorso che non
  /// corrisponde a nessuna sottocartella locale nota.
  Future<String?> risolviCoverImage(String? coverImage) async {
    if (coverImage == null) return null;
    if (coverImage.startsWith('http://') || coverImage.startsWith('https://')) {
      return coverImage;
    }
    return percorso_locale.risolvi(
      coverImage,
      _copertinaDownloader.baseDirectory,
    );
  }

  // --- Scheda del fumetto (§8, deciso su #63/#65/#67/#68, implementato su
  // #69). ---

  /// L'Edizione con le sue Copie e i suoi Autori, per la Scheda — `null` se
  /// l'Edizione non esiste più (es. appena cancellata da un'altra sessione).
  /// Un solo join con `Copie`/`ComicCreator`/`Creator` in parallelo (prodotto
  /// cartesiano raggruppato per id in Dart, stesso pattern di
  /// [watchIdentificazione]) invece di combinare più stream: nessuna
  /// dipendenza da rxdart in questo repository.
  Stream<EdizioneDettaglio?> watchEdizione(int edizioneId) {
    final query = _db.select(_db.edizioni).join([
      innerJoin(_db.opere, _db.opere.id.equalsExp(_db.edizioni.operaId)),
      leftOuterJoin(
        _db.serieTable,
        _db.serieTable.id.equalsExp(_db.edizioni.serieId),
      ),
      leftOuterJoin(
        _db.copie,
        _db.copie.edizioneId.equalsExp(_db.edizioni.id),
      ),
      leftOuterJoin(
        _db.comicCreator,
        _db.comicCreator.edizioneId.equalsExp(_db.edizioni.id),
      ),
      leftOuterJoin(
        _db.creator,
        _db.creator.id.equalsExp(_db.comicCreator.creatorId),
      ),
    ])..where(_db.edizioni.id.equals(edizioneId));

    return query.watch().asyncMap((rows) async {
      if (rows.isEmpty) return null;

      final edizione = rows.first.readTable(_db.edizioni);
      final opera = rows.first.readTable(_db.opere);
      final serie = rows.first.readTableOrNull(_db.serieTable);

      final copieById = <int, CopiaDettaglio>{};
      final autoriById = <int, CreatorConRuolo>{};
      for (final row in rows) {
        final copia = row.readTableOrNull(_db.copie);
        if (copia != null) {
          copieById[copia.id] = CopiaDettaglio(
            id: copia.id,
            status: copia.status,
            readingStatus: copia.readingStatus,
            condition: copia.condition,
            purchasePrice: copia.purchasePrice,
            purchaseDate: copia.purchaseDate,
            seller: copia.seller,
            location: copia.location,
            notes: copia.notes,
          );
        }
        final comicCreator = row.readTableOrNull(_db.comicCreator);
        final creator = row.readTableOrNull(_db.creator);
        if (comicCreator != null && creator != null) {
          autoriById[comicCreator.id] = (
            comicCreatorId: comicCreator.id,
            creatorId: creator.id,
            name: creator.name,
            ruolo: comicCreator.ruolo,
          );
        }
      }

      final copie = copieById.values.toList()
        ..sort((a, b) => a.id.compareTo(b.id));
      final autori = autoriById.values.toList()
        ..sort((a, b) => a.comicCreatorId.compareTo(b.comicCreatorId));

      return EdizioneDettaglio(
        edizioneId: edizione.id,
        operaId: opera.id,
        titolo: opera.title,
        serieId: serie?.id,
        serieName: serie?.name,
        publisher: edizione.publisher,
        issueNumber: edizione.issueNumber,
        issueNumberLabel: edizione.issueNumberLabel,
        coverImage: await risolviCoverImage(edizione.coverImage),
        releaseDate: edizione.releaseDate,
        coverPrice: edizione.coverPrice,
        pageCount: edizione.pageCount,
        language: edizione.language,
        color: edizione.color,
        ean: edizione.ean,
        volume: edizione.volume,
        description: edizione.description,
        autori: autori,
        copie: copie,
      );
    });
  }

  /// Il valore grezzo (relativo, non risolto) di `Edizioni.coverImage` — a
  /// differenza di [watchEdizione]/[risolviCoverImage] (che lo risolvono
  /// assoluto per la visualizzazione), serve alla modifica bibliografica
  /// (#67) per non alterare la cover quando l'utente non ne sceglie una
  /// nuova dalla galleria.
  Future<String?> coverImageGrezzoDi(int edizioneId) async {
    final riga = await (_db.select(
      _db.edizioni,
    )..where((e) => e.id.equals(edizioneId))).getSingle();
    return riga.coverImage;
  }

  /// Salva una cover scelta dalla galleria (`image_picker`) per la modifica
  /// bibliografica della Scheda (§8.1, deciso su #67) e la relativizza nello
  /// stesso formato del resto del catalogo — vedi [_coverImagePerCandidato].
  Future<String> salvaCoverLocale(File file) async {
    final locale = await _copertinaDownloader.salvaLocale(file);
    final base = await _copertinaDownloader.baseDirectory();
    return percorso_locale.relativizza(locale, base);
  }

  /// Aggiorna il titolo dell'Opera collegata a un'Edizione (§8.1) — il
  /// titolo vive su `Opere`, non su `Edizioni` (§36, distinzione Opera/
  /// Edizione).
  Future<void> aggiornaTitoloOpera({
    required int operaId,
    required String title,
  }) {
    return (_db.update(
      _db.opere,
    )..where((o) => o.id.equals(operaId))).write(
      OpereCompanion(title: Value(title)),
    );
  }

  /// Aggiorna i campi bibliografici di un'Edizione (§8.1, flusso deciso su
  /// #67) — esclusi titolo ([aggiornaTitoloOpera]) e Autori
  /// ([collegaCreatorAEdizione]/[rimuoviCreatorDaEdizione]).
  Future<void> aggiornaEdizione({
    required int id,
    int? serieId,
    String? publisher,
    int? issueNumber,
    String? issueNumberLabel,
    String? coverImage,
    String? releaseDate,
    String? coverPrice,
    int? pageCount,
    String? language,
    String? color,
    String? ean,
    String? volume,
    String? description,
  }) {
    return (_db.update(
      _db.edizioni,
    )..where((e) => e.id.equals(id))).write(
      EdizioniCompanion(
        serieId: Value(serieId),
        publisher: Value(publisher),
        issueNumber: Value(issueNumber),
        issueNumberLabel: Value(issueNumberLabel),
        coverImage: Value(coverImage),
        releaseDate: Value(releaseDate),
        coverPrice: Value(coverPrice),
        pageCount: Value(pageCount),
        language: Value(language),
        color: Value(color),
        ean: Value(ean),
        volume: Value(volume),
        description: Value(description),
      ),
    );
  }

  /// Aggiorna i campi personali §8.2 di una Copia (flusso deciso su #67) —
  /// esclusi `status`/`readingStatus` (§8.3, [cambiaStatoCopia]): scrive
  /// solo le colonne qui elencate, lasciando lo stato invariato.
  Future<void> aggiornaCopia({
    required int id,
    CondizioneCopia? condition,
    double? purchasePrice,
    DateTime? purchaseDate,
    String? seller,
    String? location,
    String? notes,
  }) {
    return (_db.update(
      _db.copie,
    )..where((c) => c.id.equals(id))).write(
      CopieCompanion(
        condition: Value(condition),
        purchasePrice: Value(purchasePrice),
        purchaseDate: Value(purchaseDate),
        seller: Value(seller),
        location: Value(location),
        notes: Value(notes),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Cambia lo stato di una Copia (§8.3, selettore singolo mutuamente
  /// esclusivo — deciso in apertura della mappa #63, vedi `voce_stato.dart`):
  /// scrive solo `status`/`readingStatus`, lasciando invariati i campi §8.2.
  Future<void> cambiaStatoCopia({
    required int id,
    required StatoCopia status,
    StatoLettura? readingStatus,
  }) {
    return (_db.update(
      _db.copie,
    )..where((c) => c.id.equals(id))).write(
      CopieCompanion(
        status: Value(status),
        readingStatus: Value(readingStatus),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Rimuove una singola Copia (§8.4). Se era l'ultima Copia della sua
  /// Edizione, elimina anche l'Edizione (deciso su #68: nessuno stato
  /// "orfana, 0 copie") — ritorna `true` in quel caso, così il chiamante
  /// (la Scheda) sa di dover navigare via.
  Future<bool> rimuoviCopia(int id) {
    return _db.transaction(() async {
      final copia = await (_db.select(
        _db.copie,
      )..where((c) => c.id.equals(id))).getSingle();
      await (_db.delete(_db.copie)..where((c) => c.id.equals(id))).go();

      final rimanenti = await (_db.select(
        _db.copie,
      )..where((c) => c.edizioneId.equals(copia.edizioneId))).get();
      if (rimanenti.isEmpty) {
        await _eliminaEdizioneSenzaCopie(copia.edizioneId);
        return true;
      }
      return false;
    });
  }

  /// Elimina un'intera Edizione con tutte le sue Copie (§8.4) — il bottone
  /// "Elimina edizione" sempre visibile deciso su #65/#68.
  Future<void> eliminaEdizione(int edizioneId) {
    return _db.transaction(() async {
      await (_db.delete(
        _db.copie,
      )..where((c) => c.edizioneId.equals(edizioneId))).go();
      await _eliminaEdizioneSenzaCopie(edizioneId);
    });
  }

  /// Rimuove i collegamenti Autore e la riga `Edizioni` — presuppone che le
  /// Copie siano già state eliminate dal chiamante ([rimuoviCopia],
  /// [eliminaEdizione]).
  Future<void> _eliminaEdizioneSenzaCopie(int edizioneId) async {
    await (_db.delete(
      _db.comicCreator,
    )..where((c) => c.edizioneId.equals(edizioneId))).go();
    await (_db.delete(
      _db.edizioni,
    )..where((e) => e.id.equals(edizioneId))).go();
  }
}
