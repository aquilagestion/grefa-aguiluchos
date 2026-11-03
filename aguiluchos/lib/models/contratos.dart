import 'package:flutter/material.dart';

import 'nido_grefa_model.dart';

/// Datos de parcelas, propietarios y convenios (solo lectura en la app).
/// Reflejan las tablas `*_grefa` de Supabase; la lógica es la misma que la del
/// panel web (`contratos_logic.js`).

const avisoCaducidadDias = 60;

String _t(Object? v) => v == null ? '' : '$v'.trim();
String? _n(Object? v) => _t(v).isEmpty ? null : _t(v);
double? _d(Object? v) => v == null ? null : double.tryParse('$v');
DateTime? _fecha(Object? v) {
  final s = _t(v);
  if (s.length < 10) return null;
  return DateTime.tryParse(s.substring(0, 10));
}

String normRefCat(String? s) =>
    (s ?? '').toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

class Propietario {
  Propietario.fromJson(Map<String, dynamic> j)
      : id = '${j['id']}',
        nombre = _t(j['nombre']),
        tipo = _t(j['tipo']),
        entidad = _n(j['entidad']),
        telefono = _n(j['telefono']),
        email = _n(j['email']);

  final String id;
  final String nombre;
  final String tipo;
  final String? entidad;
  final String? telefono;
  final String? email;
}

class Parcela {
  Parcela.fromJson(Map<String, dynamic> j)
      : id = '${j['id']}',
        provincia = _n(j['provincia']),
        municipio = _n(j['municipio']),
        poligono = _n(j['sigpac_poligono']),
        parcela = _n(j['sigpac_parcela']),
        recinto = _n(j['sigpac_recinto']),
        referenciaCatastral = _n(j['referencia_catastral']),
        superficieHa = _d(j['superficie_ha']),
        uso = _n(j['uso']),
        lat = _d(j['lat']),
        lon = _d(j['lon']),
        zonaPrograma = _n(j['zona_programa']);

  final String id;
  final String? provincia;
  final String? municipio;
  final String? poligono;
  final String? parcela;
  final String? recinto;
  final String? referenciaCatastral;
  final double? superficieHa;
  final String? uso;
  final double? lat;
  final double? lon;
  final String? zonaPrograma;

  Uri? get mapaUri => (lat == null || lon == null)
      ? null
      : Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lon');

  /// «Pol. 10 · Parc. 21 · Rec. 1 · Ref. … · Madrid, Madrid».
  String get descripcion {
    final sig = (poligono != null || parcela != null)
        ? 'Pol. ${poligono ?? '—'} · Parc. ${parcela ?? '—'}'
            '${recinto != null ? ' · Rec. $recinto' : ''}'
        : '';
    final lugar = [municipio, provincia].whereType<String>().join(', ');
    final partes = [
      sig,
      if (referenciaCatastral != null) 'Ref. $referenciaCatastral',
      lugar,
    ].where((s) => s.isNotEmpty);
    return partes.isEmpty ? 'Parcela sin identificar' : partes.join(' · ');
  }
}

enum EstadoConvenio {
  borrador('Borrador'),
  enviado('Enviado a firma'),
  firmado('Firmado'),
  caducado('Caducado'),
  rechazado('Rechazado');

  const EstadoConvenio(this.etiqueta);
  final String etiqueta;

  static EstadoConvenio desde(String? s) => EstadoConvenio.values
      .firstWhere((e) => e.name == s, orElse: () => EstadoConvenio.borrador);

  /// Orden de preferencia cuando una parcela tiene varios convenios.
  int get prioridad => switch (this) {
        EstadoConvenio.firmado => 0,
        EstadoConvenio.enviado => 1,
        EstadoConvenio.borrador => 2,
        EstadoConvenio.caducado => 3,
        EstadoConvenio.rechazado => 4,
      };
}

class Convenio {
  Convenio.fromJson(Map<String, dynamic> j)
      : id = '${j['id']}',
        propietarioId = _n(j['propietario_id']),
        campana = (j['campana'] as num?)?.toInt() ?? 0,
        programa = _n(j['programa']),
        estado = EstadoConvenio.desde(_n(j['estado'])),
        fechaFirma = _fecha(j['fecha_firma']),
        vigenciaDesde = _fecha(j['vigencia_desde']),
        vigenciaHasta = _fecha(j['vigencia_hasta']);

