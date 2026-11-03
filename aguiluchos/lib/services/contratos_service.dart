import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/contratos.dart';
import '../models/nido_grefa_model.dart';
import 'app_directories.dart';

/// Origen de los datos de contratos (Supabase en producción, falso en tests).
abstract class ContratosRemote {
  /// Filas por tabla. Lanza si no hay red o sesión.
  Future<Map<String, List<Map<String, dynamic>>>> descargar();
}

/// Lee de Supabase solo las columnas que la app necesita. No se descargan NIF,
/// dirección, IBAN ni importes: en el campo no hacen falta.
class SupabaseContratosRemote implements ContratosRemote {
  SupabaseContratosRemote(this._client);
  final SupabaseClient _client;

  static const columnas = <String, String>{
    'propietarios_grefa': 'id,nombre,tipo,entidad,telefono,email',
    'parcelas_grefa':
        'id,provincia,municipio,sigpac_poligono,sigpac_parcela,sigpac_recinto,'
            'referencia_catastral,superficie_ha,uso,lat,lon,zona_programa',
    'parcela_propietarios_grefa': 'parcela_id,propietario_id',
    'nido_parcela_grefa': 'nido_id,parcela_id',
    'contratos_grefa':
        'id,propietario_id,campana,programa,estado,fecha_firma,vigencia_desde,vigencia_hasta',
    'contrato_parcelas_grefa':
        'id,contrato_id,parcela_id,campana,superficie_ha,uso,ayudas',
  };

  @override
  Future<Map<String, List<Map<String, dynamic>>>> descargar() async {
    const pagina = 1000;
    final out = <String, List<Map<String, dynamic>>>{};
    for (final e in columnas.entries) {
      final filas = <Map<String, dynamic>>[];
      for (var desde = 0;; desde += pagina) {
        final r = await _client
            .from(e.key)
            .select(e.value)
            .range(desde, desde + pagina - 1);
        filas.addAll([for (final f in r) Map<String, dynamic>.from(f)]);
        if (r.length < pagina) break;
      }
      out[e.key] = filas;
    }
    return out;
  }
}

/// Mantiene en memoria y en disco (para trabajar sin cobertura) los datos de
/// contratos y calcula el semáforo de cada nido. Solo lectura.
class ContratosService extends ChangeNotifier {
  // ignore: prefer_initializing_formals
  ContratosService({this.remote, Directory? directorio}) : _directorio = directorio;

  final ContratosRemote? remote;
  final Directory? _directorio;

  DatosContratos _datos = DatosContratos();
  DateTime? _ultima;
  bool _cargando = false;
  String? _error;

  DatosContratos get datos => _datos;

  /// Última descarga correcta (la de la caché si aún no se ha refrescado).
  DateTime? get ultimaActualizacion => _ultima;
  bool get cargando => _cargando;
  String? get error => _error;
  bool get hayOrigen => remote != null;

  Future<File> _archivo() async {
    final dir = _directorio ?? await appDataDirectory();
    return File(p.join(dir.path, 'contratos_cache.json'));
  }

  /// Carga lo último descargado (rápido, sin red).
  Future<void> cargarCache() async {
    try {
      final f = await _archivo();
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      _datos = DatosContratos.fromRaw(Map<String, dynamic>.from(j['datos'] as Map));
      _ultima = DateTime.tryParse('${j['descargado']}');
      notifyListeners();
    } catch (e) {
      debugPrint('Caché de contratos ilegible: $e');
    }
  }

  /// Descarga de nuevo. Devuelve `false` si no se pudo (se conserva la caché).
  Future<bool> refrescar() async {
    final r = remote;
    if (r == null || _cargando) return false;
    _cargando = true;
    _error = null;
    notifyListeners();
    try {
      final raw = await r.descargar();
      _datos = DatosContratos.fromRaw(raw);
      _ultima = DateTime.now();
      try {
        final f = await _archivo();
        await f.parent.create(recursive: true);
        await f.writeAsString(jsonEncode({
          'descargado': _ultima!.toUtc().toIso8601String(),
          'datos': raw,
        }));
      } catch (e) {
        debugPrint('No se pudo guardar la caché de contratos: $e');
      }
      return true;
    } catch (e) {
      _error = _mensaje(e);
      return false;
    } finally {
      _cargando = false;
      notifyListeners();
    }
  }

  static String _mensaje(Object e) {
    if (e is PostgrestException) {
      return e.code == '42P01'
          ? 'Aún no existen las tablas de contratos en el servidor.'
          : 'El servidor rechazó la consulta (${e.code ?? e.message}).';
    }
    return 'Sin conexión o sin sesión: se muestran los últimos datos descargados.';
  }

  EstadoContratoNido estadoDe(NidoGrefaModel n) => _datos.estadoDeNido(n);
}
