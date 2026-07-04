const _conAcento = 'áéíóúÁÉÍÓÚñÑüÜ';
const _sinAcento = 'aeiouAEIOUnNuU';

/// Quita tildes/diéresis y pasa a minúsculas, para que una búsqueda como
/// "jose" encuentre "José" sin que el usuario tenga que escribir el acento.
String normalizarBusqueda(String texto) {
  var resultado = texto.trim();
  for (var i = 0; i < _conAcento.length; i++) {
    resultado = resultado.replaceAll(_conAcento[i], _sinAcento[i]);
  }
  return resultado.toLowerCase();
}
