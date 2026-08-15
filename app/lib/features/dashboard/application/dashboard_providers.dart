import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/domain/dashboard_kpis.dart';

final dashboardKpisProvider = StreamProvider<DashboardKpis>((ref) {
  return ref.watch(comicsRepositoryProvider).watchDashboardKpis();
});

final serieIncompleteProvider = StreamProvider<List<SerieIncompleta>>((ref) {
  return ref.watch(comicsRepositoryProvider).watchSerieIncomplete();
});
