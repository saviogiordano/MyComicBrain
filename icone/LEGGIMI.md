# MyComicBrain — icona app (direzione 1E, "balloon con retino")

Colori: ciano #22B8CF, inchiostro #0B1416.

## iOS
`ios/AppIcon.appiconset/` — trascina la cartella in Xcode (Assets.xcassets).
PNG quadrati full-bleed senza angoli arrotondati e senza alpha, come richiede App Store.
Marketing: `icon-1024.png`.

## Android
`android/res/` rispecchia la struttura delle risorse: copiala in `app/src/main/res/`.
- `mipmap-*/ic_launcher.png` — icona legacy (API < 26)
- `mipmap-*/ic_launcher_foreground.png` + `_background.png` — livelli dell'icona adattiva; il balloon sta nella safe zone centrale (66%), quindi regge crop tondo, squadrato e squircle
- `mipmap-anydpi-v26/ic_launcher.xml` — definizione adattiva
- `play-store-512.png` — scheda Play Store

## Note
Sotto i 40 px il segno perde la terza riga di testo nel balloon: se serve una versione ancora più piccola (badge, favicon 16 px) la preparo a parte.
