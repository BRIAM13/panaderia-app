/**
 * Enmascarado de datos de contacto para respuestas PÚBLICAS (sin login).
 *
 * Por qué existe: el formulario público de pedidos (ver publicoController.js)
 * autocompleta el correo/celular que ya tenemos guardados de un DNI/RUC, para
 * que el cliente que vuelve no tenga que reescribirlos. Pero el DNI en Perú
 * NO es un secreto fuerte (aparece en boletas, contratos, listas): si el
 * endpoint devolviera el correo/celular COMPLETO de cualquier documento,
 * cualquiera que conociera el DNI de otra persona podría extraer su contacto
 * real sin ser el dueño. Por eso lo que sale de la API pública siempre va
 * enmascarado — el pedido igual queda asociado a la Persona correcta por DNI
 * del lado del servidor, así que no se pierde nada funcional.
 *
 * Funciones puras a propósito (sin base de datos, sin req/res): así se
 * prueban solas (ver __tests__/enmascarar.test.js).
 */

/**
 * `juan.perez@gmail.com` → `j***@gmail.com`.
 * Se conserva el primer carácter y el dominio completo (el dominio no
 * identifica a nadie por sí solo y le sirve al cliente para reconocer cuál
 * de sus correos es). Un correo vacío/sin `@` devuelve null: no hay nada
 * que enmascarar y es preferible responder "no hay dato" a inventar algo.
 */
function enmascararEmail(email) {
  if (typeof email !== 'string') return null;
  const limpio = email.trim();
  const posArroba = limpio.lastIndexOf('@');
  if (posArroba < 1 || posArroba === limpio.length - 1) return null;
  return `${limpio[0]}***${limpio.slice(posArroba)}`;
}

/**
 * `987654321` → `9*****321`: primer dígito + 5 asteriscos + últimos 3.
 * Los últimos 3 son los que el cliente reconoce de un vistazo, y con 4 de 9
 * dígitos visibles quedan 100 000 combinaciones posibles: no alcanza para
 * reconstruir el número.
 *
 * El formato de arriba es el del celular peruano (9 dígitos, el único que
 * acepta el formulario público). Si en la base hubiera un número de otro
 * largo (cargado a mano desde la app, que sí admite fijos), se aplica el
 * mismo criterio de forma proporcional en vez de devolver algo raro.
 */
function enmascararTelefono(telefono) {
  if (typeof telefono !== 'string') return null;
  const limpio = telefono.trim();
  if (limpio.length === 0) return null;
  if (limpio.length <= 4) return '*'.repeat(limpio.length);
  const ocultos = limpio.length - 4;
  return `${limpio[0]}${'*'.repeat(ocultos)}${limpio.slice(-3)}`;
}

/**
 * Estado de un canal de contacto tal como lo ve la página pública:
 * si tenemos algo guardado, si ese algo ya está verificado (y por lo tanto
 * no se puede cambiar desde acá, solo desde la app) y su versión
 * enmascarada. `mascara` es null siempre que `enArchivo` sea false.
 */
function estadoContacto(valor, verificado) {
  const mascara = typeof valor === 'string' && valor.trim().length > 0 ? valor.trim() : null;
  if (mascara === null) {
    return { enArchivo: false, verificado: false, mascara: null };
  }
  return { enArchivo: true, verificado: Boolean(verificado), mascara: null };
}

/** Estado del canal de correo, ya enmascarado. */
function estadoEmail(email, verificado) {
  const base = estadoContacto(email, verificado);
  if (!base.enArchivo) return base;
  const mascara = enmascararEmail(email);
  // Un correo guardado con formato imposible de enmascarar (sin `@`) se
  // trata como si no hubiera dato: nunca se devuelve el valor crudo.
  if (mascara === null) return { enArchivo: false, verificado: false, mascara: null };
  return { ...base, mascara };
}

/** Estado del canal de celular, ya enmascarado. */
function estadoTelefono(telefono, verificado) {
  const base = estadoContacto(telefono, verificado);
  if (!base.enArchivo) return base;
  return { ...base, mascara: enmascararTelefono(telefono) };
}

/** Bloque `contacto` completo, listo para el JSON de la respuesta pública. */
function contactoEnmascarado(fila) {
  const persona = fila || {};
  return {
    email: estadoEmail(persona.Email, persona.EmailVerificado),
    telefono: estadoTelefono(persona.Telefono, persona.TelefonoVerificado),
  };
}

/** Ambos canales vacíos: documento que todavía no existe en Personas. */
function contactoVacio() {
  return {
    email: { enArchivo: false, verificado: false, mascara: null },
    telefono: { enArchivo: false, verificado: false, mascara: null },
  };
}

module.exports = {
  enmascararEmail,
  enmascararTelefono,
  estadoEmail,
  estadoTelefono,
  contactoEnmascarado,
  contactoVacio,
};
