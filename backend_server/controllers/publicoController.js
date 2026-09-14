const { sql, getPool } = require('../config/db');
const { registrarAuditoria } = require('../utils/auditLog');
const { obtenerSiguienteNumeroPedidoDia } = require('../utils/numeracionPedidos');
const { buscarPersonaPorDni, buscarEmpresaPorRuc } = require('./externalController');
const {
  crearUsuarioPendienteActivacion,
  registrarActivacionCuenta,
  enviarCorreoActivacion,
} = require('../services/activacionService');
const {
  notificarPersonalTienda,
  SELECT_PEDIDOS_BASE,
  armarPedidosConItems,
  insertarItemsPedido,
  resumirProductos,
} = require('./pedidosController');
const { obtenerHorariosPanaderia, esMuyProntoParaHoy, esMuyTardeParaHoy, fueraDeHorarioAtencion, franjaEfectiva } = require('../utils/horariosPanaderia');
const {
  ESTADO_NO_APLICA,
  ESTADO_VERIFICANDO,
  requierePagoAdelanto,
  normalizarCodigoOperacion,
  codigoOperacionValido,
  validarMontoDeclarado,
  LARGO_MAXIMO_CODIGO,
} = require('../utils/pagoAdelanto');
const { calcularDescuentoCliente, aplicarDescuento } = require('../utils/descuentosCliente');
const { instantePeru, fechaEntregaEsAnteriorAHoy } = require('../utils/fechaPeru');
const crypto = require('crypto');
const { RUC_PERU_REGEX, EMAIL_REGEX, CELULAR_PERU_REGEX } = require('../middlewares/validators');
const { contactoEnmascarado, contactoVacio } = require('../utils/enmascarar');

// Tiendas que la página web pública puede mostrar/vender — Mercadería y
// Pastelería todavía no tienen catálogo real, y Horneados tiene precio
// variable (aderezo, tipo de carne) que no encaja en un pedido de un solo
// producto+cantidad como este.
const SLUGS_TIENDA_PUBLICA = ['hamburguesas', 'panaderia'];

// Pan vendido por unidad (Pan de Agua/Francés) tiene un pedido mínimo — el
// pan de hamburguesa no aplica, se vende por paquete de 12 a precio fijo.
// Misma regla que CANTIDAD_MINIMA_UNIDAD en pedidosController.js
// (crearMiPedido), para que el mínimo no dependa de qué canal usó el
// cliente (página web o app).
const CANTIDAD_MINIMA_UNIDAD = 50;

/** "22:00" -> "10pm" — mismo formato sin espacio ni puntos que usa la
 * página web, para que un mensaje de error del servidor se lea igual que
 * el resto del sitio. */
function formatearHora12(horaTexto) {
  const [h, m] = horaTexto.split(':').map(Number);
  const periodo = h >= 12 ? 'pm' : 'am';
  const hora12 = h % 12 === 0 ? 12 : h % 12;
  return m === 0 ? `${hora12}${periodo}` : `${hora12}:${String(m).padStart(2, '0')}${periodo}`;
}

/**
 * Límite simple en memoria (sin dependencia nueva): esta es la única ruta
 * de todo el backend sin JWT, y cada intento puede disparar una consulta
 * PAGA a apiperu.dev — sin esto, cualquiera podría automatizar pedidos y
 * agotar el saldo de la API o llenar Pedidos de basura. 5 intentos cada 15
 * minutos por IP alcanza de sobra para un cliente real pidiendo pan.
 */
const INTENTOS_MAXIMOS = 5;
const VENTANA_MS = 15 * 60 * 1000;
const intentosPorIp = new Map();

function limiteExcedido(ip) {
  const ahora = Date.now();
  const intentos = (intentosPorIp.get(ip) || []).filter((t) => ahora - t < VENTANA_MS);
  intentos.push(ahora);
  intentosPorIp.set(ip, intentos);
  return intentos.length > INTENTOS_MAXIMOS;
}

/**
 * Límite aparte (más alto) solo para consultar el estado de un pedido: a
 * diferencia de crear un pedido, esto no toca ninguna API paga, solo lee la
 * base — y la página lo usa para refrescarse sola cada 20s mientras el
 * cliente deja el panel abierto esperando el estado de su pedido. Con el
 * límite estricto de arriba (pensado para no gastar saldo de apiperu.dev),
 * ese sondeo agotaría el cupo en menos de dos minutos y el cliente se
 * quedaría viendo un error de "demasiados intentos" sin haber hecho nada
 * raro.
 */
const INTENTOS_MAXIMOS_CONSULTA = 60;
const intentosConsultaPorIp = new Map();

function limiteConsultaExcedido(ip) {
  const ahora = Date.now();
  const intentos = (intentosConsultaPorIp.get(ip) || []).filter((t) => ahora - t < VENTANA_MS);
  intentos.push(ahora);
  intentosConsultaPorIp.set(ip, intentos);
  return intentos.length > INTENTOS_MAXIMOS_CONSULTA;
}

/**
 * Límite aparte para verificar un DNI/RUC antes de enviar el pedido: a
 * diferencia de crearPedidoPublico, esto puede dispararse varias veces
 * mientras el cliente corrige un número mal tecleado, así que necesita más
 * margen que los 5/15min pensados para pedidos reales — pero sigue
 * pudiendo golpear la API paga de apiperu.dev (solo para documentos que
 * todavía no están en la base), así que no puede ser tan alto como el de
 * simple consulta de estado.
 */
const INTENTOS_MAXIMOS_VERIFICAR = 15;
const intentosVerificarPorIp = new Map();

function limiteVerificarExcedido(ip) {
  const ahora = Date.now();
  const intentos = (intentosVerificarPorIp.get(ip) || []).filter((t) => ahora - t < VENTANA_MS);
  intentos.push(ahora);
  intentosVerificarPorIp.set(ip, intentos);
  return intentos.length > INTENTOS_MAXIMOS_VERIFICAR;
}

/**
 * El token que ata la segunda petición (el código de operación) al pedido
 * recién creado. 32 caracteres hex de `crypto.randomBytes` — entra holgado
 * en `Pedidos.TokenConfirmacionPago VARCHAR(40)`.
 *
 * No es una credencial y no pretende serlo: lo único que impide es que
 * alguien adivine un `IdPedido` correlativo y le meta un código falso al
 * pedido de otra persona. El candado real es la máquina de estados (un
 * código se acepta UNA vez, solo mientras el pedido siga 'VERIFICANDO' y
 * sin código). Por eso no hay expiración ni hash: el pedido queda abierto
 * justamente hasta que su dueño vuelva de pagar, que puede ser mañana.
 */
function generarTokenConfirmacionPago() {
  return crypto.randomBytes(16).toString('hex');
}

/**
 * El medio de pago ACTIVO con el que el cliente web paga por adelantado en
 * una tienda: el Yape del negocio, con su número y (si el dueño lo subió)
 * la imagen del QR real. Se prefiere un YAPE; si no hay ninguno, se toma
 * cualquier otro medio activo antes que dejar al cliente sin nada.
 *
 * Devuelve null cuando la tienda no tiene ni un medio de pago cargado —
 * que es el estado de HOY: `MediosPagoTienda` está vacía para todas las
 * tiendas. La página está preparada para ese null y muestra un aviso de
 * "todavía no habilitamos el pago en línea" en vez de una caja rota.
 */
