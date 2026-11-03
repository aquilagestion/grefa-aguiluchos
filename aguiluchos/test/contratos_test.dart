import 'dart:io';

import 'package:aguiluchos/models/contratos.dart';
import 'package:aguiluchos/models/nido_grefa_model.dart';
import 'package:aguiluchos/services/contratos_service.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> crudos({String estado = 'firmado', String? hasta = '2027-06-30'}) => {
      'propietarios_grefa': [
        {'id': 'pr1', 'nombre': 'Persona Ficticia Uno', 'tipo': 'particular', 'telefono': '600 000 111'},
      ],
      'parcelas_grefa': [
        {
          'id': 'pa1', 'municipio': 'Madrid', 'provincia': 'Madrid', 'sigpac_poligono': '10',
          'sigpac_parcela': '21', 'sigpac_recinto': '1', 'referencia_catastral': '28 079-A.001',
          'superficie_ha': 5.5, 'lat': 40.4, 'lon': -3.7,
        },
        {'id': 'pa2', 'municipio': 'Getafe', 'sigpac_poligono': '3', 'sigpac_parcela': '4'},
      ],
      'parcela_propietarios_grefa': [
        {'parcela_id': 'pa1', 'propietario_id': 'pr1'},
      ],
      'nido_parcela_grefa': [
        {'nido_id': 'n-vinculado', 'parcela_id': 'pa1'},
      ],
      'contratos_grefa': [
        {
          'id': 'c1', 'propietario_id': 'pr1', 'campana': 2025, 'estado': estado,
          'fecha_firma': '2025-06-16', 'vigencia_hasta': hasta,
        },
      ],
      'contrato_parcelas_grefa': [
        {'id': 'l1', 'contrato_id': 'c1', 'parcela_id': 'pa1', 'campana': 2025, 'ayudas': [1, 4]},
      ],
    };

NidoGrefaModel nido(String id, {String? refCat, int campana = 2025}) => NidoGrefaModel(id: id)
  ..etiqueta = id
  ..referenciaCatastral = refCat
  ..fechaIncubacion = DateTime(campana, 5, 10);

class _Remoto implements ContratosRemote {
  _Remoto(this.respuesta);
  Object respuesta; // Map o excepción
  int llamadas = 0;

  @override
  Future<Map<String, List<Map<String, dynamic>>>> descargar() async {
    llamadas++;
    final r = respuesta;
    if (r is Exception) throw r;
    return (r as Map<String, dynamic>).map((k, v) =>
        MapEntry(k, [for (final f in v as List) Map<String, dynamic>.from(f as Map)]));
  }
}

void main() {
  final hoy = DateTime(2026, 11, 3);

  group('semáforo de contrato', () {
    test('nido vinculado con convenio firmado y vigente', () {
      final d = DatosContratos.fromRaw(crudos());
      final e = d.estadoDeNido(nido('n-vinculado'), hoy);
      expect(e.codigo, Semaforo.firmado);
      expect(e.parcela?.id, 'pa1');
      expect(e.convenio?.id, 'c1');
      expect(d.titularesDe('pa1').single.nombre, 'Persona Ficticia Uno');
    });

    test('sin vínculo, se asocia por referencia catastral', () {
      final d = DatosContratos.fromRaw(crudos());
      expect(d.estadoDeNido(nido('x', refCat: '28079a001'), hoy).parcela?.id, 'pa1');
      expect(d.estadoDeNido(nido('y'), hoy).codigo, Semaforo.sinparcela);
    });

    test('otra campaña o convenio rechazado: sin contrato', () {
      final d = DatosContratos.fromRaw(crudos());
      expect(d.estadoDeNido(nido('n-vinculado', campana: 2024), hoy).codigo, Semaforo.sin);
      final r = DatosContratos.fromRaw(crudos(estado: 'rechazado'));
      expect(r.estadoDeNido(nido('n-vinculado'), hoy).codigo, Semaforo.sin);
    });

    test('caducidad: pasada, próxima y lejana', () {
      expect(DatosContratos.fromRaw(crudos(hasta: '2026-10-01')).estadoDeNido(nido('n-vinculado'), hoy).codigo,
          Semaforo.caducado);
      expect(DatosContratos.fromRaw(crudos(hasta: '2026-12-15')).estadoDeNido(nido('n-vinculado'), hoy).codigo,
          Semaforo.caduca);
      expect(DatosContratos.fromRaw(crudos(hasta: '2027-06-30')).estadoDeNido(nido('n-vinculado'), hoy).codigo,
          Semaforo.firmado);
      expect(DatosContratos.fromRaw(crudos(hasta: null)).estadoDeNido(nido('n-vinculado'), hoy).codigo,
          Semaforo.firmado);
    });

    test('borrador o enviado: pendiente', () {
      for (final s in ['borrador', 'enviado']) {
        expect(DatosContratos.fromRaw(crudos(estado: s)).estadoDeNido(nido('n-vinculado'), hoy).codigo,
            Semaforo.pendiente);
      }
    });

    test('campaña del nido: incubación, luego otras fechas, luego hoy', () {
      expect(campanaDeNido(NidoGrefaModel()..fechaIncubacion = DateTime(2024, 5, 1)), 2024);
      expect(campanaDeNido(NidoGrefaModel()..fechaVuelo = DateTime(2023, 7, 1)), 2023);
      expect(campanaDeNido(NidoGrefaModel(), DateTime(2026, 1, 1)), 2026);
    });
  });

  test('descripción de parcela y enlace al mapa', () {
    final p = DatosContratos.fromRaw(crudos()).parcela('pa1')!;
    expect(p.descripcion, 'Pol. 10 · Parc. 21 · Rec. 1 · Ref. 28 079-A.001 · Madrid, Madrid');
    expect(p.mapaUri.toString(), contains('40.4,-3.7'));
    expect(DatosContratos.fromRaw(crudos()).parcela('pa2')!.mapaUri, isNull);
  });

  group('ContratosService', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('contratos_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('descarga, guarda caché y la recupera sin red', () async {
      final remoto = _Remoto(crudos());
      final s = ContratosService(remote: remoto, directorio: tmp);
      expect(await s.refrescar(), isTrue);
      expect(s.datos.convenios, hasLength(1));
      expect(s.ultimaActualizacion, isNotNull);

      final offline = ContratosService(directorio: tmp);
      await offline.cargarCache();
      expect(offline.datos.parcelas, hasLength(2));
      expect(offline.estadoDe(nido('n-vinculado')).parcela?.id, 'pa1');
    });

    test('si falla la red se conservan los últimos datos y se avisa', () async {
      final remoto = _Remoto(crudos());
      final s = ContratosService(remote: remoto, directorio: tmp);
      await s.refrescar();
      remoto.respuesta = const SocketException('sin red');
      expect(await s.refrescar(), isFalse);
      expect(s.error, isNotNull);
      expect(s.datos.convenios, hasLength(1));
    });

    test('sin origen remoto no hace nada', () async {
      final s = ContratosService(directorio: tmp);
      expect(await s.refrescar(), isFalse);
      expect(s.datos.vacio, isTrue);
    });
  });

  test('la consulta a Supabase no pide datos sensibles', () {
    final cols = SupabaseContratosRemote.columnas.values.join(',');
    for (final prohibido in ['nif', 'iban', 'direccion', 'importe', 'regepa']) {
      expect(cols.contains(prohibido), isFalse, reason: prohibido);
    }
  });
}
