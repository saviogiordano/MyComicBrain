import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:mycomicbrain/core/domain/catalogo_stampabile.dart';
import 'package:mycomicbrain/core/domain/copia.dart';
import 'package:mycomicbrain/core/domain/formato.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Timeout per il download di una cover remota durante la generazione del
/// PDF — stesso valore di `copertinaDownloadTimeout`
/// (`copertina_downloader.dart`): una copia irraggiungibile non deve
/// bloccare a tempo indeterminato l'intero catalogo, ricade sulla copertina
/// procedurale.
const catalogoStampabileCoverTimeout = Duration(seconds: 45);

final _colInk = PdfColor.fromHex('#1b1d1f');
final _colInkSoft = PdfColor.fromHex('#5b6166');
final _colLine = PdfColor.fromHex('#d8dade');
final _colAccent = PdfColor.fromHex('#0f7a8c');

/// Stessa palette/formula di seme di `ProceduralComicCover`
/// (`comic_cover.dart`) — coppie (sfondo, testo), scelta da
/// `(titolo.length + numero) % _paletteProcedurale.length` — per una
/// copertina segnaposto coerente con quella mostrata in app.
const _paletteProcedurale = <(int bg, int ink)>[
  (0xFF1B3A4B, 0xFFEFE7D6),
  (0xFFB23A2E, 0xFFF7E4C8),
  (0xFF2E2A4F, 0xFFE6E2F2),
  (0xFF0F5C4A, 0xFFEAF3E5),
  (0xFFC4771B, 0xFF22160C),
  (0xFF3A3A3C, 0xFFF0F0F2),
  (0xFF7A2E4E, 0xFFF6E1EA),
  (0xFF1E4620, 0xFFE8F0DE),
];

/// Genera il PDF/catalogo stampabile della collezione (§16, layout —
/// variante C, schede ibride raggruppate Serie → Opera — deciso su
/// [#141](https://github.com/saviogiordano/MyComicBrain/issues/141)):
/// formato A4, una scheda per copia con copertina (reale se disponibile,
/// altrimenti procedurale), Editore, Anno/Formato, Autori, Condizione,
/// Prezzo di acquisto, Posizione e Note.
///
/// Font e caricamento delle cover sono responsabilità del chiamante
/// (`EsportazioneService`, che ha accesso a `rootBundle`/rete): questa
/// funzione si occupa solo di layout e impaginazione, così resta testabile
/// senza bindings Flutter. [caricaBytesCopertina] è iniettabile per i test
/// (di default legge il file locale o scarica l'URL remoto, stesso
/// principio di `CopertinaDownloader.scarica` — un fallimento ricade sulla
/// copertina procedurale, mai un errore visibile).
Future<Uint8List> generaPdfCatalogoStampabile(
  List<RigaCatalogoStampabile> righe, {
  required pw.Font fontRegular,
  required pw.Font fontBold,
  required pw.Font fontMono,
  Future<Uint8List?> Function(String coverImage)? caricaBytesCopertina,
}) async {
  final carica = caricaBytesCopertina ?? _caricaBytesCopertinaDefault;

  final copertine = <int, Uint8List>{};
  for (final riga in righe) {
    final coverImage = riga.coverImage;
    if (coverImage == null) continue;
    final bytes = await carica(coverImage);
    if (bytes != null) copertine[riga.copiaId] = bytes;
  }

  final gruppi = _raggruppaPerSerieEOpera(righe);
  final dataGenerazione = DateTime.now();

  final documento = pw.Document(
    theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
  )..addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(
        horizontal: 14 * PdfPageFormat.mm,
        vertical: 16 * PdfPageFormat.mm,
      ),
      header: (context) => context.pageNumber == 1
          ? _intestazioneDocumento(righe.length, dataGenerazione, fontMono)
          : pw.SizedBox(),
      footer: (context) => _piePagina(context, fontMono),
      build: (context) => [
        for (final gruppo in gruppi)
          ..._sezioneSerie(gruppo, fontRegular, fontBold, fontMono, copertine),
      ],
    ),
  );

  return documento.save();
}

Future<Uint8List?> _caricaBytesCopertinaDefault(String coverImage) async {
  try {
    if (coverImage.startsWith('http://') ||
        coverImage.startsWith('https://')) {
      final response = await http
          .get(Uri.parse(coverImage))
          .timeout(catalogoStampabileCoverTimeout);
      if (response.statusCode != 200) return null;
      return response.bodyBytes;
    }
    final file = File(coverImage);
    if (!file.existsSync()) return null;
    return await file.readAsBytes();
  } on Object {
    return null;
  }
}

