const axios = require('axios');
const { sql, getPool } = require('../config/db');

/**
 * Consulta real de DNI/RUC contra apiperu.dev (RENIEC/SUNAT). Si la API de
 * pago falla (red, timeout, token vencido, etc.) cae de forma elegante a un
 * simulador local para no bloquear las pruebas ni la operación diaria.
 *
 * `fuente` en la respuesta indica de dónde vinieron los datos:
 *   'API_REAL'  -> apiperu.dev respondió con éxito (dispara la clonación
 *                  automática de Usuario en clientesController.js).
 *   'SIMULADO'  -> se usó el simulador local (no dispara clonación).
 */

const API_PERU_BASE_URL = process.env.API_PERU_BASE_URL || 'https://apiperu.dev/api';

/**
 * El token vive en Configuraciones (editable por el SUPERADMIN desde la
 * app, ver configuracionesController.js) — se relee de la BD en cada
 * consulta, así un cambio hecho desde la app surte efecto de inmediato, sin
 * reiniciar el servidor. Si la fila todavía no existe (o la BD no
 * responde), cae a la variable de entorno como red de seguridad.
 */
async function obtenerTokenApiPeru() {
  try {
    const pool = await getPool();
    const result = await pool
      .request()
      .input('Clave', sql.VarChar(50), 'API_PERU_TOKEN')
      .query('SELECT Valor FROM Configuraciones WHERE Clave = @Clave');
    const valor = result.recordset[0]?.Valor?.trim();
    if (valor) return valor;
  } catch (err) {
    console.warn('No se pudo leer API_PERU_TOKEN de la BD, usando variable de entorno:', err.message);
  }
  return process.env.API_PERU_TOKEN || null;
}

function crearClienteApiPeru(token) {
  return axios.create({
    baseURL: API_PERU_BASE_URL,
    timeout: 6000,
    headers: token ? { Authorization: `Bearer ${token}` } : {},
  });
}

/**
 * Memoria de corta duración de las respuestas DEFINITIVAS de apiperu.dev.
 *
 * Existe por una razón muy concreta de costo: apiperu.dev es una API PAGA
 * con cupo limitado, y desde que el backend dejó de creerle al cliente HTTP
 * cuando dice `origenValidacion: 'RENIEC'` (ver utils/verificacionDocumento.js),
 * el MISMO documento se consulta dos veces en un alta normal: una cuando el
 * formulario pulsa "Buscar" (POST /api/externo/dni) y otra cuando el
 * servidor comprueba por su cuenta al guardar el cliente. Con esta memoria,
 * la segunda consulta la responde el propio proceso — sin gastar un consumo
 * más — pero la respuesta sigue siendo del servidor, nunca del cliente: es
 * la respuesta que ESTE proceso recibió de la API real, no un dato que
 * viajó por la red y podría venir manipulado.
 *
 * Solo se recuerdan las respuestas AUTORITATIVAS de la API real
 * ('API_REAL' y 'NO_ENCONTRADO'). 'SIMULADO' nunca se guarda: es una
 * respuesta degradada (la API no estaba disponible) y recordarla dejaría al
 * servidor devolviendo datos inventados durante media hora después de que
 * apiperu.dev ya volvió a funcionar.
 */
const MEMORIA_TTL_MS = Number(process.env.VERIFICACION_DOCUMENTO_TTL_MS) || 30 * 60 * 1000;
const MEMORIA_MAXIMA = 300;
const memoriaDocumentos = new Map();

function purgarMemoriaVencida(ahora) {
  for (const [clave, entrada] of memoriaDocumentos) {
    if (entrada.expiraEn <= ahora) memoriaDocumentos.delete(clave);
  }
}

function recordarConsulta(documento, resultado) {
  if (resultado.fuente !== 'API_REAL' && resultado.fuente !== 'NO_ENCONTRADO') return resultado;

  const ahora = Date.now();
  if (memoriaDocumentos.size >= MEMORIA_MAXIMA) {
    purgarMemoriaVencida(ahora);
    // Tope duro: si después de purgar sigue llena (mucho movimiento en poco
    // tiempo), se descarta la entrada más antigua. Es una caché, no un
    // registro — perder una entrada solo cuesta una consulta más.
    if (memoriaDocumentos.size >= MEMORIA_MAXIMA) {
      memoriaDocumentos.delete(memoriaDocumentos.keys().next().value);
    }
  }
  memoriaDocumentos.set(documento, { resultado, expiraEn: ahora + MEMORIA_TTL_MS });
  return resultado;
}

