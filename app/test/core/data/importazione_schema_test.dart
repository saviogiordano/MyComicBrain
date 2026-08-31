import 'dart:convert';

import 'package:csv/csv.dart' as csv_pkg;
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/esportazione_schema.dart';
import 'package:mycomicbrain/core/data/importazione_schema.dart';
import 'package:mycomicbrain/core/domain/copia.dart';
import 'package:mycomicbrain/core/domain/creator.dart';
import 'package:mycomicbrain/core/domain/esportazione.dart';
import 'package:mycomicbrain/core/domain/formato.dart';

void main() {
  final intestazione = [for (final c in colonneEsportazione) c.etichetta];

  /// Un CSV con una sola riga dati, coi soli campi in [valori] impostati
  /// (etichetta->valore) e tutti gli altri vuoti — per testare campi con
  /// valori non producibili dal dominio (es. uno "Stato" inventato).
  String csvConValori(Map<String, String> valori) {
    final riga = [
      for (final etichetta in intestazione) valori[etichetta] ?? '',
    ];
    return csv_pkg.csv.encode([intestazione, riga]);
  }

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

  group('roundtrip export->import', () {
    test('CSV: una riga completa riparte identica sui campi chiave', () {
      final csv = generaCsvEsportazione([rigaCompleta()]);
      final risultato = analizzaCsvImportazione(csv);

      expect(risultato.scartate, isEmpty);
      expect(risultato.valide, hasLength(1));
      final riga = risultato.valide.single;
      expect(riga.operaTitolo, 'Dylan Dog');
      expect(riga.serieName, 'Dylan Dog');
      expect(riga.publisher, 'Sergio Bonelli Editore');
      expect(riga.issueNumberLabel, '1');
      expect(riga.issueNumber, 1);
      expect(riga.format, FormatoEdizione.spillato);
      expect(riga.condition, CondizioneCopia.veryFine);
      expect(riga.status, StatoCopia.posseduta);
      expect(riga.readingStatus, StatoLettura.letto);
      expect(riga.purchasePrice, 5);
      expect(riga.purchaseDate, DateTime(2020, 3, 15));
      expect(riga.seller, 'Fumetteria Rossi');
      expect(riga.notes, 'Prima edizione');
      expect(riga.autori, hasLength(1));
      expect(riga.autori.single.name, 'Tiziano Sclavi');
      expect(riga.autori.single.ruolo, RuoloCreator.sceneggiatore);
    });

    test('JSON: stesso esito del CSV per la stessa riga', () {
      final json = generaJsonEsportazione([rigaCompleta()]);
      final risultato = analizzaJsonImportazione(json);

      expect(risultato.scartate, isEmpty);
      expect(risultato.valide, hasLength(1));
      expect(risultato.valide.single.operaTitolo, 'Dylan Dog');
      expect(
        risultato.valide.single.status,
        StatoCopia.posseduta,
      );
    });

    test('una riga "Mancante" (Copia persa) riparte con lo status giusto', () {
      final rigaPersa = RigaEsportazioneCopia(
        copiaId: 2,
        edizioneId: 20,
        operaTitolo: 'Volume unico',
        status: StatoCopia.persa,
        createdAt: DateTime(2024, 5),
      );
      final csv = generaCsvEsportazione([rigaPersa]);
      final risultato = analizzaCsvImportazione(csv);

      expect(risultato.valide, hasLength(1));
      expect(risultato.valide.single.status, StatoCopia.persa);
      expect(risultato.valide.single.readingStatus, isNull);
    });
  });

  group('righe malformate', () {
    test('Opera mancante viene scartata con motivo', () {
      final csv = generaCsvEsportazione([
        RigaEsportazioneCopia(
          copiaId: 1,
          edizioneId: 1,
          operaTitolo: '',
          status: StatoCopia.posseduta,
          createdAt: DateTime(2024),
        ),
      ]);
      final risultato = analizzaCsvImportazione(csv);

      expect(risultato.valide, isEmpty);
      expect(risultato.scartate, hasLength(1));
      expect(risultato.scartate.single.motivo, contains('Opera'));
    });

    test('Stato non riconosciuto viene scartato senza bloccare le altre', () {
      final rigaScartata = [
        for (final e in intestazione)
          if (e == 'Opera')
            'Prima'
          else if (e == 'Stato')
            'Stato inesistente'
          else
            '',
      ];
      final rigaValida = [
        for (final e in intestazione)
          if (e == 'Opera') 'Seconda' else if (e == 'Stato') 'Letto' else '',
      ];
      final csv = csv_pkg.csv.encode([intestazione, rigaScartata, rigaValida]);
      final risultato = analizzaCsvImportazione(csv);

      expect(risultato.valide, hasLength(1));
      expect(risultato.valide.single.operaTitolo, 'Seconda');
      expect(risultato.scartate, hasLength(1));
      expect(risultato.scartate.single.numeroRiga, 1);
      expect(risultato.scartate.single.motivo, contains('Stato inesistente'));
    });

    test('un valore Formato non riconosciuto non scarta la riga', () {
      final csv = csvConValori({
        'Opera': 'Prima',
        'Stato': 'Letto',
        'Formato': 'Digitale',
      });
      final risultato = analizzaCsvImportazione(csv);

      expect(risultato.scartate, isEmpty);
      expect(risultato.valide, hasLength(1));
      expect(risultato.valide.single.format, isNull);
    });

    test("JSON malformato (righe non è una lista) propaga l'errore", () {
      expect(
        () => analizzaJsonImportazione(jsonEncode({'righe': 'non una lista'})),
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('Excel', () {
    test('una riga completa riparte identica sui campi chiave', () {
      final bytes = generaExcelEsportazione([rigaCompleta()]);
      final risultato = analizzaExcelImportazione(bytes);

      expect(risultato.scartate, isEmpty);
      expect(risultato.valide, hasLength(1));
      final riga = risultato.valide.single;
      expect(riga.operaTitolo, 'Dylan Dog');
      expect(riga.serieName, 'Dylan Dog');
      expect(riga.format, FormatoEdizione.spillato);
      expect(riga.status, StatoCopia.posseduta);
      expect(riga.readingStatus, StatoLettura.letto);
      expect(riga.autori, hasLength(1));
      expect(riga.autori.single.name, 'Tiziano Sclavi');
    });

    test('Opera mancante viene scartata con motivo, come per il CSV', () {
      final bytes = generaExcelEsportazione([
        RigaEsportazioneCopia(
          copiaId: 1,
          edizioneId: 1,
          operaTitolo: '',
          status: StatoCopia.posseduta,
          createdAt: DateTime(2024),
        ),
      ]);
      final risultato = analizzaExcelImportazione(bytes);

      expect(risultato.valide, isEmpty);
      expect(risultato.scartate, hasLength(1));
      expect(risultato.scartate.single.motivo, contains('Opera'));
    });
  });
}
