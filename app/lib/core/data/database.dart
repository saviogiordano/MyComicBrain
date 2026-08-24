import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:mycomicbrain/core/data/database.steps.dart';
import 'package:mycomicbrain/core/domain/analisi_copertina.dart';
import 'package:mycomicbrain/core/domain/copia.dart';
import 'package:mycomicbrain/core/domain/creator.dart';
import 'package:mycomicbrain/core/domain/identificazione.dart';
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

/// Converter condiviso per le colonne di tag liberi di `AnalisiCopertinaTable`
/// (`characters`, `coverStyleTags`, `visualElementTags`, deciso su #48):
/// liste di stringhe, serializzate come JSON nella colonna testuale.
class StringListConverter extends TypeConverter<List<String>, String> {
  const StringListConverter();

  @override
  List<String> fromSql(String fromDb) => (jsonDecode(fromDb) as List<dynamic>).cast<String>();

  @override
  String toSql(List<String> value) => jsonEncode(value);
}

/// `Opera`: la storia/testata a prescindere da come è stata pubblicata.
/// Separata da `Edizione` fin dalla v1 (§36), anche se oggi popolata quasi
/// 1:1 — evita una migrazione quando servirà collegare più edizioni alla
/// stessa opera.
class Opere extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text()();
  DateTimeColumn get createdAt => dateTime()();
}

/// `Serie`: raggruppamento facoltativo di edizioni con numerazione
/// progressiva. `totalIssues` è il campo "numeri totali" del glossario —
/// senza di esso la serie non è valutabile per completezza/numeri mancanti.
class SerieTable extends Table {
  @override
  String get tableName => 'serie';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  IntColumn get totalIssues => integer().nullable()();

  /// ISSN della collana (es. edicola italiana, deciso su #63) — identifica
  /// la testata periodica nel suo complesso, non la singola Edizione: sta
  /// su `Serie`/collana, non su `Edizioni`.
  TextColumn get issn => text().nullable()();
}

