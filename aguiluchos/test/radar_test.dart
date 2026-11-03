import 'dart:async';
import 'dart:io';

import 'package:aguiluchos/app/app_services.dart';
import 'package:aguiluchos/models/nido_grefa_model.dart';
import 'package:aguiluchos/screens/radar_screen.dart';
import 'package:aguiluchos/services/database_service.dart';
import 'package:aguiluchos/services/export_service.dart';
import 'package:aguiluchos/services/image_storage_service.dart';
import 'package:aguiluchos/services/location_service.dart';
import 'package:aguiluchos/services/sync_service.dart';
import 'package:aguiluchos/utils/geo.dart';
import 'package:aguiluchos/utils/radar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'helpers/fakes.dart';

const _lat = 40.4;
const _lon = -3.7;

NidoGrefaModel _nido(String etiqueta, double dLatM, double dLonM) {
  // ~111 195 m por grado de latitud; la longitud se corrige por el coseno.
  final lat = _lat + dLatM / 111195;
  final lon = _lon + dLonM / (111195 * 0.7627);
  return nidoDesdePosicion(lat, lon)..etiqueta = etiqueta;
}

Position _pos({double acc = 8}) => Position(
      latitude: _lat,
      longitude: _lon,
      timestamp: DateTime(2026, 11, 3),
      accuracy: acc,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

class _FakeLocation extends LocationService {
  final ctrl = StreamController<Position>.broadcast();
  @override
  Stream<Position> posiciones({int distanciaMinimaM = 3}) => ctrl.stream;
}

void main() {
  group('utilidades del radar', () {
    test('rumbo: norte 0°, este 90°, sur 180°, oeste 270°', () {
      expect(rumboGrados(40, -3, 41, -3), closeTo(0, 0.01));
      expect(rumboGrados(40, -3, 40, -2), closeTo(90, 0.6));
      expect(rumboGrados(40, -3, 39, -3), closeTo(180, 0.01));
      expect(rumboGrados(40, -3, 40, -4), closeTo(270, 0.6));
    });

    test('puntos cardinales de 8 vientos', () {
      expect(puntoCardinal(0), 'N');
      expect(puntoCardinal(359), 'N');
      expect(puntoCardinal(44), 'NE');
      expect(puntoCardinal(90), 'E');
      expect(puntoCardinal(135), 'SE');
      expect(puntoCardinal(180), 'S');
      expect(puntoCardinal(225), 'SO');
      expect(puntoCardinal(270), 'O');
      expect(puntoCardinal(315), 'NO');
      expect(puntoCardinal(-10), 'N');
    });

    test('formato de distancias y radios', () {
      expect(formatoDistancia(85.4), '85 m');
      expect(formatoDistancia(1400), '1,4 km');
      expect(formatoDistancia(12400), '12 km');
      expect(etiquetaRadio(500), '500 m');
      expect(etiquetaRadio(1000), '1 km');
      expect(etiquetaRadio(2000), '2 km');
      expect(etiquetaRadio(25000), '25 km');
    });

    test('radio más cercano en escala logarítmica', () {
      expect(indiceRadioCercano(100), 0);
      expect(indiceRadioCercano(1000), 3);
      expect(indiceRadioCercano(1300), 3);
      expect(indiceRadioCercano(1500), 4);
      expect(indiceRadioCercano(1900), 4);
      expect(indiceRadioCercano(999999), radiosRadarM.length - 1);
      expect(indiceRadioCercano(0), 0);
    });

    test('nidosEnRadio: filtra por radio, ordena y descarta borrados/sin coordenadas', () {
      final cerca = _nido('CERCA', 100, 0);
      final medio = _nido('MEDIO', 0, 600);
      final lejos = _nido('LEJOS', 5000, 0);
      final borrado = _nido('BORRADO', 10, 0)..isDeleted = true;
      final r = nidosEnRadio([lejos, medio, borrado, cerca, NidoGrefaModel()], _lat, _lon, 1000);
      expect(r.map((e) => e.nido.etiqueta), ['CERCA', 'MEDIO']);
      expect(r[0].metros, closeTo(100, 3));
      expect(r[0].rumbo, closeTo(0, 1));
      expect(r[1].metros, closeTo(600, 6));
      expect(r[1].rumbo, closeTo(90, 1));
      expect(nidosEnRadio([lejos], _lat, _lon, 1000), isEmpty);
    });

    test('posicionEnRadar: norte arriba (y negativa) y este a la derecha (x positiva)', () {
      final n = posicionEnRadar(500, 0, 1000);
      expect(n.x, closeTo(0, 1e-9));
      expect(n.y, closeTo(-0.5, 1e-9));
      final e = posicionEnRadar(1000, 90, 1000);
      expect(e.x, closeTo(1, 1e-9));
      expect(e.y, closeTo(0, 1e-9));
    });
  });

  group('pantalla del radar', () {
    late DatabaseService db;
    late SyncService sync;
    late Directory tmp;
    late _FakeLocation loc;

    setUpAll(() async {
      await initializeDateFormatting('es_ES');
    });

    tearDown(() async {
      await loc.ctrl.close();
      sync.dispose();
      await db.close();
      await tmp.delete(recursive: true);
    });

    Future<void> espera(WidgetTester tester) async {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump(const Duration(milliseconds: 100));
    }

    Future<void> arrancar(WidgetTester tester, List<NidoGrefaModel> nidos) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      loc = _FakeLocation();
      await tester.runAsync(() async {
        db = await openTestDb(FakeClock());
        tmp = await Directory.systemTemp.createTemp('radar_test');
        for (final n in nidos) {
          await db.guardar(n);
        }
      });
      sync = SyncService(db: db);
      await tester.pumpWidget(AppServices(
        db: db,
        sync: sync,
        images: ImageStorageService(baseDirectory: tmp),
        location: loc,
        export: ExportService(),
        child: const MaterialApp(
          locale: Locale('es', 'ES'),
          supportedLocales: [Locale('es', 'ES')],
          localizationsDelegates: [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: RadarScreen(animar: false),
        ),
      ));
      await espera(tester);
    }

    Future<void> cierra(WidgetTester tester) async {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump(const Duration(seconds: 15));
    }

    testWidgets('espera el GPS y luego muestra los nidos del radio; el radio se amplía y reduce', (tester) async {
      await arrancar(tester, [_nido('A-NORTE', 120, 0), _nido('B-ESTE', 0, 800), _nido('C-LEJOS', 3000, 0)]);
      expect(find.textContaining('Buscando tu posición'), findsOneWidget);

      loc.ctrl.add(_pos());
      await espera(tester);
      // Radio inicial: 1 km → A y B.
      expect(find.byKey(const Key('radar-vista')), findsOneWidget);
      expect(find.textContaining('2 nidos a menos de 1 km'), findsOneWidget);
      expect(find.textContaining('A-NORTE'), findsOneWidget);
      expect(find.textContaining('B-ESTE'), findsOneWidget);
      expect(find.textContaining('C-LEJOS'), findsNothing);

      // Reducir dos veces: 500 m y 250 m → solo A.
      await tester.tap(find.byKey(const Key('radar-reducir')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('radar-reducir')));
      await tester.pump();
      expect(find.text('Radio: 250 m'), findsOneWidget);
      expect(find.textContaining('1 nido a menos de 250 m'), findsOneWidget);
      expect(find.textContaining('B-ESTE'), findsNothing);

      // Ampliar hasta 5 km → los tres.
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byKey(const Key('radar-ampliar')));
        await tester.pump();
      }
      expect(find.text('Radio: 5 km'), findsOneWidget);
      expect(find.textContaining('3 nidos a menos de 5 km'), findsOneWidget);
      expect(find.textContaining('C-LEJOS'), findsOneWidget);
      await cierra(tester);
    });

    testWidgets('al pulsar un nido de la lista aparece su resumen con distancia y rumbo', (tester) async {
      final b = _nido('B-ESTE', 0, 800);
      await arrancar(tester, [b]);
      loc.ctrl.add(_pos());
      await espera(tester);

      expect(find.byKey(const Key('radar-seleccion')), findsNothing);
      await tester.tap(find.byKey(Key('radar-item-${b.id}')));
      await tester.pump();
      expect(find.byKey(const Key('radar-seleccion')), findsOneWidget);
      expect(find.textContaining('al E (90°)'), findsOneWidget);
      expect(find.byKey(const Key('radar-ficha')), findsOneWidget);
      await cierra(tester);
    });

    testWidgets('sin nidos en el radio sugiere ampliar', (tester) async {
      await arrancar(tester, [_nido('LEJOS', 8000, 0)]);
      loc.ctrl.add(_pos());
      await espera(tester);
      expect(find.textContaining('No hay nidos dentro de este radio'), findsOneWidget);
      expect(find.textContaining('ningún nido a menos de 1 km'), findsOneWidget);
      await cierra(tester);
    });

    testWidgets('si falla el GPS muestra el motivo y permite reintentar', (tester) async {
      await arrancar(tester, const []);
      loc.ctrl.addError(LocationException('El GPS está desactivado.'));
      await espera(tester);
      expect(find.text('El GPS está desactivado.'), findsOneWidget);
      expect(find.byKey(const Key('radar-reintentar')), findsOneWidget);
      await cierra(tester);
    });
  });
}
