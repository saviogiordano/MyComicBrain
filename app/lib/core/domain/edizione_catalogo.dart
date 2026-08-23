/// Una riga del catalogo interno (Opera + Serie già risolte via join) letta
/// per il motore di matching dell'Identificazione (§6.3, deciso su #52) —
/// proiezione di sola lettura, distinta dai tipi di scrittura di
/// `ComicsRepository` (`aggiungiOpera`/`aggiungiEdizione`/...).
class EdizioneCatalogo {
  const EdizioneCatalogo({
    required this.edizioneId,
    required this.title,
    required this.serieId,
    required this.seriesName,
    required this.publisher,
    required this.issueNumber,
    required this.issueNumberLabel,
    required this.coverImage,
  });

  final int edizioneId;
  final String title;
  final int? serieId;
  final String? seriesName;
  final String? publisher;
  final int? issueNumber;
  final String? issueNumberLabel;
  final String? coverImage;
}