async function obtenerMedioPagoActivo(pool, tiendaSlug) {
  const result = await pool
    .request()
    .input('Slug', sql.VarChar(50), tiendaSlug)
    .query(`
      SELECT TOP 1 mp.IdMedioPago, mp.Tipo, mp.Titular, mp.NumeroDestino, mp.Notas, mp.ImagenQrBase64
      FROM MediosPagoTienda mp
      INNER JOIN Tiendas t ON t.IdTienda = mp.IdTienda
      WHERE t.Slug = @Slug AND t.Estado = 1 AND mp.Estado = 1
      ORDER BY CASE WHEN mp.Tipo = 'YAPE' THEN 0 ELSE 1 END, mp.IdMedioPago
    `);
  if (result.recordset.length === 0) return null;
  const medio = result.recordset[0];
  return {
    // `IdMedioPago` NO se expone: el visitante no tiene nada que hacer con
    // él y este endpoint es público. Solo lo que necesita para pagar.
    tipo: medio.Tipo,
    titular: medio.Titular,
    numeroDestino: medio.NumeroDestino,
    notas: medio.Notas ?? null,
    imagenQrBase64: medio.ImagenQrBase64 || null,
  };
}

/**
 * `GET /publico/medio-pago?tiendaSlug=panaderia` — a dónde yapear.
 *
 * Endpoint aparte y no un campo más del catálogo a propósito: la página
 * sondea el catálogo cada cierto tiempo mientras el visitante arma su
 * pedido, y el QR en base64 pesa cientos de KB. Esto se pide UNA vez, en el
 * momento en que aparece la pantalla de pago.
 */
async function obtenerMedioPagoPublico(req, res, next) {
  if (limiteConsultaExcedido(req.ip)) {
    return res.status(429).json({ mensaje: 'Demasiados intentos. Intenta de nuevo en unos minutos.' });
  }

  const tiendaSlug = String(req.query.tiendaSlug || '').trim();
  if (!SLUGS_TIENDA_PUBLICA.includes(tiendaSlug)) {
    return res.status(400).json({ mensaje: 'Tienda no válida.' });
  }

  try {
    const pool = await getPool();
    return res.status(200).json({ medioPago: await obtenerMedioPagoActivo(pool, tiendaSlug) });
  } catch (err) {
    return next(err);
  }
}

async function obtenerPrecioPaquete(pool) {
  const result = await pool.request().query("SELECT Valor FROM Configuraciones WHERE Clave = 'PRECIO_PAQUETE'");
  return result.recordset.length > 0 ? Number(result.recordset[0].Valor) : null;
}

/**
 * IdCliente a partir del IdPersona, con el mismo par de saltos
 * Personas -> Clientes que ya usa `consultarPedidosPublicos`. Devuelve null
 * cuando la persona existe pero todavía no es cliente (o cuando ni siquiera
 * hay fila en Personas): un visitante así es, por definición, un cliente
 * NUEVO — no un caso de error.
 */
async function buscarIdClientePorPersona(pool, idPersona) {
  if (!idPersona) return null;
  const result = await pool
    .request()
    .input('IdPersona', sql.Int, idPersona)
    .query('SELECT IdCliente FROM Clientes WHERE IdPersona = @IdPersona');
  return result.recordset.length > 0 ? result.recordset[0].IdCliente : null;
}

/**
 * El descuento por fidelidad tal como lo consume la página web:
 * `{ segmento, porcentaje }` o null.
 *
 * null cuando la tienda no vino en la petición, no es una tienda pública, o
 * no está en `DESCUENTOS_TIENDAS_HABILITADAS` — nunca un objeto con
 * porcentaje 0, para que el formulario no tenga que distinguir entre "no
 * hay descuento acá" y "hay descuento, de 0%".
 *
 * OJO: esto es solo para MOSTRARLE el descuento al cliente antes de que
 * envíe. El monto que de verdad se cobra lo recalcula el servidor en
 * `crearPedidoPublico` con el IdCliente real; nada de lo que responda este
 * endpoint se acepta de vuelta como entrada.
 */
async function resolverDescuentoPublico(pool, { idPersona, tiendaSlug }) {
  if (!tiendaSlug || !SLUGS_TIENDA_PUBLICA.includes(tiendaSlug)) return null;

  const idCliente = await buscarIdClientePorPersona(pool, idPersona);
  const descuento = await calcularDescuentoCliente({ pool, idCliente, tiendaSlug });
  if (!descuento.aplica || descuento.porcentaje <= 0) return null;

  return { segmento: descuento.segmento, porcentaje: descuento.porcentaje };
}

/** Catálogo público: solo lo que un visitante sin cuenta puede pedir desde
 * la página web, no expone la estructura interna de Tiendas/Categorias.
 * El pan de hamburguesa se vende por paquete de 12 a precio fijo (el mismo
 * que usa el personal en la app, Configuraciones.PRECIO_PAQUETE), no por
 * unidad suelta como el resto del catálogo, así que acá se marca con
 * `esPaquete` para que el formulario lo sepa y pida "cantidad de paquetes"
 * en vez de "cantidad de unidades". */
async function listarCatalogoPublico(req, res, next) {
  try {
    const pool = await getPool();
    const result = await pool.request().query(`
      SELECT p.IdProducto, p.Nombre, p.PrecioUnitario, t.Slug
      FROM Productos p
      INNER JOIN Categorias c ON c.IdCategoria = p.IdCategoria
      INNER JOIN Tiendas t ON t.IdTienda = c.IdTienda
      WHERE p.Estado = 1 AND t.Estado = 1 AND t.Slug IN ('${SLUGS_TIENDA_PUBLICA.join("','")}')
      ORDER BY p.IdProducto
    `);
    const precioPaquete = await obtenerPrecioPaquete(pool);
    const horarios = await obtenerHorariosPanaderia(pool);

    return res.status(200).json({
      productos: result.recordset.map((p) => {
        const esPaquete = p.Slug === 'hamburguesas';
        return {
          idProducto: p.IdProducto,
          nombre: p.Nombre,
          precioUnitario: esPaquete && precioPaquete != null ? precioPaquete : p.PrecioUnitario,
          esPaquete,
          // A qué tienda pertenece el producto. Lo necesita el formulario
          // para saber si el descuento por fidelidad aplica a lo que el
          // visitante eligió: la lista de tiendas habilitadas
          // (DESCUENTOS_TIENDAS_HABILITADAS) la decide el dueño desde la
          // app, así que la web no puede deducirla de `esPaquete`.
          tiendaSlug: p.Slug,
        };
      }),
      // Horario de pedido/recojo de los panes vendidos por unidad (Pan de
      // Agua/Francés) — el formulario lo usa para calcular la fecha/hora
      // mínima de recojo que puede elegir el cliente. No aplica al pan de
      // hamburguesa (esPaquete), que no tiene esta restricción.
      horarios,
    });
  } catch (err) {
    return next(err);
  }
}