class _GruppoOpera {
  _GruppoOpera(this.titolo, this.copie);

  final String titolo;
  final List<RigaCatalogoStampabile> copie;
}

class _GruppoSerie {
  _GruppoSerie(this.nome, this.opere);

  final String nome;
  final List<_GruppoOpera> opere;

  int get numeroCopie =>
      opere.fold(0, (somma, opera) => somma + opera.copie.length);
}

/// Raggruppamento Serie → Opera deciso su #141: le Opere senza Serie
/// formano il gruppo "Volumi unici", ordinato per ultimo. All'interno di
/// ogni Serie le Opere sono ordinate alfabeticamente, le copie per numero
/// (le copie senza numero, es. volumi unici, in coda).
List<_GruppoSerie> _raggruppaPerSerieEOpera(
  List<RigaCatalogoStampabile> righe,
) {
  const senzaSerie = 'Volumi unici';
  final perSerie = <String, Map<String, List<RigaCatalogoStampabile>>>{};
  for (final riga in righe) {
    final serie = riga.serieName ?? senzaSerie;
    final perOpera = perSerie.putIfAbsent(serie, () => {});
    perOpera.putIfAbsent(riga.operaTitolo, () => []).add(riga);
  }

  int confrontaNumero(RigaCatalogoStampabile a, RigaCatalogoStampabile b) {
    if (a.issueNumber == null && b.issueNumber == null) {
      return a.copiaId.compareTo(b.copiaId);
    }
    if (a.issueNumber == null) return 1;
    if (b.issueNumber == null) return -1;
    return a.issueNumber!.compareTo(b.issueNumber!);
  }

  final nomiSerie = perSerie.keys.toList()
    ..sort((a, b) {
      if (a == senzaSerie) return b == senzaSerie ? 0 : 1;
      if (b == senzaSerie) return -1;
      return a.compareTo(b);
    });

  return [
    for (final serie in nomiSerie)
      _GruppoSerie(serie, [
        for (final opera in perSerie[serie]!.keys.toList()..sort())
          _GruppoOpera(
            opera,
            perSerie[serie]![opera]!..sort(confrontaNumero),
          ),
      ]),
  ];
}

pw.Widget _intestazioneDocumento(
  int numeroCopie,
  DateTime dataGenerazione,
  pw.Font fontMono,
) {
  return pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 14),
    padding: const pw.EdgeInsets.only(bottom: 8),
    decoration: pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: _colInk, width: 1.5)),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'La mia collezione — schede',
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              '$numeroCopie copie · generato il ${_dataItaliana(dataGenerazione)}',
              style: pw.TextStyle(
                font: fontMono,
                fontSize: 9,
                color: _colInkSoft,
              ),
            ),
            pw.Text(
              'raggruppato per Serie → Opera',
              style: pw.TextStyle(
                font: fontMono,
                fontSize: 9,
                color: _colInkSoft,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

pw.Widget _piePagina(pw.Context context, pw.Font fontMono) {
  return pw.Container(
    margin: const pw.EdgeInsets.only(top: 5),
    padding: const pw.EdgeInsets.only(top: 5),
    decoration: pw.BoxDecoration(
      border: pw.Border(top: pw.BorderSide(color: _colLine, width: 0.75)),
    ),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'MyComicBrain — catalogo personale',
          style: pw.TextStyle(font: fontMono, fontSize: 8, color: _colInkSoft),
        ),
        pw.Text(
          'Pagina ${context.pageNumber}',
          style: pw.TextStyle(font: fontMono, fontSize: 8, color: _colInkSoft),
        ),
      ],
    ),
  );
}

List<pw.Widget> _sezioneSerie(
  _GruppoSerie gruppo,
  pw.Font fontRegular,
  pw.Font fontBold,
  pw.Font fontMono,
  Map<int, Uint8List> copertine,
) {
  return [
    pw.Container(
      margin: const pw.EdgeInsets.only(top: 12, bottom: 6),
      padding: const pw.EdgeInsets.only(bottom: 4),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _colLine, width: 0.75)),
      ),
      child: pw.RichText(
        text: pw.TextSpan(
          children: [
            pw.TextSpan(
              text: gruppo.nome.toUpperCase(),
              style: pw.TextStyle(
                font: fontBold,
                fontSize: 12,
                color: _colAccent,
                letterSpacing: 0.4,
              ),
            ),
            pw.TextSpan(
              text: '   ${gruppo.numeroCopie} copie',
              style: pw.TextStyle(
                font: fontRegular,
                fontSize: 10,
                color: _colInkSoft,
              ),
            ),
          ],
        ),
      ),
    ),
    for (final opera in gruppo.opere)
      for (final copia in opera.copie)
        _scheda(copia, fontRegular, fontBold, fontMono, copertine[copia.copiaId]),
  ];
}

