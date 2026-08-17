import 'package:image_cropper/image_cropper.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/core/domain/scansione.dart';

/// Avvolge `image_cropper` (scelto in #17) dietro un'interfaccia iniettabile
/// — stesso pattern di `ScansioneStorage` — così la coda di revisione (#24)
/// resta testabile senza passare dal platform channel nativo.
///
/// L'editor stesso è quello nativo del plugin (uCrop/TOCropViewController):
/// riquadro di ritaglio ad angoli trascinabili direttamente sopra la foto,
/// nessuna anteprima separata, rotazione integrata nella UI nativa — è
/// esattamente il comportamento deciso come R-A su #20, qui realizzato con
/// il pacchetto scelto invece che con un widget Flutter custom.
class ImageCropService {
  ImageCropService({Future<String?> Function(String sourcePath)? ritaglia})
    : _ritaglia = ritaglia ?? _ritagliaConEditorNativo;

  final Future<String?> Function(String sourcePath) _ritaglia;

  /// Apre l'editor di ritaglio/rotazione su [sourcePath]. Ritorna il percorso
  /// del file ritagliato (temporaneo, da spostare in storage permanente) o
  /// `null` se l'utente ha annullato — "Riscatta", nessuna Scansione va
  /// creata in quel caso (Q6 del grilling su #15).
  Future<String?> ritagliaFoto(String sourcePath) => _ritaglia(sourcePath);

  static Future<String?> _ritagliaConEditorNativo(String sourcePath) async {
    final risultato = await ImageCropper().cropImage(
      sourcePath: sourcePath,
      aspectRatio: const CropAspectRatio(ratioX: coverAspectRatio, ratioY: 1),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Ritaglia',
          toolbarColor: AppColors.surfaceDeepest,
          toolbarWidgetColor: AppColors.textPrimary,
          backgroundColor: AppColors.surfaceDeepest,
          activeControlsWidgetColor: AppColors.accent,
          cropFrameColor: AppColors.accent,
          statusBarLight: false,
          navBarLight: false,
          lockAspectRatio: true,
        ),
        IOSUiSettings(
          title: 'Ritaglia',
          doneButtonTitle: 'Conferma',
          cancelButtonTitle: 'Riscatta',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
          aspectRatioPickerButtonHidden: true,
        ),
      ],
    );
    return risultato?.path;
  }
}
