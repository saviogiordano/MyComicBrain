import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mycomicbrain/core/design_system/app_theme.dart';
import 'package:mycomicbrain/core/routing/router.dart';

void main() {
  runApp(const ProviderScope(child: MyComicBrainApp()));
}

class MyComicBrainApp extends StatelessWidget {
  const MyComicBrainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'MyComicBrain',
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: router,
    );
  }
}
