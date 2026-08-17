import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/data/image_crop_service.dart';
import 'package:mycomicbrain/core/data/scansione_storage.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final comicsRepositoryProvider = Provider<ComicsRepository>((ref) {
  return ComicsRepository(ref.watch(appDatabaseProvider));
});

final imageCropServiceProvider = Provider<ImageCropService>((ref) => ImageCropService());

final scansioneStorageProvider = Provider<ScansioneStorage>((ref) => ScansioneStorage());
