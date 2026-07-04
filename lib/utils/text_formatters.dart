import 'package:flutter/services.dart';

/// Fuerza mayúsculas en cada tecla, sin importar el idioma/capitalización
/// del teclado del dispositivo (físico o virtual) ni si el texto llega por
/// pegado/autocompletado. A diferencia de `TextCapitalization` (que solo es
/// una sugerencia visual para el teclado virtual y no bloquea minúsculas),
/// este formatter transforma el valor real que llega al controller.
///
/// Nota: los `TextInputFormatter` solo se aplican a ediciones del usuario a
/// través del campo — una asignación programática (`controller.text = x`,
/// por ejemplo al autocompletar con datos de RENIEC/SUNAT) NO pasa por
/// aquí. Esos casos deben normalizarse a mayúsculas explícitamente en el
/// propio código que hace la asignación.
class UpperCaseTextFormatter extends TextInputFormatter {
  const UpperCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