/**
 * Pedido desde la página web pública, sin login: el visitante solo da su
 * DNI — se verifica contra RENIEC (misma lógica que usa el personal en la
 * app) y, si la persona no existía, se crea su Persona + Cliente. Si además
 * dejó un correo, se le crea una cuenta de acceso SIN activar y se le manda
 * un enlace para que él mismo elija su contraseña, así ya le funciona si
 * más adelante se descarga la app móvil; sin correo no se crea ninguna
 * cuenta. El pedido nace 'SOLICITADO' — igual que el autoservicio de la
 * app — porque nadie del personal lo revisó todavía; hay que llamar al
 * cliente a confirmar antes de darlo por bueno.
 *
 * PANADERÍA (pan por unidad) es la excepción: ahí el pedido se paga por
 * adelantado con Yape, así que nace además con
 * `EstadoPagoAdelanto = 'VERIFICANDO'` y un `TokenConfirmacionPago`. El
 * código de operación NO llega acá: el cliente todavía no pagó cuando
 * envía este formulario. Lo manda después, por
 * `registrarCodigoPagoPublico` — ver el porqué de esa separación en el
 * encabezado de `2026_09_pago_adelanto_panaderia.sql` (resumen: para pagar
 * hay que salir a la app de Yape, y volver al navegador a menudo encuentra
 * la pestaña recargada; con el pedido ya creado no se pierde nada).
 */
