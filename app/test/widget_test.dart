import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/auth/session_controller.dart';
import 'package:mycomicbrain/main.dart';

import 'core/auth/fake_auth_gateway.dart';

void main() {
  testWidgets('app starts without throwing', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authGatewayProvider.overrideWithValue(FakeAuthGateway()),
          accountPreferencesProvider.overrideWithValue(PreferencesInMemoria()),
          haDatiLocaliProvider.overrideWithValue(() async => false),
        ],
        child: const MyComicBrainApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('Usa senza account'), findsOneWidget);
  });
}
