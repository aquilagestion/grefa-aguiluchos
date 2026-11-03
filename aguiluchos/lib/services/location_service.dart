import 'package:geolocator/geolocator.dart';

class LocationException implements Exception {
  LocationException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Captura de la posición GPS actual.
class LocationService {
  Future<void> _asegurarPermiso() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw LocationException('El GPS está desactivado.');
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      throw LocationException('Permiso de ubicación denegado.');
    }
  }

  Future<Position> posicionActual() async {
    try {
      await _asegurarPermiso();
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 25),
        ),
      );
    } on LocationException {
      rethrow;
    } catch (e) {
      throw LocationException(
          'No se pudo obtener la ubicación en este dispositivo. Introduce las coordenadas a mano. ($e)');
    }
  }

  /// Posición GPS en continuo (para el radar): emite al moverse unos metros.
  /// Los fallos (GPS apagado, permiso denegado…) llegan como
  /// [LocationException] en el propio flujo.
  Stream<Position> posiciones({int distanciaMinimaM = 3}) async* {
    try {
      await _asegurarPermiso();
      // Última posición conocida: el radar se pinta enseguida, sin esperar al primer fix.
      final ultima = await Geolocator.getLastKnownPosition();
      if (ultima != null) yield ultima;
      yield* Geolocator.getPositionStream(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: distanciaMinimaM,
        ),
      );
    } on LocationException {
      rethrow;
    } catch (e) {
      throw LocationException('No se pudo seguir la ubicación en este dispositivo. ($e)');
    }
  }
}