function leerConsultaRecordada(documento) {
  const entrada = memoriaDocumentos.get(documento);
  if (!entrada) return null;
  if (entrada.expiraEn <= Date.now()) {
    memoriaDocumentos.delete(documento);
    return null;
  }
  return entrada.resultado;
}

/** Solo para pruebas: deja la memoria en blanco entre casos. */
function olvidarConsultasRecordadas() {
  memoriaDocumentos.clear();
}

const NOMBRES = [
  'Carlos', 'María', 'José', 'Ana', 'Luis', 'Rosa', 'Jorge', 'Carmen', 'Miguel', 'Lucía',
  'Pedro', 'Elena', 'Juan', 'Sofía', 'Diego', 'Valentina', 'Fernando', 'Gabriela', 'Ricardo', 'Patricia',
];

const APELLIDOS = [
  'García', 'Rodríguez', 'Martínez', 'López', 'González', 'Pérez', 'Sánchez', 'Ramírez', 'Torres', 'Flores',
  'Vargas', 'Castillo', 'Rojas', 'Mendoza', 'Chávez', 'Quispe', 'Huamán', 'Vega', 'Salazar', 'Cruz',
];

const RUBROS = [
  'Restaurante', 'Bodega', 'Panadería', 'Minimarket', 'Cevichería',
  'Pollería', 'Cafetería', 'Distribuidora', 'Abarrotes', 'Pastelería',
];

const DISTRITOS = [
  'San Juan de Lurigancho', 'Los Olivos', 'Comas', 'San Martín de Porres', 'Ate',
  'Villa El Salvador', 'Surco', 'Miraflores', 'La Victoria', 'El Agustino',
];

const ESTADOS_RUC = ['ACTIVO', 'ACTIVO', 'ACTIVO', 'SUSPENDIDO', 'BAJA DEFINITIVA'];
const CONDICIONES_RUC = ['HABIDO', 'HABIDO', 'HABIDO', 'NO HALLADO'];

// DNI de prueba fijo, para poder demostrar el flujo sin gastar cupo de la
// API real ni depender de que esté disponible.
const DNI_DEMO = '72701801';
const DNI_DEMO_DATOS = { nombres: 'Briam Luis', apellidoPaterno: 'Ronceros', apellidoMaterno: 'Achuli' };

/**
 * SUNAT suele devolver '-' (o cadena vacía) para indicar "sin dato" en
 * campos como nombre comercial o domicilio fiscal. Se normaliza a '' para
 * que el frontend pueda distinguir con un simple isEmpty en vez de tener
 * que conocer esta convención de la API.
 */
function limpiarValorSunat(valor) {
  const limpio = (valor || '').trim();
  return limpio === '-' ? '' : limpio;
}

/**
 * Llama a apiperu.dev y clasifica el resultado en tres estados distintos:
 *   'ENCONTRADO'    -> la API respondió con éxito y trae los datos.
 *   'NO_ENCONTRADO' -> la API respondió pero el documento no existe/es
 *                      inválido (success:false, sin datos, o un status
 *                      HTTP de "no encontrado"). Nunca debe caer al
 *                      simulador: inventar datos aquí sería mostrarle al
 *                      vendedor un cliente que SUNAT/RENIEC dice que no
 *                      existe.
 *   'NO_DISPONIBLE' -> la API no pudo responder en absoluto (red, timeout,
 *                      token vencido, error 5xx). Aquí sí es razonable caer
 *                      al simulador para no bloquear la operación diaria.
 */
async function consultarApiPeru(client, endpoint, body, tieneExito) {
  try {
    const { data } = await client.post(endpoint, body);
    if (tieneExito(data)) return { estado: 'ENCONTRADO', data };
    return { estado: 'NO_ENCONTRADO' };
  } catch (err) {
    const status = err.response?.status;
    const data = err.response?.data;
    // apiperu.dev a veces marca "no encontrado" con success:false pero
    // devolviendo un status HTTP de error (confirmado: 500 en /dni para DNIs
    // no asignados) en vez de un 404 limpio. Se trata igual como "no
    // encontrado" — nunca como caída del servicio — mientras el cuerpo
    // confirme explícitamente success:false.
    if (status === 404 || status === 422 || status === 400 || data?.success === false) {
      return { estado: 'NO_ENCONTRADO' };
    }
    return { estado: 'NO_DISPONIBLE', error: err };
  }
}

