/// Ruolo di un Creator su una specifica Edizione (§8.1, deciso su #64):
/// enum chiuso con valvola di sfogo `altro` per crediti non standard
/// (adattamento, traduzione, crediti compositi).
enum RuoloCreator {
  sceneggiatore,
  disegnatore,
  inchiostratore,
  colorista,
  letterista,
  copertinista,
  altro,
}

/// Un Creator collegato a un'Edizione col relativo ruolo (§8.1, deciso su
/// #64), per il rendering della Scheda — proiezione di sola lettura di una
/// riga `ComicCreator` con il `name` del `Creator` già risolto via join.
typedef CreatorConRuolo = ({
  int comicCreatorId,
  int creatorId,
  String name,
  RuoloCreator ruolo,
});
