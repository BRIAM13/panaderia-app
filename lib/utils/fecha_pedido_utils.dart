import 'package:intl/intl.dart';

/// Formatea la fecha/hora de entrega de un pedido. Si la hora es
/// exactamente medianoche (00:00), se interpreta como "no se especificó
/// una hora" (ver nuevo_pedido_page.dart/hacer_pedido_page.dart) y se
/// omite de la salida — mostrar "12:00 a.m." sería engañoso, ya que nadie
/// eligió esa hora a propósito.
String formatearFechaEntrega(DateTime fecha, {bool formatoLargo = false}) {
  final sinHoraEspecificada = fecha.hour == 0 && fecha.minute == 0;
  final patronFecha = formatoLargo ? "EEEE d 'de' MMMM" : 'EEE d MMM';
  final patron = sinHoraEspecificada ? patronFecha : '$patronFecha, h:mm a';
  return DateFormat(patron, 'es').format(fecha);
}
