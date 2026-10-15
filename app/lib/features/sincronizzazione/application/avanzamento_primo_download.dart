/// I passi del primo download: le pagine di `cambiamenti_da`, poi la
/// scrittura nella Replica (il pull scrive solo dopo l'ultima pagina).
enum PassoPrimoDownload { scarico, salvo }

/// Quanto manca al primo download (prototipo #201, punto 3): le righe
/// arrivate sul totale delle tabelle replicate, raccontate in fumetti
/// ("N di M fumetti").
class AvanzamentoPrimoDownload {
  const AvanzamentoPrimoDownload._({
    required this.frazione,
    required this.fumetti,
    required this.passo,
  });

  /// [righe] sono quelle arrivate finora (null prima della prima pagina),
  /// [dimensioni] quelle della collezione sul server, se si conoscono.
  factory AvanzamentoPrimoDownload.da({
    required int? righe,
    required ({int righe, int fumetti})? dimensioni,
  }) {
    final arrivate = righe ?? 0;
    if (dimensioni == null) {
      return const AvanzamentoPrimoDownload._(
        frazione: null,
        fumetti: null,
        passo: PassoPrimoDownload.scarico,
      );
    }
    final frazione = dimensioni.righe == 0
        ? 0.0
        : (arrivate / dimensioni.righe).clamp(0.0, 1.0);
    final completo = dimensioni.righe > 0 && arrivate >= dimensioni.righe;
    return AvanzamentoPrimoDownload._(
      frazione: frazione,
      fumetti: (
        scaricati: (dimensioni.fumetti * frazione).round(),
        totale: dimensioni.fumetti,
      ),
      passo: completo ? PassoPrimoDownload.salvo : PassoPrimoDownload.scarico,
    );
  }

  /// In [0, 1]; null se il totale non si conosce.
  final double? frazione;
  final ({int scaricati, int totale})? fumetti;
  final PassoPrimoDownload passo;

  int? get percentuale => frazione == null ? null : (frazione! * 100).round();
}
