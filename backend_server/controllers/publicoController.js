const { sql, getPool } = require('../config/db');
const { registrarAuditoria } = require('../utils/auditLog');
const { obtenerSiguienteNumeroPedidoDia } = require('../utils/numeracionPedidos');
const { buscarPersonaPorDni, buscarEmpresaPorRuc } = require('./externalController');
const { intentarClonarUsuarioCliente } = require('./clientesController');
const { notificarPersonalTienda, SELECT_PEDIDOS_BASE, mapearFilaPedido } = require('./pedidosController');
const { obtenerHorariosPanaderia, esMuyProntoParaHoy } = require('../utils/horariosPanaderia');
const { instantePeru, fechaEntregaEsAnteriorAHoy } = require('../utils/fechaPeru');
const { RUC_PERU_REGEX } = require('../middlewares/validators');

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

async function obtenerPrecioPaquete(pool) {
  const result = await pool.request().query("SELECT Valor FROM Configuraciones WHERE Clave = 'PRECIO_PAQUETE'");
  return result.recordset.length > 0 ? Number(result.recordset[0].Valor) : null;
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
 * app) y, si la persona no existía, se crea su Persona + Cliente + una
 * cuenta de acceso (usuario=DNI, contraseña=DNI, con cambio obligatorio en
 * el primer ingreso) para que ya le funcione si más adelante se descarga la
 * app móvil. El pedido nace 'SOLICITADO' — igual que el autoservicio de la
 * app — porque nadie del personal lo revisó todavía; hay que llamar al
 * cliente a confirmar antes de darlo por bueno.
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
  const { documento, telefono, idProducto, cantidad, notas, fechaEntrega } = req.body;
  const documentoLimpio = String(documento).trim();
  const esRuc = RUC_PERU_REGEX.test(documentoLimpio);
  const telefonoLimpio = String(telefono).trim();
  const cantidadNum = Number(cantidad);

  const pool = await getPool();

  // La fecha/hora de recojo (solo pan de agua/francés, vendidos por
  // unidad) se valida ANTES de abrir la transacción. A propósito NO se
  // rechaza un horario fuera del rango configurado (Configuraciones) — el
  // cliente puede elegir cualquier hora, y si cae fuera del horario normal
  // el pedido se registra igual: el negocio confirma disponibilidad de
  // stock por WhatsApp antes de separarlo (ver PedidoForm.tsx, el aviso
  // que le muestra esto al cliente). Lo único que de verdad se exige es
  // una fecha/hora con formato válido y que no sea anterior a hoy.
  let fechaEntregaUtc = null;
  const productoPreview = await pool.request()
    .input('IdProducto', sql.Int, idProducto)
    .query(`
      SELECT t.Slug
      FROM Productos p
      INNER JOIN Categorias c ON c.IdCategoria = p.IdCategoria
      INNER JOIN Tiendas t ON t.IdTienda = c.IdTienda
      WHERE p.IdProducto = @IdProducto AND p.Estado = 1 AND t.Estado = 1
        AND t.Slug IN ('${SLUGS_TIENDA_PUBLICA.join("','")}')
    `);
  const esPaquetePreview = productoPreview.recordset[0]?.Slug === 'hamburguesas';

  if (!esPaquetePreview) {
    const coincidencia = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$/.exec(String(fechaEntrega || ''));
    if (!coincidencia) {
      return res.status(400).json({ mensaje: 'Elige una fecha y hora de recojo válidas.' });
    }
    const [, anio, mes, dia, hora, minuto] = coincidencia.map(Number);
    const fechaPropuesta = instantePeru({ anio, mes, dia, hora, minuto });
    if (fechaEntregaEsAnteriorAHoy(fechaPropuesta)) {
      return res.status(400).json({ mensaje: 'La fecha de recojo no puede ser anterior a hoy.' });
    }
    // Único piso realmente duro (a diferencia del horario normal de
    // recojo, que solo advierte): si la fecha elegida es hoy, no se puede
    // recoger en menos de "minutos de tolerancia" desde ahora mismo — es
    // el margen que necesita la tienda para confirmar stock por WhatsApp
    // antes de que llegue la hora que el cliente eligió.
    const horarios = await obtenerHorariosPanaderia(pool);
    if (esMuyProntoParaHoy({ anio, mes, dia, hora, minuto }, horarios)) {
      return res.status(400).json({
        mensaje: `Para pedidos de hoy necesitamos al menos ${horarios.minutosTolerancia} minutos de anticipación. Elige una hora un poco más adelante.`,
      });
    }
    fechaEntregaUtc = fechaPropuesta;
  }

  const transaction = new sql.Transaction(pool);

  try {
    await transaction.begin();

    const productoResult = await new sql.Request(transaction)
      .input('IdProducto', sql.Int, idProducto)
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
      return res.status(400).json({ mensaje: 'Ese producto ya no está disponible para pedir en línea.' });
    }
    const { Nombre: nombreProducto, IdTienda: idTienda, Slug: slugTienda } = productoResult.recordset[0];

    // El pan de hamburguesa se vende por paquete de 12 a precio fijo (no por
    // unidad suelta) — mismo precio y mismo TipoPedido que usa el personal
    // en la app (ver crearMiPedido en pedidosController.js).
    const esPaquete = slugTienda === 'hamburguesas';
    const tipoPedido = esPaquete ? 'PAQUETES' : 'UNIDADES';

    if (!esPaquete && cantidadNum < CANTIDAD_MINIMA_UNIDAD) {
      await transaction.rollback();
      return res.status(400).json({
        mensaje: `El pedido mínimo de ${nombreProducto} es ${CANTIDAD_MINIMA_UNIDAD} unidades.`,
      });
    }

    const precioUnitario = esPaquete
      ? (await obtenerPrecioPaquete(pool)) ?? productoResult.recordset[0].PrecioUnitario
      : productoResult.recordset[0].PrecioUnitario;

    const personaExistente = await new sql.Request(transaction)
      .input('DNI', sql.VarChar(15), documentoLimpio)
      .query('SELECT IdPersona, Nombres, ApellidoPaterno FROM Personas WHERE DNI = @DNI');

    let idPersona;
    let nombreParaAviso;

    if (personaExistente.recordset.length > 0) {
      idPersona = personaExistente.recordset[0].IdPersona;
      nombreParaAviso = [personaExistente.recordset[0].Nombres, personaExistente.recordset[0].ApellidoPaterno].filter(Boolean).join(' ');
    } else {
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
      const origenValidacion = esRuc
        ? (datosDocumento.fuente === 'API_REAL' ? 'SUNAT' : 'MANUAL')
        : (datosDocumento.fuente === 'API_REAL' ? 'RENIEC' : 'MANUAL');

      const nuevaPersona = await new sql.Request(transaction)
        .input('DNI', sql.VarChar(15), documentoLimpio)
        .input('Nombres', sql.NVarChar(100), nombres.toUpperCase())
        .input('ApellidoPaterno', sql.NVarChar(100), apellidoPaterno.toUpperCase())
        .input('ApellidoMaterno', sql.NVarChar(100), apellidoMaterno ? apellidoMaterno.toUpperCase() : null)
        .input('Telefono', sql.VarChar(20), telefonoLimpio)
        .input('OrigenValidacion', sql.VarChar(20), origenValidacion)
        .query(`
          INSERT INTO Personas (DNI, Nombres, ApellidoPaterno, ApellidoMaterno, Telefono, OrigenValidacion)
          OUTPUT INSERTED.IdPersona
          VALUES (@DNI, @Nombres, @ApellidoPaterno, @ApellidoMaterno, @Telefono, @OrigenValidacion)
        `);
      idPersona = nuevaPersona.recordset[0].IdPersona;
      nombreParaAviso = [nombres, apellidoPaterno].filter(Boolean).join(' ');

      if (!esRuc && datosDocumento.fuente === 'API_REAL') {
        await intentarClonarUsuarioCliente(transaction, idPersona, documentoLimpio);
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

    const total = Number((precioUnitario * cantidadNum).toFixed(2));
    const numeroPedidoDia = await obtenerSiguienteNumeroPedidoDia(transaction, idTienda);
    const notaWeb = `PEDIDO WEB — Cel: ${telefonoLimpio}${notas ? ' — ' + String(notas).trim().toUpperCase() : ''}`;

    const insertPedido = await new sql.Request(transaction)
      .input('IdCliente', sql.Int, idCliente)
      .input('IdTienda', sql.Int, idTienda)
      .input('IdProducto', sql.Int, idProducto)
      .input('TipoPedido', sql.VarChar(20), tipoPedido)
      .input('Cantidad', sql.Int, cantidadNum)
      .input('PrecioUnitario', sql.Decimal(10, 2), precioUnitario)
      .input('Total', sql.Decimal(10, 2), total)
      .input('Notas', sql.NVarChar(300), notaWeb.slice(0, 300))
      .input('NumeroPedidoDia', sql.Int, numeroPedidoDia)
      .input('FechaEntrega', sql.DateTime, fechaEntregaUtc)
      .query(`
        INSERT INTO Pedidos (IdCliente, IdTienda, IdProducto, IdTrabajador, TipoPedido, Cantidad, PrecioUnitario, Total, Notas, NumeroPedidoDia, FechaEntrega, Estado)
        OUTPUT INSERTED.IdPedido, INSERTED.FechaCreacion
        VALUES (@IdCliente, @IdTienda, @IdProducto, NULL, @TipoPedido, @Cantidad, @PrecioUnitario, @Total, @Notas, @NumeroPedidoDia, @FechaEntrega, 'SOLICITADO')
      `);
    const { IdPedido: idPedido } = insertPedido.recordset[0];

    await transaction.commit();

    await registrarAuditoria({
      idUsuario: null,
      accion: 'CREAR_PEDIDO_WEB_PUBLICO',
      tablaAfectada: 'Pedidos',
      registroAfectadoId: String(idPedido),
      datosNuevos: { documento: documentoLimpio, idProducto, cantidad: cantidadNum, total, telefono: telefonoLimpio },
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    await notificarPersonalTienda({
      idTienda,
      titulo: 'Nuevo pedido desde la página web',
      cuerpo: `${nombreParaAviso} pidió ${cantidadNum} — S/ ${total.toFixed(2)}. Cel: ${telefonoLimpio}. Confírmalo en la app.`,
      datos: { tipo: 'PEDIDO_SOLICITADO', idTienda: String(idTienda), idPedido: String(idPedido) },
    });

    return res.status(201).json({
      mensaje: 'Recibimos tu pedido. Te llamaremos al número que dejaste para confirmarlo.',
      numeroPedidoDia,
      total,
    });
  } catch (err) {
    await transaction.rollback();
    return next(err);
  }
}

/**
 * Consulta pública de pedidos por DNI, sin login: el visitante solo escribe
 * su DNI (ya validado por validateConsultarPedidosPublico) y ve el estado
 * de cada uno de sus pedidos recientes (pendiente de confirmar, rechazado,
 * confirmado por entregar o ya entregado) — la página lo vuelve a llamar
 * sola cada cierto tiempo mientras deja el panel abierto, para que el
 * estado se actualice sin que tenga que volver a buscar a mano.
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
      pedidos: pedidosResult.recordset.map((fila) => mapearFilaPedido(fila)),
    });
  } catch (err) {
    return next(err);
  }
}

module.exports = { listarCatalogoPublico, crearPedidoPublico, consultarPedidosPublicos };
