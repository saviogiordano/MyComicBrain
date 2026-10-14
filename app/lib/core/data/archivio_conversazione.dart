import 'package:drift/drift.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/domain/conversazione.dart';

/// Un Messaggio come lo conserva un [ArchivioConversazione]: le Edizioni
/// sono solo id, risolti da `ComicsRepository.watchMessaggi` sul catalogo.
class RigaMessaggio {
  const RigaMessaggio({
    required this.id,
    required this.ruolo,
    required this.testo,
    required this.createdAt,
    this.sottotipoSistema,
    this.edizioneIds = const [],
  });

  final int id;
  final RuoloMessaggio ruolo;
  final SottotipoSistema? sottotipoSistema;
  final String testo;
  final DateTime createdAt;
  final List<String> edizioneIds;
}

/// Dove vive la Conversazione dell'Assistente (§10/§24, #128): nel database
/// drift per la Modalità locale, su Supabase per un Profilo autenticato, la
/// cui Replica locale non la contiene (ADR-0008). `DriftComicsRepository`
/// le passa i metodi della Conversazione di `ComicsRepository`.
abstract interface class ArchivioConversazione {
  /// Id dell'unica Conversazione, creandola se non esiste ancora — vincolo
  /// di singleton solo applicativo (#128), non imposto dallo schema.
  Future<int> getOrCrea();

  Future<int> aggiungiMessaggio({
    required int conversazioneId,
    required RuoloMessaggio ruolo,
    required String testo,
    SottotipoSistema? sottotipoSistema,
    List<String> edizioneIds = const [],
    DateTime? createdAt,
  });

  /// I Messaggi in ordine cronologico, riemessi a ogni scrittura.
  Stream<List<RigaMessaggio>> watchMessaggi(int conversazioneId);

  /// Tutti i Messaggi, poi la Conversazione stessa.
  Future<void> elimina(int conversazioneId);
}

/// La Conversazione nelle tabelle drift `conversazione`/`messaggio`.
class ArchivioConversazioneDrift implements ArchivioConversazione {
  ArchivioConversazioneDrift(this._db);

  final AppDatabase _db;

  @override
  Future<int> getOrCrea() async {
    final esistente = await _db.select(_db.conversazioneTable).get();
    if (esistente.isNotEmpty) return esistente.single.id;

    return _db
        .into(_db.conversazioneTable)
        .insert(ConversazioneTableCompanion.insert(createdAt: DateTime.now()));
  }

  @override
  Future<int> aggiungiMessaggio({
    required int conversazioneId,
    required RuoloMessaggio ruolo,
    required String testo,
    SottotipoSistema? sottotipoSistema,
    List<String> edizioneIds = const [],
    DateTime? createdAt,
  }) {
    return _db
        .into(_db.messaggioTable)
        .insert(
          MessaggioTableCompanion.insert(
            conversazioneId: conversazioneId,
            ruolo: ruolo,
            testo: testo,
            sottotipoSistema: Value(sottotipoSistema),
            edizioneIds: edizioneIds.isEmpty
                ? const Value.absent()
                : Value(edizioneIds),
            createdAt: createdAt ?? DateTime.now(),
          ),
        );
  }

  @override
  Stream<List<RigaMessaggio>> watchMessaggi(int conversazioneId) {
    final query = _db.select(_db.messaggioTable)
      ..where((m) => m.conversazioneId.equals(conversazioneId))
      ..orderBy([(m) => OrderingTerm.asc(m.createdAt)]);

    return query.watch().map(
      (righe) => [
        for (final riga in righe)
          RigaMessaggio(
            id: riga.id,
            ruolo: riga.ruolo,
            sottotipoSistema: riga.sottotipoSistema,
            testo: riga.testo,
            createdAt: riga.createdAt,
            edizioneIds: riga.edizioneIds ?? const [],
          ),
      ],
    );
  }

  @override
  Future<void> elimina(int conversazioneId) {
    return _db.transaction(() async {
      await (_db.delete(
        _db.messaggioTable,
      )..where((m) => m.conversazioneId.equals(conversazioneId))).go();
      await (_db.delete(
        _db.conversazioneTable,
      )..where((c) => c.id.equals(conversazioneId))).go();
    });
  }
}
