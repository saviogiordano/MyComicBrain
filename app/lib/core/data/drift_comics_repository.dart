import 'dart:io';

import 'package:drift/drift.dart';
import 'package:mycomicbrain/core/data/archivio_conversazione.dart';
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/data/conferma_candidato.dart';
import 'package:mycomicbrain/core/data/copertina_downloader.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/data/exchange_rate_client.dart';
import 'package:mycomicbrain/core/data/importazione_schema.dart';
import 'package:mycomicbrain/core/data/percorso_locale.dart' as percorso_locale;
import 'package:mycomicbrain/core/domain/analisi_copertina.dart';
import 'package:mycomicbrain/core/domain/catalogo_stampabile.dart';
import 'package:mycomicbrain/core/domain/conversazione.dart';
import 'package:mycomicbrain/core/domain/copia.dart';
import 'package:mycomicbrain/core/domain/creator.dart';
import 'package:mycomicbrain/core/domain/dashboard_kpis.dart';
import 'package:mycomicbrain/core/domain/edizione_catalogo.dart';
import 'package:mycomicbrain/core/domain/edizione_collezione.dart';
import 'package:mycomicbrain/core/domain/edizione_dettaglio.dart';
import 'package:mycomicbrain/core/domain/esportazione.dart';
import 'package:mycomicbrain/core/domain/formato.dart';
import 'package:mycomicbrain/core/domain/genere.dart';
import 'package:mycomicbrain/core/domain/identificazione.dart';
import 'package:mycomicbrain/core/domain/ricerca_assistente.dart';
import 'package:mycomicbrain/core/domain/serie_dettaglio.dart';
import 'package:mycomicbrain/core/domain/serie_lista.dart';
import 'package:mycomicbrain/core/domain/valore_stimato.dart';
import 'package:path/path.dart' as p;

/// [ComicsRepository] su drift: il catalogo della Modalità locale, nel
/// database SQLite sul device (ADR-0005, ADR-0007).
class DriftComicsRepository implements ComicsRepository {
  DriftComicsRepository(
    this._db, {
    CopertinaDownloader? copertinaDownloader,
    ExchangeRateClient? exchangeRateClient,
    ArchivioConversazione? conversazione,
  }) : _copertinaDownloader = copertinaDownloader ?? CopertinaDownloader(),
       _exchangeRateClient =
           exchangeRateClient ?? FrankfurterExchangeRateClient(),
       _conversazione = conversazione ?? ArchivioConversazioneDrift(_db);

  final AppDatabase _db;
  final CopertinaDownloader _copertinaDownloader;
  final ExchangeRateClient _exchangeRateClient;

  /// Nel database stesso per la Modalità locale; su Supabase per la Replica
  /// di un Profilo autenticato, che non contiene la Conversazione
  /// (ADR-0008).
  final ArchivioConversazione _conversazione;

  /// Cache in-process del tasso USD→EUR per [watchDashboardKpis]: una sola
  /// chiamata di rete ogni [_validitaCacheTasso], non una ad ogni emissione
  /// dello stream (che altrimenti ripartirebbe ad ogni scrittura sul
  /// catalogo — la Dashboard resta reattiva sulle sole tabelle SQL).
  double? _tassoUsdEurCache;
  DateTime? _tassoUsdEurCacheAl;
  static const _validitaCacheTasso = Duration(hours: 1);

  Future<double> _tassoUsdEur() async {
    final cacheAl = _tassoUsdEurCacheAl;
    if (cacheAl != null &&
        DateTime.now().difference(cacheAl) < _validitaCacheTasso) {
      return _tassoUsdEurCache!;
    }
    final tasso = await _exchangeRateClient.tassoUsdEur();
    _tassoUsdEurCache = tasso;
    _tassoUsdEurCacheAl = DateTime.now();
    return tasso;
  }

  @override
  Future<bool> haDatiDaImportare() async {
    for (final tabella in <TableInfo<Table, Object?>>[
      _db.opere,
      _db.serieTable,
      _db.scansioni,
      _db.creator,
      _db.character,
      _db.tagTable,
    ]) {
      final riga =
          await (_db.selectOnly(tabella)
                ..addColumns([const CustomExpression<int>('1')])
                ..limit(1))
              .getSingleOrNull();
      if (riga != null) return true;
    }
    return false;
  }

  // --- Scrittura (usata dai test per costruire fixture; superficie minima
  // per il catalogo — nessuna schermata di questa mappa scrive dati). ---

  @override
  Future<String> aggiungiOpera({required String title, DateTime? createdAt}) {
    return _db
        .into(_db.opere)
        .insertReturning(
          OpereCompanion.insert(
            title: title,
            createdAt: createdAt ?? DateTime.now(),
          ),
        )
        .then((riga) => riga.id);
  }

  @override
  Future<String> aggiungiSerie({
    required String name,
    int? totalIssues,
    String? issn,
  }) async {
    final nomeNormalizzato = name.trim();
    final esistente =
        await (_db.select(_db.serieTable)..where(
              (s) => s.name.lower().equals(nomeNormalizzato.toLowerCase()),
            ))
            .getSingleOrNull();
    if (esistente != null) return esistente.id;

    return _db
        .into(_db.serieTable)
        .insertReturning(
          SerieTableCompanion.insert(
            name: nomeNormalizzato,
            totalIssues: Value(totalIssues),
            issn: Value(issn),
          ),
        )
        .then((riga) => riga.id);
  }

  @override
  Future<String> nomeSerieDiEdizione({
    required String edizioneId,
    required String serieId,
    required String nome,
  }) {
    return _db.transaction(() async {
      final nomeNormalizzato = nome.trim();
      final altreEdizioni =
          await (_db.select(_db.edizioni)..where(
                (e) =>
                    e.serieId.equals(serieId) & e.id.equals(edizioneId).not(),
              ))
              .get();
      final omonima =
          await (_db.select(_db.serieTable)..where(
                (s) =>
                    s.name.lower().equals(nomeNormalizzato.toLowerCase()) &
                    s.id.equals(serieId).not(),
              ))
              .get();
      if (altreEdizioni.isNotEmpty || omonima.isNotEmpty) {
        return aggiungiSerie(name: nomeNormalizzato);
      }
      await (_db.update(_db.serieTable)..where((s) => s.id.equals(serieId)))
          .write(SerieTableCompanion(name: Value(nomeNormalizzato)));
      return serieId;
    });
  }

  /// Cancella la Serie [serieId] se non ha più Edizioni: una Serie è solo
  /// un raggruppamento, vuota non ha senso (e gonfia i KPI).
  Future<void> _eliminaSerieSeVuota(String? serieId) async {
    if (serieId == null) return;
    final edizioni = await (_db.select(
      _db.edizioni,
    )..where((e) => e.serieId.equals(serieId))).get();
    if (edizioni.isNotEmpty) return;
    await (_db.delete(
      _db.serieTable,
    )..where((s) => s.id.equals(serieId))).go();
  }

  @override
  Future<void> unisciSerieDuplicate() {
    return _db.transaction(() async {
      final tutte = await _db.select(_db.serieTable).get();
      final gruppi = <String, List<SerieTableData>>{};
      for (final serie in tutte) {
        gruppi
            .putIfAbsent(serie.name.trim().toLowerCase(), () => [])
            .add(serie);
      }

      for (final gruppo in gruppi.values) {
        if (gruppo.length < 2) continue;
        gruppo.sort((a, b) => a.id.compareTo(b.id));
        final superstite = gruppo.first;
        final duplicate = gruppo.skip(1);

        final totalIssues =
            superstite.totalIssues ??
            gruppo
                .map((s) => s.totalIssues)
                .firstWhere((v) => v != null, orElse: () => null);
        final issn =
            superstite.issn ??
            gruppo
                .map((s) => s.issn)
                .firstWhere((v) => v != null, orElse: () => null);
        if (totalIssues != superstite.totalIssues || issn != superstite.issn) {
          await (_db.update(
            _db.serieTable,
          )..where((s) => s.id.equals(superstite.id))).write(
            SerieTableCompanion(
              totalIssues: Value(totalIssues),
              issn: Value(issn),
            ),
          );
        }

        for (final dup in duplicate) {
          await (_db.update(_db.edizioni)
                ..where((e) => e.serieId.equals(dup.id)))
              .write(EdizioniCompanion(serieId: Value(superstite.id)));
          await (_db.delete(
            _db.serieTable,
          )..where((s) => s.id.equals(dup.id))).go();
        }
      }
    });
  }

