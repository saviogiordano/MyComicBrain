import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mycomicbrain/core/data/comics_repository.dart';
import 'package:mycomicbrain/core/data/database.dart';
import 'package:mycomicbrain/core/data/providers.dart';
import 'package:mycomicbrain/core/design_system/design_system.dart';
import 'package:mycomicbrain/core/domain/copia.dart';
import 'package:mycomicbrain/core/domain/formato.dart';
import 'package:mycomicbrain/features/collezione/presentation/collezione_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppDatabase db;
  late ComicsRepository repository;
  late SharedPreferences sharedPreferences;

  setUp(() async {
    db = AppDatabase(
      DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
    );
    repository = ComicsRepository(db);
    SharedPreferences.setMockInitialValues({});
    sharedPreferences = await SharedPreferences.getInstance();
  });

  tearDown(() => db.close());

  Future<int> edizionePosseduta({
    required String titolo,
    String? serieName,
    String? publisher,
    String? language,
    FormatoEdizione? format,
  }) async {
    int? serieId;
    if (serieName != null) serieId = await repository.aggiungiSerie(name: serieName);
    final operaId = await repository.aggiungiOpera(title: titolo);
    final edizioneId = await repository.aggiungiEdizione(
      operaId: operaId,
      serieId: serieId,
      publisher: publisher,
      language: language,
      format: format,
    );
    await repository.aggiungiCopia(edizioneId: edizioneId, status: StatoCopia.posseduta);
    return edizioneId;
  }

  Future<void> pumpCollezione(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/collezione',
      routes: [
        GoRoute(path: '/collezione', builder: (context, state) => const CollezionePage()),
        GoRoute(path: '/scheda/:id', builder: (context, state) => const Scaffold(body: Text('Scheda'))),
        GoRoute(path: '/scansione', builder: (context, state) => const Scaffold(body: Text('Scansione'))),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          comicsRepositoryProvider.overrideWithValue(repository),
          sharedPreferencesProvider.overrideWithValue(sharedPreferences),
        ],
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets("collezione vuota: mostra l'invito a scansionare il primo fumetto", (tester) async {
    await pumpCollezione(tester);

    expect(find.text('Nessun fumetto in collezione'), findsOneWidget);
    expect(find.text('Scansiona il primo fumetto'), findsOneWidget);
  });

  testWidgets('con Edizioni possedute: mostra il conteggio e le card in griglia', (tester) async {
    await edizionePosseduta(titolo: 'Dylan Dog', serieName: 'Dylan Dog', publisher: 'Bonelli');
    await edizionePosseduta(titolo: 'Watchmen', publisher: 'Panini');

    await pumpCollezione(tester);

    expect(find.text('2 fumetti'), findsOneWidget);
    // Il titolo compare più volte (copertina procedurale, titolo card,
    // eventuale sottotitolo con la Serie): basta che compaia, non contarlo.
    expect(find.text('Dylan Dog'), findsWidgets);
    expect(find.text('Watchmen'), findsWidgets);
  });

  testWidgets('apre il pannello "Filtri e ordina" con i 12 assi e il blocco di ordinamento', (tester) async {
    await edizionePosseduta(titolo: 'Dylan Dog', serieName: 'Dylan Dog', publisher: 'Bonelli');

    await pumpCollezione(tester);

    await tester.tap(find.text('Filtri e ordina'));
    await tester.pumpAndSettle();

    expect(find.text('Serie'), findsWidgets);
    expect(find.text('Editore'), findsWidgets);
    expect(find.text('Genere'), findsWidgets);
    expect(find.text('Ordina per'), findsOneWidget);
    expect(find.text('Ricorda filtri e ordinamento'), findsOneWidget);
  });

  testWidgets('filtro senza risultati: mostra il secondo stato vuoto con "Rimuovi filtri"', (tester) async {
    // Combinazione impossibile nel dataset: nessuna Edizione Giapponese è
    // anche Cartonata — stesso scenario "③" del prototipo #96.
    await edizionePosseduta(titolo: 'Dylan Dog', language: 'Italiano', format: FormatoEdizione.cartonato);
    await edizionePosseduta(titolo: 'Berserk', language: 'Giapponese', format: FormatoEdizione.brossurato);

    await pumpCollezione(tester);
    await tester.tap(find.text('Filtri e ordina'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Giapponese'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cartonato'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mostra 0 risultati'));
    await tester.pumpAndSettle();

    expect(find.text('Nessun fumetto corrisponde ai filtri'), findsOneWidget);
    expect(find.text('Rimuovi filtri'), findsOneWidget);
  });
}
