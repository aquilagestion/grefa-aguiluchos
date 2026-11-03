import 'package:aguiluchos/models/nido_filter.dart';
import 'package:aguiluchos/models/nido_grefa_model.dart';
import 'package:aguiluchos/services/database_service.dart';
import 'package:aguiluchos/utils/geografia.dart';
import 'package:aguiluchos/widgets/filtro_geografico.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fakes.dart';

NidoGrefaModel _n(String municipio, String provincia) =>
    nidoDeEjemplo(etiqueta: municipio.isEmpty ? 'X' : municipio, municipio: municipio)
      ..provincia = provincia;

void main() {
  final datos = [
    _n('Portillo de Toledo', 'Toledo'),
    _n('Pinto', 'Madrid'),
    _n('Guadalajara', 'Guadalajara'),
    _n('Sanabria', 'Zamora'),
    _n('LIMIA', 'Galicia'),
    _n('Fermoselle', 'orense'),
    _n('Rara', 'Atlantida'),
    _n('', ''),
  ];

  group('ubicación derivada', () {
    test('provincia -> comunidad, alias y comunidades en el campo provincia', () {
      expect(ubicacionDe(datos[0]),
          const Ubicacion('España', 'Castilla-La Mancha', 'Toledo', 'Portillo de Toledo'));
      expect(ubicacionDe(datos[1]).comunidad, 'Comunidad de Madrid');
      expect(ubicacionDe(datos[3]).comunidad, 'Castilla y León');
      // «Galicia» en provincia es una comunidad; LIMIA se sitúa en Ourense.
      expect(ubicacionDe(datos[4]), const Ubicacion('España', 'Galicia', 'Ourense', 'LIMIA'));
      expect(ubicacionDe(datos[5]).provincia, 'Ourense');
      expect(ubicacionDe(datos[5]).comunidad, 'Galicia');
      expect(ubicacionDe(datos[6]).provincia, 'Atlantida');
      expect(ubicacionDe(datos[6]).comunidad, sinDato);
      expect(ubicacionDe(datos[7]), const Ubicacion('España', sinDato, sinDato, sinDato));
    });

    test('normalizarGeo quita tildes y signos', () {
      expect(normalizarGeo('  Castilla-La  Mancha '), 'castilla la mancha');
      expect(normalizarGeo('Málaga'), 'malaga');
    });

    test('opciones en cascada', () {
      final todo = opcionesCascada(datos);
      expect(todo.paises, ['España']);
      expect(todo.comunidades, contains('Galicia'));
      expect(todo.localidades, contains('Pinto'));

      final clm = opcionesCascada(datos, pais: 'España', comunidad: 'Castilla-La Mancha');
      expect(clm.provincias, ['Guadalajara', 'Toledo']);
      expect(clm.localidades, ['Guadalajara', 'Portillo de Toledo']);

      final tol = opcionesCascada(datos, comunidad: 'Castilla-La Mancha', provincia: 'Toledo');
      expect(tol.localidades, ['Portillo de Toledo']);
    });

    test('agrupar por nivel ordena por tamaño', () {
      final g = agruparPorNivel(datos, 'comunidad');
      expect(g.firstWhere((e) => e.key == 'Galicia').value.length, 2);
      expect(g.first.value.length, greaterThanOrEqualTo(g.last.value.length));
    });

    test('sanearGeo limpia selecciones que ya no existen', () {
      const f = NidoFilter();
      final ok = f.conGeo(pais: 'España', comunidad: 'Galicia', provincia: 'Ourense', localidad: 'LIMIA');
      expect(sanearGeo(ok, datos), same(ok));

      final mal = f.conGeo(pais: 'España', comunidad: 'Galicia', provincia: 'Ourense', localidad: 'Borrada');
      final s = sanearGeo(mal, datos);
      expect(s.provincia, 'Ourense');
      expect(s.localidad, isNull);

      final peor = f.conGeo(pais: 'España', comunidad: 'Canarias', provincia: 'Las Palmas');
      final s2 = sanearGeo(peor, datos);
      expect(s2.comunidad, isNull);
      expect(s2.provincia, isNull);
    });

    test('copyWith conserva la ubicación; conGeo la sustituye', () {
      final f = const NidoFilter().conGeo(pais: 'España', comunidad: 'Galicia');
      expect(f.copyWith(query: 'x').comunidad, 'Galicia');
      expect(f.conGeo(pais: 'España').comunidad, isNull);
      expect(f.isEmpty, isFalse);
      expect(const NidoFilter().conGeo().isEmpty, isTrue);
    });
  });

  group('consultar por ubicación', () {
    late DatabaseService db;
    setUp(() async {
      db = await openTestDb(FakeClock());
      for (final n in datos) {
        await db.guardar(n);
      }
    });
    tearDown(() => db.close());

    Future<List<String>> loc(NidoFilter f) async =>
        ((await db.consultar(f)).map((n) => n.municipio ?? '').toList())..sort();

    test('país, comunidad, provincia y localidad', () async {
      expect((await db.consultar(const NidoFilter().conGeo(pais: 'España'))).length, datos.length);
      expect(await loc(const NidoFilter().conGeo(comunidad: 'Castilla-La Mancha')),
          ['Guadalajara', 'Portillo de Toledo']);
      expect(
          await loc(const NidoFilter().conGeo(comunidad: 'Castilla-La Mancha', provincia: 'Toledo')),
          ['Portillo de Toledo']);
      expect(await loc(const NidoFilter().conGeo(comunidad: 'Galicia')), ['Fermoselle', 'LIMIA']);
      expect(await loc(const NidoFilter().conGeo(localidad: 'Pinto')), ['Pinto']);
      expect(await loc(const NidoFilter().conGeo(provincia: 'Madrid', localidad: 'Guadalajara')), isEmpty);
    });
  });

  testWidgets('selectores en cascada: elegir comunidad filtra provincias y localidades', (tester) async {
    var filtro = const NidoFilter();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => SingleChildScrollView(
            child: FiltroGeografico(
              nidos: datos,
              filter: filtro,
              onChanged: (f) => setState(() => filtro = f),
            ),
          ),
        ),
      ),
    ));
    expect(find.text('País'), findsOneWidget);
    expect(find.text('Comunidad autónoma'), findsOneWidget);
    expect(find.text('Provincia'), findsOneWidget);
    expect(find.text('Localidad'), findsOneWidget);

    await tester.tap(find.byKey(const Key('geo-comunidad')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Castilla-La Mancha').last);
    await tester.pumpAndSettle();
    expect(filtro.comunidad, 'Castilla-La Mancha');
    expect(filtro.provincia, isNull);
    expect(opcionesCascada(datos, comunidad: filtro.comunidad).provincias, ['Guadalajara', 'Toledo']);
  });
}
