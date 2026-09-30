import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' as archive_pkg;
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
    coverImage: '/covers/dylan1.jpg',
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

    test('"Copertina" non è fra le colonne base (è aggiunta in coda)', () {
      final etichette = [for (final c in colonneEsportazione) c.etichetta];
      expect(etichette, isNot(contains(etichettaColonnaCopertina)));
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

    test('ultima colonna "Copertina" col nome del file nello zip', () {
      final csv = generaCsvEsportazione(
        [rigaCompleta(), rigaMinima()],
        fileCopertine: {10: 'copertine/edizione_10.jpg'},
      );
      final righe = csv.split('\r\n')..removeWhere((r) => r.isEmpty);

      expect(righe[0], endsWith(',Copertina'));
      expect(righe[1], endsWith(',copertine/edizione_10.jpg'));
      // Nessuna cover per l'Edizione 20: cella vuota.
      expect(righe[2], endsWith(','));
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
        etichettaColonnaCopertina,
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
        etichettaColonnaCopertina,
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

  group('raccogliCopertineEsportazione', () {
    final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2]);
    final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2]);

    RigaEsportazioneCopia riga(int copiaId, int edizioneId, String? cover) =>
        RigaEsportazioneCopia(
          copiaId: copiaId,
          edizioneId: edizioneId,
          operaTitolo: 'Opera $edizioneId',
          status: StatoCopia.posseduta,
          createdAt: DateTime(2024),
          coverImage: cover,
        );

    test('un file per Edizione, estensione dai byte, cover illeggibili '
        'saltate', () async {
      final caricate = <String>[];
      final copertine = await raccogliCopertineEsportazione(
        [
          riga(1, 10, '/a.jpg'),
          // Seconda Copia della stessa Edizione: nessun secondo caricamento.
          riga(2, 10, '/a.jpg'),
          riga(3, 20, 'https://example.com/b'),
          riga(4, 30, '/mancante.jpg'),
          riga(5, 40, null),
        ],
        caricaBytesCopertina: (cover) async {
          caricate.add(cover);
          return switch (cover) {
            '/a.jpg' => jpeg,
            'https://example.com/b' => png,
            _ => null,
          };
        },
      );

      expect(caricate, ['/a.jpg', 'https://example.com/b', '/mancante.jpg']);
      expect(copertine.fileCopertine, {
        10: 'copertine/edizione_10.jpg',
        20: 'copertine/edizione_20.png',
      });
      expect(copertine.bytesPerFile, {
        'copertine/edizione_10.jpg': jpeg,
        'copertine/edizione_20.png': png,
      });
    });
  });

  group('generaZipEsportazione', () {
    test('file dati alla radice più le cover in copertine/', () {
      final dati = utf8.encode('Opera,Copertina\r\n');
      final cover = Uint8List.fromList([0xFF, 0xD8, 0xFF]);

      final zip = generaZipEsportazione(
        nomeFileDati: 'collezione.csv',
        bytesDati: dati,
        copertine: {'copertine/edizione_10.jpg': cover},
      );
      final archivio = archive_pkg.ZipDecoder().decodeBytes(zip);

      expect(archivio.files.map((f) => f.name), [
        'collezione.csv',
        'copertine/edizione_10.jpg',
      ]);
      expect(archivio.findFile('collezione.csv')!.content, dati);
      expect(archivio.findFile('copertine/edizione_10.jpg')!.content, cover);
    });
  });
}