function sumaDigitos(texto) {
  let suma = 0;
  for (const caracter of texto) {
    const digito = Number(caracter);
    if (!Number.isNaN(digito)) suma += digito;
  }
  return suma;
}

function simularPersonaPorDni(dni) {
  if (dni === DNI_DEMO) return { dni, ...DNI_DEMO_DATOS };

  const semilla = sumaDigitos(dni);
  return {
    dni,
    nombres: NOMBRES[semilla % NOMBRES.length],
    apellidoPaterno: APELLIDOS[(semilla * 7 + 3) % APELLIDOS.length],
    apellidoMaterno: APELLIDOS[(semilla * 13 + 5) % APELLIDOS.length],
  };
}

function simularEmpresaPorRuc(ruc) {
  const semilla = sumaDigitos(ruc);
  const rubro = RUBROS[semilla % RUBROS.length];
  const distrito = DISTRITOS[(semilla * 3 + 1) % DISTRITOS.length];
  const apellidoEmpresa = APELLIDOS[(semilla * 11 + 2) % APELLIDOS.length];
  const numeroDireccion = 100 + (semilla % 900);
  const esPersonaNatural = ruc.startsWith('10');
  // Una de cada cinco simulaciones no tiene nombre comercial ni domicilio
  // fiscal registrado (como pasa en la vida real), para poder probar que
  // el formulario deja esos campos vacíos en vez de rellenarlos solo.
  const sinDatosOpcionales = semilla % 5 === 0;

  return {
    ruc,
    razonSocial: esPersonaNatural
      ? `${NOMBRES[semilla % NOMBRES.length].toUpperCase()} ${apellidoEmpresa.toUpperCase()}`
      : `${rubro.toUpperCase()} ${apellidoEmpresa.toUpperCase()} E.I.R.L.`,
    nombreComercial: sinDatosOpcionales ? '' : `${rubro} ${apellidoEmpresa}`,
    direccion: sinDatosOpcionales ? '' : `AV. LOS PROCERES ${numeroDireccion}, ${distrito}`,
    estado: ESTADOS_RUC[semilla % ESTADOS_RUC.length],
    condicion: CONDICIONES_RUC[semilla % CONDICIONES_RUC.length],
  };
}

/**
 * Núcleo de la consulta de DNI, sin la capa HTTP — para que otros
 * controllers (ver publicoController.js, el pedido web público) puedan
 * reusar exactamente la misma lógica (API real -> simulador de respaldo)
 * sin pasar por una petición Express de por medio.
 * Devuelve `fuente`: 'API_REAL' | 'SIMULADO' | 'NO_ENCONTRADO'.
 */
async function buscarPersonaPorDni(dni) {
  const documento = String(dni).trim();
  const recordado = leerConsultaRecordada(documento);
  if (recordado) return recordado;

  const tokenApiPeru = await obtenerTokenApiPeru();
  if (tokenApiPeru) {
    const cliente = crearClienteApiPeru(tokenApiPeru);
    const resultado = await consultarApiPeru(cliente, '/dni', { dni: documento }, (data) => Boolean(data?.success && data.data?.nombres));

    if (resultado.estado === 'ENCONTRADO') {
      const { data } = resultado;
      return recordarConsulta(documento, {
        fuente: 'API_REAL',
        dni: data.data.numero || documento,
        nombres: data.data.nombres,
        apellidoPaterno: data.data.apellido_paterno || '',
        apellidoMaterno: data.data.apellido_materno || '',
      });
    }

    if (resultado.estado === 'NO_ENCONTRADO') {
      return recordarConsulta(documento, { fuente: 'NO_ENCONTRADO' });
    }

    console.warn('apiperu.dev /dni no disponible, usando simulador:', resultado.error.message);
  }

  return { fuente: 'SIMULADO', ...simularPersonaPorDni(documento) };
}

async function consultarDni(req, res) {
  const dni = req.body.dni ?? req.params.dni;

  if (!/^\d{8}$/.test(String(dni || ''))) {
    return res.status(400).json({ mensaje: 'El DNI debe tener 8 dígitos numéricos' });
  }

  const resultado = await buscarPersonaPorDni(String(dni));

  if (resultado.fuente === 'NO_ENCONTRADO') {
    return res.status(404).json({
      mensaje: 'Documento no encontrado. El DNI ingresado no se encuentra registrado o es inválido.',
      encontrado: false,
    });
  }

  const mensaje = resultado.fuente === 'API_REAL'
    ? 'Consulta real de RENIEC (apiperu.dev)'
    : 'Consulta simulada de RENIEC (apiperu.dev no disponible)';
  return res.status(200).json({ mensaje, ...resultado });
}