pw.Widget _scheda(
  RigaCatalogoStampabile riga,
  pw.Font fontRegular,
  pw.Font fontBold,
  pw.Font fontMono,
  Uint8List? copertinaBytes,
) {
  final titolo = riga.issueNumberLabel != null
      ? '${riga.operaTitolo} #${riga.issueNumberLabel}'
      : riga.operaTitolo;

  return pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 8),
    padding: const pw.EdgeInsets.all(8),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: _colLine, width: 0.75),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 24 * PdfPageFormat.mm,
          child: pw.AspectRatio(
            aspectRatio: 2 / 3,
            child: _copertinaScheda(riga, fontMono, copertinaBytes),
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                titolo,
                style: pw.TextStyle(
                  font: fontBold,
                  fontSize: 12.5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              _tabellaCampi(riga, fontRegular, fontMono),
              if (riga.notes != null && riga.notes!.isNotEmpty) ...[
                pw.SizedBox(height: 3),
                pw.Text(
                  riga.notes!,
                  style: pw.TextStyle(
                    font: fontRegular,
                    fontSize: 9,
                    color: _colInkSoft,
                    fontStyle: pw.FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

pw.Widget _copertinaScheda(
  RigaCatalogoStampabile riga,
  pw.Font fontMono,
  Uint8List? copertinaBytes,
) {
  if (copertinaBytes != null) {
    try {
      return pw.ClipRRect(
        horizontalRadius: 3,
        verticalRadius: 3,
        child: pw.Image(pw.MemoryImage(copertinaBytes), fit: pw.BoxFit.cover),
      );
    } on Object {
      // Bytes non decodificabili come immagine: ricade sulla procedurale.
    }
  }

  final numero = riga.issueNumber ?? 0;
  final coppia =
      _paletteProcedurale[(riga.operaTitolo.length + numero) %
          _paletteProcedurale.length];
  return pw.Container(
    decoration: pw.BoxDecoration(
      color: PdfColor.fromInt(coppia.$1),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
    ),
    alignment: pw.Alignment.topRight,
    padding: const pw.EdgeInsets.all(2),
    child: riga.issueNumberLabel == null
        ? null
        : pw.Text(
            '#${riga.issueNumberLabel}',
            style: pw.TextStyle(
              font: fontMono,
              fontSize: 7,
              color: PdfColor.fromInt(coppia.$2),
            ),
          ),
  );
}

pw.Widget _tabellaCampi(
  RigaCatalogoStampabile riga,
  pw.Font fontRegular,
  pw.Font fontMono,
) {
  final formatoLabel = riga.format?.label ?? '';
  final annoFormato = [
    if (riga.year != null) riga.year.toString(),
    formatoLabel,
  ].where((v) => v.isNotEmpty).join(' · ');
  final autori = riga.autori.map((a) => a.name).join(', ');
  final prezzo = riga.purchasePrice == null
      ? ''
      : '${riga.purchasePrice!.toStringAsFixed(2)} €';

  final campi = <(String, String)>[
    ('Editore', riga.publisher ?? ''),
    ('Anno / Formato', annoFormato),
    ('Autori', autori),
    ('Condizione', riga.condition?.label ?? ''),
    ('Prezzo acquisto', prezzo),
    ('Posizione', riga.location ?? ''),
  ];

  pw.Widget cella((String, String) campo) {
    final (etichetta, valore) = campo;
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            etichetta.toUpperCase(),
            style: pw.TextStyle(
              font: fontMono,
              fontSize: 6.5,
              color: _colInkSoft,
              letterSpacing: 0.3,
            ),
          ),
          pw.Text(
            valore.isEmpty ? '—' : valore,
            style: pw.TextStyle(font: fontRegular, fontSize: 10),
          ),
        ],
      ),
    );
  }

  return pw.Table(
    columnWidths: const {0: pw.FlexColumnWidth(), 1: pw.FlexColumnWidth()},
    children: [
      for (var i = 0; i < campi.length; i += 2)
        pw.TableRow(
          children: [
            cella(campi[i]),
            if (i + 1 < campi.length) cella(campi[i + 1]) else pw.SizedBox(),
          ],
        ),
    ],
  );
}

String _dataItaliana(DateTime data) =>
    '${data.day.toString().padLeft(2, '0')}/'
    '${data.month.toString().padLeft(2, '0')}/'
    '${data.year}';