  final String id;
  final String? propietarioId;
  final int campana;
  final String? programa;
  final EstadoConvenio estado;
  final DateTime? fechaFirma;
  final DateTime? vigenciaDesde;
  final DateTime? vigenciaHasta;
}

class LineaConvenio {
  LineaConvenio.fromJson(Map<String, dynamic> j)
      : contratoId = '${j['contrato_id']}',
        parcelaId = '${j['parcela_id']}',
        campana = (j['campana'] as num?)?.toInt() ?? 0,
        superficieHa = _d(j['superficie_ha']),
        uso = _n(j['uso']),
        ayudas = [
          for (final a in (j['ayudas'] as List? ?? const []))
            if (a is num) a.toInt(),
        ];

  final String contratoId;
  final String parcelaId;
  final int campana;
  final double? superficieHa;
  final String? uso;
  final List<int> ayudas;
}

/// Semáforo de contrato de un nido (mismos códigos y colores que el panel).
enum Semaforo {
  firmado(Color(0xFF2E6B3A), 'Contrato firmado'),
  caduca(Color(0xFFE08A1E), 'Contrato firmado: caduca pronto'),
  pendiente(Color(0xFFE08A1E), 'Contrato pendiente de firma'),
  sin(Color(0xFFC0392B), 'Sin contrato'),
  caducado(Color(0xFFC0392B), 'Contrato caducado'),
  sinparcela(Color(0xFF8A8F8C), 'Sin parcela vinculada');

  const Semaforo(this.color, this.etiqueta);
  final Color color;
  final String etiqueta;
}

class EstadoContratoNido {
  const EstadoContratoNido(this.codigo, this.campana, {this.parcela, this.convenio});
  final Semaforo codigo;
  final int campana;
  final Parcela? parcela;
  final Convenio? convenio;
}

/// Campaña (año) de un nido: la de su incubación o, si falta, la de la primera
/// fecha disponible.
int campanaDeNido(NidoGrefaModel n, [DateTime? hoy]) {
  final f = n.fechaIncubacion ?? n.fechaEntradaNido ?? n.fechaEclosion ?? n.fechaVuelo;
  return f?.year ?? (hoy ?? DateTime.now()).year;
}

class DatosContratos {
  DatosContratos({
    this.propietarios = const [],
    this.parcelas = const [],
    this.convenios = const [],
    this.lineas = const [],
    this.titulares = const [],
    this.vinculos = const {},
  })  : _propietarioPorId = {for (final p in propietarios) p.id: p},
        _parcelaPorId = {for (final p in parcelas) p.id: p},
        _convenioPorId = {for (final c in convenios) c.id: c} {
    for (final p in parcelas) {
      final k = normRefCat(p.referenciaCatastral);
      if (k.isNotEmpty) _porRefCat.putIfAbsent(k, () => p);
    }
    for (final l in lineas) {
      (_lineasPorParcela[l.parcelaId] ??= []).add(l);
      (_lineasPorConvenio[l.contratoId] ??= []).add(l);
    }
    for (final t in titulares) {
      (_titularesPorParcela[t.$1] ??= []).add(t.$2);
    }
  }

  /// A partir de las filas tal como las devuelve Supabase.
  factory DatosContratos.fromRaw(Map<String, dynamic> raw) {
    List<Map<String, dynamic>> filas(String k) => [
          for (final r in (raw[k] as List? ?? const []))
            Map<String, dynamic>.from(r as Map),
        ];
    return DatosContratos(
      propietarios: filas('propietarios_grefa').map(Propietario.fromJson).toList(),
      parcelas: filas('parcelas_grefa').map(Parcela.fromJson).toList(),
      convenios: filas('contratos_grefa').map(Convenio.fromJson).toList(),
      lineas: filas('contrato_parcelas_grefa').map(LineaConvenio.fromJson).toList(),
      titulares: [
        for (final r in filas('parcela_propietarios_grefa'))
          ('${r['parcela_id']}', '${r['propietario_id']}'),
      ],
      vinculos: {
        for (final r in filas('nido_parcela_grefa')) '${r['nido_id']}': '${r['parcela_id']}',
      },
    );
  }

