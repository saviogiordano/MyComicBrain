# MyComicBrain — icona 06 per Flutter

## Installazione diretta (nessuna dipendenza)
1. Fai una copia delle icone esistenti del progetto.
2. Copia il contenuto della cartella `ios/Runner/Assets.xcassets/AppIcon.appiconset/` nella cartella omonima del progetto, sostituendo i file e Contents.json.
3. Copia il contenuto di `android/app/src/main/res/` nella stessa cartella del progetto, unendo le cartelle e sostituendo i file omonimi.
4. Verifica che AndroidManifest.xml usi `android:icon="@mipmap/ic_launcher"`. Se è presente un attributo `android:roundIcon` che punta a un'altra icona, rimuovilo oppure impostalo a `@mipmap/ic_launcher`.
5. In Xcode il set di icone deve chiamarsi `AppIcon`.
6. Esegui `flutter clean`, `flutter pub get`, poi `flutter run`. Se il launcher mostra ancora la vecchia icona, disinstalla e reinstalla l'app (la disinstallazione elimina i dati locali).

## Contenuto
- iOS: PNG per iPhone, iPad e App Store, con Contents.json; immagini opache.
- Android: icone legacy nelle cinque densità e adaptive icon da Android 8 con livelli foreground/background. Le maschere vengono applicate dal sistema.
- assets/icon/mycomicbrain-06.png: master raster quadrato 1024×1024.
- store/: esportazioni per gli store.

## Qualità e provenienza
Il disegno è estratto dalla numero 06 della tavola turchese selezionata. L'originale nella tavola è di circa 200 pixel: il master 1024 è un ingrandimento, non un originale vettoriale o una rigenerazione ad alta definizione. I margini sono stati adattati per le maschere di sistema. La resa va controllata sul dispositivo, soprattutto prima della pubblicazione sugli store.

Riferimenti: https://developer.apple.com/documentation/xcode/configuring-your-app-icon e https://developer.android.com/develop/ui/compose/system/icon_design_adaptive
