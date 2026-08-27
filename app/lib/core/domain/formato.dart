/// Formato fisico di stampa dell'Edizione (§9, deciso su
/// [Formato: valori esatti dell'enum](https://github.com/saviogiordano/MyComicBrain/issues/83)):
/// enum chiuso, valore singolo, nullable — distinto da Tipo di stampa
/// (prima stampa/ristampa/variant, non la forma fisica). Il digitale è
/// escluso dall'enum: rompe le assunzioni di possesso fisico su cui si
/// basano Copia/Condizione/Posizione.
enum FormatoEdizione {
  spillato,
  bonellide,
  brossurato,
  cartonato,
  tankobon,
  omnibus,
}

extension FormatoEdizioneLabel on FormatoEdizione {
  String get label => switch (this) {
    FormatoEdizione.spillato => 'Spillato',
    FormatoEdizione.bonellide => 'Bonellide',
    FormatoEdizione.brossurato => 'Brossurato',
    FormatoEdizione.cartonato => 'Cartonato',
    FormatoEdizione.tankobon => 'Tankōbon',
    FormatoEdizione.omnibus => 'Omnibus',
  };
}