  final List<Propietario> propietarios;
  final List<Parcela> parcelas;
  final List<Convenio> convenios;
  final List<LineaConvenio> lineas;

  /// (parcelaId, propietarioId)
  final List<(String, String)> titulares;

  /// nidoId -> parcelaId
  final Map<String, String> vinculos;

  final Map<String, Propietario> _propietarioPorId;
  final Map<String, Parcela> _parcelaPorId;
  final Map<String, Convenio> _convenioPorId;
  final Map<String, Parcela> _porRefCat = {};
  final Map<String, List<LineaConvenio>> _lineasPorParcela = {};
  final Map<String, List<LineaConvenio>> _lineasPorConvenio = {};
  final Map<String, List<String>> _titularesPorParcela = {};

  bool get vacio => parcelas.isEmpty && convenios.isEmpty && propietarios.isEmpty;

  Propietario? propietario(String? id) => id == null ? null : _propietarioPorId[id];
  Parcela? parcela(String id) => _parcelaPorId[id];
  Convenio? convenio(String id) => _convenioPorId[id];
  List<LineaConvenio> lineasDeConvenio(String id) => _lineasPorConvenio[id] ?? const [];
  List<LineaConvenio> lineasDeParcela(String id) => _lineasPorParcela[id] ?? const [];
  List<Propietario> titularesDe(String parcelaId) => [
        for (final id in _titularesPorParcela[parcelaId] ?? const <String>[])
          if (_propietarioPorId[id] != null) _propietarioPorId[id]!,
      ];

  /// Ids de nido vinculados a una parcela.
  List<String> nidosDeParcela(String parcelaId) =>
      [for (final e in vinculos.entries) if (e.value == parcelaId) e.key];

  /// Parcela de un nido: el vínculo explícito o, si no, la referencia catastral.
  Parcela? parcelaDeNido(NidoGrefaModel n) {
    final v = vinculos[n.id];
    if (v != null && _parcelaPorId.containsKey(v)) return _parcelaPorId[v];
    final k = normRefCat(n.referenciaCatastral);
    return k.isEmpty ? null : _porRefCat[k];
  }

  /// Estado del contrato de un nido para su campaña.
  EstadoContratoNido estadoDeNido(NidoGrefaModel n, [DateTime? ahora]) {
    final hoy = ahora ?? DateTime.now();
    final campana = campanaDeNido(n, hoy);
    final parcela = parcelaDeNido(n);
    if (parcela == null) return EstadoContratoNido(Semaforo.sinparcela, campana);

    final candidatos = [
      for (final l in lineasDeParcela(parcela.id))
        if (l.campana == campana && _convenioPorId[l.contratoId] != null)
          _convenioPorId[l.contratoId]!,
    ]..sort((a, b) => a.estado.prioridad.compareTo(b.estado.prioridad));

    EstadoContratoNido r(Semaforo s, [Convenio? c]) =>
        EstadoContratoNido(s, campana, parcela: parcela, convenio: c);

    if (candidatos.isEmpty) return r(Semaforo.sin);
    final c = candidatos.first;
    switch (c.estado) {
      case EstadoConvenio.rechazado:
        return r(Semaforo.sin, c);
      case EstadoConvenio.caducado:
        return r(Semaforo.caducado, c);
      case EstadoConvenio.firmado:
        final fin = c.vigenciaHasta;
        final hoy0 = DateTime(hoy.year, hoy.month, hoy.day);
        if (fin != null && fin.isBefore(hoy0)) return r(Semaforo.caducado, c);
        if (fin != null && fin.difference(hoy0).inDays <= avisoCaducidadDias) {
          return r(Semaforo.caduca, c);
        }
        return r(Semaforo.firmado, c);
      case EstadoConvenio.borrador:
      case EstadoConvenio.enviado:
        return r(Semaforo.pendiente, c);
    }
  }
}
