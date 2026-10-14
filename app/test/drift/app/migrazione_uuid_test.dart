import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/database.dart';

import 'generated/schema.dart';

/// Migrazione 15 → 16 (ADR-0008, #204): gli id interi della Modalità locale
/// diventano uuid v7, con collegamenti e ordine di creazione conservati.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  final uuidV7 = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  test('gli id interi diventano uuid v7 con collegamenti e ordine '
      'conservati', () async {
    final schema = await verifier.schemaAt(15);
    const ora = "'2026-10-01T10:00:00.000'";
    schema.rawDatabase.execute('''
      insert into opere (id, title, created_at) values
        (1, 'Dylan Dog', $ora), (2, 'Tex', $ora);
      insert into serie (id, name) values (1, 'Dylan Dog');
      insert into edizioni (id, opera_id, serie_id, created_at) values
        (1, 1, 1, $ora), (2, 2, null, $ora);
      insert into scansioni (id, image, created_at) values (5, 'scan.jpg', $ora);
      insert into copie (id, edizione_id, status, created_at, updated_at,
                         scansione_id) values
        (1, 1, 'posseduta', $ora, $ora, 5),
        (2, 2, 'posseduta', $ora, $ora, null);
      insert into valore_stimato (id, copia_id, status, value, created_at)
        values (1, 1, 'completata', 12.5, $ora);
      insert into analisi_copertina (id, scansione_id, status, created_at)
        values (1, 5, 'completata', $ora);
      insert into identificazione (id, scansione_id, status, created_at)
        values (1, 5, 'completata', $ora);
      insert into candidati (id, identificazione_id, source, edizione_id,
                             punteggio) values (1, 1, 'interno', 2, 80);
      insert into creator (id, name) values (1, 'C'), (2, 'A'), (3, 'B');
      insert into comic_creator (id, edizione_id, creator_id, ruolo) values
        (1, 1, 1, 'altro'), (2, 1, 2, 'altro'), (3, 1, 3, 'altro');
      insert into tag (id, name) values (1, 'horror');
      insert into edizione_tag (id, edizione_id, tag_id) values (1, 1, 1);
      insert into character (id, name) values (1, 'Groucho');
      insert into comic_character (id, edizione_id, character_id)
        values (1, 1, 1);
      insert into edizione_genere (id, edizione_id, genere)
        values (1, 1, 'horror');
      insert into conversazione (id, created_at) values (1, $ora);
      insert into messaggio (id, conversazione_id, ruolo, testo, edizione_ids,
                             created_at)
        values (1, 1, 'assistente', 'eccole', '[2,1]', $ora);
    ''');

    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 16);

    Future<List<String>> colonna(String sql) async => [
      for (final riga in await db.customSelect(sql).get())
        riga.data.values.first as String,
    ];

    for (final tabella in [
      'opere',
      'serie',
      'edizioni',
      'copie',
      'scansioni',
      'valore_stimato',
      'analisi_copertina',
      'identificazione',
      'candidati',
      'creator',
      'comic_creator',
      'tag',
      'edizione_tag',
      'character',
      'comic_character',
      'edizione_genere',
    ]) {
      expect(
        await colonna('select id from $tabella'),
        everyElement(
          matches(uuidV7),
        ),
        reason: tabella,
      );
    }

    expect(
      await colonna('''
        select o.title || '/' || coalesce(s.name, '-') || '/'
               || coalesce(sc.image, '-') || '/' || coalesce(v.value, '-')
        from copie c join edizioni e on e.id = c.edizione_id
        join opere o on o.id = e.opera_id
        left join serie s on s.id = e.serie_id
        left join scansioni sc on sc.id = c.scansione_id
        left join valore_stimato v on v.copia_id = c.id
        order by c.id'''),
      ['Dylan Dog/Dylan Dog/scan.jpg/12.5', 'Tex/-/-/-'],
      reason:
          'Copie, Edizioni, Opere, Serie, Scansioni e Valore stimato '
          'restano collegati',
    );
    expect(
      await colonna('''
        select o.title from candidati k
        join identificazione i on i.id = k.identificazione_id
        join analisi_copertina a on a.scansione_id = i.scansione_id
        join edizioni e on e.id = k.edizione_id
        join opere o on o.id = e.opera_id'''),
      ['Tex'],
      reason: 'Candidato, Identificazione e Analisi restano collegati',
    );
    expect(
      await colonna('''
        select cr.name from comic_creator cc
        join creator cr on cr.id = cc.creator_id order by cc.id'''),
      ['C', 'A', 'B'],
      reason: "l'ordine di creazione dei collegamenti si conserva",
    );
    expect(
      await colonna('''
        select t.name || '/' || ch.name || '/' || g.genere from edizione_tag et
        join tag t on t.id = et.tag_id
        join comic_character cch on cch.edizione_id = et.edizione_id
        join character ch on ch.id = cch.character_id
        join edizione_genere g on g.edizione_id = et.edizione_id'''),
      ['horror/Groucho/horror'],
    );

    final edizioni = await colonna('select id from edizioni order by id');
    final idsMessaggio = jsonDecode(
      (await colonna('select edizione_ids from messaggio')).single,
    );
    expect(idsMessaggio, [
      edizioni[1],
      edizioni[0],
    ], reason: 'i Messaggi riferiscono le stesse Edizioni, in ordine');

    final nuova = await db
        .into(db.opere)
        .insertReturning(
          OpereCompanion.insert(title: 'Nuova', createdAt: DateTime.now()),
        );
    expect(nuova.id, matches(uuidV7));
    expect(
      await colonna('select title from opere order by id'),
      ['Dylan Dog', 'Tex', 'Nuova'],
      reason: 'le righe nuove vengono dopo quelle convertite',
    );

    await db.close();
  });
}
