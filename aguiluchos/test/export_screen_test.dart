import 'dart:io';

import 'package:aguiluchos/app/app_services.dart';
import 'package:aguiluchos/screens/export_screen.dart';
import 'package:aguiluchos/services/database_service.dart';
import 'package:aguiluchos/services/export_service.dart';
import 'package:aguiluchos/services/image_storage_service.dart';
import 'package:aguiluchos/services/location_service.dart';
import 'package:aguiluchos/services/sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'helpers/fakes.dart';

void main() {
  late DatabaseService db;
  late SyncService sync;
  late Directory tmp;

  setUpAll(() async {
    await initializeDateFormatting('es_ES');
  });

  tearDown(() async {
    sync.dispose();
    await db.close();
    await tmp.delete(recursive: true);
  });

  testWidgets('Excel + PDF pregunta dónde guardar o compartir cada informe',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      db = await openTestDb(FakeClock());
      tmp = await Directory.systemTemp.createTemp('export_test');
      await db.guardar(nidoDeEjemplo());
    });
    sync = SyncService(db: db);

    await tester.pumpWidget(AppServices(
      db: db,
      sync: sync,
      images: ImageStorageService(baseDirectory: tmp),
      location: LocationService(),
      export: ExportService(),
      child: const MaterialApp(
        locale: Locale('es', 'ES'),
        supportedLocales: [Locale('es', 'ES')],
        localizationsDelegates: [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: ExportScreen(),
      ),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pump();

    await tester.tap(find.byKey(const Key('exportar-ambos')));
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byKey(const Key('entrega-guardar')).evaluate().isNotEmpty) break;
    }

    // Se ofrece elegir ubicación y compartir, y se listan ambos informes.
    expect(find.byKey(const Key('entrega-guardar')), findsOneWidget);
    expect(find.byKey(const Key('entrega-compartir')), findsOneWidget);
    expect(find.textContaining('nidos_aguiluchos_'), findsOneWidget);
    expect(find.textContaining('informe_aguiluchos_'), findsOneWidget);

    // Cierra la hoja sin elegir (no se abre ningún diálogo del sistema).
    await tester.tapAt(const Offset(10, 10));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('entrega-guardar')), findsNothing);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pump(const Duration(seconds: 15));
  });
}
