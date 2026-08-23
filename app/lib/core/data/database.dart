import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:mycomicbrain/core/data/database.steps.dart';
import 'package:mycomicbrain/core/domain/analisi_copertina.dart';
import 'package:mycomicbrain/core/domain/copia.dart';
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
  DateTimeColumn get createdAt => dateTime()();
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

@DriftDatabase(tables: [Opere, SerieTable, Edizioni, Copie, Scansioni, AnalisiCopertinaTable])
class AppDatabase extends _$AppDatabase {
  /// Il costruttore che accetta un [QueryExecutor] opzionale è necessario
  /// per i test in memoria (vedi `test/core/data/comics_repository_test.dart`).
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: stepByStep(
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
