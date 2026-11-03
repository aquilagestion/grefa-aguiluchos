import '../models/nido_grefa_model.dart';

/// Jerarquía administrativa derivada de los datos del nido:
/// País > Comunidad autónoma > Provincia > Localidad.
///
/// No hay columnas nuevas: se calcula a partir de `provincia` y `municipio`
/// (si `provincia` trae una comunidad, p. ej. «Galicia», se respeta). Es el
/// mismo criterio que usa el panel web.

const paisUnico = 'España';
const sinDato = 'Sin indicar';

/// Comunidad -> provincias (nombre canónico).
const comunidadesProvincias = <String, List<String>>{
  'Andalucía': ['Almería', 'Cádiz', 'Córdoba', 'Granada', 'Huelva', 'Jaén', 'Málaga', 'Sevilla'],
  'Aragón': ['Huesca', 'Teruel', 'Zaragoza'],
  'Principado de Asturias': ['Asturias'],
  'Illes Balears': ['Illes Balears'],
  'Canarias': ['Las Palmas', 'Santa Cruz de Tenerife'],
  'Cantabria': ['Cantabria'],
  'Castilla y León': ['Ávila', 'Burgos', 'León', 'Palencia', 'Salamanca', 'Segovia', 'Soria', 'Valladolid', 'Zamora'],
  'Castilla-La Mancha': ['Albacete', 'Ciudad Real', 'Cuenca', 'Guadalajara', 'Toledo'],
  'Cataluña': ['Barcelona', 'Girona', 'Lleida', 'Tarragona'],
  'Comunitat Valenciana': ['Alicante', 'Castellón', 'Valencia'],
  'Extremadura': ['Badajoz', 'Cáceres'],
  'Galicia': ['A Coruña', 'Lugo', 'Ourense', 'Pontevedra'],
  'Comunidad de Madrid': ['Madrid'],
  'Región de Murcia': ['Murcia'],
  'Comunidad Foral de Navarra': ['Navarra'],
  'País Vasco': ['Álava', 'Bizkaia', 'Gipuzkoa'],
  'La Rioja': ['La Rioja'],
  'Ceuta': ['Ceuta'],
  'Melilla': ['Melilla'],
};

const _aliasProvincia = <String, String>{
  'la coruna': 'A Coruña', 'coruna': 'A Coruña', 'a coruna': 'A Coruña',
  'orense': 'Ourense', 'gerona': 'Girona', 'lerida': 'Lleida', 'alacant': 'Alicante',
  'castello': 'Castellón', 'baleares': 'Illes Balears', 'islas baleares': 'Illes Balears',
  'illes balears': 'Illes Balears', 'alava': 'Álava', 'araba': 'Álava', 'vizcaya': 'Bizkaia',
  'guipuzcoa': 'Gipuzkoa', 'rioja': 'La Rioja', 'nafarroa': 'Navarra',
  'santa cruz tenerife': 'Santa Cruz de Tenerife',
};

const _aliasComunidad = <String, String>{
  'andalucia': 'Andalucía', 'aragon': 'Aragón', 'asturias': 'Principado de Asturias',
  'castilla la mancha': 'Castilla-La Mancha', 'castilla y leon': 'Castilla y León',
  'cataluna': 'Cataluña', 'catalunya': 'Cataluña',
  'comunidad valenciana': 'Comunitat Valenciana', 'comunitat valenciana': 'Comunitat Valenciana',
  'valenciana': 'Comunitat Valenciana', 'comunidad de madrid': 'Comunidad de Madrid',
  'region de murcia': 'Región de Murcia', 'comunidad foral de navarra': 'Comunidad Foral de Navarra',
  'pais vasco': 'País Vasco', 'euskadi': 'País Vasco', 'canarias': 'Canarias',
  'islas canarias': 'Canarias', 'illes balears': 'Illes Balears', 'baleares': 'Illes Balears',
};

/// Localidades cuyo nombre es una comarca/espacio y cuya provincia es conocida.
const _provinciaPorLocalidad = <String, String>{
  'limia': 'Ourense', 'xures': 'Ourense', 'a limia': 'Ourense',
};

const _tildes = {
  'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', 'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
  'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i', 'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o',
  'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u', 'ñ': 'n', 'ç': 'c',
};

