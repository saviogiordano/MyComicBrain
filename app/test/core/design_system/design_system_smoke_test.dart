import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';

void main() {
  testWidgets('base components render on AppTheme.dark without throwing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: ListView(
            children: [
              const SectionHeader(label: 'la tua collezione'),
              KpiCard(value: '87', label: 'serie', onTap: () {}),
              const KpiCard(value: '23', label: 'duplicati', valueColor: AppColors.amber),
              Row(
                children: [
                  AppChip(label: 'Tutti', selected: true, onTap: () {}),
                  AppChip(label: 'Duplicati', selected: false, onTap: () {}),
                ],
              ),
              const AppProgressBar(value: 0.6),
              const AppCard(child: Text('contenuto')),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('LA TUA COLLEZIONE'), findsOneWidget);
    expect(find.text('87'), findsOneWidget);
    expect(find.text('contenuto'), findsOneWidget);
  });
}
