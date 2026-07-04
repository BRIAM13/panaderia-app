import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

/// Error de geolocalización con un mensaje ya listo para mostrar al usuario
/// (GPS apagado, permiso denegado, o no se pudo traducir la ubicación).
class GeolocationException implements Exception {
  const GeolocationException(this.mensaje);
  final String mensaje;
}

/// Obtiene la ubicación GPS de alta precisión del dispositivo y la traduce
/// a una dirección física legible (geocodificación inversa), solicitando
/// los permisos nativos correspondientes en el camino.
class GeolocationService {
  const GeolocationService();

  Future<String> obtenerDireccionActual() async {
    final servicioActivo = await Geolocator.isLocationServiceEnabled();
    if (!servicioActivo) {
      throw const GeolocationException(
        'Activa el GPS de tu dispositivo para autocompletar la dirección.',
      );
    }

    var permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
    }
    if (permiso == LocationPermission.denied ||
        permiso == LocationPermission.deniedForever) {
      throw const GeolocationException(
        'Necesitamos permiso de ubicación para autocompletar la dirección.',
      );
    }

    final posicion = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );

    List<Placemark> lugares;
    try {
      lugares = await placemarkFromCoordinates(
        posicion.latitude,
        posicion.longitude,
      );
    } catch (_) {
      throw const GeolocationException(
        'No se pudo traducir tu ubicación a una dirección.',
      );
    }

    if (lugares.isEmpty) {
      throw const GeolocationException(
        'No se pudo traducir tu ubicación a una dirección.',
      );
    }

    final direccion = _formatearDireccion(lugares.first);
    if (direccion.isEmpty) {
      throw const GeolocationException(
        'No se pudo traducir tu ubicación a una dirección.',
      );
    }
    return direccion;
  }

  String _formatearDireccion(Placemark lugar) {
    final calle = [
      lugar.thoroughfare,
      lugar.subThoroughfare,
    ].where((p) => p != null && p.trim().isNotEmpty).join(' ');

    final partes = [
      calle.isNotEmpty ? calle : lugar.street,
      lugar.subLocality,
      lugar.locality,
    ].where((p) => p != null && p.trim().isNotEmpty).cast<String>().toList();

    return partes.join(', ');
  }
}
