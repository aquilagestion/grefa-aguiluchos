import 'dart:io';

import 'package:aguiluchos/app/aguiluchos_app.dart';
import 'package:aguiluchos/models/nido_grefa_model.dart';
import 'package:aguiluchos/services/database_service.dart';
import 'package:aguiluchos/services/image_storage_service.dart';
import 'package:aguiluchos/services/location_service.dart';
import 'package:aguiluchos/services/sync_service.dart';
import 'package:aguiluchos/utils/geo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'helpers/fakes.dart';

class _FakeLocation extends LocationService {
  _FakeLocation({this.pos, this.error});
  final Position? pos;
  final String? error;
  @override
  Future<Position> posicionActual() async {
    if (error != null) throw LocationException(error!);
    return pos!;
  }
}

Position _pos(double lat, double lon, {double acc = 5}) => Position(
      latitude: lat,
      longitude: lon,
      timestamp: DateTime(2026, 11, 2),
      accuracy: acc,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

void main() {
  group('utilidades geográficas', () {
    test('distancia: 1 grado de latitud son ~111 km', () {
      final d = distanciaMetros(40, -3, 41, -3);
      expect(d, closeTo(111195, 300));
      expect(distanciaMetros(40.4, -3.7, 40.4, -3.7), 0);
    });

    test('nido más cercano dentro del radio, ignorando borrados', () {
      final a = nidoDesdePosicion(40.4000, -3.7000)..etiqueta = 'A';
      final b = nidoDesdePosicion(40.4001, -3.7000)..etiqueta = 'B'; // ~11 m
      final borrado = nidoDesdePosicion(40.40001, -3.7000)
        ..etiqueta = 'X'
        ..isDeleted = true;
      final lejos = nidoDesdePosicion(41, -3.7)..etiqueta = 'LEJOS';
      final r = nidoMasCercano([lejos, borrado, b, a], 40.4, -3.7);
      expect(r!.nido.etiqueta, 'A');
      expect(r.metros, lessThan(1));
      expect(nidoMasCercano([lejos], 40.4, -3.7), isNull);
      expect(nidoMasCercano([NidoGrefaModel()], 40.4, -3.7), isNull);
    });

    test('nido desde posición: UTM y enlace de Google Maps', () {
      final n = nidoDesdePosicion(40.4168, -3.7038);
      expect(n.tieneCoordenadas, isTrue);
      expect(n.latLon!.lat, closeTo(40.4168, 0.0001));
      expect(n.latLon!.lon, closeTo(-3.7038, 0.0001));
      expect(n.googleMapsUrl, contains('40.4168,-3.7038'));
    });
  });

  group('botón «Nido en mi posición»', () {
    late DatabaseService db;
    late SyncService sync;
    late Directory tmp;

    setUpAll(() async {
      await initializeDateFormatting('es_ES');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => Directory.systemTemp.path,
      );
    });

    tearDown(() async {
      sync.dispose();
      await db.close();
      await tmp.delete(recursive: true);
    });

    Future<void> arrancar(WidgetTester tester, LocationService loc,
        {List<NidoGrefaModel> previos = const []}) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        db = await openTestDb(FakeClock());
        tmp = await Directory.systemTemp.createTemp('gps_test');
        for (final n in previos) {
          await db.guardar(n);
        }
      });
      sync = SyncService(db: db);
      await tester.pumpWidget(AguiluchosApp(
        db: db,
        sync: sync,
        images: ImageStorageService(baseDirectory: tmp),
        location: loc,
      ));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump();
    }

    Future<void> esperar(WidgetTester tester) async {
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> drenar(WidgetTester tester) async {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump(const Duration(seconds: 15));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump(const Duration(seconds: 15));
    }

    testWidgets('captura la posición y abre un nido nuevo con las coordenadas', (tester) async {
      await arrancar(tester, _FakeLocation(pos: _pos(40.4168, -3.7038)));
      expect(find.byKey(const Key('fab-nido-gps')), findsOneWidget);

      await tester.tap(find.byKey(const Key('fab-nido-gps')));
      await esperar(tester);

      expect(find.text('Nuevo nido'), findsOneWidget);
      final esperado = nidoDesdePosicion(40.4168, -3.7038);
      expect(find.textContaining(esperado.coordenadaX!.round().toString()), findsWidgets);
      expect(find.textContaining(esperado.coordenadaY!.round().toString()), findsWidgets);
      await drenar(tester);
    });

    testWidgets('si ya hay un nido a pocos metros pide confirmación', (tester) async {
      final existente = nidoDesdePosicion(40.4168, -3.7038)..etiqueta = 'YA-EXISTE';
      await arrancar(tester, _FakeLocation(pos: _pos(40.41681, -3.7038)), previos: [existente]);

      await tester.tap(find.byKey(const Key('fab-nido-gps')));
      await esperar(tester);
      expect(find.textContaining('Ya existe el nido YA-EXISTE'), findsOneWidget);

      await tester.tap(find.byKey(const Key('gps-cancelar')));
      await esperar(tester);
      expect(find.text('Nuevo nido'), findsNothing);

      await tester.tap(find.byKey(const Key('fab-nido-gps')));
      await esperar(tester);
      await tester.tap(find.byKey(const Key('gps-crear')));
      await esperar(tester);
      expect(find.text('Nuevo nido'), findsOneWidget);
      await drenar(tester);
    });

    testWidgets('precisión baja: avisa antes de crear', (tester) async {
      await arrancar(tester, _FakeLocation(pos: _pos(40.5, -3.5, acc: 80)));
      await tester.tap(find.byKey(const Key('fab-nido-gps')));
      await esperar(tester);
      expect(find.textContaining('precisión del GPS es baja (±80 m)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('gps-cancelar')));
      await esperar(tester);
      await drenar(tester);
    });

    testWidgets('GPS desactivado: muestra el motivo y no abre el formulario', (tester) async {
      await arrancar(tester, _FakeLocation(error: 'El GPS está desactivado.'));
      await tester.tap(find.byKey(const Key('fab-nido-gps')));
      await esperar(tester);
      expect(find.text('El GPS está desactivado.'), findsOneWidget);
      expect(find.text('Nuevo nido'), findsNothing);
      await drenar(tester);
    });
  });
}
