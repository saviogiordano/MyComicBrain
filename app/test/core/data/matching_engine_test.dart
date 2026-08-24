import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/data/comic_vine_client.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/data/matching_engine.dart';
import 'package:mycomicbrain/core/domain/analisi_copertina.dart';
import 'package:mycomicbrain/core/domain/edizione_catalogo.dart';
import 'package:mycomicbrain/core/domain/identificazione.dart';

AnalisiCopertinaTableData _analisi({
  String? title,
  String? seriesName,
  String? issueNumberLabel,
  String? publisher,
  List<String> characters = const [],
  List<String> coverStyleTags = const [],
  List<String> visualElementTags = const [],
  String? recognizedPublisherLogo,
  String? recognizedSeriesLogo,
}) => AnalisiCopertinaTableData(
  id: 1,
  scansioneId: 1,
  title: title,
  seriesName: seriesName,
  issueNumberLabel: issueNumberLabel,
  publisher: publisher,
  characters: characters,
  coverStyleTags: coverStyleTags,
  visualElementTags: visualElementTags,
  recognizedPublisherLogo: recognizedPublisherLogo,
  recognizedSeriesLogo: recognizedSeriesLogo,
  status: StatoAnalisiCopertina.completata,
  createdAt: DateTime(2026),
);

EdizioneCatalogo _edizione({
  int edizioneId = 1,
  String title = 'Batman',
  int? serieId,
  String? seriesName,
  String? publisher,
  int? issueNumber,
  String? issueNumberLabel,
  String? coverImage,
}) => EdizioneCatalogo(
  edizioneId: edizioneId,
  title: title,
  serieId: serieId,
  seriesName: seriesName,
  publisher: publisher,
  issueNumber: issueNumber,
  issueNumberLabel: issueNumberLabel,
  coverImage: coverImage,
);

