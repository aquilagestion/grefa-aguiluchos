import 'dart:math' as math;

import '../models/nido_grefa_model.dart';
import 'geo.dart';

/// Radios disponibles en el radar, en metros (de menor a mayor).
const List<double> radiosRadarM = [100, 250, 500, 1000, 2000, 5000, 10000, 25000];

/// Radio inicial: 1 km.
const int radioRadarInicial = 3;

/// Nido situado dentro del radio del radar, con su distancia y rumbo.
class NidoEnRadio {
  const NidoEnRadio(this.nido, this.metros, this.rumbo);
  final NidoGrefaModel nido;

  /// Distancia en metros desde la posición del observador.
  final double metros;

  /// Rumbo en grados (0 = norte, 90 = este) desde el observador hasta el nido.
  final double rumbo;
}

/// Rumbo inicial (0–360°, 0 = norte) del punto 1 al punto 2.
double rumboGrados(double lat1, double lon1, double lat2, double lon2) {
  double rad(double g) => g * math.pi / 180;
  final dLon = rad(lon2 - lon1);
  final y = math.sin(dLon) * math.cos(rad(lat2));
  final x = math.cos(rad(lat1)) * math.sin(rad(lat2)) -
      math.sin(rad(lat1)) * math.cos(rad(lat2)) * math.cos(dLon);
  final g = math.atan2(y, x) * 180 / math.pi;
  return (g + 360) % 360;
}

/// Punto cardinal de 8 vientos (N, NE, E, SE, S, SO, O, NO).
String puntoCardinal(double grados) {
  const p = ['N', 'NE', 'E', 'SE', 'S', 'SO', 'O', 'NO'];
  final g = ((grados % 360) + 360) % 360;
  return p[((g + 22.5) ~/ 45) % 8];
}

/// «85 m», «1,4 km» o «12 km».
String formatoDistancia(double metros) {
  if (metros < 1000) return '${metros.round()} m';
  final km = metros / 1000;
  if (km >= 10) return '${km.round()} km';
  return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
}

/// Radio para mostrar en la etiqueta del selector: «500 m», «2 km».
String etiquetaRadio(double metros) => metros < 1000
    ? '${metros.round()} m'
    : '${(metros / 1000).toStringAsFixed(metros % 1000 == 0 ? 0 : 1).replaceAll('.', ',')} km';

/// Índice del radio disponible más cercano (en escala logarítmica) a [metros].
int indiceRadioCercano(double metros) {
  var mejor = 0;
  var dif = double.infinity;
  for (var i = 0; i < radiosRadarM.length; i++) {
    final d = (math.log(radiosRadarM[i]) - math.log(math.max(1, metros))).abs();
    if (d < dif) {
      dif = d;
      mejor = i;
    }
  }
  return mejor;
}

/// Nidos con coordenadas a menos de [radioM] metros de (lat, lon), del más
/// cercano al más lejano. Ignora los borrados y los que no tienen coordenadas.
List<NidoEnRadio> nidosEnRadio(
  Iterable<NidoGrefaModel> nidos,
  double lat,
  double lon,
  double radioM,
) {
  final r = <NidoEnRadio>[];
  for (final n in nidos) {
    if (n.isDeleted) continue;
    final p = n.latLon;
    if (p == null) continue;
    final d = distanciaMetros(lat, lon, p.lat, p.lon);
    if (d > radioM) continue;
    r.add(NidoEnRadio(n, d, rumboGrados(lat, lon, p.lat, p.lon)));
  }
  r.sort((a, b) => a.metros.compareTo(b.metros));
  return r;
}

/// Posición normalizada (x hacia el este, y hacia el sur, ambos en -1..1,
/// donde 1 es el borde del radar) para pintar un nido en pantalla con el norte
/// arriba.
({double x, double y}) posicionEnRadar(double metros, double rumbo, double radioM) {
  final f = metros / radioM;
  final a = rumbo * math.pi / 180;
  return (x: f * math.sin(a), y: -f * math.cos(a));
}
