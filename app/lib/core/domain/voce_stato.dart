import 'package:mycomicbrain/core/domain/copia.dart';

/// Le 7 voci di stato di §8.3 come un solo elenco piatto — un selettore
/// mutuamente esclusivo per Copia, deciso in apertura della mappa #63: il
/// requisito le elenca insieme, ma il DB le modella con due enum separati
/// (`StatoCopia`/`StatoLettura`). Le prime 4 sono voci di lettura (forzano
/// `StatoCopia.posseduta`); le ultime 3 sono `StatoCopia` diretto e
/// nascondono lo stato di lettura.
enum VoceStato {
  daLeggere,
  inLettura,
  letto,
  daRileggere,
  prestato,
  venduto,
  mancante,
}

extension VoceStatoLabel on VoceStato {
  String get label => switch (this) {
    VoceStato.daLeggere => 'Da leggere',
    VoceStato.inLettura => 'In lettura',
    VoceStato.letto => 'Letto',
    VoceStato.daRileggere => 'Da rileggere',
    VoceStato.prestato => 'Prestato',
    VoceStato.venduto => 'Venduto',
    VoceStato.mancante => 'Mancante',
  };
}

/// Deriva la voce da mostrare come selezionata a partire dai due campi DB.
VoceStato voceStatoDi(StatoCopia status, StatoLettura? readingStatus) =>
    switch (status) {
      StatoCopia.prestata => VoceStato.prestato,
      StatoCopia.venduta => VoceStato.venduto,
      StatoCopia.persa => VoceStato.mancante,
      StatoCopia.posseduta => switch (readingStatus) {
        StatoLettura.daLeggere => VoceStato.daLeggere,
        StatoLettura.inLettura => VoceStato.inLettura,
        StatoLettura.letto => VoceStato.letto,
        StatoLettura.daRileggere => VoceStato.daRileggere,
        null => VoceStato.daLeggere,
      },
    };

/// I due campi DB da scrivere per una voce scelta — una voce di lettura
/// forza `posseduta` + quel `readingStatus`; le altre tre impostano lo
/// `status` diretto e azzerano il `readingStatus`.
({StatoCopia status, StatoLettura? readingStatus}) statoPerVoce(
  VoceStato voce,
) => switch (voce) {
  VoceStato.daLeggere => (
    status: StatoCopia.posseduta,
    readingStatus: StatoLettura.daLeggere,
  ),
  VoceStato.inLettura => (
    status: StatoCopia.posseduta,
    readingStatus: StatoLettura.inLettura,
  ),
  VoceStato.letto => (
    status: StatoCopia.posseduta,
    readingStatus: StatoLettura.letto,
  ),
  VoceStato.daRileggere => (
    status: StatoCopia.posseduta,
    readingStatus: StatoLettura.daRileggere,
  ),
  VoceStato.prestato => (status: StatoCopia.prestata, readingStatus: null),
  VoceStato.venduto => (status: StatoCopia.venduta, readingStatus: null),
  VoceStato.mancante => (status: StatoCopia.persa, readingStatus: null),
};