/// Minúsculas, sin tildes ni signos, espacios simples.
String normalizarGeo(String? s) {
  final b = StringBuffer();
  for (final r in (s ?? '').toLowerCase().runes) {
    final ch = String.fromCharCode(r);
    b.write(_tildes[ch] ?? ch);
  }
  return b.toString().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

final Map<String, String> _provACom = {};
final Map<String, String> _normProv = {};
final Map<String, String> _normCom = {};

void _inicializar() {
  if (_normProv.isNotEmpty) return;
  comunidadesProvincias.forEach((com, provs) {
    _normCom[normalizarGeo(com)] = com;
    for (final p in provs) {
      _provACom[p] = com;
      _normProv[normalizarGeo(p)] = p;
    }
  });
  _normProv.addAll(_aliasProvincia);
  _normCom.addAll(_aliasComunidad);
}

class Ubicacion {
  const Ubicacion(this.pais, this.comunidad, this.provincia, this.localidad);
  final String pais;
  final String comunidad;
  final String provincia;
  final String localidad;

  /// Valor de un nivel: 'pais' | 'comunidad' | 'provincia' | 'localidad'.
  String nivel(String nivel) => switch (nivel) {
        'pais' => pais,
        'comunidad' => comunidad,
        'provincia' => provincia,
        _ => localidad,
      };

  @override
  bool operator ==(Object other) =>
      other is Ubicacion &&
      other.pais == pais &&
      other.comunidad == comunidad &&
      other.provincia == provincia &&
      other.localidad == localidad;

  @override
  int get hashCode => Object.hash(pais, comunidad, provincia, localidad);

  @override
  String toString() => '$pais > $comunidad > $provincia > $localidad';
}

/// Ubicación de un nido; usa «Sin indicar» cuando el dato falta o no se reconoce.
Ubicacion ubicacionDe(NidoGrefaModel n) =>
    ubicacionDeTextos(provincia: n.provincia, municipio: n.municipio);

Ubicacion ubicacionDeTextos({String? provincia, String? municipio}) {
  _inicializar();
  final prov = (provincia ?? '').trim();
  final loc = (municipio ?? '').trim();
  final k = normalizarGeo(prov);
  var p = sinDato;
  var c = sinDato;

  if (prov.isNotEmpty && _normProv.containsKey(k)) {
    p = _normProv[k]!;
    c = _provACom[p] ?? sinDato;
  } else if (prov.isNotEmpty && _normCom.containsKey(k)) {
    c = _normCom[k]!; // «provincia» trae una comunidad (p. ej. «Galicia»)
  } else if (prov.isNotEmpty) {
    p = prov; // valor desconocido: se conserva tal cual
  }
  if (p == sinDato) {
    final deducida = _provinciaPorLocalidad[normalizarGeo(loc)];
    if (deducida != null) {
      p = deducida;
      if (c == sinDato) c = _provACom[deducida] ?? sinDato;
    }
  }
  return Ubicacion(paisUnico, c, p, loc.isEmpty ? sinDato : loc);
}

List<String> _ordenar(Iterable<String> v) {
  final l = v.toSet().toList();
  l.sort((a, b) => normalizarGeo(a).compareTo(normalizarGeo(b)));
  return l;
}

/// Opciones de cada nivel de filtro, en cascada: cada nivel solo muestra lo
/// que existe dentro de la selección de los niveles superiores.
class OpcionesGeo {
  const OpcionesGeo(this.paises, this.comunidades, this.provincias, this.localidades);
  final List<String> paises;
  final List<String> comunidades;
  final List<String> provincias;
  final List<String> localidades;
}

OpcionesGeo opcionesCascada(
  Iterable<NidoGrefaModel> nidos, {
  String? pais,
  String? comunidad,
  String? provincia,
}) {
  final u = [for (final n in nidos) ubicacionDe(n)];
  bool pasa(Ubicacion x, int hasta) =>
      (pais == null || x.pais == pais) &&
      (hasta < 1 || comunidad == null || x.comunidad == comunidad) &&
      (hasta < 2 || provincia == null || x.provincia == provincia);
  List<String> uniq(String nivel, int hasta) =>
      _ordenar(u.where((x) => pasa(x, hasta)).map((x) => x.nivel(nivel)));
  return OpcionesGeo(uniq('pais', 0), uniq('comunidad', 0), uniq('provincia', 1), uniq('localidad', 2));
}

/// Agrupa nidos por un nivel; los grupos más numerosos primero.
List<MapEntry<String, List<NidoGrefaModel>>> agruparPorNivel(
  Iterable<NidoGrefaModel> nidos,
  String nivel,
) {
  final m = <String, List<NidoGrefaModel>>{};
  for (final n in nidos) {
    (m[ubicacionDe(n).nivel(nivel)] ??= []).add(n);
  }
  final out = m.entries.toList();
  out.sort((a, b) {
    final c = b.value.length.compareTo(a.value.length);
    return c != 0 ? c : normalizarGeo(a.key).compareTo(normalizarGeo(b.key));
  });
  return out;
}