async function crearPedidoPublico(req, res, next) {
  if (limiteExcedido(req.ip)) {
    return res.status(429).json({ mensaje: 'Demasiados intentos. Intenta de nuevo en unos minutos, o contáctanos directamente.' });
  }

  // documento/telefono/cantidad ya vienen validados por
  // validateCrearPedidoPublico. `documento` acepta DNI (8 dígitos, se
  // valida contra RENIEC) o RUC (11 dígitos, contra SUNAT) — se distingue
  // solo por el largo, mismo criterio que ya usa validateCliente para el
  // registro manual de clientes.
  const { documento, telefono, email, items, notas, fechaEntrega } = req.body;
  const documentoLimpio = String(documento).trim();
  const esRuc = RUC_PERU_REGEX.test(documentoLimpio);
  // Ambos pueden llegar vacíos/ausentes: si el documento ya está registrado
  // con ese canal guardado, el formulario público NO lo reenvía (solo vio
  // una máscara, nunca el valor real). El celular que de verdad se usa para
  // el pedido se resuelve más abajo, ya con la fila de Personas a la vista.
  const telefonoBody = telefono === undefined || telefono === null ? '' : String(telefono).trim();
  const emailBody = email === undefined || email === null ? '' : String(email).trim();
  // Revalidación server-side del correo: el validador ya lo revisó, pero
  // esta es la única barrera real (no hay JWT detrás) y el valor termina en
  // la base, así que no se confía en que el middleware haya corrido.
  // El `includes('*')` descarta la máscara (`j***@gmail.com`), que
  // EMAIL_REGEX sí aceptaría — ver la misma guarda en el validador.
  const emailNuevo =
    emailBody.length > 0 && emailBody.length <= 150 && EMAIL_REGEX.test(emailBody) && !emailBody.includes('*')
      ? emailBody
      : null;

  const pool = await getPool();

  // La fecha/hora de recojo (solo pan de agua/francés, vendidos por
  // unidad) se valida ANTES de abrir la transacción. A propósito NO se
  // rechaza un horario fuera del rango configurado (Configuraciones) — el
  // cliente puede elegir cualquier hora, y si cae fuera del horario normal
  // el pedido se registra igual: el negocio confirma disponibilidad de
  // stock por WhatsApp antes de separarlo (ver PedidoForm.tsx, el aviso
  // que le muestra esto al cliente). Lo único que de verdad se exige es
  // una fecha/hora con formato válido y que no sea anterior a hoy.
  //
  // Con carrito, la fecha/hora de recojo sigue siendo UNA sola (es de la
  // cabecera del pedido): se exige en cuanto AL MENOS UNA línea sea de pan
  // por unidad. Un carrito solo de paquetes de hamburguesa sigue sin
  // necesitar hora de recojo, igual que antes.
  let fechaEntregaUtc = null;
  const idsProductos = items.map((i) => Number(i.idProducto));
  const productosPreview = await pool.request().query(`
      SELECT p.IdProducto, t.Slug
      FROM Productos p
      INNER JOIN Categorias c ON c.IdCategoria = p.IdCategoria
      INNER JOIN Tiendas t ON t.IdTienda = c.IdTienda
      WHERE p.IdProducto IN (${idsProductos.join(',')}) AND p.Estado = 1 AND t.Estado = 1
        AND t.Slug IN ('${SLUGS_TIENDA_PUBLICA.join("','")}')
    `);
  const hayPanPorUnidad = productosPreview.recordset.some((p) => p.Slug !== 'hamburguesas');

  if (hayPanPorUnidad) {
    const coincidencia = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$/.exec(String(fechaEntrega || ''));
    if (!coincidencia) {
      return res.status(400).json({ mensaje: 'Elige una fecha y hora de recojo válidas.' });
    }
    const [, anio, mes, dia, hora, minuto] = coincidencia.map(Number);
    const fechaPropuesta = instantePeru({ anio, mes, dia, hora, minuto });
    if (fechaEntregaEsAnteriorAHoy(fechaPropuesta)) {
      return res.status(400).json({ mensaje: 'La fecha de recojo no puede ser anterior a hoy.' });
    }
    const horarios = await obtenerHorariosPanaderia(pool);
    // Piso/tope duro que rige CUALQUIER fecha, no solo hoy: nunca se
    // recoge antes de que abra ni después de que cierre. Los interruptores
    // de franja (mañana/tarde) solo achican ese rango cuando la fecha
    // propuesta es HOY — son la señal de "hoy no queda stock de esa
    // hornada", no una decisión de horario que deba seguir aplicando a un
    // pedido de mañana (ver franjaEfectiva).
    if (fueraDeHorarioAtencion({ anio, mes, dia, hora, minuto }, horarios)) {
      const franja = franjaEfectiva({ anio, mes, dia }, horarios);
      const mensaje = franja
        ? `Atendemos de ${formatearHora12(franja.piso)} a ${formatearHora12(franja.tope)}. Elige una hora dentro de ese horario.`
        : 'Por ahora no estamos recibiendo pedidos nuevos. Intenta de nuevo más tarde.';
      return res.status(400).json({ mensaje });
    }
    // Único piso realmente duro adicional (a diferencia del horario
    // normal de recojo, que solo advierte): si la fecha elegida es hoy,
    // no se puede recoger en menos de "minutos de tolerancia" desde ahora
    // mismo — es el margen que necesita la tienda para confirmar stock
    // por WhatsApp antes de que llegue la hora que el cliente eligió.
    if (esMuyProntoParaHoy({ anio, mes, dia, hora, minuto }, horarios)) {
      return res.status(400).json({
        mensaje: `Para pedidos de hoy necesitamos al menos ${horarios.minutosTolerancia} minutos de anticipación. Elige una hora un poco más adelante.`,
      });
    }
    // Segundo piso duro: el negocio ya cerró para recoger hoy después de
    // esta hora, sin importar la tolerancia — el cliente tiene que elegir
    // desde mañana.
    if (esMuyTardeParaHoy({ anio, mes, dia, hora, minuto }, horarios)) {
      return res.status(400).json({
        mensaje: `Ya no se puede recoger hoy después de las ${formatearHora12(horarios.horaTopeRecojo)}. Elige una fecha desde mañana.`,
      });
    }
    fechaEntregaUtc = fechaPropuesta;
  }

  const transaction = new sql.Transaction(pool);

  // Datos del correo de activación, si este pedido terminó creando una
  // cuenta nueva. Se llena dentro de la transacción y se usa DESPUÉS del
  // commit: un correo enviado no se puede deshacer con un rollback.
  let activacionPendiente = null;

  try {
    await transaction.begin();

    // El precio del paquete de 12 es uno solo para toda la tienda de
    // Hamburguesas (Configuraciones.PRECIO_PAQUETE): se resuelve una vez
    // por request, no por línea.
    const precioPaquete = await obtenerPrecioPaquete(pool);

    const lineas = [];
    let idTienda = null;
    // Slug de la tienda del pedido (todas las líneas comparten tienda, ver
    // más abajo): lo necesita el descuento por fidelidad, que se habilita
    // por slug desde Configuraciones.
    let slugTienda = null;

    for (const item of items) {
      const productoResult = await new sql.Request(transaction)
        .input('IdProducto', sql.Int, item.idProducto)
        .query(`
          SELECT p.IdProducto, p.Nombre, p.PrecioUnitario, c.IdTienda, t.Slug
          FROM Productos p
          INNER JOIN Categorias c ON c.IdCategoria = p.IdCategoria
          INNER JOIN Tiendas t ON t.IdTienda = c.IdTienda
          WHERE p.IdProducto = @IdProducto AND p.Estado = 1 AND t.Estado = 1
            AND t.Slug IN ('${SLUGS_TIENDA_PUBLICA.join("','")}')
        `);
      if (productoResult.recordset.length === 0) {
        await transaction.rollback();
        return res.status(400).json({ mensaje: 'Uno de los productos ya no está disponible para pedir en línea.' });
      }
      const producto = productoResult.recordset[0];

      // Un pedido pertenece a una sola tienda — mismo criterio que la app
      // (ver crearPedido en pedidosController.js).
      if (idTienda === null) {
        idTienda = producto.IdTienda;
        slugTienda = producto.Slug;
      } else if (producto.IdTienda !== idTienda) {
        await transaction.rollback();
        return res.status(400).json({
          mensaje: 'Todos los productos de un pedido deben ser de la misma tienda.',
        });
      }

      // El pan de hamburguesa se vende por paquete de 12 a precio fijo (no por
      // unidad suelta) — mismo precio y mismo TipoPedido que usa el personal
      // en la app (ver crearMiPedido en pedidosController.js).
      const esPaquete = producto.Slug === 'hamburguesas';
      const tipoPedido = esPaquete ? 'PAQUETES' : 'UNIDADES';
      const cantidadNum = Number(item.cantidad);

      // El mínimo es por línea: 50 unidades de ESE pan, no 50 sumando dos
      // productos distintos.
      if (!esPaquete && cantidadNum < CANTIDAD_MINIMA_UNIDAD) {
        await transaction.rollback();
        return res.status(400).json({
          mensaje: `El pedido mínimo de ${producto.Nombre} es ${CANTIDAD_MINIMA_UNIDAD} unidades.`,
        });
      }

      const precioUnitario = esPaquete ? (precioPaquete ?? producto.PrecioUnitario) : producto.PrecioUnitario;

      lineas.push({
        idProducto: producto.IdProducto,
        producto: producto.Nombre,
        tipoPedido,
        cantidad: cantidadNum,
        precioUnitario,
        subtotal: Number((precioUnitario * cantidadNum).toFixed(2)),
      });
    }

    const personaExistente = await new sql.Request(transaction)
      .input('DNI', sql.VarChar(15), documentoLimpio)
      .query(`
        SELECT IdPersona, Nombres, ApellidoPaterno, Email, Telefono, EmailVerificado, TelefonoVerificado
        FROM Personas WHERE DNI = @DNI
      `);

    let idPersona;
    let nombreParaAviso;
    // Celular con el que de verdad se contacta al cliente por este pedido:
    // el que acaba de escribir, o el que ya teníamos guardado si no mandó
    // ninguno (porque el formulario se lo mostró enmascarado y él no lo
    // cambió). Nunca queda vacío: si no hay ni uno ni otro, se rechaza.
    let telefonoLimpio = telefonoBody;

    if (personaExistente.recordset.length > 0) {
      const persona = personaExistente.recordset[0];
      idPersona = persona.IdPersona;
      nombreParaAviso = [persona.Nombres, persona.ApellidoPaterno].filter(Boolean).join(' ');

      const telefonoGuardado = persona.Telefono ? String(persona.Telefono).trim() : '';
      const emailGuardado = persona.Email ? String(persona.Email).trim() : '';
      // BIT de MariaDB/mssql puede llegar como 1/0, true/false o Buffer
      // según el driver — Boolean() sobre el valor crudo alcanza para los
      // dos primeros, que son los que devuelve la capa de compatibilidad.
      //
      // Un canal sin valor guardado NO se considera bloqueado aunque su flag
      // esté en 1 (fila inconsistente): así el servidor decide exactamente
      // igual que el bloque `contacto` que vio la página (enArchivo:false =>
      // campo editable), y el cliente nunca queda trabado en un campo que el
      // formulario sí le dejó llenar.
      const telefonoVerificado = Boolean(persona.TelefonoVerificado) && telefonoGuardado.length > 0;
      const emailVerificado = Boolean(persona.EmailVerificado) && emailGuardado.length > 0;

      // Un canal YA VERIFICADO no se toca desde acá bajo ningún concepto:
      // cambiarlo exige pasar por el código de verificación dentro de la app
      // (ver CodigosVerificacion). El formulario público ni siquiera ofrece
      // editarlo, pero esta es la única barrera real — el body es del
      // cliente y podría venir con cualquier cosa.
      if (telefonoVerificado) {
        telefonoLimpio = telefonoGuardado;
      } else if (telefonoBody.length > 0 && telefonoBody !== telefonoGuardado) {
        await new sql.Request(transaction)
          .input('IdPersona', sql.Int, idPersona)
          .input('Telefono', sql.VarChar(20), telefonoBody)
          .query('UPDATE Personas SET Telefono = @Telefono WHERE IdPersona = @IdPersona');
      } else if (telefonoBody.length === 0) {
        telefonoLimpio = telefonoGuardado;
      }

      if (!emailVerificado && emailNuevo !== null && emailNuevo !== emailGuardado) {
        await new sql.Request(transaction)
          .input('IdPersona', sql.Int, idPersona)
          .input('Email', sql.VarChar(150), emailNuevo)
          .query('UPDATE Personas SET Email = @Email WHERE IdPersona = @IdPersona');
      }

      if (!CELULAR_PERU_REGEX.test(telefonoLimpio)) {
        await transaction.rollback();
        return res.status(400).json({ mensaje: 'Ingresa un número de celular válido de 9 dígitos.' });
      }
    } else {
      // Persona nueva: no hay nada guardado que reutilizar, así que el
      // celular tiene que venir sí o sí en el body (el formulario lo pide
      // como campo obligatorio en este caso).
      if (!CELULAR_PERU_REGEX.test(telefonoLimpio)) {
        await transaction.rollback();
        return res.status(400).json({ mensaje: 'Ingresa un número de celular válido de 9 dígitos.' });
      }
      // RUC (empresa/negocio, vía SUNAT) no tiene apellidos — se guarda la
      // razón social en Nombres, igual que ya hace el registro manual de
      // clientes-empresa en la app (ver Clientes/Personas, sin columna
      // propia de RUC: el documento vive en la misma columna DNI).
      const datosDocumento = esRuc
        ? await buscarEmpresaPorRuc(documentoLimpio)
        : await buscarPersonaPorDni(documentoLimpio);

      if (datosDocumento.fuente === 'NO_ENCONTRADO') {
        await transaction.rollback();
        return res.status(404).json({
          mensaje: esRuc
            ? 'No encontramos ese RUC en SUNAT. Verifica el número.'
            : 'No encontramos ese DNI en RENIEC. Verifica el número.',
        });
      }

      const nombres = esRuc ? datosDocumento.razonSocial : datosDocumento.nombres;
      const apellidoPaterno = esRuc ? '' : datosDocumento.apellidoPaterno || '';
      const apellidoMaterno = esRuc ? null : datosDocumento.apellidoMaterno || null;
      // 'RENIEC' para cualquier documento (DNI o RUC) confirmado por la API
      // real: la columna solo admite 'RENIEC'/'MANUAL' (ver
      // CK_Personas_OrigenValidacion en database_schema.sql), igual criterio
      // que resolverOrigenValidacion() en utils/verificacionDocumento.js.
      const origenValidacion = datosDocumento.fuente === 'API_REAL' ? 'RENIEC' : 'MANUAL';

      const nuevaPersona = await new sql.Request(transaction)
        .input('DNI', sql.VarChar(15), documentoLimpio)
        .input('Nombres', sql.NVarChar(100), nombres.toUpperCase())
        .input('ApellidoPaterno', sql.NVarChar(100), apellidoPaterno.toUpperCase())
        .input('ApellidoMaterno', sql.NVarChar(100), apellidoMaterno ? apellidoMaterno.toUpperCase() : null)
        .input('Telefono', sql.VarChar(20), telefonoLimpio)
        // El correo es opcional: si el visitante no lo dejó, la columna
        // queda NULL (nace sin verificar en los dos casos — EmailVerificado
        // tiene DEFAULT 0 —, la verificación real vive en la app).
        .input('Email', sql.VarChar(150), emailNuevo)
        .input('OrigenValidacion', sql.VarChar(20), origenValidacion)
        .query(`
          INSERT INTO Personas (DNI, Nombres, ApellidoPaterno, ApellidoMaterno, Telefono, Email, OrigenValidacion)
          OUTPUT INSERTED.IdPersona
          VALUES (@DNI, @Nombres, @ApellidoPaterno, @ApellidoMaterno, @Telefono, @Email, @OrigenValidacion)
        `);
      idPersona = nuevaPersona.recordset[0].IdPersona;
      nombreParaAviso = [nombres, apellidoPaterno].filter(Boolean).join(' ');

      // Cuenta de acceso para la app — SOLO si dejó un correo.
      //
      // Antes se creaba siempre, con usuario = DNI y contraseña = DNI. En
      // Perú el DNI está en cualquier boleta: eso equivalía a dejarle la
      // cuenta abierta a quien lo conociera, a una persona que ni sabía
      // que tenía cuenta. Ahora la cuenta nace inutilizable
      // (`Activado = 0`, contraseña aleatoria que nadie conoce) y se le
      // manda un correo para que ella misma elija su contraseña.
      //
      // Sin correo no hay a dónde mandar ese enlace, así que directamente
      // NO se crea ninguna cuenta: la Persona y el Cliente sí se crean
      // (el pedido tiene que quedar asociado a alguien), simplemente esa
      // persona todavía no tiene acceso a la app.
      //
      // Las tres escrituras (Persona, Usuario y el token) van dentro de la
      // MISMA transacción del pedido: si el pedido termina en rollback, no
      // queda ni una cuenta huérfana ni un token vivo. El correo, que no
      // se puede "desenviar", se manda recién después del commit.
      if (!esRuc && datosDocumento.fuente === 'API_REAL' && emailNuevo) {
        const cuenta = await crearUsuarioPendienteActivacion(transaction, {
          idPersona,
          nombreUsuario: documentoLimpio,
        });
        if (cuenta.creado) {
          const { token } = await registrarActivacionCuenta({ transaction, idPersona, destino: emailNuevo });
          activacionPendiente = { idPersona, destino: emailNuevo, token };
        }
      }
    }

    let clienteResult = await new sql.Request(transaction)
      .input('IdPersona', sql.Int, idPersona)
      .query('SELECT IdCliente FROM Clientes WHERE IdPersona = @IdPersona');

    let idCliente;
    if (clienteResult.recordset.length > 0) {
      idCliente = clienteResult.recordset[0].IdCliente;
    } else {
      const nuevoCliente = await new sql.Request(transaction)
        .input('IdPersona', sql.Int, idPersona)
        .query('INSERT INTO Clientes (IdPersona) OUTPUT INSERTED.IdCliente VALUES (@IdPersona)');
      idCliente = nuevoCliente.recordset[0].IdCliente;

      const rolResult = await new sql.Request(transaction).query("SELECT IdRol FROM Roles WHERE NombreRol = 'CLIENTE'");
      await new sql.Request(transaction)
        .input('IdPersona', sql.Int, idPersona)
        .input('IdRol', sql.Int, rolResult.recordset[0].IdRol)
        .query(`
          INSERT INTO PersonaRoles (IdPersona, IdRol)
          SELECT @IdPersona, @IdRol
          WHERE NOT EXISTS (SELECT 1 FROM PersonaRoles WHERE IdPersona = @IdPersona AND IdRol = @IdRol)
        `);
    }

    const subtotal = Number(lineas.reduce((acc, l) => acc + l.subtotal, 0).toFixed(2));

    // Descuento por fidelidad — ESTE es el cálculo que manda. El
    // formulario ya le mostró un descuento al cliente cuando escribió su
    // documento (ver verificarDocumentoPublico), pero eso fue solo
    // informativo: acá se vuelve a calcular desde cero con el IdCliente
    // real que se acaba de resolver, y el body del cliente HTTP no tiene
    // forma de influir en el porcentaje.
    //
    // Se consulta con `pool` y no con la transacción abierta a propósito:
    // lo que se mide es el historial YA COMMITEADO del cliente (pedidos
    // entregados de antes), no nada de lo que está pasando en esta
    // transacción — el pedido nuevo ni siquiera está insertado todavía, y
    // aunque lo estuviera nace 'SOLICITADO', que no cuenta como compra.
    const descuento = await calcularDescuentoCliente({ pool, idCliente, tiendaSlug: slugTienda });
    const descuentoPorcentaje = descuento.aplica ? descuento.porcentaje : 0;
    // `Total` guarda lo que el cliente DEBE PAGAR, ya descontado — mismo
    // significado que en todo el resto del sistema (deudas, resúmenes,
    // historial del CRM), así que nada río abajo necesita cambiar.
    const total = aplicarDescuento(subtotal, descuentoPorcentaje);

    const numeroPedidoDia = await obtenerSiguienteNumeroPedidoDia(transaction, idTienda);
    const notaWeb = `PEDIDO WEB — Cel: ${telefonoLimpio}${notas ? ' — ' + String(notas).trim().toUpperCase() : ''}`;

    // Pago por adelantado: solo Panadería con pan por unidad. Cualquier
    // otro pedido web (el pan de hamburguesa por paquete) sigue como
    // siempre, con 'NO_APLICA' y sin token — ver utils/pagoAdelanto.js.
    const exigePagoAdelanto = requierePagoAdelanto({ tiendaSlug: slugTienda, hayPanPorUnidad });
    const estadoPagoAdelanto = exigePagoAdelanto ? ESTADO_VERIFICANDO : ESTADO_NO_APLICA;
    const tokenConfirmacionPago = exigePagoAdelanto ? generarTokenConfirmacionPago() : null;

    const insertPedido = await new sql.Request(transaction)
      .input('IdCliente', sql.Int, idCliente)
      .input('IdTienda', sql.Int, idTienda)
      .input('Total', sql.Decimal(10, 2), total)
      .input('DescuentoPorcentaje', sql.Decimal(5, 2), descuentoPorcentaje)
      .input('Notas', sql.NVarChar(300), notaWeb.slice(0, 300))
      .input('NumeroPedidoDia', sql.Int, numeroPedidoDia)
      .input('FechaEntrega', sql.DateTime, fechaEntregaUtc)
      .input('EstadoPagoAdelanto', sql.VarChar(20), estadoPagoAdelanto)
      .input('TokenConfirmacionPago', sql.VarChar(40), tokenConfirmacionPago)
      .query(`
        INSERT INTO Pedidos (IdCliente, IdTienda, IdTrabajador, Total, DescuentoPorcentaje, Notas, NumeroPedidoDia, FechaEntrega, Estado, EstadoPagoAdelanto, TokenConfirmacionPago)
        OUTPUT INSERTED.IdPedido, INSERTED.FechaCreacion
        VALUES (@IdCliente, @IdTienda, NULL, @Total, @DescuentoPorcentaje, @Notas, @NumeroPedidoDia, @FechaEntrega, 'SOLICITADO', @EstadoPagoAdelanto, @TokenConfirmacionPago)
      `);
    const { IdPedido: idPedido } = insertPedido.recordset[0];

    await insertarItemsPedido(transaction, idPedido, lineas);

    await transaction.commit();

    // Correo de activación de la cuenta recién creada. Va después del
    // commit y con su propio try/catch: el pedido YA está guardado y es lo
    // que de verdad le importa al cliente en este momento. Si el envío
    // falla (Gmail caído, cuota agotada), no se le puede tirar abajo el
    // pedido ni devolverle un error — queda registrado en los logs del
    // servidor y la cuenta sigue esperando, sin activar, hasta que se
    // resuelva.
    if (activacionPendiente) {
      try {
        await enviarCorreoActivacion(activacionPendiente);
      } catch (err) {
        console.error('Error al enviar el correo de activación de cuenta:', err.message);
      }
    }

    const resumen = resumirProductos(lineas);

    await registrarAuditoria({
      idUsuario: null,
      accion: 'CREAR_PEDIDO_WEB_PUBLICO',
      tablaAfectada: 'Pedidos',
      registroAfectadoId: String(idPedido),
      datosNuevos: {
        documento: documentoLimpio,
        items: lineas,
        subtotal,
        descuentoPorcentaje,
        segmentoCliente: descuento.segmento,
        total,
        telefono: telefonoLimpio,
        email: emailNuevo,
      },
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    await notificarPersonalTienda({
      idTienda,
      titulo: 'Nuevo pedido desde la página web',
      cuerpo: exigePagoAdelanto
        ? `${nombreParaAviso} pidió ${resumen} — S/ ${total.toFixed(2)}. Está pagando por Yape; cuando mande su código, verifícalo en la app.`
        : `${nombreParaAviso} pidió ${resumen} — S/ ${total.toFixed(2)}. Cel: ${telefonoLimpio}. Confírmalo en la app.`,
      datos: { tipo: 'PEDIDO_SOLICITADO', idTienda: String(idTienda), idPedido: String(idPedido) },
    });

    return res.status(201).json({
      mensaje: exigePagoAdelanto
        ? 'Registramos tu pedido. Ahora paga por Yape y escribe tu código de operación para que lo confirmemos.'
        : 'Recibimos tu pedido. Te llamaremos al número que dejaste para confirmarlo.',
      // El pedido YA existe con estos dos datos, aunque todavía no se haya
      // pagado: son lo que la página guarda en localStorage para poder
      // retomar la pantalla de pago si la pestaña se muere mientras el
      // cliente está en Yape (ver el encabezado de esta función).
      idPedido,
      numeroPedidoDia,
      // Solo en Panadería. `tokenConfirmacionPago` es lo único de toda la
      // respuesta que no se le muestra al cliente: viaja para poder mandar
      // después el código de operación (registrarCodigoPagoPublico).
      estadoPagoAdelanto,
      tokenConfirmacionPago,
      // `total` sigue siendo lo que el cliente paga (ya descontado): la
      // pantalla de confirmación no cambia de significado. `subtotal` y
      // `descuentoCliente` se suman para poder mostrar el desglose de
      // cuánto se ahorró, y son los valores REALES que se guardaron.
      subtotal,
      total,
      descuentoCliente: descuentoPorcentaje > 0
        ? { segmento: descuento.segmento, porcentaje: descuentoPorcentaje }
        : null,
    });
  } catch (err) {
    await transaction.rollback();
    return next(err);
  }
}

/**
 * `POST /publico/pedidos/:idPedido/codigo-pago` — el segundo paso del pago
 * por adelantado: el cliente ya yapeó y escribe el código de operación que
 * le dio Yape, más cuánto pagó.
 *
 * Cómo se prueba que este pedido es suyo, sin login: o manda el
 * `tokenConfirmacionPago` que recibió al crearlo (el caso normal, viene de
 * localStorage), o manda el `documento` con el que lo hizo (el caso de
 * "se me murió la pestaña y estoy en otro celular", desde el seguimiento
 * por DNI que ya existe). Cualquiera de los dos alcanza: ninguno es una
 * credencial fuerte —el DNI en Perú no es un secreto— y lo que de verdad
 * limita el daño es que esto solo se puede hacer UNA vez, solo mientras el
 * pedido siga 'VERIFICANDO' y sin código, y que lo único que se puede
 * escribir es un código que después una persona va a contrastar contra el
 * Yape real.
 *
 * El estado NO cambia acá: sigue 'VERIFICANDO'. Pasa a PAGADO /
 * DEUDA_PARCIAL / VUELTO_PENDIENTE recién cuando el personal confirma
 * (pagoAdelantoController.js).
 */
async function registrarCodigoPagoPublico(req, res, next) {
  if (limiteExcedido(req.ip)) {
    return res.status(429).json({ mensaje: 'Demasiados intentos. Intenta de nuevo en unos minutos, o contáctanos directamente.' });
  }

  const idPedido = Number(req.params.idPedido);
  if (!Number.isInteger(idPedido) || idPedido <= 0) {
    return res.status(400).json({ mensaje: 'Pedido no encontrado.' });
  }

  const { token, documento } = req.body || {};
  const codigo = normalizarCodigoOperacion(req.body?.codigoOperacionYape);
  if (!codigoOperacionValido(codigo)) {
    return res.status(400).json({
      mensaje: `El código de operación de Yape son solo números (hasta ${LARGO_MAXIMO_CODIGO} dígitos). Cópialo tal cual de tu constancia.`,
    });
  }

  try {
    const pool = await getPool();
    const pedidoResult = await pool
      .request()
      .input('IdPedido', sql.Int, idPedido)
      .query(`
        SELECT pd.IdPedido, pd.NumeroPedidoDia, pd.IdTienda, pd.Total, pd.Estado,
               pd.EstadoPagoAdelanto, pd.CodigoOperacionYape, pd.TokenConfirmacionPago,
               per.DNI
        FROM Pedidos pd
        INNER JOIN Clientes c ON c.IdCliente = pd.IdCliente
        INNER JOIN Personas per ON per.IdPersona = c.IdPersona
        WHERE pd.IdPedido = @IdPedido
      `);

    if (pedidoResult.recordset.length === 0) {
      return res.status(404).json({ mensaje: 'No encontramos ese pedido.' });
    }
    const pedido = pedidoResult.recordset[0];

    // Mismo 404 que un pedido inexistente cuando ni el token ni el
    // documento coinciden: sin esto, probar tokens al azar contra un
    // `IdPedido` correlativo diría si ese pedido existe o no.
    const tokenCoincide =
      Boolean(pedido.TokenConfirmacionPago) &&
      typeof token === 'string' &&
      token.trim() === pedido.TokenConfirmacionPago;
    const documentoCoincide =
      typeof documento === 'string' && documento.trim().length > 0 && documento.trim() === String(pedido.DNI);
    if (!tokenCoincide && !documentoCoincide) {
      return res.status(404).json({ mensaje: 'No encontramos ese pedido.' });
    }

    if (pedido.EstadoPagoAdelanto !== ESTADO_VERIFICANDO) {
      return res.status(400).json({
        mensaje:
          pedido.EstadoPagoAdelanto === ESTADO_NO_APLICA
            ? 'Este pedido no se paga por adelantado.'
            : 'El pago de este pedido ya fue verificado por la tienda.',
      });
    }
    if (pedido.CodigoOperacionYape) {
      return res.status(400).json({
        mensaje: 'Ya registramos un código de operación para este pedido. Si te equivocaste, escríbenos por WhatsApp.',
      });
    }
    if (['CANCELADO', 'RECHAZADO'].includes(pedido.Estado)) {
      return res.status(400).json({ mensaje: 'Este pedido ya no está activo.' });
    }

    const total = Number(pedido.Total);
    // Red blanda contra el error honesto, no contra la mentira: quien
    // escriba un monto mayor al que pagó igual pasa por acá y lo descubre
    // el personal al mirar el Yape real (ver validarMontoDeclarado).
    const revision = validarMontoDeclarado(total, req.body?.montoDeclaradoCliente);
    if (!revision.valido) {
      return res.status(400).json({ mensaje: revision.mensaje });
    }
    const montoDeclarado = Number(req.body.montoDeclaradoCliente);

    try {
      await pool
        .request()
        .input('IdPedido', sql.Int, idPedido)
        .input('CodigoOperacionYape', sql.VarChar(30), codigo)
        .input('MontoDeclaradoCliente', sql.Decimal(10, 2), montoDeclarado)
        .query(`
          UPDATE Pedidos
          SET CodigoOperacionYape = @CodigoOperacionYape, MontoDeclaradoCliente = @MontoDeclaradoCliente
          WHERE IdPedido = @IdPedido AND CodigoOperacionYape IS NULL
        `);
    } catch (err) {
      // UQ_Pedidos_CodigoOperacionYape: ese código ya está en otro pedido.
      // ESTE es el mecanismo anti-doble-uso — un UNIQUE de base es atómico
      // aunque dos personas envíen el mismo código en el mismo instante,
      // cosa que un "consultar y después escribir" desde acá no puede
      // garantizar. Se traduce a un 400 con un mensaje entendible en vez de
      // dejarlo salir como un 500 genérico.
      if (err && (err.code === 'ER_DUP_ENTRY' || err.errno === 1062)) {
        return res.status(400).json({
          mensaje: 'Ese código de operación ya fue usado en otro pedido. Revisa tu constancia de Yape y copia el código correcto.',
        });
      }
      throw err;
    }

    await registrarAuditoria({
      idUsuario: null,
      accion: 'REGISTRAR_CODIGO_PAGO_WEB',
      tablaAfectada: 'Pedidos',
      registroAfectadoId: String(idPedido),
      datosNuevos: { codigoOperacionYape: codigo, montoDeclaradoCliente: montoDeclarado, total },
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    await notificarPersonalTienda({
      idTienda: pedido.IdTienda,
      titulo: 'Pago por Yape para verificar',
      cuerpo: `El pedido #${pedido.NumeroPedidoDia} reportó el código ${codigo} por S/ ${montoDeclarado.toFixed(2)} (total S/ ${total.toFixed(2)}). Revísalo en tu Yape y confírmalo.`,
      datos: {
        tipo: 'PAGO_ADELANTO_REPORTADO',
        idTienda: String(pedido.IdTienda),
        idPedido: String(idPedido),
      },
    });

    return res.status(200).json({
      mensaje: 'Recibimos tu código. Estamos verificando el pago con la tienda y te confirmamos apenas lo revisen.',
      idPedido,
      numeroPedidoDia: pedido.NumeroPedidoDia,
      estadoPagoAdelanto: ESTADO_VERIFICANDO,
      codigoOperacionYape: codigo,
      montoDeclaradoCliente: montoDeclarado,
      total,
    });
  } catch (err) {
    return next(err);
  }
}

/**
 * Consulta pública de pedidos por DNI o RUC, sin login: el visitante
 * escribe su documento (ya validado por validateConsultarPedidosPublico,
 * acepta cualquiera de los dos formatos) y ve el estado de cada uno de sus
 * pedidos recientes (pendiente de confirmar, rechazado, confirmado por
 * entregar o ya entregado) — la página lo vuelve a llamar sola cada cierto
 * tiempo mientras deja el panel abierto, para que el estado se actualice
 * sin que tenga que volver a buscar a mano. Es una búsqueda pura contra
 * nuestra propia base (columna `Personas.DNI`, que guarda DNI y RUC por
 * igual — ver convención del resto del backend): nunca gasta un consumo
 * de apiperu.dev, a diferencia de verificarDocumentoPublico.
 */
async function consultarPedidosPublicos(req, res, next) {
  if (limiteConsultaExcedido(req.ip)) {
    return res.status(429).json({ mensaje: 'Demasiados intentos. Intenta de nuevo en unos minutos.' });
  }

  const dniLimpio = String(req.query.dni).trim();

  try {
    const pool = await getPool();

    const personaResult = await pool.request()
      .input('DNI', sql.VarChar(15), dniLimpio)
      .query('SELECT IdPersona, Nombres, ApellidoPaterno FROM Personas WHERE DNI = @DNI');
    if (personaResult.recordset.length === 0) {
      return res.status(200).json({ nombre: null, pedidos: [] });
    }
    const { IdPersona: idPersona, Nombres: nombres, ApellidoPaterno: apellidoPaterno } = personaResult.recordset[0];

    const clienteResult = await pool.request()
      .input('IdPersona', sql.Int, idPersona)
      .query('SELECT IdCliente FROM Clientes WHERE IdPersona = @IdPersona');
    if (clienteResult.recordset.length === 0) {
      return res.status(200).json({ nombre: [nombres, apellidoPaterno].filter(Boolean).join(' '), pedidos: [] });
    }
    const { IdCliente: idCliente } = clienteResult.recordset[0];

    // Los 20 más recientes de cualquier estado (antes solo se mostraban
    // SOLICITADO/PENDIENTE) — así el cliente ve si su pedido fue
    // rechazado, confirmado o ya entregado, no solo mientras sigue
    // pendiente. Un tope razonable, no todo el historial de siempre.
    const pedidosResult = await pool.request()
      .input('IdCliente', sql.Int, idCliente)
      .query(`SELECT TOP 20 * FROM (${SELECT_PEDIDOS_BASE} WHERE pd.IdCliente = @IdCliente) sub ORDER BY sub.FechaCreacion DESC`);

    return res.status(200).json({
      nombre: [nombres, apellidoPaterno].filter(Boolean).join(' '),
      pedidos: await armarPedidosConItems(pool, pedidosResult.recordset),
    });
  } catch (err) {
    return next(err);
  }
}

/**
 * Verifica si un DNI/RUC existe de verdad (RENIEC/SUNAT) ANTES de que el
 * cliente llene el resto del formulario y lo envíe — sin esto, alguien
 * podía escribir un documento inventado y solo enterarse de que no existe
 * al final, después de completar todo. No crea nada (a diferencia de
 * crearPedidoPublico, que si el documento existe de verdad crea la
 * Persona/Cliente): esto solo responde sí/no.
 *
 * Primero mira la propia base (Personas) — si el documento ya está
 * registrado ahí Y ese registro nació de una verificación real (RENIEC o
 * SUNAT), responde de una sin gastar ni un solo consumo de la API paga.
 * Un registro 'MANUAL' (cargado a mano por el personal, ej. un cliente de
 * prueba o alguien que dictó mal su número) NO cuenta como verificado acá
 * — su sola presencia en la base no prueba que el documento sea real, así
 * que igual se revalida contra RENIEC/SUNAT.
 *
 * Con `?tiendaSlug=panaderia` (opcional) además devuelve `descuentoCliente`:
 * el descuento por fidelidad que le tocaría a ese documento en esa tienda,
 * para que el formulario pueda mostrárselo antes de enviar el pedido. Sin
 * el parámetro —o si esa tienda no tiene el descuento habilitado— el campo
 * viaja en null y el formulario se comporta como siempre. El slug va en la
 * consulta y no se deduce del documento porque este endpoint se llama
 * apenas el visitante termina de teclear su DNI, cuando el servidor todavía
 * no sabe nada del carrito.
 */
async function verificarDocumentoPublico(req, res, next) {
  if (limiteVerificarExcedido(req.ip)) {
    return res.status(429).json({ mensaje: 'Demasiados intentos. Intenta de nuevo en unos minutos.' });
  }

  const documentoLimpio = String(req.query.documento || '').trim();
  const esRuc = RUC_PERU_REGEX.test(documentoLimpio);
  const tiendaSlug = String(req.query.tiendaSlug || '').trim();

  try {
    const pool = await getPool();
    // La fila se busca SIN filtrar por OrigenValidacion, pero el filtro
    // sigue existiendo (`esCacheValida`): solo un registro nacido de una
    // verificación real ahorra la consulta paga. La diferencia es que ahora
    // el contacto guardado se puede aprovechar igual aunque la fila sea
    // 'MANUAL' — si no, un cliente cargado a mano por el personal vería los
    // campos vacíos acá y sin embargo, al enviar, el servidor conservaría
    // sus datos verificados: dos comportamientos distintos para la misma
    // fila. Que el documento exista de verdad se sigue decidiendo igual.
    const existente = await pool.request()
      .input('DNI', sql.VarChar(15), documentoLimpio)
      .query(`
        SELECT IdPersona, Email, Telefono, EmailVerificado, TelefonoVerificado, OrigenValidacion
        FROM Personas WHERE DNI = @DNI
      `);
    const filaPersona = existente.recordset.length > 0 ? existente.recordset[0] : null;
    // `contacto` le dice a la página qué canales ya tenemos guardados de
    // este documento y cuáles están verificados, para que pueda
    // autocompletarlos en vez de pedirlos de nuevo. SIEMPRE enmascarado: el
    // DNI en Perú no es un secreto fuerte, así que devolver el correo o el
    // celular completos convertiría este endpoint público en una forma de
    // extraer el contacto real de cualquiera con solo saber su documento
    // (ver utils/enmascarar.js).
    const contacto = filaPersona ? contactoEnmascarado(filaPersona) : contactoVacio();
    // Se calcula una sola vez y sirve para las dos salidas de "documento
    // válido" de abajo. Un documento que todavía no tiene fila en Personas
    // igual recibe su descuento: `idPersona` null -> sin Cliente -> sin
    // historial -> segmento NUEVO, que también descuenta.
    const descuentoCliente = await resolverDescuentoPublico(pool, {
      idPersona: filaPersona ? filaPersona.IdPersona : null,
      tiendaSlug,
    });

    const esCacheValida = filaPersona && ['RENIEC', 'SUNAT'].includes(filaPersona.OrigenValidacion);
    if (esCacheValida) {
      return res.status(200).json({ existe: true, contacto, descuentoCliente });
    }

    const datosDocumento = esRuc
      ? await buscarEmpresaPorRuc(documentoLimpio)
      : await buscarPersonaPorDni(documentoLimpio);

    if (datosDocumento.fuente === 'NO_ENCONTRADO') {
      return res.status(200).json({
        existe: false,
        contacto: contactoVacio(),
        // Un documento que RENIEC/SUNAT no reconoce no va a poder pedir
        // nada, así que tampoco tiene sentido anunciarle un descuento.
        descuentoCliente: null,
        mensaje: esRuc
          ? 'No encontramos ese RUC en SUNAT. Verifica el número.'
          : 'No encontramos ese DNI en RENIEC. Verifica el número.',
      });
    }

    // Documento confirmado por RENIEC/SUNAT. `contacto` va vacío si nunca
    // pidió por acá (no hay fila en Personas), o con lo que ya tuviéramos
    // guardado si la fila existía pero era 'MANUAL'.
    return res.status(200).json({ existe: true, contacto, descuentoCliente });
  } catch (err) {
    return next(err);
  }
}

module.exports = {
  listarCatalogoPublico,
  crearPedidoPublico,
  registrarCodigoPagoPublico,
  consultarPedidosPublicos,
  verificarDocumentoPublico,
  obtenerMedioPagoPublico,
};
