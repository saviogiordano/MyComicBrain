/// Genere dell'Edizione (§9, deciso su
/// [Personaggio e Genere: tag liberi o entità catalogabili?](https://github.com/saviogiordano/MyComicBrain/issues/84)):
/// enum chiuso, multi-valore per Edizione (relazione many-to-many, a
/// differenza di `FormatoEdizione` che è singolo).
enum GenereEdizione {
  supereroi,
  azioneAvventura,
  fantascienza,
  fantasy,
  horror,
  gialloNoir,
  commedia,
  drammatico,
  romantico,
  storico,
  sliceOfLife,
  eroticoAdulti,
}

extension GenereEdizioneLabel on GenereEdizione {
  String get label => switch (this) {
    GenereEdizione.supereroi => 'Supereroi',
    GenereEdizione.azioneAvventura => 'Azione/Avventura',
    GenereEdizione.fantascienza => 'Fantascienza',
    GenereEdizione.fantasy => 'Fantasy',
    GenereEdizione.horror => 'Horror',
    GenereEdizione.gialloNoir => 'Giallo/Noir',
    GenereEdizione.commedia => 'Commedia',
    GenereEdizione.drammatico => 'Drammatico',
    GenereEdizione.romantico => 'Romantico',
    GenereEdizione.storico => 'Storico',
    GenereEdizione.sliceOfLife => 'Slice of life',
    GenereEdizione.eroticoAdulti => 'Erotico/Adulti',
  };
}