  @override
  Future<String> aggiungiEdizione({
    required String operaId,
    String? serieId,
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
    String? printingType,
    String? classificazione,
    int? year,
    FormatoEdizione? format,
    DateTime? createdAt,
  }) {
    return _db
        .into(_db.edizioni)
        .insertReturning(
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
            printingType: Value(printingType),
            classificazione: Value(classificazione),
            year: Value(year),
            format: Value(format),
            createdAt: createdAt ?? DateTime.now(),
          ),
        )
        .then((riga) => riga.id);
  }

  @override
  Future<String> aggiungiCopia({
    required String edizioneId,
    required StatoCopia status,
    StatoLettura? readingStatus,
    CondizioneCopia? condition,
    double? purchasePrice,
    ValutaPrezzo? purchasePriceCurrency,
    DateTime? purchaseDate,
    String? seller,
    String? location,
    String? notes,
    double? valutazione,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? scansioneId,
  }) {
    final now = DateTime.now();
    return _db
        .into(_db.copie)
        .insertReturning(
          CopieCompanion.insert(
            edizioneId: edizioneId,
            status: status,
            readingStatus: Value(readingStatus),
            condition: Value(condition),
            purchasePrice: Value(purchasePrice),
            purchasePriceCurrency: Value(purchasePriceCurrency),
            purchaseDate: Value(purchaseDate),
            seller: Value(seller),
            location: Value(location),
            notes: Value(notes),
            valutazione: Value(valutazione),
            createdAt: createdAt ?? now,
            updatedAt: updatedAt ?? createdAt ?? now,
            scansioneId: Value(scansioneId),
          ),
        )
        .then((riga) => riga.id);
  }

  @override
  Future<List<CreatorData>> cercaCreator(String query) {
    return (_db.select(
      _db.creator,
    )..where((c) => c.name.like('%$query%'))).get();
  }

  @override
  Future<String> aggiungiCreator(String name) {
    return _db
        .into(_db.creator)
        .insertReturning(CreatorCompanion.insert(name: name))
        .then((riga) => riga.id);
  }

  @override
  Future<void> collegaCreatorAEdizione({
    required String edizioneId,
    required String creatorId,
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

  @override
  Future<void> rimuoviCreatorDaEdizione(String comicCreatorId) {
    return (_db.delete(
      _db.comicCreator,
    )..where((c) => c.id.equals(comicCreatorId))).go();
  }

  @override
  Future<List<CreatorConRuolo>> autoriDiEdizione(String edizioneId) {
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

  // --- Personaggio (§9, deciso su #84) — stesso pattern di Creator/#64. ---

  @override
  Future<List<CharacterData>> cercaCharacter(String query) {
    return (_db.select(
      _db.character,
    )..where((c) => c.name.like('%$query%'))).get();
  }

  @override
  Future<String> aggiungiCharacter(String name) {
    return _db
        .into(_db.character)
        .insertReturning(CharacterCompanion.insert(name: name))
        .then((riga) => riga.id);
  }

  @override
  Future<void> collegaCharacterAEdizione({
    required String edizioneId,
    required String characterId,
  }) {
    return _db
        .into(_db.comicCharacter)
        .insert(
          ComicCharacterCompanion.insert(
            edizioneId: edizioneId,
            characterId: characterId,
          ),
        );
  }

  @override
  Future<void> rimuoviCharacterDaEdizione(String comicCharacterId) {
    return (_db.delete(
      _db.comicCharacter,
    )..where((c) => c.id.equals(comicCharacterId))).go();
  }

  // --- Tag personalizzati (§9, deciso su #82) — stesso pattern di Creator/#64. ---

  @override
  Future<List<TagTableData>> cercaTag(String query) {
    return (_db.select(
      _db.tagTable,
    )..where((t) => t.name.like('%$query%'))).get();
  }

  @override
  Future<String> aggiungiTag(String name) {
    return _db
        .into(_db.tagTable)
        .insertReturning(TagTableCompanion.insert(name: name))
        .then((riga) => riga.id);
  }

  @override
  Future<void> collegaTagAEdizione({
    required String edizioneId,
    required String tagId,
  }) {
    return _db
        .into(_db.edizioneTag)
        .insert(
          EdizioneTagCompanion.insert(edizioneId: edizioneId, tagId: tagId),
        );
  }

  @override
  Future<void> rimuoviTagDaEdizione(String edizioneTagId) {
    return (_db.delete(
      _db.edizioneTag,
    )..where((t) => t.id.equals(edizioneTagId))).go();
  }

  // --- Genere (§9, deciso su #84) — enum multi-valore, sostituzione intera. ---

  @override
  Future<void> impostaGeneriEdizione({
    required String edizioneId,
    required Set<GenereEdizione> generi,
  }) {
    return _db.transaction(() async {
      await (_db.delete(
        _db.edizioneGenere,
      )..where((g) => g.edizioneId.equals(edizioneId))).go();
      for (final genere in generi) {
        await _db
            .into(_db.edizioneGenere)
            .insert(
              EdizioneGenereCompanion.insert(
                edizioneId: edizioneId,
                genere: genere,
              ),
            );
      }
    });
  }

  @override
  Future<String> aggiungiScansione({
    required String image,
    DateTime? createdAt,
  }) {
    return _db
        .into(_db.scansioni)
        .insertReturning(
          ScansioniCompanion.insert(
            image: image,
            createdAt: createdAt ?? DateTime.now(),
          ),
        )
        .then((riga) => riga.id);
  }

  @override
  Future<String> idScansionePerImmagine(String image) async {
    final riga = await (_db.select(
      _db.scansioni,
    )..where((s) => s.image.equals(image))).getSingle();
    return riga.id;
  }

  @override
  Future<String> coverImagePerScansione(String scansioneId) async {
    final riga = await (_db.select(
      _db.scansioni,
    )..where((s) => s.id.equals(scansioneId))).getSingle();
    final base = await _copertinaDownloader.baseDirectory();
    return _coverDaScansione(riga.image, base);
  }

  /// La cover di un'Edizione presa dall'immagine di una Scansione, relativa
  /// a [base]. Risolta prima di relativizzare: il percorso assoluto di una
  /// Scansione scritta da un'installazione precedente punta al vecchio
  /// container iOS, e relativizzato così com'è diventerebbe un `../..` che
  /// non esiste (segnalato da utente: cover assente dopo una
  /// reinstallazione).
  Future<String> _coverDaScansione(String image, Directory base) async {
    final assoluto = await percorso_locale.risolvi(image, () async => base);
    return percorso_locale.relativizza(assoluto, base);
  }

  @override
  Future<void> eliminaScansione({required String id}) {
    return (_db.delete(_db.scansioni)..where((s) => s.id.equals(id))).go();
  }

  @override
  Future<String> avviaAnalisiCopertina({
    required String scansioneId,
    DateTime? createdAt,
  }) {
    return _db
        .into(_db.analisiCopertinaTable)
        .insertReturning(
          AnalisiCopertinaTableCompanion.insert(
            scansioneId: scansioneId,
            status: const Value(StatoAnalisiCopertina.inCorso),
            createdAt: createdAt ?? DateTime.now(),
          ),
        )
        .then((riga) => riga.id);
  }

  @override
  Future<String> accodaAnalisiCopertina({
    required String scansioneId,
    DateTime? createdAt,
  }) {
    return _db.transaction(() async {
      final esistente =
          await (_db.select(_db.analisiCopertinaTable)
                ..where((a) => a.scansioneId.equals(scansioneId))
                ..limit(1))
              .getSingleOrNull();
      if (esistente != null) return esistente.id;
      final riga = await _db
          .into(_db.analisiCopertinaTable)
          .insertReturning(
            AnalisiCopertinaTableCompanion.insert(
              scansioneId: scansioneId,
              status: const Value(StatoAnalisiCopertina.pending),
              createdAt: createdAt ?? DateTime.now(),
            ),
          );
      return riga.id;
    });
  }

  @override
  Stream<List<ScansioneInAttesa>> watchScansioniInAttesaDiAnalisi() {
    final query =
        _db.select(_db.analisiCopertinaTable).join([
            innerJoin(
              _db.scansioni,
              _db.scansioni.id.equalsExp(_db.analisiCopertinaTable.scansioneId),
            ),
          ])
          ..where(
            _db.analisiCopertinaTable.status.equalsValue(
              StatoAnalisiCopertina.pending,
            ),
          )
          ..orderBy([
            OrderingTerm.asc(_db.analisiCopertinaTable.createdAt),
            OrderingTerm.asc(_db.analisiCopertinaTable.id),
          ]);
    return query.watch().map(
      (righe) => [
        for (final riga in righe)
          (
            analisiId: riga.readTable(_db.analisiCopertinaTable).id,
            scansioneId: riga.readTable(_db.scansioni).id,
            image: riga.readTable(_db.scansioni).image,
          ),
      ],
    );
  }

  @override
  Future<void> completaAnalisiCopertina({
    required String id,
    required String rawResponse,
    String? title,
    String? issueNumberLabel,
    String? publisher,
    String? seriesName,
    String? isbn,
    String? barcode,
    String? price,
    String? releaseDate,
    int? year,
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
        year: Value(year),
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

  @override
  Future<void> fallisciAnalisiCopertina({
    required String id,
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

  @override
  Future<String> idAnalisiCopertinaPerScansione(String scansioneId) async {
    final riga = await (_db.select(
      _db.analisiCopertinaTable,
    )..where((a) => a.scansioneId.equals(scansioneId))).getSingle();
    return riga.id;
  }

  @override
  Future<void> riavviaAnalisiCopertina({required String id}) {
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

  @override
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

  @override
  Stream<bool> watchScansioneConfermata(String image) {
    final query = _db.select(_db.scansioni).join([
      leftOuterJoin(
        _db.copie,
        _db.copie.scansioneId.equalsExp(_db.scansioni.id),
      ),
    ])..where(_db.scansioni.image.equals(image));

    return query.watch().map((rows) {
      return rows.any((row) => row.readTableOrNull(_db.copie) != null);
    });
  }

  @override
  Stream<List<String>> watchImmaginiScansioniNonConfermate() {
    final query = _db.select(_db.scansioni).join([
      leftOuterJoin(
        _db.copie,
        _db.copie.scansioneId.equalsExp(_db.scansioni.id),
      ),
    ])..orderBy([OrderingTerm.asc(_db.scansioni.createdAt)]);

    return query.watch().map((rows) {
      final confermate = <String>{};
      final immagini = <String, String>{};
      for (final row in rows) {
        final scansione = row.readTable(_db.scansioni);
        immagini[scansione.id] = scansione.image;
        if (row.readTableOrNull(_db.copie) != null) {
          confermate.add(scansione.id);
        }
      }
      return [
        for (final entry in immagini.entries)
          if (!confermate.contains(entry.key)) entry.value,
      ];
    });
  }

  @override
  Future<String> avviaIdentificazione({
    required String scansioneId,
    DateTime? createdAt,
  }) {
    return _db
        .into(_db.identificazioneTable)
        .insertReturning(
          IdentificazioneTableCompanion.insert(
            scansioneId: scansioneId,
            status: const Value(StatoIdentificazione.inCorso),
            createdAt: createdAt ?? DateTime.now(),
          ),
        )
        .then((riga) => riga.id);
  }

  @override
  Future<String?> idIdentificazionePerScansione(String scansioneId) async {
    final riga = await (_db.select(
      _db.identificazioneTable,
    )..where((i) => i.scansioneId.equals(scansioneId))).getSingleOrNull();
    return riga?.id;
  }

  @override
  Future<void> riavviaIdentificazione({required String id}) async {
    await (_db.delete(
      _db.candidatiTable,
    )..where((c) => c.identificazioneId.equals(id))).go();
    await (_db.update(
      _db.identificazioneTable,
    )..where((i) => i.id.equals(id))).write(
      const IdentificazioneTableCompanion(
        status: Value(StatoIdentificazione.inCorso),
        errorMessage: Value(null),
        completedAt: Value(null),
      ),
    );
  }

  @override
  Future<String> aggiungiCandidato({
    required String identificazioneId,
    required FonteCandidato source,
    required double punteggio,
    String? edizioneId,
    String? title,
    String? seriesName,
    String? issueNumberLabel,
    String? publisher,
    int? year,
    String? coverImageUrl,
  }) {
    return _db
        .into(_db.candidatiTable)
        .insertReturning(
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
        )
        .then((riga) => riga.id);
  }

  @override
  Future<void> completaIdentificazione({
    required String id,
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

  @override
  Future<void> fallisciIdentificazione({
    required String id,
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

  @override
  Future<void> marcaCandidatoScelto({required String id}) {
    return (_db.update(_db.candidatiTable)..where((c) => c.id.equals(id)))
        .write(const CandidatiTableCompanion(scelto: Value(true)));
  }

  @override
  Stream<EsitoIdentificazione> watchIdentificazione(String scansioneId) {
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
    );
  }

  @override
  Future<String> confermaCandidato({
    required Candidato candidato,
    required String scansioneId,
  }) async {
    await marcaCandidatoScelto(id: candidato.id);

    final analisi = await (_db.select(
      _db.analisiCopertinaTable,
    )..where((a) => a.scansioneId.equals(scansioneId))).getSingleOrNull();

    final String edizioneId;
    if (candidato.source == FonteCandidato.interno) {
      edizioneId = candidato.edizioneId!;
      await _completaDescrizioneMancante(edizioneId, analisi);
    } else {
      // Un candidato `esterno` presuppone un'Analisi Copertina completata
      // (l'Identificazione parte solo dopo, vedi commento su
      // `analisiCopertinaPerScansione`).
      edizioneId = await _creaEdizioneDaCandidato(candidato, analisi!);
    }

    final prezzo = prezzoCopiaConfermata(analisi);
    return aggiungiCopia(
      edizioneId: edizioneId,
      status: StatoCopia.posseduta,
      condition: condizioneCopiaConfermata,
      purchasePrice: prezzo?.importo,
      purchasePriceCurrency: prezzo?.valuta,
      scansioneId: scansioneId,
    );
  }

  /// Crea Opera/Serie/Edizione per un Candidato `esterno` (ComicVine) con i
  /// campi di [nuovaEdizioneDaCandidato] e la cover di
  /// [_coverImagePerCandidato].
  Future<String> _creaEdizioneDaCandidato(
    Candidato candidato,
    AnalisiCopertinaTableData analisi,
  ) async {
    final e = nuovaEdizioneDaCandidato(candidato, analisi);
    final operaId = await aggiungiOpera(title: e.title);
    final seriesName = e.seriesName;
    final serieId = seriesName == null
        ? null
        : await aggiungiSerie(name: seriesName);
    return aggiungiEdizione(
      operaId: operaId,
      serieId: serieId,
      publisher: e.publisher,
      issueNumber: e.issueNumber,
      issueNumberLabel: e.issueNumberLabel,
      coverImage: await _coverImagePerCandidato(candidato),
      releaseDate: e.releaseDate,
      year: e.year,
      coverPrice: e.coverPrice,
      pageCount: e.pageCount,
      language: e.language,
      color: e.color,
      ean: e.ean,
      description: e.description,
      printingType: e.printingType,
      classificazione: e.classificazione,
    );
  }

  /// Completa la Descrizione di un'Edizione già catalogata con quella di
  /// [descrizioneDaCompletare], senza mai sovrascriverne una presente.
  Future<void> _completaDescrizioneMancante(
    String edizioneId,
    AnalisiCopertinaTableData? analisi,
  ) async {
    final descrizioneAi = descrizioneDaCompletare(analisi);
    if (descrizioneAi == null) return;
    final edizione = await (_db.select(
      _db.edizioni,
    )..where((e) => e.id.equals(edizioneId))).getSingleOrNull();
    if (edizione == null || nonVuoto(edizione.description) != null) return;
    await (_db.update(_db.edizioni)..where((e) => e.id.equals(edizioneId)))
        .write(EdizioniCompanion(description: Value(descrizioneAi)));
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

  @override
  Future<AnalisiCopertinaTableData> analisiCopertinaPerScansione(
    String scansioneId,
  ) {
    return (_db.select(
      _db.analisiCopertinaTable,
    )..where((a) => a.scansioneId.equals(scansioneId))).getSingle();
  }

  @override
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

  @override
  Future<Map<String, Set<int>>> numeriPossedutiPerSerie() {
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
      final risultato = <String, Set<int>>{};
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

  // --- Valore stimato (§35, deciso su #157/#161). ---

  @override
  Future<
    ({
      String title,
      String? seriesName,
      String? issueNumberLabel,
      String? publisher,
      CondizioneCopia? condition,
    })
  >
  copiaConEdizionePerId(String copiaId) async {
    final query = _db.select(_db.copie).join([
      innerJoin(_db.edizioni, _db.edizioni.id.equalsExp(_db.copie.edizioneId)),
      innerJoin(_db.opere, _db.opere.id.equalsExp(_db.edizioni.operaId)),
      leftOuterJoin(
        _db.serieTable,
        _db.serieTable.id.equalsExp(_db.edizioni.serieId),
      ),
    ])..where(_db.copie.id.equals(copiaId));
    final row = await query.getSingle();
    return (
      title: row.readTable(_db.opere).title,
      seriesName: row.readTableOrNull(_db.serieTable)?.name,
      issueNumberLabel: row.readTable(_db.edizioni).issueNumberLabel,
      publisher: row.readTable(_db.edizioni).publisher,
      condition: row.readTable(_db.copie).condition,
    );
  }

  @override
  Future<String> avviaOrRiavviaValoreStimato({
    required String copiaId,
    DateTime? createdAt,
  }) async {
    final esistente = await (_db.select(
      _db.valoreStimatoTable,
    )..where((v) => v.copiaId.equals(copiaId))).getSingleOrNull();
    if (esistente == null) {
      return _db
          .into(_db.valoreStimatoTable)
          .insertReturning(
            ValoreStimatoTableCompanion.insert(
              copiaId: copiaId,
              status: StatoValoreStimato.inCorso,
              createdAt: createdAt ?? DateTime.now(),
            ),
          )
          .then((riga) => riga.id);
    }
    await (_db.update(
      _db.valoreStimatoTable,
    )..where((v) => v.id.equals(esistente.id))).write(
      const ValoreStimatoTableCompanion(
        status: Value(StatoValoreStimato.inCorso),
        errorMessage: Value(null),
      ),
    );
    return esistente.id;
  }

  @override
  Future<void> completaValoreStimato({
    required String id,
    required double value,
    DateTime? completedAt,
  }) {
    return (_db.update(
      _db.valoreStimatoTable,
    )..where((v) => v.id.equals(id))).write(
      ValoreStimatoTableCompanion(
        status: const Value(StatoValoreStimato.completata),
        value: Value(value),
        completedAt: Value(completedAt ?? DateTime.now()),
      ),
    );
  }

  @override
  Future<void> segnaValoreStimatoNonDisponibile({
    required String id,
    DateTime? completedAt,
  }) {
    return (_db.update(
      _db.valoreStimatoTable,
    )..where((v) => v.id.equals(id))).write(
      ValoreStimatoTableCompanion(
        status: const Value(StatoValoreStimato.nonDisponibile),
        value: const Value(null),
        errorMessage: const Value(null),
        completedAt: Value(completedAt ?? DateTime.now()),
      ),
    );
  }

  @override
  Future<void> fallisciValoreStimato({
    required String id,
    required String errorMessage,
  }) {
    return (_db.update(
      _db.valoreStimatoTable,
    )..where((v) => v.id.equals(id))).write(
      ValoreStimatoTableCompanion(
        status: const Value(StatoValoreStimato.fallita),
        errorMessage: Value(errorMessage),
      ),
    );
  }

  // --- KPI della Dashboard (§4.1, regole fissate su #2). ---

  @override
  Stream<DashboardKpis> watchDashboardKpis() async* {
    final ora = DateTime.now();
    final inizioMese = DateTime(ora.year, ora.month);
    final inizioMeseProssimo = DateTime(ora.year, ora.month + 1);
    // Le Copie con `purchasePriceCurrency = 'usd'` (prezzo letto in dollari
    // da una Scansione di un fumetto americano) entrano nel totale "Speso
    // finora" convertite in EUR con il tasso corrente — §4.1 mostra un solo
    // totale in EUR, non una cifra mista per valuta. Il tasso è interrogato
    // solo se esiste almeno una Copia in dollari: altrimenti il `CASE` SQL
    // sotto non lo usa mai, e la stragrande maggioranza delle collezioni
    // (tutta in EUR) non paga mai questa chiamata di rete.
    final haCopieInDollari =
        await (_db.selectOnly(_db.copie)
              ..addColumns([_db.copie.id])
              ..where(
                _db.copie.purchasePriceCurrency.equalsValue(ValutaPrezzo.usd),
              )
              ..limit(1))
            .getSingleOrNull() !=
        null;
    final tassoUsdEur = haCopieInDollari ? await _tassoUsdEur() : 1.0;

    yield* _db
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
  COALESCE((SELECT SUM(
     CASE WHEN purchase_price_currency = 'usd' THEN purchase_price * ?3 ELSE purchase_price END
   ) FROM copie WHERE status IN ('posseduta', 'prestata')), 0.0) AS speso_finora,
  (SELECT COUNT(*) FROM copie
     WHERE status IN ('posseduta', 'prestata') AND created_at >= ?1 AND created_at < ?2) AS aggiunti_mese,
  COALESCE((SELECT SUM(vs.value) FROM copie c
     JOIN valore_stimato vs ON vs.copia_id = c.id
     WHERE c.status IN ('posseduta', 'prestata') AND vs.status = 'completata'), 0.0) AS valore_stimato_totale,
  (SELECT COUNT(*) FROM copie c
     JOIN valore_stimato vs ON vs.copia_id = c.id
     WHERE c.status IN ('posseduta', 'prestata') AND vs.status = 'completata') AS copie_con_valore
''',
          variables: [
            Variable.withDateTime(inizioMese),
            Variable.withDateTime(inizioMeseProssimo),
            Variable.withReal(tassoUsdEur),
          ],
          readsFrom: {
            _db.serieTable,
            _db.edizioni,
            _db.copie,
            _db.valoreStimatoTable,
          },
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
            valoreStimatoTotale: r.read<double>('valore_stimato_totale'),
            copieConValoreStimato: r.read<int>('copie_con_valore'),
          );
        });
  }

  @override
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
          final perSerie = <String, List<QueryRow>>{};
          for (final row in rows) {
            perSerie
                .putIfAbsent(row.read<String>('serie_id'), () => [])
                .add(row);
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

  // --- Schermo Serie (§11, deciso su #97/#98/#99). ---

  @override
  Stream<SerieLista> watchSerieLista() {
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
  ),
  serie_posseduta AS (
    SELECT DISTINCT e.serie_id AS serie_id
    FROM edizioni e
    JOIN copie c ON c.edizione_id = e.id AND c.status IN ('posseduta', 'prestata')
    WHERE e.serie_id IS NOT NULL
  ),
  mancanti_count AS (
    SELECT ns.serie_id AS serie_id, COUNT(*) AS n
    FROM numeri_serie ns
    WHERE NOT EXISTS (
      SELECT 1 FROM numeri_posseduti np WHERE np.serie_id = ns.serie_id AND np.n = ns.n
    )
    GROUP BY ns.serie_id
  ),
  posseduti_count AS (
    SELECT serie_id, COUNT(*) AS n FROM numeri_posseduti GROUP BY serie_id
  )
SELECT
  s.id AS serie_id,
  s.name AS nome,
  s.total_issues AS numeri_totali,
  s.cover_image AS cover_override,
  COALESCE(pc.n, 0) AS numeri_posseduti,
  COALESCE(mc.n, 0) AS numeri_mancanti,
  (SELECT e3.cover_image FROM edizioni e3
     WHERE e3.serie_id = s.id
     AND EXISTS (
       SELECT 1 FROM copie c3
       WHERE c3.edizione_id = e3.id AND c3.status IN ('posseduta', 'prestata')
     )
     ORDER BY (e3.issue_number IS NULL), e3.issue_number ASC,
       e3.created_at ASC, e3.id ASC LIMIT 1) AS cover_default
FROM serie s
JOIN serie_posseduta sp ON sp.serie_id = s.id
LEFT JOIN posseduti_count pc ON pc.serie_id = s.id
LEFT JOIN mancanti_count mc ON mc.serie_id = s.id
''',
          readsFrom: {_db.serieTable, _db.edizioni, _db.copie},
        )
        .watch()
        .asyncMap((rows) async {
          final incomplete = <SerieRiga>[];
          final complete = <SerieRiga>[];
          final senzaTotale = <SerieRiga>[];

          for (final row in rows) {
            final coverOverride = row.readNullable<String>('cover_override');
            final coverDefault = row.readNullable<String>('cover_default');
            final riga = SerieRiga(
              serieId: row.read<String>('serie_id'),
              nome: row.read<String>('nome'),
              numeriPosseduti: row.read<int>('numeri_posseduti'),
              numeriTotali: row.readNullable<int>('numeri_totali'),
              coverImage: await risolviCoverImage(
                coverOverride ?? coverDefault,
              ),
            );
            if (riga.numeriTotali == null) {
              senzaTotale.add(riga);
            } else if (row.read<int>('numeri_mancanti') == 0) {
              complete.add(riga);
            } else {
              incomplete.add(riga);
            }
          }

          incomplete.sort(
            (a, b) => a.percentualeCompletamento!.compareTo(
              b.percentualeCompletamento!,
            ),
          );
          complete.sort((a, b) => a.nome.compareTo(b.nome));
          senzaTotale.sort((a, b) => a.nome.compareTo(b.nome));

          return SerieLista(
            incomplete: incomplete,
            complete: complete,
            senzaTotale: senzaTotale,
          );
        });
  }

  @override
  Stream<SerieDettaglio?> watchSerieDettaglio(String serieId) {
    return _db
        .customSelect(
          '''
WITH posseduti AS (
  SELECT DISTINCT e.issue_number AS n
  FROM edizioni e
  JOIN copie c ON c.edizione_id = e.id AND c.status IN ('posseduta', 'prestata')
  WHERE e.serie_id = ?1 AND e.issue_number IS NOT NULL
)
SELECT
  s.id AS serie_id,
  s.name AS nome,
  s.total_issues AS numeri_totali,
  s.issn AS issn,
  s.cover_image AS cover_override,
  p.n AS numero_posseduto,
  (SELECT publisher FROM edizioni WHERE serie_id = ?1 AND publisher IS NOT NULL
     GROUP BY publisher ORDER BY COUNT(*) DESC, publisher LIMIT 1) AS publisher,
  (SELECT MIN(year) FROM edizioni WHERE serie_id = ?1 AND year IS NOT NULL) AS anno_inizio,
  (SELECT COUNT(*) FROM (
     SELECT e2.id FROM edizioni e2
     JOIN copie c2 ON c2.edizione_id = e2.id AND c2.status IN ('posseduta', 'prestata')
     WHERE e2.serie_id = ?1
     GROUP BY e2.id HAVING COUNT(*) >= 2
   )) AS duplicati,
  (SELECT e3.cover_image FROM edizioni e3
     WHERE e3.serie_id = ?1
     AND EXISTS (
       SELECT 1 FROM copie c3
       WHERE c3.edizione_id = e3.id AND c3.status IN ('posseduta', 'prestata')
     )
     ORDER BY (e3.issue_number IS NULL), e3.issue_number ASC,
       e3.created_at ASC, e3.id ASC LIMIT 1) AS cover_default
FROM serie s
LEFT JOIN posseduti p ON 1 = 1
WHERE s.id = ?1
ORDER BY p.n
''',
          variables: [Variable.withString(serieId)],
          readsFrom: {_db.serieTable, _db.edizioni, _db.copie},
        )
        .watch()
        .asyncMap((rows) async {
          if (rows.isEmpty) return null;
          final first = rows.first;
          final coverOverride = first.readNullable<String>('cover_override');
          final coverDefault = first.readNullable<String>('cover_default');
          return SerieDettaglio(
            serieId: first.read<String>('serie_id'),
            nome: first.read<String>('nome'),
            issn: first.readNullable<String>('issn'),
            numeriTotali: first.readNullable<int>('numeri_totali'),
            numeriPosseduti: [
              for (final row in rows)
                if (row.readNullable<int>('numero_posseduto') != null)
                  row.read<int>('numero_posseduto'),
            ],
            duplicati: first.read<int>('duplicati'),
            publisher: first.readNullable<String>('publisher'),
            annoInizio: first.readNullable<int>('anno_inizio'),
            coverImage: await risolviCoverImage(coverOverride ?? coverDefault),
            coverImageOverride: coverOverride,
          );
        });
  }

  @override
  Future<void> aggiornaSerie({
    required String id,
    required String name,
    int? totalIssues,
    String? issn,
    String? coverImage,
  }) {
    return (_db.update(_db.serieTable)..where((s) => s.id.equals(id))).write(
      SerieTableCompanion(
        name: Value(name.trim()),
        totalIssues: Value(totalIssues),
        issn: Value(issn),
        coverImage: Value(coverImage),
      ),
    );
  }

  @override
  Future<List<EdizioneCatalogo>> edizioniPosseduteDiSerie(
    String serieId,
  ) async {
    final query =
        _db.select(_db.edizioni).join([
            innerJoin(_db.opere, _db.opere.id.equalsExp(_db.edizioni.operaId)),
            innerJoin(
              _db.copie,
              _db.copie.edizioneId.equalsExp(_db.edizioni.id),
            ),
          ])
          ..where(
            _db.edizioni.serieId.equals(serieId) &
                _db.copie.status.isInValues(const [
                  StatoCopia.posseduta,
                  StatoCopia.prestata,
                ]),
          )
          ..groupBy([_db.edizioni.id])
          ..orderBy([
            OrderingTerm.asc(_db.edizioni.issueNumber),
            OrderingTerm.asc(_db.edizioni.createdAt),
          ]);

    final rows = await query.get();
    final risultati = <EdizioneCatalogo>[];
    for (final row in rows) {
      final edizione = row.readTable(_db.edizioni);
      risultati.add(
        EdizioneCatalogo(
          edizioneId: edizione.id,
          title: row.readTable(_db.opere).title,
          serieId: edizione.serieId,
          seriesName: null,
          publisher: edizione.publisher,
          issueNumber: edizione.issueNumber,
          issueNumberLabel: edizione.issueNumberLabel,
          coverImage: await risolviCoverImage(edizione.coverImage),
        ),
      );
    }
    return risultati;
  }

  @override
  Future<String?> coverDefaultDiSerie(String serieId) async {
    final query =
        _db.select(_db.edizioni).join([
            innerJoin(
              _db.copie,
              _db.copie.edizioneId.equalsExp(_db.edizioni.id),
            ),
          ])
          ..where(
            _db.edizioni.serieId.equals(serieId) &
                _db.copie.status.isInValues(const [
                  StatoCopia.posseduta,
                  StatoCopia.prestata,
                ]),
          )
          ..orderBy([
            OrderingTerm.asc(_db.edizioni.issueNumber.isNull()),
            OrderingTerm.asc(_db.edizioni.issueNumber),
            OrderingTerm.asc(_db.edizioni.createdAt),
            OrderingTerm.asc(_db.edizioni.id),
          ])
          ..limit(1);

    final row = await query.getSingleOrNull();
    if (row == null) return null;
    return risolviCoverImage(row.readTable(_db.edizioni).coverImage);
  }

  /// Quante copie mostrare nel carosello "Aggiunti di recente" — oltre lo
  /// scroll orizzontale di una Dashboard non aggiunge informazione utile.
  static const _limiteAggiuntiDiRecente = 12;

  @override
  Stream<List<ComicRecente>> watchAggiuntiDiRecente() {
    final query =
        _db.select(_db.copie).join([
            innerJoin(
              _db.edizioni,
              _db.edizioni.id.equalsExp(_db.copie.edizioneId),
            ),
            innerJoin(_db.opere, _db.opere.id.equalsExp(_db.edizioni.operaId)),
            leftOuterJoin(
              _db.serieTable,
              _db.serieTable.id.equalsExp(_db.edizioni.serieId),
            ),
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
            serieName: row.readTableOrNull(_db.serieTable)?.name,
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

  @override
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

  @override
  Stream<EdizioneDettaglio?> watchEdizione(String edizioneId) {
    final query = _db.select(_db.edizioni).join([
      innerJoin(_db.opere, _db.opere.id.equalsExp(_db.edizioni.operaId)),
      leftOuterJoin(
        _db.serieTable,
        _db.serieTable.id.equalsExp(_db.edizioni.serieId),
      ),
      leftOuterJoin(_db.copie, _db.copie.edizioneId.equalsExp(_db.edizioni.id)),
      leftOuterJoin(
        _db.valoreStimatoTable,
        _db.valoreStimatoTable.copiaId.equalsExp(_db.copie.id),
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

      final copieById = <String, CopiaDettaglio>{};
      final autoriById = <String, CreatorConRuolo>{};
      for (final row in rows) {
        final copia = row.readTableOrNull(_db.copie);
        if (copia != null) {
          final valoreStimato = row.readTableOrNull(_db.valoreStimatoTable);
          copieById[copia.id] = CopiaDettaglio(
            id: copia.id,
            status: copia.status,
            readingStatus: copia.readingStatus,
            condition: copia.condition,
            purchasePrice: copia.purchasePrice,
            purchasePriceCurrency: copia.purchasePriceCurrency,
            purchaseDate: copia.purchaseDate,
            seller: copia.seller,
            location: copia.location,
            notes: copia.notes,
            valutazione: copia.valutazione,
            statoValoreStimato: valoreStimato?.status,
            valoreStimato: valoreStimato?.value,
            valoreStimatoErrorMessage: valoreStimato?.errorMessage,
            valoreStimatoAggiornatoAl: valoreStimato?.completedAt,
            forSale: copia.forSale,
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
        year: edizione.year,
        coverPrice: edizione.coverPrice,
        pageCount: edizione.pageCount,
        language: edizione.language,
        color: edizione.color,
        ean: edizione.ean,
        volume: edizione.volume,
        description: edizione.description,
        printingType: edizione.printingType,
        classificazione: edizione.classificazione,
        autori: autori,
        copie: copie,
      );
    });
  }

  @override
  Future<String?> coverImageGrezzoDi(String edizioneId) async {
    final riga = await (_db.select(
      _db.edizioni,
    )..where((e) => e.id.equals(edizioneId))).getSingle();
    return riga.coverImage;
  }

  @override
  Future<int> ripristinaCoverMancantiDaScansione() async {
    final query = _db.select(_db.edizioni).join([
      innerJoin(_db.copie, _db.copie.edizioneId.equalsExp(_db.edizioni.id)),
      innerJoin(
        _db.scansioni,
        _db.scansioni.id.equalsExp(_db.copie.scansioneId),
      ),
    ])..where(_db.edizioni.coverImage.isNull());

    final righe = await query.get();
    final base = await _copertinaDownloader.baseDirectory();

    final daRipristinare = <String, String>{};
    for (final riga in righe) {
      final edizioneId = riga.readTable(_db.edizioni).id;
      if (daRipristinare.containsKey(edizioneId)) continue;
      final immagine = riga.readTable(_db.scansioni).image;
      daRipristinare[edizioneId] = await _coverDaScansione(immagine, base);
    }

    for (final entry in daRipristinare.entries) {
      await (_db.update(_db.edizioni)..where((e) => e.id.equals(entry.key)))
          .write(EdizioniCompanion(coverImage: Value(entry.value)));
    }

    return daRipristinare.length;
  }

  @override
  Future<String> salvaCoverLocale(File file) async {
    final locale = await _copertinaDownloader.salvaLocale(file);
    final base = await _copertinaDownloader.baseDirectory();
    return percorso_locale.relativizza(locale, base);
  }

  @override
  Future<void> aggiornaTitoloOpera({
    required String operaId,
    required String title,
  }) {
    return (_db.update(_db.opere)..where((o) => o.id.equals(operaId))).write(
      OpereCompanion(title: Value(title)),
    );
  }

  @override
  Future<void> aggiornaEdizione({
    required String id,
    String? serieId,
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
    int? year,
    FormatoEdizione? format,
  }) {
    return _db.transaction(() async {
      final prima = await (_db.select(
        _db.edizioni,
      )..where((e) => e.id.equals(id))).getSingleOrNull();
      await (_db.update(_db.edizioni)..where((e) => e.id.equals(id))).write(
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
          year: Value(year),
          format: Value(format),
        ),
      );
      if (prima?.serieId != serieId) {
        await _eliminaSerieSeVuota(prima?.serieId);
      }
    });
  }

  @override
  Future<void> aggiornaCopia({
    required String id,
    CondizioneCopia? condition,
    double? purchasePrice,
    ValutaPrezzo? purchasePriceCurrency,
    DateTime? purchaseDate,
    String? seller,
    String? location,
    String? notes,
    double? valutazione,
  }) {
    return (_db.update(_db.copie)..where((c) => c.id.equals(id))).write(
      CopieCompanion(
        condition: Value(condition),
        purchasePrice: Value(purchasePrice),
        purchasePriceCurrency: Value(purchasePriceCurrency),
        purchaseDate: Value(purchaseDate),
        seller: Value(seller),
        location: Value(location),
        notes: Value(notes),
        valutazione: Value(valutazione),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> cambiaStatoCopia({
    required String id,
    required StatoCopia status,
    StatoLettura? readingStatus,
  }) {
    return (_db.update(_db.copie)..where((c) => c.id.equals(id))).write(
      CopieCompanion(
        status: Value(status),
        readingStatus: Value(readingStatus),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> impostaInVendita({required String id, required bool inVendita}) {
    return (_db.update(_db.copie)..where((c) => c.id.equals(id))).write(
      CopieCompanion(
        forSale: Value(inVendita),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<int> segnaEdizioniInVendita(List<String> edizioneIds) {
    if (edizioneIds.isEmpty) return Future.value(0);
    return (_db.update(_db.copie)..where(
          (c) =>
              c.edizioneId.isIn(edizioneIds) &
              c.status.isInValues(const [
                StatoCopia.posseduta,
                StatoCopia.prestata,
              ]),
        ))
        .write(
          CopieCompanion(
            forSale: const Value(true),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  @override
  Future<bool> rimuoviCopia(String id) {
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

  @override
  Future<void> eliminaEdizione(String edizioneId) {
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
  Future<void> _eliminaEdizioneSenzaCopie(String edizioneId) async {
    final edizione = await (_db.select(
      _db.edizioni,
    )..where((e) => e.id.equals(edizioneId))).getSingleOrNull();
    await (_db.delete(
      _db.comicCreator,
    )..where((c) => c.edizioneId.equals(edizioneId))).go();
    await (_db.delete(
      _db.edizioni,
    )..where((e) => e.id.equals(edizioneId))).go();
    await _eliminaSerieSeVuota(edizione?.serieId);
  }

  // --- Collezione (§9, deciso su #79/#90, split indice/hydration #113). ---

  /// La query di base della Collezione — Edizioni+Opera+Serie+Copie
  /// possedute (per il badge duplicato e gli assi per-Copia), filtrata alle
  /// sole Edizioni con almeno una Copia `posseduta`/`prestata` (stessa
  /// regola "Edizione posseduta" del resto del catalogo) e raggruppata per
  /// `edizioneId` — condivisa da [watchIndiceCollezione] (nessun filtro su
  /// [edizioneIds]) e [watchHydratazioneCollezione] (filtrata alla finestra
  /// caricata). Reattiva: qualunque cambiamento di Edizioni/Copie che
  /// tocchi le tabelle lette fa riemettere entrambe le stream.
  Stream<Map<String, List<TypedResult>>> _watchRigheEdizioniPossedute({
    Iterable<String>? edizioneIds,
  }) {
    final query = _db.select(_db.edizioni).join([
      innerJoin(_db.opere, _db.opere.id.equalsExp(_db.edizioni.operaId)),
      leftOuterJoin(
        _db.serieTable,
        _db.serieTable.id.equalsExp(_db.edizioni.serieId),
      ),
      leftOuterJoin(
        _db.copie,
        _db.copie.edizioneId.equalsExp(_db.edizioni.id) &
            _db.copie.status.isInValues(const [
              StatoCopia.posseduta,
              StatoCopia.prestata,
            ]),
      ),
    ]);
    if (edizioneIds != null) {
      query.where(_db.edizioni.id.isIn(edizioneIds));
    }

    return query.watch().map((rows) {
      final righePerEdizione = <String, List<TypedResult>>{};
      for (final row in rows) {
        righePerEdizione
            .putIfAbsent(row.readTable(_db.edizioni).id, () => [])
            .add(row);
      }
      // Il leftOuterJoin include anche le Edizioni senza copie possedute
      // (riga con Copie null): solo l'"Edizione posseduta" entra in
      // Collezione.
      righePerEdizione.removeWhere(
        (_, righe) => righe.every((r) => r.readTableOrNull(_db.copie) == null),
      );
      return righePerEdizione;
    });
  }

  @override
  Stream<List<EdizioneCollezioneIndice>> watchIndiceCollezione() {
    return _watchRigheEdizioniPossedute().asyncMap((righePerEdizione) async {
      if (righePerEdizione.isEmpty) {
        return const <EdizioneCollezioneIndice>[];
      }

      final ids = righePerEdizione.keys.toList();
      final autori = await _autoriPerEdizione(ids);
      final personaggi = await _personaggiPerEdizione(ids);
      final tag = await _tagPerEdizione(ids);
      final generi = await _generiPerEdizione(ids);

      return [
        for (final entry in righePerEdizione.entries)
          _edizioneCollezioneIndiceDaRighe(
            entry.value,
            autori: autori[entry.key] ?? const [],
            personaggi: personaggi[entry.key] ?? const [],
            tag: tag[entry.key] ?? const [],
            generi: generi[entry.key] ?? const [],
          ),
      ];
    });
  }

  @override
  Stream<Map<String, String?>> watchHydratazioneCollezione(
    List<String> edizioneIds,
  ) {
    if (edizioneIds.isEmpty) return Stream.value(const <String, String?>{});

    return _watchRigheEdizioniPossedute(edizioneIds: edizioneIds).asyncMap((
      righePerEdizione,
    ) async {
      final risultato = <String, String?>{};
      for (final entry in righePerEdizione.entries) {
        final edizione = entry.value.first.readTable(_db.edizioni);
        risultato[entry.key] = await risolviCoverImage(edizione.coverImage);
      }
      return risultato;
    });
  }

  /// Autori collegati (§8.1/§9), raggruppati per `edizioneId`, per
  /// l'insieme di Edizioni date — bulk equivalente di [autoriDiEdizione]
  /// per più Edizioni insieme, usato da [watchIndiceCollezione].
  Future<Map<String, List<String>>> _autoriPerEdizione(
    List<String> edizioneIds,
  ) async {
    final query = _db.select(_db.comicCreator).join([
      innerJoin(
        _db.creator,
        _db.creator.id.equalsExp(_db.comicCreator.creatorId),
      ),
    ])..where(_db.comicCreator.edizioneId.isIn(edizioneIds));

    final righe = await query.get();
    final risultato = <String, List<String>>{};
    for (final riga in righe) {
      final edizioneId = riga.readTable(_db.comicCreator).edizioneId;
      risultato
          .putIfAbsent(edizioneId, () => [])
          .add(riga.readTable(_db.creator).name);
    }
    return risultato;
  }

  /// Personaggi collegati (§9, #84), raggruppati per `edizioneId`, per
  /// l'insieme di Edizioni date — usato da [watchIndiceCollezione].
  Future<Map<String, List<String>>> _personaggiPerEdizione(
    List<String> edizioneIds,
  ) async {
    final query = _db.select(_db.comicCharacter).join([
      innerJoin(
        _db.character,
        _db.character.id.equalsExp(_db.comicCharacter.characterId),
      ),
    ])..where(_db.comicCharacter.edizioneId.isIn(edizioneIds));

    final righe = await query.get();
    final risultato = <String, List<String>>{};
    for (final riga in righe) {
      final edizioneId = riga.readTable(_db.comicCharacter).edizioneId;
      risultato
          .putIfAbsent(edizioneId, () => [])
          .add(riga.readTable(_db.character).name);
    }
    return risultato;
  }

  /// Tag collegati (§9, #82), raggruppati per `edizioneId`, per l'insieme
  /// di Edizioni date — usato da [watchIndiceCollezione].
  Future<Map<String, List<String>>> _tagPerEdizione(
    List<String> edizioneIds,
  ) async {
    final query = _db.select(_db.edizioneTag).join([
      innerJoin(_db.tagTable, _db.tagTable.id.equalsExp(_db.edizioneTag.tagId)),
    ])..where(_db.edizioneTag.edizioneId.isIn(edizioneIds));

    final righe = await query.get();
    final risultato = <String, List<String>>{};
    for (final riga in righe) {
      final edizioneId = riga.readTable(_db.edizioneTag).edizioneId;
      risultato
          .putIfAbsent(edizioneId, () => [])
          .add(riga.readTable(_db.tagTable).name);
    }
    return risultato;
  }

  Future<Map<String, List<GenereEdizione>>> _generiPerEdizione(
    List<String> edizioneIds,
  ) async {
    final righe = await (_db.select(
      _db.edizioneGenere,
    )..where((g) => g.edizioneId.isIn(edizioneIds))).get();
    final risultato = <String, List<GenereEdizione>>{};
    for (final riga in righe) {
      risultato.putIfAbsent(riga.edizioneId, () => []).add(riga.genere);
    }
    return risultato;
  }

  EdizioneCollezioneIndice _edizioneCollezioneIndiceDaRighe(
    List<TypedResult> righe, {
    required List<String> autori,
    required List<String> personaggi,
    required List<String> tag,
    required List<GenereEdizione> generi,
  }) {
    final edizione = righe.first.readTable(_db.edizioni);
    final opera = righe.first.readTable(_db.opere);
    final serie = righe.first.readTableOrNull(_db.serieTable);

    final copiePerId = <String, CopiaAsseCollezione>{};
    for (final riga in righe) {
      final copia = riga.readTableOrNull(_db.copie);
      if (copia == null) continue;
      copiePerId[copia.id] = CopiaAsseCollezione(
        readingStatus: copia.readingStatus,
        condition: copia.condition,
        location: copia.location,
        createdAt: copia.createdAt,
        forSale: copia.forSale,
      );
    }

    return EdizioneCollezioneIndice(
      edizioneId: edizione.id,
      titolo: opera.title,
      serieId: serie?.id,
      serieName: serie?.name,
      publisher: edizione.publisher,
      issueNumber: edizione.issueNumber,
      issueNumberLabel: edizione.issueNumberLabel,
      year: edizione.year,
      format: edizione.format,
      language: edizione.language,
      autori: autori,
      personaggi: personaggi,
      generi: generi,
      tag: tag,
      copiePossedute: copiePerId.values.toList(),
      ean: edizione.ean,
    );
  }

  // --- Tool-calling dell'Assistente (§10, schema deciso su ADR-0002). ---

  @override
  Future<List<SerieTableData>> cercaSerie(String query) {
    return (_db.select(
      _db.serieTable,
    )..where((s) => s.name.like('%$query%'))).get();
  }

  @override
  Future<RisultatoCercaEdizioni> cercaEdizioni({
    String? titolo,
    String? serie,
    String? autore,
    String? editore,
    String? personaggio,
    String? tag,
    int? numero,
    String? isbn,
    String? testoLibero,
  }) async {
    return filtraIndiceCollezione(
      await watchIndiceCollezione().first,
      titolo: titolo,
      serieIds: serie == null
          ? null
          : {for (final s in await cercaSerie(serie)) s.id},
      autore: autore,
      editore: editore,
      personaggio: personaggio,
      tag: tag,
      numero: numero,
      isbn: isbn,
      testoLibero: testoLibero,
    );
  }

  @override
  Future<Map<String, int>> conteggioPer(CampoConteggio campo) async {
    final indice = await watchIndiceCollezione().first;
    final conteggi = <String, int>{};
    for (final edizione in indice) {
      final valore = switch (campo) {
        CampoConteggio.editore => edizione.publisher,
        CampoConteggio.anno => edizione.year?.toString(),
      };
      if (valore == null) continue;
      conteggi[valore] = (conteggi[valore] ?? 0) + 1;
    }
    final ordinati = conteggi.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return {for (final entry in ordinati) entry.key: entry.value};
  }

  /// Soglia fissa del tool `serieQuasiComplete` (§10, ADR-0002): "quasi
  /// completa" da qui in su. Nessuna serie completa può comparire nel
  /// risultato perché [watchSerieIncomplete] esclude già quelle senza
  /// numeri mancanti (percentuale sempre < 100%).
  static const _sogliaSerieQuasiCompleta = 0.8;

  @override
  Future<List<SerieIncompleta>> serieQuasiComplete() async {
    final incomplete = await watchSerieIncomplete().first;
    return incomplete
        .where((s) => s.percentualeCompletamento >= _sogliaSerieQuasiCompleta)
        .toList();
  }

  @override
  Future<List<EdizioneDuplicata>> trovaDuplicati() {
    return _db
        .customSelect('''
WITH edizioni_possedute AS (
  SELECT e.id AS edizione_id, e.serie_id AS serie_id, COUNT(*) AS copie_possedute
  FROM edizioni e
  JOIN copie c ON c.edizione_id = e.id AND c.status IN ('posseduta', 'prestata')
  GROUP BY e.id
)
SELECT
  e.id AS edizione_id,
  o.title AS titolo,
  s.name AS serie,
  e.issue_number_label AS numero_label,
  e.publisher AS editore,
  ep.copie_possedute AS copie_possedute
FROM edizioni_possedute ep
JOIN edizioni e ON e.id = ep.edizione_id
JOIN opere o ON o.id = e.opera_id
LEFT JOIN serie s ON s.id = ep.serie_id
WHERE ep.copie_possedute >= 2
ORDER BY o.title, e.issue_number
''')
        .get()
        .then(
          (rows) => [
            for (final row in rows)
              (
                edizioneId: row.read<String>('edizione_id'),
                titolo: row.read<String>('titolo'),
                serieName: row.readNullable<String>('serie'),
                issueNumberLabel: row.readNullable<String>('numero_label'),
                publisher: row.readNullable<String>('editore'),
                copiePossedute: row.read<int>('copie_possedute'),
              ),
          ],
        );
  }

  // --- Conversazione dell'Assistente (§10/§24, deciso su #122/#124/#128). ---

  @override
  Future<int> getOrCreaConversazione() => _conversazione.getOrCrea();

  @override
  Future<int> aggiungiMessaggio({
    required int conversazioneId,
    required RuoloMessaggio ruolo,
    required String testo,
    SottotipoSistema? sottotipoSistema,
    List<String> edizioneIds = const [],
    DateTime? createdAt,
  }) => _conversazione.aggiungiMessaggio(
    conversazioneId: conversazioneId,
    ruolo: ruolo,
    testo: testo,
    sottotipoSistema: sottotipoSistema,
    edizioneIds: edizioneIds,
    createdAt: createdAt,
  );

  @override
  Stream<List<Messaggio>> watchMessaggi(int conversazioneId) {
    return _conversazione.watchMessaggi(conversazioneId).asyncMap((
      righe,
    ) async {
      if (righe.isEmpty) return const <Messaggio>[];

      final tuttiGliId = {for (final riga in righe) ...riga.edizioneIds};
      final edizioniPerId = tuttiGliId.isEmpty
          ? const <String, EdizioneCollezioneIndice>{}
          : {
              for (final edizione in await watchIndiceCollezione().first)
                if (tuttiGliId.contains(edizione.edizioneId))
                  edizione.edizioneId: edizione,
            };

      return [
        for (final riga in righe)
          Messaggio(
            id: riga.id,
            ruolo: riga.ruolo,
            sottotipoSistema: riga.sottotipoSistema,
            testo: riga.testo,
            createdAt: riga.createdAt,
            edizioni: [
              for (final id in riga.edizioneIds) ?edizioniPerId[id],
            ],
          ),
      ];
    });
  }

  @override
  Future<void> eliminaConversazione(int conversazioneId) =>
      _conversazione.elimina(conversazioneId);

  // --- Export/import (§16, deciso su #139/#140). ---

  @override
  Future<List<RigaEsportazioneCopia>> tutteLeCopiePerEsportazione() async {
    final query = _db.select(_db.copie).join([
      innerJoin(_db.edizioni, _db.edizioni.id.equalsExp(_db.copie.edizioneId)),
      innerJoin(_db.opere, _db.opere.id.equalsExp(_db.edizioni.operaId)),
      leftOuterJoin(
        _db.serieTable,
        _db.serieTable.id.equalsExp(_db.edizioni.serieId),
      ),
    ])..orderBy([OrderingTerm.asc(_db.copie.id)]);

    final righe = await query.get();
    if (righe.isEmpty) return const <RigaEsportazioneCopia>[];

    final edizioneIds = {
      for (final riga in righe) riga.readTable(_db.edizioni).id,
    }.toList();
    final autoriPerEdizione = await _autoriConRuoloPerEdizione(edizioneIds);

    return [
      for (final riga in righe)
        await _rigaEsportazioneDaJoin(
          riga,
          autori:
              autoriPerEdizione[riga.readTable(_db.edizioni).id] ?? const [],
        ),
    ];
  }

  /// Bulk equivalente di [autoriDiEdizione] per più Edizioni insieme (con
  /// ruolo, a differenza di [_autoriPerEdizione] che risolve solo i nomi),
  /// usato da [tutteLeCopiePerEsportazione].
  Future<Map<String, List<CreatorConRuolo>>> _autoriConRuoloPerEdizione(
    List<String> edizioneIds,
  ) async {
    if (edizioneIds.isEmpty) return const {};

    final query = _db.select(_db.comicCreator).join([
      innerJoin(
        _db.creator,
        _db.creator.id.equalsExp(_db.comicCreator.creatorId),
      ),
    ])..where(_db.comicCreator.edizioneId.isIn(edizioneIds));

    final righe = await query.get();
    final risultato = <String, List<CreatorConRuolo>>{};
    for (final riga in righe) {
      final comicCreator = riga.readTable(_db.comicCreator);
      risultato.putIfAbsent(comicCreator.edizioneId, () => []).add((
        comicCreatorId: comicCreator.id,
        creatorId: riga.readTable(_db.creator).id,
        name: riga.readTable(_db.creator).name,
        ruolo: comicCreator.ruolo,
      ));
    }
    return risultato;
  }

  Future<RigaEsportazioneCopia> _rigaEsportazioneDaJoin(
    TypedResult riga, {
    required List<CreatorConRuolo> autori,
  }) async {
    final copia = riga.readTable(_db.copie);
    final edizione = riga.readTable(_db.edizioni);
    final opera = riga.readTable(_db.opere);
    final serie = riga.readTableOrNull(_db.serieTable);
    return RigaEsportazioneCopia(
      copiaId: copia.id,
      edizioneId: edizione.id,
      operaTitolo: opera.title,
      serieName: serie?.name,
      publisher: edizione.publisher,
      issueNumber: edizione.issueNumber,
      issueNumberLabel: edizione.issueNumberLabel,
      releaseDate: edizione.releaseDate,
      year: edizione.year,
      coverPrice: edizione.coverPrice,
      pageCount: edizione.pageCount,
      language: edizione.language,
      color: edizione.color,
      ean: edizione.ean,
      volume: edizione.volume,
      description: edizione.description,
      printingType: edizione.printingType,
      classificazione: edizione.classificazione,
      format: edizione.format,
      autori: autori,
      status: copia.status,
      readingStatus: copia.readingStatus,
      condition: copia.condition,
      purchasePrice: copia.purchasePrice,
      purchaseDate: copia.purchaseDate,
      seller: copia.seller,
      location: copia.location,
      notes: copia.notes,
      createdAt: copia.createdAt,
      coverImage: await risolviCoverImage(edizione.coverImage),
    );
  }

  @override
  Future<List<RigaCatalogoStampabile>>
  tutteLeCopiePerCatalogoStampabile() async {
    final query = _db.select(_db.copie).join([
      innerJoin(_db.edizioni, _db.edizioni.id.equalsExp(_db.copie.edizioneId)),
      innerJoin(_db.opere, _db.opere.id.equalsExp(_db.edizioni.operaId)),
      leftOuterJoin(
        _db.serieTable,
        _db.serieTable.id.equalsExp(_db.edizioni.serieId),
      ),
    ])..orderBy([OrderingTerm.asc(_db.copie.id)]);

    final righe = await query.get();
    if (righe.isEmpty) return const <RigaCatalogoStampabile>[];

    final edizioneIds = {
      for (final riga in righe) riga.readTable(_db.edizioni).id,
    }.toList();
    final autoriPerEdizione = await _autoriConRuoloPerEdizione(edizioneIds);

    return [
      for (final riga in righe)
        await _rigaCatalogoStampabileDaJoin(
          riga,
          autori:
              autoriPerEdizione[riga.readTable(_db.edizioni).id] ?? const [],
        ),
    ];
  }

  Future<RigaCatalogoStampabile> _rigaCatalogoStampabileDaJoin(
    TypedResult riga, {
    required List<CreatorConRuolo> autori,
  }) async {
    final copia = riga.readTable(_db.copie);
    final edizione = riga.readTable(_db.edizioni);
    final opera = riga.readTable(_db.opere);
    final serie = riga.readTableOrNull(_db.serieTable);
    return RigaCatalogoStampabile(
      copiaId: copia.id,
      operaTitolo: opera.title,
      serieName: serie?.name,
      issueNumberLabel: edizione.issueNumberLabel,
      issueNumber: edizione.issueNumber,
      publisher: edizione.publisher,
      year: edizione.year,
      format: edizione.format,
      autori: autori,
      condition: copia.condition,
      purchasePrice: copia.purchasePrice,
      location: copia.location,
      notes: copia.notes,
      coverImage: await risolviCoverImage(edizione.coverImage),
    );
  }

  @override
  Future<void> importaRighe(
    List<RigaImportazioneParsata> righe, {
    Map<String, Uint8List> copertine = const {},
  }) async {
    final coverPerFile = <String, String>{};
    if (copertine.isNotEmpty) {
      final base = await _copertinaDownloader.baseDirectory();
      for (final riga in righe) {
        final nomeFile = riga.fileCopertina;
        if (nomeFile == null || coverPerFile.containsKey(nomeFile)) continue;
        final bytes = copertine[nomeFile];
        if (bytes == null || bytes.isEmpty) continue;
        final estensione = p.extension(nomeFile).replaceFirst('.', '');
        final locale = await _copertinaDownloader.salvaBytes(
          bytes,
          estensione: estensione.isEmpty ? 'jpg' : estensione.toLowerCase(),
        );
        coverPerFile[nomeFile] = percorso_locale.relativizza(locale, base);
      }
    }

    return _db.transaction(() async {
      for (final riga in righe) {
        final operaId = await aggiungiOpera(
          title: riga.operaTitolo,
          createdAt: riga.createdAt,
        );

        String? serieId;
        if (riga.serieName != null) {
          serieId = await aggiungiSerie(name: riga.serieName!);
        }

        final edizioneId = await aggiungiEdizione(
          operaId: operaId,
          serieId: serieId,
          publisher: riga.publisher,
          issueNumber: riga.issueNumber,
          issueNumberLabel: riga.issueNumberLabel,
          releaseDate: riga.releaseDate,
          coverPrice: riga.coverPrice,
          pageCount: riga.pageCount,
          language: riga.language,
          color: riga.color,
          ean: riga.ean,
          volume: riga.volume,
          description: riga.description,
          printingType: riga.printingType,
          classificazione: riga.classificazione,
          year: riga.year,
          format: riga.format,
          coverImage: coverPerFile[riga.fileCopertina],
          createdAt: riga.createdAt,
        );

        for (final autore in riga.autori) {
          final creatorId = await aggiungiCreator(autore.name);
          await collegaCreatorAEdizione(
            edizioneId: edizioneId,
            creatorId: creatorId,
            ruolo: autore.ruolo,
          );
        }

        await aggiungiCopia(
          edizioneId: edizioneId,
          status: riga.status,
          readingStatus: riga.readingStatus,
          condition: riga.condition,
          purchasePrice: riga.purchasePrice,
          purchaseDate: riga.purchaseDate,
          seller: riga.seller,
          location: riga.location,
          notes: riga.notes,
          createdAt: riga.createdAt,
        );
      }
    });
  }
}
