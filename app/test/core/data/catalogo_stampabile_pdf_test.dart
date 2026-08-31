import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/catalogo_stampabile_pdf.dart';
import 'package:mycomicbrain/core/domain/catalogo_stampabile.dart';
import 'package:mycomicbrain/core/domain/copia.dart';
import 'package:mycomicbrain/core/domain/creator.dart';
import 'package:mycomicbrain/core/domain/formato.dart';
import 'package:pdf/widgets.dart' as pw;

/// PNG 1×1 trasparente valido — il più piccolo possibile decodificabile da
/// `image` (usato internamente da `pw.MemoryImage`), per esercitare il ramo
/// "cover reale" senza dipendere da asset esterni.
final Uint8List _pngMinimo = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY'
  '42YAAAAASUVORK5CYII=',
);

void main() {
  // Font Type1 built-in (nessun asset/rootBundle necessario): questa
  // funzione riceve i font già caricati dal chiamante, vedi il commento
  // su `generaPdfCatalogoStampabile`.
  final fontRegular = pw.Font.helvetica();
  final fontBold = pw.Font.helveticaBold();
  final fontMono = pw.Font.courier();

  Future<Uint8List> genera(
    List<RigaCatalogoStampabile> righe, {
    Future<Uint8List?> Function(String)? caricaBytesCopertina,
  }) => generaPdfCatalogoStampabile(
    righe,
    fontRegular: fontRegular,
    fontBold: fontBold,
    fontMono: fontMono,
    caricaBytesCopertina: caricaBytesCopertina,
  );

  void expectPdfValido(Uint8List bytes) {
    expect(bytes.length, greaterThan(0));
    expect(utf8.decode(bytes.sublist(0, 5), allowMalformed: true), '%PDF-');
  }

  RigaCatalogoStampabile riga({
    int copiaId = 1,
    String operaTitolo = 'Dylan Dog',
    String? serieName = 'Dylan Dog',
    String? issueNumberLabel = '1',
    int? issueNumber = 1,
    String? coverImage,
  }) => RigaCatalogoStampabile(
    copiaId: copiaId,
    operaTitolo: operaTitolo,
    serieName: serieName,
    issueNumberLabel: issueNumberLabel,
    issueNumber: issueNumber,
    publisher: 'Sergio Bonelli Editore',
    year: 1986,
    format: FormatoEdizione.spillato,
    autori: const [
      (
        comicCreatorId: 1,
        creatorId: 1,
        name: 'Tiziano Sclavi',
        ruolo: RuoloCreator.sceneggiatore,
      ),
    ],
    condition: CondizioneCopia.veryFine,
    purchasePrice: 5,
    location: 'Scaffale A1',
    notes: 'Prima edizione',
    coverImage: coverImage,
  );

  test('nessuna copia: genera comunque un PDF valido', () async {
    expectPdfValido(await genera(const []));
  });

  test('una copia con tutti i campi: PDF valido', () async {
    expectPdfValido(await genera([riga()]));
  });

  test('campi opzionali assenti: non lancia (celle vuote in tabella)', () async {
    final righeMinime = [
      const RigaCatalogoStampabile(copiaId: 1, operaTitolo: 'Volume unico'),
    ];
    expectPdfValido(await genera(righeMinime));
  });

  test(
    "un'Opera senza Serie finisce nel gruppo Volumi unici, senza lanciare",
    () async {
      expectPdfValido(
        await genera([
          riga(operaTitolo: 'Watchmen', serieName: null),
        ]),
      );
    },
  );

  group('copertina', () {
    test(
      'coverImage assente: ricade sulla procedurale senza chiamare il loader',
      () async {
        var chiamato = false;
        final bytes = await genera(
          [riga()],
          caricaBytesCopertina: (_) async {
            chiamato = true;
            return null;
          },
        );
        expectPdfValido(bytes);
        expect(chiamato, isFalse);
      },
    );

    test('loader restituisce bytes validi: embedda la cover reale', () async {
      final bytes = await genera(
        [riga(coverImage: 'https://example.com/cover.jpg')],
        caricaBytesCopertina: (url) async => _pngMinimo,
      );
      expectPdfValido(bytes);
    });

    test(
      'loader restituisce null (download fallito): ricade sulla procedurale',
      () async {
        final bytes = await genera(
          [riga(coverImage: 'https://example.com/cover.jpg')],
          caricaBytesCopertina: (url) async => null,
        );
        expectPdfValido(bytes);
      },
    );

    test(
      'loader restituisce bytes non decodificabili come immagine: ricade '
      'sulla procedurale invece di lanciare',
      () async {
        final bytes = await genera(
          [riga(coverImage: 'https://example.com/cover.jpg')],
          caricaBytesCopertina: (url) async => Uint8List.fromList([1, 2, 3]),
        );
        expectPdfValido(bytes);
      },
    );
  });

  test(
    'collezione grande su più Serie/Opere: genera senza lanciare '
    '(impaginazione multi-pagina)',
    () async {
      final righe = [
        for (var s = 0; s < 5; s++)
          for (var n = 0; n < 8; n++)
            riga(
              copiaId: s * 8 + n,
              serieName: 'Serie $s',
              operaTitolo: 'Serie $s',
              issueNumberLabel: '$n',
              issueNumber: n,
            ),
      ];
      expectPdfValido(await genera(righe));
    },
  );
}