/**
 * Núcleo de la consulta de RUC, sin la capa HTTP — mismo motivo que
 * buscarPersonaPorDni: para que otros controllers (ver publicoController.js,
 * el pedido web público cuando el cliente elige "RUC") puedan reusar
 * exactamente la misma lógica (API real -> simulador de respaldo) sin pasar
 * por una petición Express de por medio.
 * Devuelve `fuente`: 'API_REAL' | 'SIMULADO' | 'NO_ENCONTRADO'.
 */
async function buscarEmpresaPorRuc(ruc) {
  const documento = String(ruc).trim();
  const recordado = leerConsultaRecordada(documento);
  if (recordado) return recordado;

  const tokenApiPeru = await obtenerTokenApiPeru();
  if (tokenApiPeru) {
    const cliente = crearClienteApiPeru(tokenApiPeru);
    const resultado = await consultarApiPeru(cliente, '/ruc', { ruc: documento }, (data) => Boolean(data?.success && data.data?.nombre_o_razon_social));

    if (resultado.estado === 'ENCONTRADO') {
      const { data } = resultado;
      return recordarConsulta(documento, {
        fuente: 'API_REAL',
        ruc: data.data.ruc || documento,
        razonSocial: data.data.nombre_o_razon_social,
        // Si SUNAT no tiene nombre comercial registrado, se deja vacío
        // (nunca se rellena con la razón social) para que el vendedor
        // pueda escribir uno a mano si lo desea.
        nombreComercial: limpiarValorSunat(data.data.nombre_comercial),
        direccion: limpiarValorSunat(data.data.direccion_completa || data.data.direccion),
        estado: data.data.estado || '',
        condicion: data.data.condicion || '',
      });
    }

    if (resultado.estado === 'NO_ENCONTRADO') {
      return recordarConsulta(documento, { fuente: 'NO_ENCONTRADO' });
    }

    console.warn('apiperu.dev /ruc no disponible, usando simulador:', resultado.error.message);
  }

  return { fuente: 'SIMULADO', ...simularEmpresaPorRuc(documento) };
}

/**
 * Un único punto de entrada para "que el servidor compruebe este documento
 * por su cuenta", sin que quien llama tenga que saber si el número es un DNI
 * (8 dígitos -> RENIEC) o un RUC (11 -> SUNAT). Un documento con cualquier
 * otra forma no es consultable: se responde 'NO_ENCONTRADO' sin gastar un
 * consumo de la API paga.
 */
async function verificarDocumentoOficial(documento) {
  const limpio = String(documento || '').trim();
  if (/^\d{11}$/.test(limpio)) return buscarEmpresaPorRuc(limpio);
  if (/^\d{8}$/.test(limpio)) return buscarPersonaPorDni(limpio);
  return { fuente: 'NO_ENCONTRADO' };
}

async function consultarRuc(req, res) {
  const ruc = req.body.ruc ?? req.params.ruc;

  if (!/^\d{11}$/.test(String(ruc || ''))) {
    return res.status(400).json({ mensaje: 'El RUC debe tener 11 dígitos numéricos' });
  }

  const resultado = await buscarEmpresaPorRuc(String(ruc));

  if (resultado.fuente === 'NO_ENCONTRADO') {
    return res.status(404).json({
      mensaje: 'Documento no encontrado. El RUC ingresado no se encuentra registrado o es inválido.',
      encontrado: false,
    });
  }

  const mensaje = resultado.fuente === 'API_REAL'
    ? 'Consulta real de SUNAT (apiperu.dev)'
    : 'Consulta simulada de SUNAT (apiperu.dev no disponible)';
  return res.status(200).json({ mensaje, ...resultado });
}

module.exports = {
  consultarDni,
  consultarRuc,
  buscarPersonaPorDni,
  buscarEmpresaPorRuc,
  verificarDocumentoOficial,
  // Reexportados para pruebas unitarias (__tests__/verificacionDocumento.test.js).
  olvidarConsultasRecordadas,
  leerConsultaRecordada,
  recordarConsulta,
};
