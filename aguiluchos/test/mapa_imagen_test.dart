import 'dart:convert';
import 'dart:typed_data';

import 'package:aguiluchos/models/nido_grefa_model.dart';
import 'package:aguiluchos/services/informe_tecnico.dart';
import 'package:aguiluchos/services/mapa_imagen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'helpers/fakes.dart';

NidoGrefaModel _n(String et, String mun, String prov, {String? res, double? x, double? y}) =>
    nidoDeEjemplo(etiqueta: et, municipio: mun)
      ..provincia = prov
      ..resultadoReproductivo = res
      ..coordenadaX = x
      ..coordenadaY = y;

Uint8List _teselaGris() {
  final t = img.Image(width: 256, height: 256);
  img.fill(t, color: img.ColorRgb8(200, 200, 200));
  return Uint8List.fromList(img.encodePng(t));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final datos = [
    _n('A1', 'Portillo de Toledo', 'Toledo', res: 'Éxito', x: 400000, y: 4390000),
    _n('A2', 'Portillo de Toledo', 'Toledo', res: 'Fracaso', x: 401000, y: 4391000),
    _n('B1', 'Pinto', 'Madrid', x: 445000, y: 4465000),
    _n('C1', 'Sin coordenadas', 'Madrid'),
  ];

  test('proyección y encuadre', () {
    final p0 = proyectar(0, 0, 0);
    expect((p0.x - 128).abs(), lessThan(1e-6));
    expect((p0.y - 128).abs(), lessThan(1e-6));

    const pts = [PuntoMapa(40.4, -3.7, 0, ''), PuntoMapa(39.9, -4.3, 0, '')];
    final e = encuadre(pts, ancho: 760, alto: 380);
    final a = proyectar(pts[0].lat, pts[0].lon, e.z);
    final b = proyectar(pts[1].lat, pts[1].lon, e.z);
    expect((a.x - b.x).abs(), lessThanOrEqualTo(760 - 92));
    expect((a.y - b.y).abs(), lessThanOrEqualTo(380 - 92));
    expect(encuadre([pts[0]], ancho: 760, alto: 380, zMax: 14).z, 14);
  });

  test('puntosDe ignora nidos sin coordenadas y colorea por resultado', () {
    final p = puntosDe(datos);
    expect(p.length, 3);
    expect(p[0].color, colorExito);
    expect(p[1].color, colorFracaso);
    expect(p[2].color, colorEnCurso);
  });

  test('genera mapas por nivel con teselas simuladas', () async {
    final pedidas = <String>[];
    final gen = GeneradorMapas(descarga: (z, x, y) async {
      pedidas.add('$z/$x/$y');
      return _teselaGris();
    });
    final hechos = <int>[];
    final mapas = await gen.generar(
      datos,
      {'general', 'comunidad', 'provincia', 'localidad'},
      progreso: (h, t) => hechos.add(t),
    );
    // general + 2 comunidades + 2 provincias + 2 localidades (el nido sin coordenadas no cuenta)
    expect(mapas.where((m) => m.nivel == 'general').length, 1);
    expect(mapas.where((m) => m.nivel == 'comunidad').map((m) => m.titulo).toSet(),
        {'Castilla-La Mancha', 'Comunidad de Madrid'});
    expect(mapas.where((m) => m.nivel == 'provincia').length, 2);
    expect(mapas.where((m) => m.nivel == 'localidad').length, 2);
    expect(mapas.first.n, 3);
    expect(pedidas, isNotEmpty);
    // JPEG válido
    final im = img.decodeJpg(mapas.first.bytes)!;
    expect(im.width, 760);
    expect(im.height, 400);
  });

  test('sin conexión dibuja cuadrícula y no falla', () async {
    final gen = GeneradorMapas(descarga: (z, x, y) async => null);
    final mapas = await gen.generar(datos, {'general', 'provincia'});
    expect(mapas.length, 3);
    expect(img.decodeJpg(mapas.first.bytes), isNotNull);
  });

  test('nivel sin ningún nido con coordenadas no genera mapa', () async {
    final gen = GeneradorMapas(descarga: (z, x, y) async => null);
    final mapas = await gen.generar([datos.last], {'general', 'comunidad'});
    expect(mapas, isEmpty);
  });

  test('el informe incrusta los mapas (HTML y PDF) y las secciones geográficas', () async {
    final gen = GeneradorMapas(descarga: (z, x, y) async => null);
    final mapas = await gen.generar(datos, {'general', 'comunidad'});
    final b = InformeBorrador(
      nidos: datos,
      titulo: 'T',
      referencia: 'R',
      fecha: DateTime(2026, 11, 2),
      secciones: {SeccionInforme.resumen, SeccionInforme.comunidades, SeccionInforme.provincias},
    )..mapas = mapas;
    final doc = InformeTecnico.construir(b);
    final html = InformeRender.html(doc);
    expect(html, contains('2. Mapas de localización'));
    expect(html, contains('3. Resultados por comunidad autónoma'));
    expect(html, contains('4. Resultados por provincia'));
    expect(html, contains('data:image/jpeg;base64,${base64Encode(mapas.first.bytes)}'));
    expect(html, contains('Por comunidad autónoma'));
    expect(html, contains('1 nido(s) sin coordenadas'));
    expect(html, contains('Castilla-La Mancha'));

    final pdf = await InformeRender.pdf(doc);
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
    final sinMapas = await InformeRender.pdf(InformeTecnico.construir(b..mapas = []));
    expect(pdf.length, greaterThan(sinMapas.length));
  });

  test('el texto de alcance cita localidades, provincias y comunidades', () {
    final b = InformeBorrador(nidos: datos, titulo: 'T', referencia: 'R', fecha: DateTime(2026, 11, 2));
    expect(b.alcance, contains('3 localidad(es)'));
    expect(b.alcance, contains('2 provincia(s) (Toledo, Madrid)'));
    expect(b.alcance, contains('2 comunidad(es) autónoma(s) (Castilla-La Mancha, Comunidad de Madrid)'));
  });
}
