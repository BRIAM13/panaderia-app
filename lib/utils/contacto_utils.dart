/// Marcar y escribir por WhatsApp son las dos acciones que el personal hace
/// justo después de mirar a un cliente (perfil, lista "en riesgo" del
/// tablero, sheet de acciones). Vivían escritas a mano dentro del sheet de
/// acciones, así que ninguna otra pantalla podía ofrecerlas sin copiar el
/// mismo armado de URL; acá quedan una sola vez.
library;

import 'package:url_launcher/url_launcher.dart';

/// Normaliza un teléfono peruano al formato que espera `wa.me`: solo
/// dígitos y con el código de país (51) adelante.
String numeroWhatsApp(String telefono) {
  final soloDigitos = telefono.replaceAll(RegExp(r'[^0-9]'), '');
  if (soloDigitos.startsWith('51')) return soloDigitos;
  if (soloDigitos.length == 9) {
    return '51$soloDigitos'; // celular peruano sin código de país
  }
  return soloDigitos;
}

/// true si hay un número con el que se pueda hacer algo — evita ofrecer
/// botones de llamada/WhatsApp que no harían nada al tocarlos.
bool tieneTelefonoUtil(String? telefono) =>
    telefono != null && telefono.trim().isNotEmpty;

Future<void> llamarPorTelefono(String telefono) async {
  if (!tieneTelefonoUtil(telefono)) return;
  await launchUrl(Uri(scheme: 'tel', path: telefono));
}

Future<void> abrirWhatsApp(String telefono, {String? mensaje}) async {
  if (!tieneTelefonoUtil(telefono)) return;
  final texto = Uri.encodeComponent(
    mensaje ?? 'Hola, te contactamos de Panadería Ronceros.',
  );
  await launchUrl(
    Uri.parse('https://wa.me/${numeroWhatsApp(telefono)}?text=$texto'),
    mode: LaunchMode.externalApplication,
  );
}
