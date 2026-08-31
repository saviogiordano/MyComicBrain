import 'dart:convert';

import 'package:excel/excel.dart' as excel_pkg;
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/esportazione_schema.dart';
import 'package:mycomicbrain/core/domain/copia.dart';
import 'package:mycomicbrain/core/domain/creator.dart';
import 'package:mycomicbrain/core/domain/esportazione.dart';
import 'package:mycomicbrain/core/domain/formato.dart';

void main() {
  RigaEsportazioneCopia rigaCompleta() => RigaEsportazioneCopia(
    copiaId: 1,
    edizioneId: 10,
    operaTitolo: 'Dylan Dog',
    serieName: 'Dylan Dog',
    publisher: 'Sergio Bonelli Editore',
    issueNumber: 1,
    issueNumberLabel: '1',
    releaseDate: 'settembre 1986',
    year: 1986,
    coverPrice: '€ 2.000',
    pageCount: 100,
    language: 'Italiano',
    color: 'bianco e nero',
    ean: '9771234567003',
    description: 'Il trapassato',
    printingType: 'Prima stampa',
    format: FormatoEdizione.spillato,
    autori: const [
      (
        comicCreatorId: 1,
        creatorId: 1,
        name: 'Tiziano Sclavi',
        ruolo: RuoloCreator.sceneggiatore,
      ),
    ],
    status: StatoCopia.posseduta,
    readingStatus: StatoLettura.letto,
    condition: CondizioneCopia.veryFine,
    purchasePrice: 5,
    purchaseDate: DateTime(2020, 3, 15),
    seller: 'Fumetteria Rossi',
    location: 'Scaffale A',
    notes: 'Prima edizione',
    createdAt: DateTime(2024, 1, 2),
  );

  RigaEsportazioneCopia rigaMinima() => RigaEsportazioneCopia(
    copiaId: 2,
    edizioneId: 20,
    operaTitolo: 'Volume unico',
    status: StatoCopia.persa,
    createdAt: DateTime(2024, 5),
  );

  group('colonneEsportazione', () {
    test('etichette senza duplicati, stesso ordine fra CSV e JSON', () {
      final etichette = [for (final c in colonneEsportazione) c.etichetta];
      expect(etichette.toSet(), hasLength(etichette.length));
    });

    test('niente colonna immagine/cover (decisione mappa #139)', () {
      final etichette = [for (final c in colonneEsportazione) c.etichetta];
      expect(
        etichette.any((e) => e.toLowerCase().contains('cover')),
        isFalse,
      );
      expect(
        etichette.any((e) => e.toLowerCase().contains('immagine')),
        isFalse,
      );
    });
  });

  group('generaCsvEsportazione', () {
    test('intestazione con le etichette italiane, una riga per Copia', () {
      final csv = generaCsvEsportazione([rigaCompleta(), rigaMinima()]);
      final righe = csv.split('\r\n')..removeWhere((r) => r.isEmpty);

      expect(righe, hasLength(3)); // intestazione + 2 righe
      expect(righe.first, contains('Opera'));
      expect(righe.first, contains('Stato'));
      expect(righe[1], contains('Dylan Dog'));
      expect(righe[1], contains('Very Fine'));
      // "Letto" perché readingStatus è impostato su una Copia posseduta.
      expect(righe[1], contains('Letto'));
      expect(righe[2], contains('Volume unico'));
      // Stato di una Copia persa: la voce "Mancante" (§8.3, `voceStatoDi`).
      expect(righe[2], contains('Mancante'));
    });

    test('campi vuoti per una riga minima, nessuna eccezione', () {
      expect(() => generaCsvEsportazione([rigaMinima()]), returnsNormally);
    });
  });

  group('generaJsonEsportazione', () {
    test('metadata con versione schema, data e conteggio righe', () {
      final json =
          jsonDecode(generaJsonEsportazione([rigaCompleta(), rigaMinima()]))
              as Map<String, dynamic>;

      final metadata = json['metadata'] as Map<String, dynamic>;
      expect(metadata['versioneSchema'], schemaEsportazioneVersione);
      expect(metadata['numeroRighe'], 2);
      expect(
        DateTime.tryParse(metadata['dataEsportazione'] as String),
        isNotNull,
      );
    });

    test('righe come mappa etichetta->valore, stesse chiavi del CSV', () {
      final json =
          jsonDecode(generaJsonEsportazione([rigaCompleta()]))
              as Map<String, dynamic>;
      final righe = json['righe'] as List<dynamic>;

      expect(righe, hasLength(1));
      final riga = righe.single as Map<String, dynamic>;
      expect(riga.keys.toSet(), {
        for (final c in colonneEsportazione) c.etichetta,
      });
      expect(riga['Opera'], 'Dylan Dog');
      expect(riga['Autori'], 'Tiziano Sclavi (sceneggiatore)');
    });
  });

  group('generaExcelEsportazione', () {
    test('intestazione con le etichette italiane, una riga per Copia', () {
      final bytes = generaExcelEsportazione([rigaCompleta(), rigaMinima()]);
      final libro = excel_pkg.Excel.decodeBytes(bytes);

      expect(libro.sheets.keys, ['Collezione']);
      final righe = libro.sheets['Collezione']!.rows;
      expect(righe, hasLength(3)); // intestazione + 2 righe

      String? testo(excel_pkg.Data? cella) => cella?.value?.toString();
      final intestazione = righe.first.map(testo).toList();
      expect(intestazione, [
        for (final c in colonneEsportazione) c.etichetta,
      ]);

      final indiceOpera = intestazione.indexOf('Opera');
      final indiceStato = intestazione.indexOf('Stato');
      final indiceCondizione = intestazione.indexOf('Condizione');
      expect(testo(righe[1][indiceOpera]), 'Dylan Dog');
      // "Letto" perché readingStatus è impostato su una Copia posseduta.
      expect(testo(righe[1][indiceStato]), 'Letto');
      expect(testo(righe[1][indiceCondizione]), 'Very Fine');
      expect(testo(righe[2][indiceOpera]), 'Volume unico');
      // Stato di una Copia persa: la voce "Mancante" (§8.3, `voceStatoDi`).
      expect(testo(righe[2][indiceStato]), 'Mancante');
    });

    test('campi vuoti per una riga minima, nessuna eccezione', () {
      expect(() => generaExcelEsportazione([rigaMinima()]), returnsNormally);
    });
  });
}
