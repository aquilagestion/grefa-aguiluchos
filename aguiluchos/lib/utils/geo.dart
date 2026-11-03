import 'dart:math' as math;

import '../models/nido_grefa_model.dart';

/// Distancia en metros entre dos puntos WGS84 (fórmula de Haversine).
double distanciaMetros(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371008.8; // radio medio de la Tierra en metros
  double rad(double g) => g * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLon = rad(lon2 - lon1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLon / 2), 2);
  return 2 * r * math.asin(math.min(1, math.sqrt(a)));
}

/// Nido existente más cercano a la posición dada dentro de [radioM] metros
/// (o `null`). Ignora los borrados y los que no tienen coordenadas.
({NidoGrefaModel nido, double metros})? nidoMasCercano(
  Iterable<NidoGrefaModel> nidos,
  double lat,
  double lon, {
  double radioM = 25,
}) {
  ({NidoGrefaModel nido, double metros})? mejor;
  for (final n in nidos) {
    if (n.isDeleted) continue;
    final p = n.latLon;
    if (p == null) continue;
    final d = distanciaMetros(lat, lon, p.lat, p.lon);
    if (d <= radioM && (mejor == null || d < mejor.metros)) {
      mejor = (nido: n, metros: d);
    }
  }
  return mejor;
}

/// Nido nuevo (sin guardar) con la posición GPS indicada ya rellenada:
/// coordenadas UTM y enlace de Google Maps.
NidoGrefaModel nidoDesdePosicion(double lat, double lon) => NidoGrefaModel()
  ..setLatLon(lat, lon)
  ..googleMapsUrl = NidoGrefaModel.urlDesdeCoordenadas(lat, lon);
