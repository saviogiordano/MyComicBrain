import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/data/database.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final comicsRepositoryProvider = Provider<ComicsRepository>((ref) {
  return ComicsRepository(ref.watch(appDatabaseProvider));
});
