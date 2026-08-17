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

/// Restringe un campo de precio a dígitos y, como máximo, un único punto
/// decimal — bloquea cualquier otro carácter (letras, signos, coma, un
/// segundo punto) apenas se escribe, en vez de solo avisar al enviar el
/// formulario. Para cantidades enteras usar en cambio
/// `FilteringTextInputFormatter.digitsOnly` (de `package:flutter/services.dart`),
/// que ya se usa en varios formularios de este proyecto (ej. DNI/RUC).
class DecimalTextInputFormatter extends TextInputFormatter {
  const DecimalTextInputFormatter();

  static final RegExp _patron = RegExp(r'^\d*\.?\d*$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (_patron.hasMatch(newValue.text)) return newValue;
    return oldValue;
  }
}
