const { verificarDocumentoOficial } = require('../controllers/externalController');

/**
 * Quién decide que una Persona quedó "validada por RENIEC/SUNAT".
 *
 * ANTES: lo decidía el cliente HTTP. `crearCliente`/`actualizarCliente`/
 * `crearTrabajador` tomaban `origenValidacion` del body y lo guardaban tal
 * cual, así que cualquiera con una sesión de TRABAJADOR (o directamente con
 * curl, sin pasar por la app) podía inventar un DNI y unos nombres, mandar
 * `origenValidacion: 'RENIEC'` y quedarse con un cliente marcado como
 * verificado — y en `actualizarCliente` eso además CONGELA el nombre para
 * siempre, o sea que el dato falso ya no se podía corregir nunca.
 *
 * AHORA: `origenValidacion` del body es apenas una PETICIÓN ("creo que este
 * documento está verificado"). El único que puede confirmarla es el propio
 * servidor, consultando RENIEC/SUNAT por su cuenta (ver
 * controllers/externalController.js). El body no aporta ni un bit a esa
 * decisión, así que ya no hay forma de fabricar un 'RENIEC' desde afuera.
 *
 * Mismo criterio que ya usaba `publicoController.verificarDocumentoPublico`
 * para el pedido web sin login: un estado guardado (o afirmado) no prueba
 * nada — se revalida contra la fuente oficial.
 *
 * Costo: la consulta que hace el servidor NO duplica el gasto de la API
 * paga. `externalController` recuerda por media hora las respuestas
 * definitivas de apiperu.dev, así que la comprobación del alta reusa la
 * misma respuesta que ya obtuvo el "Buscar" del formulario. Y si la memoria
 * ya venció (o el proceso se reinició), se paga una consulta y se guarda un
 * dato real — nunca uno inventado.
 */

const ORIGEN_VERIFICADO = 'RENIEC';
const ORIGEN_MANUAL = 'MANUAL';

/**
 * Todo dato oficial se normaliza a mayúsculas sin espacios sobrantes, igual
 * que hace `mayuscula()` en los controllers: así lo que el servidor escribe
 * en Personas es idéntico en forma a lo que escribiría el flujo manual.
 */
function normalizar(valor) {
  return valor === undefined || valor === null ? '' : String(valor).trim().toUpperCase();
}

function esRucPeru(documento) {
  return /^\d{11}$/.test(String(documento || '').trim());
}

/**
 * 'API_REAL' es la ÚNICA fuente que justifica marcar 'RENIEC'.
 *
 * 'SIMULADO' significa que apiperu.dev no estaba disponible y respondió el
 * simulador local — que le da nombres inventados a CUALQUIER número de 8
 * dígitos. Guardar eso como 'RENIEC' sería exactamente el bug que se está
 * arreglando (un dato inventado marcado como oficial), y encima congelado
 * para siempre. Queda 'MANUAL': los datos igual se guardan y el cliente se
 * puede reverificar más adelante, cuando la API vuelva. Es el mismo mapeo
 * que ya hacía `publicoController.crearPedidoPublico`.
 */
function origenSegunFuente(fuente) {
  return fuente === 'API_REAL' ? ORIGEN_VERIFICADO : ORIGEN_MANUAL;
}

/**
 * Los datos tal como los devolvió la fuente oficial, listos para escribirse
 * en Personas. Devuelve null si la respuesta no vino de la API real: sin
 * datos oficiales, quien llama se queda con lo que escribió el vendedor
 * (guardado como 'MANUAL', nunca como verificado).
 *
 * Para RUC no hay apellidos (una empresa no los tiene) y la razón social
 * entera vive en `Nombres` — misma convención que el resto del backend.
 */
function datosOficiales(verificacion, documento) {
  if (!verificacion || verificacion.fuente !== 'API_REAL') return null;

  if (esRucPeru(documento)) {
    return {
      nombres: normalizar(verificacion.razonSocial),
      apellidoPaterno: '',
      apellidoMaterno: null,
      nombreComercial: normalizar(verificacion.nombreComercial),
    };
  }

  return {
    nombres: normalizar(verificacion.nombres),
    apellidoPaterno: normalizar(verificacion.apellidoPaterno),
    apellidoMaterno: normalizar(verificacion.apellidoMaterno) || null,
    nombreComercial: '',
  };
}

/**
 * Resuelve, con la sola autoridad del servidor, qué `OrigenValidacion` le
 * corresponde a este documento y con qué nombres debe guardarse.
 *
 * Devuelve:
 *   { aceptado: true,  origen, oficial }  -> `oficial` trae los nombres de
 *       RENIEC/SUNAT cuando el origen es 'RENIEC'; es null cuando el origen
 *       es 'MANUAL' (y entonces quien llama guarda lo que vino del
 *       formulario, que es dato manual y así queda marcado).
 *   { aceptado: false, mensaje }          -> la fuente oficial dice que ese
 *       documento NO existe. Es el caso del DNI 99999999 que reportó el
 *       dueño: nunca debe terminar en un cliente "verificado".
 *
 * Nunca lanza por culpa de la API: `verificarDocumentoOficial` ya cae al
 * simulador si apiperu.dev no responde (y eso se traduce en 'MANUAL').
 */
async function resolverOrigenValidacion({ documento, origenSolicitado }) {
  const limpio = String(documento || '').trim();

  // Sin documento no hay nada que verificar: un "registro rápido" (cliente
  // sin DNI) siempre es manual, diga lo que diga el body.
  if (origenSolicitado !== ORIGEN_VERIFICADO || !limpio) {
    return { aceptado: true, origen: ORIGEN_MANUAL, oficial: null };
  }

  const verificacion = await verificarDocumentoOficial(limpio);

  if (verificacion.fuente === 'NO_ENCONTRADO') {
    return {
      aceptado: false,
      origen: ORIGEN_MANUAL,
      oficial: null,
      mensaje: esRucPeru(limpio)
        ? 'SUNAT no reconoce ese RUC. Verifica el número: no se puede registrar como validado un documento que no existe.'
        : 'RENIEC no reconoce ese DNI. Verifica el número: no se puede registrar como validado un documento que no existe.',
    };
  }

  return {
    aceptado: true,
    origen: origenSegunFuente(verificacion.fuente),
    oficial: datosOficiales(verificacion, limpio),
  };
}

module.exports = {
  resolverOrigenValidacion,
  ORIGEN_VERIFICADO,
  ORIGEN_MANUAL,
  // Reexportadas para pruebas unitarias (__tests__/verificacionDocumento.test.js)
  // — son funciones puras, no tocan la red ni la base de datos.
  normalizar,
  esRucPeru,
  origenSegunFuente,
  datosOficiales,
};
