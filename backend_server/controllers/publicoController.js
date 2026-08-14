const { sql, getPool } = require('../config/db');
const { registrarAuditoria } = require('../utils/auditLog');
const { obtenerSiguienteNumeroPedidoDia } = require('../utils/numeracionPedidos');
const { buscarPersonaPorDni } = require('./externalController');
const { intentarClonarUsuarioCliente } = require('./clientesController');
const { notificarPersonalTienda } = require('./pedidosController');

// Tiendas que la página web pública puede mostrar/vender — Mercadería y
// Pastelería todavía no tienen catálogo real, y Horneados tiene precio
// variable (aderezo, tipo de carne) que no encaja en un pedido de un solo
// producto+cantidad como este.
const SLUGS_TIENDA_PUBLICA = ['hamburguesas', 'panaderia'];

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

/** Catálogo público: solo lo que un visitante sin cuenta puede pedir desde
 * la página web — no expone la estructura interna de Tiendas/Categorias. */
async function listarCatalogoPublico(req, res, next) {
  try {
    const pool = await getPool();
    const result = await pool.request().query(`
      SELECT p.IdProducto, p.Nombre, p.PrecioUnitario
      FROM Productos p
      INNER JOIN Categorias c ON c.IdCategoria = p.IdCategoria
      INNER JOIN Tiendas t ON t.IdTienda = c.IdTienda
      WHERE p.Estado = 1 AND t.Estado = 1 AND t.Slug IN ('${SLUGS_TIENDA_PUBLICA.join("','")}')
      ORDER BY p.IdProducto
    `);
    return res.status(200).json({
      productos: result.recordset.map((p) => ({
        idProducto: p.IdProducto,
        nombre: p.Nombre,
        precioUnitario: p.PrecioUnitario,
      })),
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

  // dni/telefono/cantidad ya vienen validados por validateCrearPedidoPublico.
  const { dni, telefono, idProducto, cantidad, notas } = req.body;
  const dniLimpio = String(dni).trim();
  const telefonoLimpio = String(telefono).trim();
  const cantidadNum = Number(cantidad);

  const pool = await getPool();
  const transaction = new sql.Transaction(pool);

  try {
    await transaction.begin();

    const productoResult = await new sql.Request(transaction)
      .input('IdProducto', sql.Int, idProducto)
      .query(`
        SELECT p.IdProducto, p.Nombre, p.PrecioUnitario, c.IdTienda
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
    const { IdTienda: idTienda, PrecioUnitario: precioUnitario } = productoResult.recordset[0];

    const personaExistente = await new sql.Request(transaction)
      .input('DNI', sql.VarChar(15), dniLimpio)
      .query('SELECT IdPersona, Nombres, ApellidoPaterno FROM Personas WHERE DNI = @DNI');

    let idPersona;
    let nombreParaAviso;

    if (personaExistente.recordset.length > 0) {
      idPersona = personaExistente.recordset[0].IdPersona;
      nombreParaAviso = [personaExistente.recordset[0].Nombres, personaExistente.recordset[0].ApellidoPaterno].filter(Boolean).join(' ');
    } else {
      const datosDni = await buscarPersonaPorDni(dniLimpio);
      if (datosDni.fuente === 'NO_ENCONTRADO') {
        await transaction.rollback();
        return res.status(404).json({ mensaje: 'No encontramos ese DNI en RENIEC. Verifica el número.' });
      }

      const nuevaPersona = await new sql.Request(transaction)
        .input('DNI', sql.VarChar(15), dniLimpio)
        .input('Nombres', sql.NVarChar(100), datosDni.nombres.toUpperCase())
        .input('ApellidoPaterno', sql.NVarChar(100), (datosDni.apellidoPaterno || '').toUpperCase())
        .input('ApellidoMaterno', sql.NVarChar(100), (datosDni.apellidoMaterno || '').toUpperCase() || null)
        .input('Telefono', sql.VarChar(20), telefonoLimpio)
        .input('OrigenValidacion', sql.VarChar(20), datosDni.fuente === 'API_REAL' ? 'RENIEC' : 'MANUAL')
        .query(`
          INSERT INTO Personas (DNI, Nombres, ApellidoPaterno, ApellidoMaterno, Telefono, OrigenValidacion)
          OUTPUT INSERTED.IdPersona
          VALUES (@DNI, @Nombres, @ApellidoPaterno, @ApellidoMaterno, @Telefono, @OrigenValidacion)
        `);
      idPersona = nuevaPersona.recordset[0].IdPersona;
      nombreParaAviso = [datosDni.nombres, datosDni.apellidoPaterno].filter(Boolean).join(' ');

      if (datosDni.fuente === 'API_REAL') {
        await intentarClonarUsuarioCliente(transaction, idPersona, dniLimpio);
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
      .input('TipoPedido', sql.VarChar(20), 'UNIDADES')
      .input('Cantidad', sql.Int, cantidadNum)
      .input('PrecioUnitario', sql.Decimal(10, 2), precioUnitario)
      .input('Total', sql.Decimal(10, 2), total)
      .input('Notas', sql.NVarChar(300), notaWeb.slice(0, 300))
      .input('NumeroPedidoDia', sql.Int, numeroPedidoDia)
      .query(`
        INSERT INTO Pedidos (IdCliente, IdTienda, IdProducto, IdTrabajador, TipoPedido, Cantidad, PrecioUnitario, Total, Notas, NumeroPedidoDia, Estado)
        OUTPUT INSERTED.IdPedido, INSERTED.FechaCreacion
        VALUES (@IdCliente, @IdTienda, @IdProducto, NULL, @TipoPedido, @Cantidad, @PrecioUnitario, @Total, @Notas, @NumeroPedidoDia, 'SOLICITADO')
      `);
    const { IdPedido: idPedido } = insertPedido.recordset[0];

    await transaction.commit();

    await registrarAuditoria({
      idUsuario: null,
      accion: 'CREAR_PEDIDO_WEB_PUBLICO',
      tablaAfectada: 'Pedidos',
      registroAfectadoId: String(idPedido),
      datosNuevos: { dni: dniLimpio, idProducto, cantidad: cantidadNum, total, telefono: telefonoLimpio },
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

module.exports = { listarCatalogoPublico, crearPedidoPublico };
