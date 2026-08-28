import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/domain/conversazione.dart';
import 'package:mycomicbrain/core/domain/copia.dart';

void main() {
  late AppDatabase db;
  late ComicsRepository repo;

  setUp(() {
    db = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    repo = ComicsRepository(db);
  });

  tearDown(() => db.close());

  Future<int> edizione() async {
    final operaId = await repo.aggiungiOpera(title: 'The Amazing Spider-Man');
    return repo.aggiungiEdizione(operaId: operaId, issueNumberLabel: '1');
  }

  test(
    'getOrCreaConversazione crea una sola riga anche se chiamata più volte',
    () async {
      final id1 = await repo.getOrCreaConversazione();
      final id2 = await repo.getOrCreaConversazione();

      expect(id1, id2);
      final tutte = await db.select(db.conversazioneTable).get();
      expect(tutte, hasLength(1));
    },
  );

  test(
    'aggiungiMessaggio + watchMessaggi restituiscono i Messaggi in ordine cronologico',
    () async {
      final conversazioneId = await repo.getOrCreaConversazione();

      await repo.aggiungiMessaggio(
        conversazioneId: conversazioneId,
        ruolo: RuoloMessaggio.utente,
        testo: 'Quanti Batman ho?',
        createdAt: DateTime(2026),
      );
      await repo.aggiungiMessaggio(
        conversazioneId: conversazioneId,
        ruolo: RuoloMessaggio.assistente,
        testo: 'Ne hai 3.',
        createdAt: DateTime(2026, 1, 2),
      );

      final messaggi = await repo.watchMessaggi(conversazioneId).first;

      expect(messaggi, hasLength(2));
      expect(messaggi[0].ruolo, RuoloMessaggio.utente);
      expect(messaggi[0].testo, 'Quanti Batman ho?');
      expect(messaggi[1].ruolo, RuoloMessaggio.assistente);
      expect(messaggi[1].testo, 'Ne hai 3.');
    },
  );

  test(
    'aggiungiMessaggio persiste sottotipoSistema solo per ruolo sistema',
    () async {
      final conversazioneId = await repo.getOrCreaConversazione();

      await repo.aggiungiMessaggio(
        conversazioneId: conversazioneId,
        ruolo: RuoloMessaggio.sistema,
        sottotipoSistema: SottotipoSistema.erroreProvider,
        testo: 'Provider AI Testuale non raggiungibile.',
      );

      final messaggi = await repo.watchMessaggi(conversazioneId).first;

      expect(messaggi.single.sottotipoSistema, SottotipoSistema.erroreProvider);
    },
  );

  test(
    'watchMessaggi risolve edizioneIds a runtime su un Messaggio assistente',
    () async {
      final conversazioneId = await repo.getOrCreaConversazione();
      final edizioneId = await edizione();
      await repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
      );

      await repo.aggiungiMessaggio(
        conversazioneId: conversazioneId,
        ruolo: RuoloMessaggio.assistente,
        testo: 'Ho trovato questo:',
        edizioneIds: [edizioneId],
      );

      final messaggi = await repo.watchMessaggi(conversazioneId).first;

      expect(messaggi.single.edizioni, hasLength(1));
      expect(messaggi.single.edizioni.single.edizioneId, edizioneId);
    },
  );

  test(
    "watchMessaggi omette in silenzio un edizioneId di un'Edizione cancellata",
    () async {
      final conversazioneId = await repo.getOrCreaConversazione();
      final edizioneId = await edizione();
      await repo.aggiungiCopia(
        edizioneId: edizioneId,
        status: StatoCopia.posseduta,
      );

      await repo.aggiungiMessaggio(
        conversazioneId: conversazioneId,
        ruolo: RuoloMessaggio.assistente,
        testo: 'Ho trovato questo:',
        edizioneIds: [edizioneId],
      );
      await repo.eliminaEdizione(edizioneId);

      final messaggi = await repo.watchMessaggi(conversazioneId).first;

      expect(messaggi.single.edizioni, isEmpty);
    },
  );

  test(
    'eliminaConversazione cancella tutti i Messaggi e la Conversazione stessa',
    () async {
      final conversazioneId = await repo.getOrCreaConversazione();
      await repo.aggiungiMessaggio(
        conversazioneId: conversazioneId,
        ruolo: RuoloMessaggio.utente,
        testo: 'Ciao',
      );

      await repo.eliminaConversazione(conversazioneId);

      final conversazioni = await db.select(db.conversazioneTable).get();
      final messaggi = await db.select(db.messaggioTable).get();
      expect(conversazioni, isEmpty);
      expect(messaggi, isEmpty);
    },
  );
}
