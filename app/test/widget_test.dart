import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/main.dart';

void main() {
  testWidgets('app starts without throwing', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MyComicBrainApp()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
