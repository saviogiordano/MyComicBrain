import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:mycomicbrain/core/domain/copia.dart';
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

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

@DriftDatabase(tables: [Opere, SerieTable, Edizioni, Copie])
class AppDatabase extends _$AppDatabase {
  /// Il costruttore che accetta un [QueryExecutor] opzionale è necessario
  /// per i test in memoria (vedi `test/core/data/comics_repository_test.dart`).
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => 1;

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