/// `Edizione`: la pubblicazione specifica di un'opera — l'unità catalogata.
class Edizioni extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get operaId => integer().references(Opere, #id)();
  IntColumn get serieId => integer().nullable().references(SerieTable, #id)();
  TextColumn get publisher => text().nullable()();

  /// Numero come intero, per il CTE dei numeri mancanti (§17).
  IntColumn get issueNumber => integer().nullable()();

  /// Numero come testo mostrato in UI ("4 Variant", "Annual 1") — una
  /// variant/speciale non genera un proprio buco: copre il numero intero
  /// corrispondente se posseduta.
  TextColumn get issueNumberLabel => text().nullable()();
  TextColumn get coverImage => text().nullable()();

  /// Data di pubblicazione così com'è riportata sulla copertina/testata
  /// (es. "dicembre 2010", deciso su #63) — testo grezzo e non parsato: i
  /// fumetti a periodicità mensile/bimestrale spesso riportano solo
  /// mese/anno, un `DateTimeColumn` costringerebbe a inventare un giorno.
  TextColumn get releaseDate => text().nullable()();

  /// Prezzo di copertina originale (es. "€ 5,30", deciso su #63) — testo
  /// grezzo, non un importo numerico: distinto da `Copia.purchasePrice`
  /// (quanto pagato da chi possiede l'esemplare, spesso diverso dal
  /// prezzo di copertina per usato/sconti).
  TextColumn get coverPrice => text().nullable()();
  IntColumn get pageCount => integer().nullable()();
  TextColumn get language => text().nullable()();

  /// "a colori" / "bianco e nero" — testo libero (deciso su #63): non
  /// un enum, lo spettro reale (seppia, colore parziale, ...) non è
  /// abbastanza vincolato da giustificarne uno.
  TextColumn get color => text().nullable()();

  /// EAN/ISBN riportato sulla copertina (deciso su #63) — un solo campo:
  /// sulle edizioni italiane da edicola è quasi sempre un EAN periodico
  /// (prefisso 977), non un ISBN da libreria; tenerli distinti come in
  /// `AnalisiCopertinaTable` avrebbe richiesto due campi quasi sempre
  /// ridondanti per un dato mai usato per il matching.
  TextColumn get ean => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  /// Volume/raccolta (es. "Vol. 3", "Omnibus 1", §8.1, deciso su #64) — testo
  /// libero come `issueNumberLabel`, non un intero: distinto da
  /// issueNumber/issueNumberLabel (il numero del singolo albo) e da serieId
  /// (la collana/serie periodica).
  TextColumn get volume => text().nullable()();

  /// Descrizione libera dell'edizione (§8.1).
  TextColumn get description => text().nullable()();

  /// Tipo di stampa (§6.4/§8.1, deciso su #71) — vedi il commento gemello su
  /// `AnalisiCopertinaTable.printingType` per il perché del nome.
  TextColumn get printingType => text().nullable()();

  /// Classificazione/rating (§8.1, deciso su #71) — vedi il commento
  /// gemello su `AnalisiCopertinaTable.classificazione`.
  TextColumn get classificazione => text().nullable()();
}

/// `Copia`: un esemplare fisico posseduto di un'edizione. `status` guida
/// tutti i KPI di volume della Dashboard (#2); `readingStatus` non li tocca.
class Copie extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get edizioneId => integer().references(Edizioni, #id)();
  TextColumn get status => textEnum<StatoCopia>()();
  TextColumn get readingStatus => textEnum<StatoLettura>().nullable()();
  TextColumn get condition => textEnum<CondizioneCopia>().nullable()();
  RealColumn get purchasePrice => real().nullable()();
  DateTimeColumn get purchaseDate => dateTime().nullable()();
  TextColumn get seller => text().nullable()();

  /// Campo libero, niente albero: nessuna schermata di questa mappa
  /// richiede una gerarchia di posizioni.
  TextColumn get location => text().nullable()();
  TextColumn get notes => text().nullable()();

  /// Pilota "aggiunti di recente" e il KPI "aggiunti nel mese".
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// Scansione da cui questa Copia è nata — conferma di un Candidato o
  /// inserimento manuale (§6.3, deciso su #53). Nullable: le fixture dei test
  /// create direttamente con `ComicsRepository.aggiungiCopia` non passano da
  /// una Scansione.
  IntColumn get scansioneId => integer().nullable().references(Scansioni, #id)();
}

/// `Scansione`: una fotografia di cover acquisita e confermata, non ancora
/// processata dal riconoscimento AI (§6.3, fuori scope in questa mappa —
/// vedi `CONTEXT.md`). `userId` è un placeholder per l'autenticazione
/// futura. `ocrText`/`recognitionStatus`/`confidence` (placeholder
/// anticipati per errore di design, mai consumati) sono stati rimossi in
/// #32: l'Analisi Copertina vive ora nella propria tabella, vedi
/// `AnalisiCopertinaTable`.
class Scansioni extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get userId => integer().nullable()();

  /// Percorso filesystem dell'immagine salvata (vedi `ScansioneStorage`).
  TextColumn get image => text()();
  DateTimeColumn get createdAt => dateTime()();
}

/// `Analisi Copertina`: risultato dell'estrazione automatica via Claude
/// (OCR §6.1, forma decisa su #31; computer vision §6.2, campi aggiunti su
/// #48/#49 — la tabella si chiamava `AnalisiOcrTable`/`analisi_ocr` prima di
/// coprire anche la computer vision). Relazione 1:1 con `Scansioni` via
/// `scansioneId`, una riga creata quando la pipeline (#32) prende in carico
/// la Scansione. Campi grezzi e non parsati (il parsing verso
/// Opera/Edizione/Serie è §6.3, fuori scope): un campo non trovato/non
/// riconosciuto da Claude resta `null` (valori singoli) o lista vuota
/// (`characters`/`coverStyleTags`/`visualElementTags`). `rawResponse`
/// preserva l'intera risposta strutturata — autori, codici identificativi,
/// posizione del testo — perché nessuna schermata di questa mappa li
/// consuma ancora.
class AnalisiCopertinaTable extends Table {
  @override
  String get tableName => 'analisi_copertina';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get scansioneId => integer().references(Scansioni, #id)();
  TextColumn get title => text().nullable()();
  TextColumn get issueNumberLabel => text().nullable()();
  TextColumn get publisher => text().nullable()();
  TextColumn get seriesName => text().nullable()();
  TextColumn get isbn => text().nullable()();
  TextColumn get barcode => text().nullable()();
  TextColumn get price => text().nullable()();

  /// Campi aggiunti per il prefill di `InserisciManualmentePage` (deciso su
  /// #63): stessa filosofia degli altri campi di questa tabella, grezzi e
  /// non parsati. Vedi i commenti gemelli su `Edizioni`/`SerieTable` per il
  /// perché di ciascun formato.
  TextColumn get releaseDate => text().nullable()();
  IntColumn get pageCount => integer().nullable()();
  TextColumn get language => text().nullable()();
  TextColumn get color => text().nullable()();
  TextColumn get issn => text().nullable()();

  /// Personaggi raffigurati sulla copertina (§6.2, tag liberi — deciso su
  /// #48). Lista vuota se Claude non riconosce nulla con sufficiente
  /// sicurezza, mai `null`.
  TextColumn get characters =>
      text().map(const StringListConverter()).withDefault(const Constant('[]'))();

  /// Tag di stile/genere artistico o tipologia editoriale della copertina
  /// nel suo complesso (§6.2, deciso su #48), es. "manga", "variant cover".
  TextColumn get coverStyleTags =>
      text().map(const StringListConverter()).withDefault(const Constant('[]'))();

  /// Elementi visivi concreti e specifici della copertina (§6.2, deciso su
  /// #48) che non descrivono uno stile generale, es. "sfondo con
  /// esplosione".
  TextColumn get visualElementTags =>
      text().map(const StringListConverter()).withDefault(const Constant('[]'))();

  /// Logo dell'editore riconosciuto visivamente (§6.2, deciso su #48) —
  /// parallelo a [publisher] (letto testualmente via OCR), ma distinto:
  /// un logo può essere riconosciuto anche quando il nome testuale
  /// dell'editore non è leggibile sulla copertina, e viceversa.
  TextColumn get recognizedPublisherLogo => text().nullable()();

  /// Logo della serie/collana riconosciuto visivamente (§6.2, deciso su
  /// #48) — parallelo a [seriesName] (letto testualmente via OCR), stessa
  /// distinzione di [recognizedPublisherLogo].
  TextColumn get recognizedSeriesLogo => text().nullable()();

  /// Tipo di stampa (§6.4 "edizione/ristampa/variant", deciso su #71) —
  /// testo libero letto in copertina/indicia (es. "Direct Edition"), non un
  /// enum: unifica le tre nozioni di §6.4 in un solo campo. Non collide con
  /// "Edizione", già l'entità stessa nel glossario (vedi `CONTEXT.md`).
  TextColumn get printingType => text().nullable()();

  /// Classificazione/rating (es. "Rated T+", deciso su #71) — testo libero,
  /// stesso pattern di [color]/`volume` su `Edizioni`. Nuovo concetto, non
  /// letto da ComicVine: l'AI è l'unica fonte.
  TextColumn get classificazione => text().nullable()();

  /// Descrizione della storia generata dall'AI dalla propria conoscenza del
  /// fumetto specifico (deciso su #71) — non OCR: a differenza degli altri
  /// campi di questa tabella, rischia di allucinare su fumetti meno noti.
  /// `null` se l'AI non riconosce il fumetto con sufficiente sicurezza,
  /// nessun ripiego su ComicVine.
  TextColumn get description => text().nullable()();

  /// L'intera risposta JSON strutturata di Claude (autori, codici
  /// identificativi, posizione qualitativa/bounding box del testo).
  TextColumn get rawResponse => text().nullable()();
  TextColumn get status => textEnum<StatoAnalisiCopertina>()
      .withDefault(Constant(StatoAnalisiCopertina.pending.name))();

  /// Motivo di un fallimento — utile dato che non c'è retry automatico.
  TextColumn get errorMessage => text().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
}

/// `Identificazione`: il processo — e la riga che lo traccia, 1:1 con una
/// Scansione via `scansioneId` — che genera i Candidati a partire
/// dall'Analisi Copertina di quella Scansione (§6.3, deciso su #53). Stesso
/// pattern a stati di `AnalisiCopertinaTable`. Riga creata quando la
/// pipeline prende in carico la Scansione dopo il completamento
/// dell'Analisi Copertina.
class IdentificazioneTable extends Table {
  @override
  String get tableName => 'identificazione';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get scansioneId => integer().references(Scansioni, #id)();
  TextColumn get status => textEnum<StatoIdentificazione>()
      .withDefault(Constant(StatoIdentificazione.pending.name))();

  /// Motivo di un fallimento tecnico — nessun retry, come `AnalisiCopertina`.
  TextColumn get errorMessage => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get completedAt => dateTime().nullable()();
}

/// `Candidati`: un'ipotesi di corrispondenza fra una Scansione e
/// un'Edizione, proposta durante un'Identificazione (§6.3, deciso su #53).
/// N:1 con `IdentificazioneTable`. Colonne tipizzate, non un blob JSON:
/// `edizioneId` è valorizzato solo per `source = interno` (Edizione già
/// catalogata); i campi grezzi (`title`/`seriesName`/`issueNumberLabel`/
/// `publisher`/`year`/`coverImageUrl`) coprono il caso `esterno`
/// (ComicVine), che non ha ancora una riga Edizione propria. `punteggio` è
/// il Punteggio di confidenza 0-100 (#52). `scelto` marca la riga che ha
/// portato alla conferma, per poter tarare a posteriori pesi/soglie
/// dell'algoritmo (placeholder in #52) su dati reali.
class CandidatiTable extends Table {
  @override
  String get tableName => 'candidati';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get identificazioneId => integer().references(IdentificazioneTable, #id)();
  TextColumn get source => textEnum<FonteCandidato>()();
  IntColumn get edizioneId => integer().nullable().references(Edizioni, #id)();
  TextColumn get title => text().nullable()();
  TextColumn get seriesName => text().nullable()();
  TextColumn get issueNumberLabel => text().nullable()();
  TextColumn get publisher => text().nullable()();
  IntColumn get year => integer().nullable()();
  TextColumn get coverImageUrl => text().nullable()();
  RealColumn get punteggio => real()();
  BoolColumn get scelto => boolean().withDefault(const Constant(false))();

  /// Descrizione dell'albo (§6.4/§8.1, deciso su #70) — valorizzata solo
  /// per `source = esterno` (ComicVine restituisce `description` nella
  /// stessa chiamata già fatta per gli altri campi grezzi); portata
  /// sull'Edizione creata alla conferma del Candidato.
  TextColumn get description => text().nullable()();
}

/// `Creator`: un autore/artista, condiviso tra Edizioni diverse. Nessun
/// vincolo UNIQUE su `name` (deciso su #64): un constraint rigido
/// romperebbe il caso legittimo degli omonimi e non risolve comunque i
/// typo — la prevenzione dei doppioni è compito della UX di
/// ricerca/autocomplete (vedi "Not yet specified" sulla mappa #63), non
/// dello schema.
class Creator extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
}

/// `ComicCreator`: collega un Creator a un'Edizione con un ruolo (deciso
/// su #64). Chiave univoca su (edizioneId, creatorId, ruolo) — non su
/// (edizioneId, creatorId): un autore può comparire più volte sulla
/// stessa Edizione con ruoli diversi (es. "scritto e disegnato da"), e
/// un'Edizione può avere più Creator con lo stesso ruolo (es. due
/// disegnatori). Blocca solo il duplicato esatto (stesso autore, stesso
/// ruolo, stessa edizione, due volte).
class ComicCreator extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get edizioneId => integer().references(Edizioni, #id)();
  IntColumn get creatorId => integer().references(Creator, #id)();
  TextColumn get ruolo => textEnum<RuoloCreator>()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {edizioneId, creatorId, ruolo},
  ];
}

@DriftDatabase(
  tables: [
    Opere,
    SerieTable,
    Edizioni,
    Copie,
    Scansioni,
    AnalisiCopertinaTable,
    IdentificazioneTable,
    CandidatiTable,
    Creator,
    ComicCreator,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Il costruttore che accetta un [QueryExecutor] opzionale è necessario
  /// per i test in memoria (vedi `test/core/data/comics_repository_test.dart`).
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => 8;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: stepByStep(
      from7To8: (m, schema) async {
        await m.addColumn(schema.analisiCopertina, schema.analisiCopertina.printingType);
        await m.addColumn(schema.analisiCopertina, schema.analisiCopertina.classificazione);
        await m.addColumn(schema.analisiCopertina, schema.analisiCopertina.description);
        await m.addColumn(schema.edizioni, schema.edizioni.printingType);
        await m.addColumn(schema.edizioni, schema.edizioni.classificazione);
      },
      from6To7: (m, schema) async {
        await m.addColumn(schema.candidati, schema.candidati.description);
      },
      from5To6: (m, schema) async {
        await m.createTable(schema.creator);
        await m.createTable(schema.comicCreator);
        await m.addColumn(schema.edizioni, schema.edizioni.volume);
        await m.addColumn(schema.edizioni, schema.edizioni.description);
      },
      from4To5: (m, schema) async {
        await m.addColumn(schema.serie, schema.serie.issn);
        await m.addColumn(schema.edizioni, schema.edizioni.releaseDate);
        await m.addColumn(schema.edizioni, schema.edizioni.coverPrice);
        await m.addColumn(schema.edizioni, schema.edizioni.pageCount);
        await m.addColumn(schema.edizioni, schema.edizioni.language);
        await m.addColumn(schema.edizioni, schema.edizioni.color);
        await m.addColumn(schema.edizioni, schema.edizioni.ean);
        await m.addColumn(schema.analisiCopertina, schema.analisiCopertina.releaseDate);
        await m.addColumn(schema.analisiCopertina, schema.analisiCopertina.pageCount);
        await m.addColumn(schema.analisiCopertina, schema.analisiCopertina.language);
        await m.addColumn(schema.analisiCopertina, schema.analisiCopertina.color);
        await m.addColumn(schema.analisiCopertina, schema.analisiCopertina.issn);
      },
      from1To2: (m, schema) async {
        await m.dropColumn(schema.scansioni, 'ocr_text');
        await m.dropColumn(schema.scansioni, 'recognition_status');
        await m.dropColumn(schema.scansioni, 'confidence');
        await m.createTable(schema.analisiOcr);
      },
      from2To3: (m, schema) async {
        await m.renameTable(schema.analisiCopertina, 'analisi_ocr');
        await m.addColumn(schema.analisiCopertina, schema.analisiCopertina.characters);
        await m.addColumn(schema.analisiCopertina, schema.analisiCopertina.coverStyleTags);
        await m.addColumn(schema.analisiCopertina, schema.analisiCopertina.visualElementTags);
        await m.addColumn(
          schema.analisiCopertina,
          schema.analisiCopertina.recognizedPublisherLogo,
        );
        await m.addColumn(schema.analisiCopertina, schema.analisiCopertina.recognizedSeriesLogo);
      },
      from3To4: (m, schema) async {
        await m.createTable(schema.identificazione);
        await m.createTable(schema.candidati);
        await m.addColumn(schema.copie, schema.copie.scansioneId);
      },
    ),
  );

  static QueryExecutor _open() => driftDatabase(
    name: 'mycomicbrain',
    native: const DriftNativeOptions(
      // Il default è Documents, che su iOS finisce nel backup iCloud ed è
      // esposto all'utente. Application Support è la scelta corretta per
      // un database interno.
      databaseDirectory: getApplicationSupportDirectory,
    ),
  );
}