void main() {
  const motore = MatchingEngine();

  group('candidatiInterni', () {
    test('campi identici su tutti i lati producono il punteggio massimo', () {
      final analisi = _analisi(
        title: 'Batman',
        seriesName: 'Batman (1940)',
        issueNumberLabel: '42',
        publisher: 'DC Comics',
      );
      final edizione = _edizione(
        seriesName: 'Batman (1940)',
        publisher: 'DC Comics',
        issueNumberLabel: '42',
      );

      final candidati = motore.candidatiInterni(
        analisi: analisi,
        catalogo: [edizione],
        numeriPossedutiPerSerie: const {},
      );

      expect(candidati, hasLength(1));
      expect(candidati.single.punteggio, 100);
      expect(candidati.single.source, FonteCandidato.interno);
      expect(candidati.single.edizioneId, edizione.edizioneId);
    });

    test('un campo null in AnalisiCopertina è escluso, non penalizzato', () {
      // Solo seriesName è leggibile dall'OCR: gli altri pesi si
      // rinormalizzano su di esso, che combacia perfettamente.
      final analisi = _analisi(seriesName: 'Batman (1940)');
      final edizione = _edizione(
        seriesName: 'Batman (1940)',
        publisher: 'DC Comics',
        issueNumberLabel: '42',
      );

      final candidati = motore.candidatiInterni(
        analisi: analisi,
        catalogo: [edizione],
        numeriPossedutiPerSerie: const {},
      );

      expect(candidati.single.punteggio, 100);
    });

    test('nessun campo comparabile su nessun lato produce punteggio zero, escluso', () {
      final analisi = _analisi();
      final edizione = _edizione(seriesName: 'Batman (1940)');

      final candidati = motore.candidatiInterni(
        analisi: analisi,
        catalogo: [edizione],
        numeriPossedutiPerSerie: const {},
      );

      expect(candidati, isEmpty);
    });

    test('sotto la soglia minima il candidato non viene proposto', () {
      final analisi = _analisi(title: 'Batman', seriesName: 'Batman (1940)');
      final edizione = _edizione(title: 'Zzzzzzz', seriesName: 'Qqqqqqq');

      final candidati = motore.candidatiInterni(
        analisi: analisi,
        catalogo: [edizione],
        numeriPossedutiPerSerie: const {},
      );

      expect(candidati, isEmpty);
    });

    test('il boost CV corrobora un match testuale parziale senza ribaltarlo da solo', () {
      final analisiSenzaBoost = _analisi(title: 'Batman', seriesName: 'Detective Comic');
      final analisiConBoost = _analisi(
        title: 'Batman',
        seriesName: 'Detective Comic',
        characters: const ['Batman', 'Joker'],
        recognizedPublisherLogo: 'DC Comics',
      );
      final edizione = _edizione(seriesName: 'Detective Comics', publisher: 'DC Comics');

      final senzaBoost = motore.candidatiInterni(
        analisi: analisiSenzaBoost,
        catalogo: [edizione],
        numeriPossedutiPerSerie: const {},
      );
      final conBoost = motore.candidatiInterni(
        analisi: analisiConBoost,
        catalogo: [edizione],
        numeriPossedutiPerSerie: const {},
      );

      expect(senzaBoost, hasLength(1));
      expect(conBoost, hasLength(1));
      expect(conBoost.single.punteggio, greaterThan(senzaBoost.single.punteggio));
      // Il boost da solo (nessun segnale testuale) non basta a superare la soglia.
      final soloTag = motore.candidatiInterni(
        analisi: _analisi(characters: const ['Batman']),
        catalogo: [_edizione(title: 'Qualcosa di completamente diverso')],
        numeriPossedutiPerSerie: const {},
      );
      expect(soloTag, isEmpty);
    });

    test('il bonus di contesto scatta solo per un numero adiacente a quelli posseduti', () {
      // Nome OCR leggermente diverso, così il punteggio testuale resta
      // sotto 100 e lascia spazio al bonus di contesto per differenziare.
      final analisi = _analisi(seriesName: 'Spiderman');
      final edizioneAdiacente = _edizione(
        title: 'Spider-Man',
        seriesName: 'Spider-Man',
        serieId: 10,
        issueNumber: 4,
      );
      final edizioneLontana = _edizione(
        edizioneId: 2,
        title: 'Spider-Man',
        seriesName: 'Spider-Man',
        serieId: 10,
        issueNumber: 40,
      );

      final candidati = motore.candidatiInterni(
        analisi: analisi,
        catalogo: [edizioneAdiacente, edizioneLontana],
        numeriPossedutiPerSerie: {
          10: {1, 2, 3},
        },
      );

      final adiacente = candidati.firstWhere((c) => c.edizioneId == 1);
      final lontana = candidati.firstWhere((c) => c.edizioneId == 2);
      expect(adiacente.punteggio, greaterThan(lontana.punteggio));
    });

    test('ordina per punteggio decrescente e taglia a massimoCandidati', () {
      final analisi = _analisi(title: 'Batman', seriesName: 'Batman', issueNumberLabel: '5');
      final catalogo = [
        for (var i = 0; i < MatchingEngine.massimoCandidati + 3; i++)
          _edizione(edizioneId: i, seriesName: 'Batman', issueNumberLabel: '$i'),
      ];

      final candidati = motore.candidatiInterni(
        analisi: analisi,
        catalogo: catalogo,
        numeriPossedutiPerSerie: const {},
      );

      expect(candidati.length, MatchingEngine.massimoCandidati);
      expect(candidati.first.edizioneId, 5, reason: "l'etichetta identica al numero 5 vince");
      for (var i = 1; i < candidati.length; i++) {
        expect(candidati[i - 1].punteggio, greaterThanOrEqualTo(candidati[i].punteggio));
      }
    });
  });

  group('candidatiEsterni', () {
    test('genera un candidato esterno senza edizioneId', () {
      final analisi = _analisi(title: 'Amazing Fantasy', seriesName: 'Amazing Fantasy');
      const issue = ComicVineIssueMatch(
        id: 111,
        name: 'Amazing Fantasy',
        issueNumber: '15',
        volumeName: 'Amazing Fantasy',
        coverImageUrl: 'https://comicvine.example/15.jpg',
        siteDetailUrl: 'https://comicvine.example/15',
        description: 'Il primo apparire di Spider-Man.',
      );

      final candidati = motore.candidatiEsterni(
        analisi: analisi,
        risultati: const [issue],
        catalogo: const [],
        numeriPossedutiPerSerie: const {},
      );

      expect(candidati, hasLength(1));
      expect(candidati.single.source, FonteCandidato.esterno);
      expect(candidati.single.edizioneId, isNull);
      expect(candidati.single.coverImageUrl, 'https://comicvine.example/15.jpg');
      expect(candidati.single.description, 'Il primo apparire di Spider-Man.');
      expect(candidati.single.punteggio, 100);
    });

    test(
      'il bonus di contesto scatta anche su un volume ComicVine che combacia con una Serie nota',
      () {
        // Titolo OCR leggermente diverso dal nome del volume, così il
        // punteggio testuale resta sotto 100 e lascia spazio al bonus di
        // contesto per fare la differenza fra i due candidati.
        final analisi = _analisi(seriesName: 'Spiderman');
        const issueAdiacente = ComicVineIssueMatch(
          id: 1,
          name: 'Spider-Man',
          issueNumber: '4',
          volumeName: 'Spider-Man',
          coverImageUrl: null,
          siteDetailUrl: 'https://comicvine.example/1',
          description: null,
        );
        const issueLontana = ComicVineIssueMatch(
          id: 2,
          name: 'Spider-Man',
          issueNumber: '40',
          volumeName: 'Spider-Man',
          coverImageUrl: null,
          siteDetailUrl: 'https://comicvine.example/2',
          description: null,
        );
        final catalogo = [_edizione(seriesName: 'Spider-Man', serieId: 10)];

        final candidati = motore.candidatiEsterni(
          analisi: analisi,
          risultati: const [issueAdiacente, issueLontana],
          catalogo: catalogo,
          numeriPossedutiPerSerie: {
            10: {1, 2, 3},
          },
        );

        final adiacente = candidati.firstWhere((c) => c.issueNumberLabel == '4');
        final lontana = candidati.firstWhere((c) => c.issueNumberLabel == '40');
        expect(adiacente.punteggio, greaterThan(lontana.punteggio));
      },
    );
  });
}
