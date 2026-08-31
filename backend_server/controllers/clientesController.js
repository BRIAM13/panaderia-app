const bcrypt = require('bcryptjs');
const { sql, getPool } = require('../config/db');
const { registrarAuditoria } = require('../utils/auditLog');
const { solicitarCodigo, verificarCodigo, OtpError } = require('../services/otpService');
const { enviarPush } = require('../services/pushService');

const SALT_ROUNDS = Number(process.env.BCRYPT_SALT_ROUNDS) || 12;

function calcularCalidadDato(dni, origenValidacion) {
  if (!dni) return 'SIN_DNI';
  return origenValidacion === 'RENIEC' ? 'RENIEC' : 'MANUAL';
}

/**
 * RUC que empieza con '20' es Persona Jurídica (empresa): por definición no
 * tiene apellidos. Se fuerza server-side (no solo en el formulario) para que
 * ningún cliente llegue a guardar apellidos "fantasma" en una empresa.
 */
function esRucPersonaJuridica(dni) {
  return typeof dni === 'string' && /^20\d{9}$/.test(dni);
}

/**
 * Todo dato de texto libre (nombres, apellidos, dirección, descripción de
 * negocio) se guarda en mayúsculas — nunca a mitad de camino confiando solo
 * en el formatter del teclado del cliente: el backend es la garantía final,
 * igual que ya pasa con el trim(). Email y teléfono NO pasan por aquí.
 */
function mayuscula(valor) {
  return valor ? valor.trim().toUpperCase() : valor;
}

// CRM — claves de Configuraciones que controlan los umbrales de
// segmentación y la conversión de puntos de fidelidad, mismo patrón que
// PRECIO_PAQUETE/horariosPanaderia.js: se leen de la BD en cada consulta,
// así un cambio hecho desde la app surte efecto de inmediato.
const CLAVE_DIAS_EN_RIESGO = 'CLIENTES_DIAS_EN_RIESGO';
const CLAVE_PEDIDOS_FRECUENTE = 'CLIENTES_PEDIDOS_FRECUENTE';
const CLAVE_UMBRAL_VIP_SOLES = 'CLIENTES_UMBRAL_VIP_SOLES';
const CLAVE_SOLES_POR_PUNTO = 'CLIENTES_SOLES_POR_PUNTO';

async function obtenerConfiguracionesCrm(pool) {
  const result = await pool.request().query(`
    SELECT Clave, Valor FROM Configuraciones
    WHERE Clave IN ('${CLAVE_DIAS_EN_RIESGO}', '${CLAVE_PEDIDOS_FRECUENTE}', '${CLAVE_UMBRAL_VIP_SOLES}', '${CLAVE_SOLES_POR_PUNTO}')
  `);
  const mapa = Object.fromEntries(result.recordset.map((r) => [r.Clave, r.Valor]));
  return {
    diasEnRiesgo: Number(mapa[CLAVE_DIAS_EN_RIESGO]) || 30,
    pedidosFrecuente: Number(mapa[CLAVE_PEDIDOS_FRECUENTE]) || 5,
    umbralVipSoles: Number(mapa[CLAVE_UMBRAL_VIP_SOLES]) || 200,
    solesPorPunto: Number(mapa[CLAVE_SOLES_POR_PUNTO]) || 10,
  };
}

/**
 * Segmento del cliente según su historial de pedidos ENTREGADOS (los
 * únicos que cuentan como compra real, no pedidos rechazados/cancelados
 * ni todavía pendientes). Reglas, en orden de prioridad:
 *   'NUEVO'      -> nunca se le entregó un pedido.
 *   'EN_RIESGO'  -> ya compró antes, pero no hace más de `diasEnRiesgo`.
 *   'VIP'        -> gastó en total (entregado) al menos `umbralVipSoles`.
 *   'FRECUENTE'  -> al menos `pedidosFrecuente` pedidos entregados.
 *   'REGULAR'    -> cualquier otro cliente con compras.
 */
function calcularSegmento({ pedidosEntregados, totalGastado, diasDesdeUltimaCompra }, config) {
  if (!pedidosEntregados) return 'NUEVO';
  if (diasDesdeUltimaCompra !== null && diasDesdeUltimaCompra > config.diasEnRiesgo) return 'EN_RIESGO';
  if (totalGastado >= config.umbralVipSoles) return 'VIP';
  if (pedidosEntregados >= config.pedidosFrecuente) return 'FRECUENTE';
  return 'REGULAR';
}

// Orden fijo de los segmentos en el resumen de analítica: es el que usa la
// pantalla para dibujar las barras, y tiene que ser estable aunque no haya
// ni un cliente en alguno de ellos (una barra que desaparece y reaparece
// según el día haría imposible comparar dos capturas del panel).
const SEGMENTOS = ['NUEVO', 'EN_RIESGO', 'VIP', 'FRECUENTE', 'REGULAR'];
const TOPE_TOP_POR_GASTO = 10;

/**
 * Mismo criterio que `Cliente.nombreParaMostrar` en la app: un cliente con
 * RUC (11 dígitos) se muestra por su razón social, que vive entera en
 * `Nombres`; uno con DNI, por su nombre y apellidos.
 */
function nombreParaMostrar(fila) {
  if (fila.DNI && String(fila.DNI).length === 11) return fila.Nombres;
  return [fila.Nombres, fila.ApellidoPaterno, fila.ApellidoMaterno]
    .filter((parte) => parte && String(parte).trim())
    .join(' ')
    .trim();
}

/**
 * Núcleo puro de `obtenerResumenSegmentos`: recibe las filas ya agregadas
 * por cliente y devuelve el conteo por segmento más las dos listas que
 * mueven la aguja del negocio (a quién reactivar, a quién cuidar). Se
 * mantiene separado de la consulta para poder probarlo sin base de datos.
 *
 * `ahora` es un parámetro y no `Date.now()` directo porque el cálculo de
 * "días desde la última compra" es lo que decide el segmento EN_RIESGO: sin
 * poder fijar el reloj, la prueba dependería del día en que se ejecuta.
 */
function resumirSegmentosClientes(filas, config, ahora = Date.now()) {
  const resumen = Object.fromEntries(SEGMENTOS.map((s) => [s, 0]));

  const clientes = filas.map((fila) => {
    const ultimaCompra = fila.UltimaCompra ? new Date(fila.UltimaCompra) : null;
    const diasDesdeUltimaCompra = ultimaCompra
      ? Math.floor((ahora - ultimaCompra.getTime()) / 86400000)
      : null;
    const pedidosEntregados = Number(fila.PedidosEntregados) || 0;
    const totalGastado = Number(fila.TotalGastado) || 0;
    const segmento = calcularSegmento(
      { pedidosEntregados, totalGastado, diasDesdeUltimaCompra },
      config,
    );

    resumen[segmento] += 1;

    return {
      idCliente: fila.IdCliente,
      nombre: nombreParaMostrar(fila),
      telefono: fila.Telefono || null,
      pedidosEntregados,
      totalGastado,
      diasDesdeUltimaCompra,
      segmento,
    };
  });

  // Los más abandonados primero: es el orden en que conviene llamarlos.
  const enRiesgo = clientes
    .filter((c) => c.segmento === 'EN_RIESGO')
    .sort((a, b) => b.diasDesdeUltimaCompra - a.diasDesdeUltimaCompra);

  // Sin filtrar por segmento a propósito: un top 10 por gasto cae casi todo
  // en VIP solo, y si alguno no llega al umbral igual merece estar ahí.
  const topPorGasto = clientes
    .filter((c) => c.totalGastado > 0)
    .sort((a, b) => b.totalGastado - a.totalGastado)
    .slice(0, TOPE_TOP_POR_GASTO);

  return { resumen, totalClientes: clientes.length, enRiesgo, topPorGasto };
}

/**
 * CRM — analítica: la foto de TODA la cartera de clientes activos en una
 * sola consulta, en vez de pedir `obtenerPerfilCliente` uno por uno (que
 * serían N+1 consultas para dibujar un gráfico). Mismo criterio de compra
 * real (solo pedidos ENTREGADO) y mismos umbrales configurables que el
 * perfil individual, así el panel nunca contradice lo que dice la ficha de
 * un cliente puntual.
 */
async function obtenerResumenSegmentos(req, res, next) {
  try {
    const pool = await getPool();
    const config = await obtenerConfiguracionesCrm(pool);

    // LEFT JOIN (no INNER): un cliente sin ningún pedido todavía es
    // justamente el segmento NUEVO — desaparecería del conteo con un INNER.
    const result = await pool.request().query(`
      SELECT c.IdCliente,
             p.DNI, p.Nombres, p.ApellidoPaterno, p.ApellidoMaterno, p.Telefono,
             COALESCE(SUM(CASE WHEN pd.Estado = 'ENTREGADO' THEN 1 ELSE 0 END), 0) AS PedidosEntregados,
             COALESCE(SUM(CASE WHEN pd.Estado = 'ENTREGADO' THEN pd.Total ELSE 0 END), 0) AS TotalGastado,
             MAX(CASE WHEN pd.Estado = 'ENTREGADO' THEN COALESCE(pd.FechaEntregaReal, pd.FechaCreacion) END) AS UltimaCompra
      FROM Clientes c
      INNER JOIN Personas p ON p.IdPersona = c.IdPersona
      LEFT JOIN Pedidos pd ON pd.IdCliente = c.IdCliente
      WHERE c.Estado = 1
      GROUP BY c.IdCliente, p.DNI, p.Nombres, p.ApellidoPaterno, p.ApellidoMaterno, p.Telefono
    `);

    return res.status(200).json(resumirSegmentosClientes(result.recordset, config));
  } catch (err) {
    return next(err);
  }
}

function mapearCliente(fila) {
  return {
    idCliente: fila.IdCliente,
    idPersona: fila.IdPersona,
    dni: fila.DNI,
    nombres: fila.Nombres,
    apellidoPaterno: fila.ApellidoPaterno,
    apellidoMaterno: fila.ApellidoMaterno,
    telefono: fila.Telefono,
    email: fila.Email,
    direccion: fila.Direccion,
    descripcionNegocio: fila.DescripcionNegocio,
    nombreComercialOficial: Boolean(fila.NombreComercialOficial),
    origenValidacion: fila.OrigenValidacion,
    calidadDato: calcularCalidadDato(fila.DNI, fila.OrigenValidacion),
    puntosFidelidad: fila.PuntosFidelidad,
    activo: fila.Estado === undefined ? true : Boolean(fila.Estado),
    telefonoVerificado: Boolean(fila.TelefonoVerificado),
    emailVerificado: Boolean(fila.EmailVerificado),
  };
}

/**
 * CRM — perfil de cliente con historial agregado (gasto total, pedidos
 * entregados, deuda pendiente, última compra, tiendas donde compró) y su
 * segmento calculado al vuelo. Solo cuenta pedidos ENTREGADO como compra
 * real: uno pendiente/rechazado/cancelado no debe inflar el historial ni
 * la fecha de "última compra".
 */
async function obtenerPerfilCliente(req, res, next) {
  const { id } = req.params;

  try {
    const pool = await getPool();

    const clienteResult = await pool
      .request()
      .input('IdCliente', sql.Int, id)
      .query(`
        SELECT c.IdCliente, c.DescripcionNegocio, c.NombreComercialOficial, c.PuntosFidelidad, c.Estado,
               p.IdPersona, p.DNI, p.Nombres, p.ApellidoPaterno, p.ApellidoMaterno,
               p.Telefono, p.Email, p.Direccion, p.OrigenValidacion, p.TelefonoVerificado, p.EmailVerificado
        FROM Clientes c
        INNER JOIN Personas p ON p.IdPersona = c.IdPersona
        WHERE c.IdCliente = @IdCliente
      `);
    const filaCliente = clienteResult.recordset[0];
    if (!filaCliente) return res.status(404).json({ mensaje: 'Cliente no encontrado' });

    const agregadoResult = await pool
      .request()
      .input('IdCliente', sql.Int, id)
      .query(`
        SELECT
          COUNT(*) AS TotalPedidos,
          SUM(CASE WHEN Estado = 'ENTREGADO' THEN 1 ELSE 0 END) AS PedidosEntregados,
          COALESCE(SUM(CASE WHEN Estado = 'ENTREGADO' THEN Total ELSE 0 END), 0) AS TotalGastado,
          COALESCE(SUM(CASE WHEN Estado = 'ENTREGADO' AND EstadoPago = 'DEUDA' THEN Total ELSE 0 END), 0) AS DeudaPendiente,
          MAX(CASE WHEN Estado = 'ENTREGADO' THEN COALESCE(FechaEntregaReal, FechaCreacion) END) AS UltimaCompra
        FROM Pedidos
        WHERE IdCliente = @IdCliente
      `);
    const agregado = agregadoResult.recordset[0];

    const tiendasResult = await pool
      .request()
      .input('IdCliente', sql.Int, id)
      .query(`
        SELECT DISTINCT t.IdTienda, t.Nombre
        FROM Pedidos pd
        INNER JOIN Tiendas t ON t.IdTienda = pd.IdTienda
        WHERE pd.IdCliente = @IdCliente AND pd.Estado = 'ENTREGADO'
      `);

    const config = await obtenerConfiguracionesCrm(pool);
    const ultimaCompra = agregado.UltimaCompra ? new Date(agregado.UltimaCompra) : null;
    const diasDesdeUltimaCompra = ultimaCompra
      ? Math.floor((Date.now() - ultimaCompra.getTime()) / 86400000)
      : null;

    const segmento = calcularSegmento(
      {
        pedidosEntregados: Number(agregado.PedidosEntregados) || 0,
        totalGastado: Number(agregado.TotalGastado) || 0,
        diasDesdeUltimaCompra,
      },
      config,
    );

    return res.status(200).json({
      cliente: mapearCliente(filaCliente),
      historial: {
        totalPedidos: Number(agregado.TotalPedidos) || 0,
        pedidosEntregados: Number(agregado.PedidosEntregados) || 0,
        totalGastado: Number(agregado.TotalGastado) || 0,
        deudaPendiente: Number(agregado.DeudaPendiente) || 0,
        ultimaCompra: agregado.UltimaCompra,
        diasDesdeUltimaCompra,
        tiendas: tiendasResult.recordset.map((f) => ({ idTienda: f.IdTienda, nombre: f.Nombre })),
      },
      segmento,
    });
  } catch (err) {
    return next(err);
  }
}

/**
 * CRM — historial de notas internas del cliente (visible solo para
 * personal, nunca para el cliente mismo). Se listan todas, no solo la
 * última, más recientes primero.
 */
async function listarNotasCliente(req, res, next) {
  const { id } = req.params;

  try {
    const pool = await getPool();
    const result = await pool
      .request()
      .input('IdCliente', sql.Int, id)
      .query(`
        SELECT n.IdNota, n.IdCliente, n.Texto, n.FechaCreacion,
               n.IdUsuarioAutor, p.Nombres AS AutorNombres, p.ApellidoPaterno AS AutorApellidoPaterno
        FROM NotasCliente n
        INNER JOIN Usuarios u ON u.IdUsuario = n.IdUsuarioAutor
        INNER JOIN Personas p ON p.IdPersona = u.IdPersona
        WHERE n.IdCliente = @IdCliente
        ORDER BY n.FechaCreacion DESC
      `);

    return res.status(200).json({
      notas: result.recordset.map((f) => ({
        idNota: f.IdNota,
        idCliente: f.IdCliente,
        texto: f.Texto,
        fechaCreacion: f.FechaCreacion,
        autor: `${f.AutorNombres} ${f.AutorApellidoPaterno}`.trim(),
      })),
    });
  } catch (err) {
    return next(err);
  }
}

async function crearNotaCliente(req, res, next) {
  const { id } = req.params;
  const { texto } = req.body;

  if (!texto || !texto.trim()) {
    return res.status(400).json({ mensaje: 'La nota no puede estar vacía' });
  }
  if (texto.trim().length > 500) {
    return res.status(400).json({ mensaje: 'La nota no puede superar los 500 caracteres' });
  }

  try {
    const pool = await getPool();

    const clienteResult = await pool
      .request()
      .input('IdCliente', sql.Int, id)
      .query('SELECT IdCliente FROM Clientes WHERE IdCliente = @IdCliente');
    if (clienteResult.recordset.length === 0) {
      return res.status(404).json({ mensaje: 'Cliente no encontrado' });
    }

    await pool
      .request()
      .input('IdCliente', sql.Int, id)
      .input('IdUsuarioAutor', sql.Int, req.usuario.idUsuario)
      .input('Texto', sql.VarChar(500), texto.trim())
      .query(`
        INSERT INTO NotasCliente (IdCliente, IdUsuarioAutor, Texto)
        VALUES (@IdCliente, @IdUsuarioAutor, @Texto)
      `);

    return res.status(201).json({ mensaje: 'Nota agregada correctamente' });
  } catch (err) {
    return next(err);
  }
}

/**
 * CRM — canje de puntos de fidelidad: resta puntos del saldo del cliente
 * (nunca deja el saldo negativo) y lo deja registrado en la auditoría
 * general (no hace falta una tabla propia: es un evento infrecuente y
 * `registrarAuditoria` ya guarda quién, cuándo y con qué datos).
 */
async function canjearPuntos(req, res, next) {
  const { id } = req.params;
  const { puntos, descripcion } = req.body;

  if (!Number.isInteger(puntos) || puntos <= 0) {
    return res.status(400).json({ mensaje: 'Los puntos a canjear deben ser un número entero positivo' });
  }

  try {
    const pool = await getPool();
    const result = await pool
      .request()
      .input('IdCliente', sql.Int, id)
      .input('Puntos', sql.Int, puntos)
      .query(`
        UPDATE Clientes
        SET PuntosFidelidad = PuntosFidelidad - @Puntos
        WHERE IdCliente = @IdCliente AND PuntosFidelidad >= @Puntos
      `);

    if (result.rowsAffected[0] === 0) {
      return res.status(400).json({ mensaje: 'El cliente no existe o no tiene puntos suficientes' });
    }

    await registrarAuditoria({
      idUsuario: req.usuario.idUsuario,
      accion: 'CANJEAR_PUNTOS_CLIENTE',
      tablaAfectada: 'Clientes',
      registroAfectadoId: String(id),
      datosNuevos: { puntosCanjeados: puntos, descripcion: descripcion || null },
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    const nuevoSaldo = await pool
      .request()
      .input('IdCliente', sql.Int, id)
      .query('SELECT PuntosFidelidad FROM Clientes WHERE IdCliente = @IdCliente');

    return res.status(200).json({
      mensaje: 'Puntos canjeados correctamente',
      puntosFidelidad: nuevoSaldo.recordset[0].PuntosFidelidad,
    });
  } catch (err) {
    return next(err);
  }
}

/**
 * CRM — campaña de reactivación: envía un push a todos los clientes
 * segmentados como "EN_RIESGO" (recalculado al vuelo, mismo criterio que
 * `obtenerPerfilCliente`). Solo llega a quienes tienen cuenta propia
 * (clonada) con al menos un dispositivo registrado — un cliente que
 * nunca inició sesión en la app no tiene forma de recibir push todavía.
 */
async function enviarCampaniaReactivacion(req, res, next) {
  const { mensaje } = req.body;

  if (!mensaje || !mensaje.trim()) {
    return res.status(400).json({ mensaje: 'El mensaje de la campaña no puede estar vacío' });
  }

  try {
    const pool = await getPool();
    const config = await obtenerConfiguracionesCrm(pool);

    const candidatosResult = await pool.request().query(`
      SELECT c.IdCliente,
             MAX(CASE WHEN pd.Estado = 'ENTREGADO' THEN COALESCE(pd.FechaEntregaReal, pd.FechaCreacion) END) AS UltimaCompra
      FROM Clientes c
      INNER JOIN Pedidos pd ON pd.IdCliente = c.IdCliente
      WHERE c.Estado = 1
      GROUP BY c.IdCliente
      HAVING MAX(CASE WHEN pd.Estado = 'ENTREGADO' THEN 1 ELSE 0 END) = 1
    `);

    const ahora = Date.now();
    const idsEnRiesgo = candidatosResult.recordset
      .filter((f) => {
        const dias = Math.floor((ahora - new Date(f.UltimaCompra).getTime()) / 86400000);
        return dias > config.diasEnRiesgo;
      })
      .map((f) => f.IdCliente);

    if (idsEnRiesgo.length === 0) {
      return res.status(200).json({ mensaje: 'No hay clientes en riesgo por ahora', clientesNotificados: 0, dispositivosAlcanzados: 0 });
    }

    const tokensResult = await pool.request().query(`
      SELECT dn.FcmToken
      FROM Clientes c
      INNER JOIN Personas p ON p.IdPersona = c.IdPersona
      INNER JOIN Usuarios u ON u.IdPersona = p.IdPersona
      INNER JOIN DispositivosNotificacion dn ON dn.IdUsuario = u.IdUsuario
      WHERE c.IdCliente IN (${idsEnRiesgo.join(',')})
    `);
    const tokens = tokensResult.recordset.map((f) => f.FcmToken);

    let enviados = 0;
    if (tokens.length > 0) {
      const { enviados: total, tokensInvalidos } = await enviarPush({
        tokens,
        titulo: 'Te extrañamos',
        cuerpo: mensaje.trim(),
        datos: { tipo: 'CAMPANIA_REACTIVACION' },
      });
      enviados = total;
      if (tokensInvalidos.length > 0) {
        await pool
          .request()
          .query(`DELETE FROM DispositivosNotificacion WHERE FcmToken IN (${tokensInvalidos.map((t) => `'${t.replace(/'/g, "''")}'`).join(',')})`);
      }
    }

    await registrarAuditoria({
      idUsuario: req.usuario.idUsuario,
      accion: 'CAMPANIA_REACTIVACION_CLIENTES',
      tablaAfectada: 'Clientes',
      registroAfectadoId: null,
      datosNuevos: { clientesEnRiesgo: idsEnRiesgo.length, dispositivosAlcanzados: enviados, mensaje: mensaje.trim() },
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    return res.status(200).json({
      mensaje: 'Campaña enviada correctamente',
      clientesNotificados: idsEnRiesgo.length,
      dispositivosAlcanzados: enviados,
    });
  } catch (err) {
    return next(err);
  }
}

/**
 * Clonación automática: si un cliente fue verificado con datos reales de
 * apiperu.dev (no simulados, no manuales), se le crea una cuenta de acceso
 * (rol CLIENTE) usando su DNI como usuario y contraseña inicial, forzando
 * el cambio de clave en el primer login. Si ya tiene cuenta, o si el DNI ya
 * está tomado como nombre de usuario por otra persona, no hace nada (no
 * revienta la creación/edición del cliente).
 */
async function intentarClonarUsuarioCliente(transaction, idPersona, identificador) {
  const yaTieneCuenta = await new sql.Request(transaction)
    .input('IdPersona', sql.Int, idPersona)
    .query('SELECT IdUsuario FROM Usuarios WHERE IdPersona = @IdPersona');
  if (yaTieneCuenta.recordset.length > 0) {
    return { creado: false, motivo: 'La persona ya tiene una cuenta de acceso' };
  }

  const usuarioTomado = await new sql.Request(transaction)
    .input('NombreUsuario', sql.VarChar(50), identificador)
    .query('SELECT IdUsuario FROM Usuarios WHERE NombreUsuario = @NombreUsuario');
  if (usuarioTomado.recordset.length > 0) {
    return { creado: false, motivo: 'Ese identificador ya está en uso como nombre de usuario' };
  }

  const rolResult = await new sql.Request(transaction).query("SELECT IdRol FROM Roles WHERE NombreRol = 'CLIENTE'");
  const idRolCliente = rolResult.recordset[0].IdRol;
  const passwordHash = await bcrypt.hash(identificador, SALT_ROUNDS);

  await new sql.Request(transaction)
    .input('IdPersona', sql.Int, idPersona)
    .input('NombreUsuario', sql.VarChar(50), identificador)
    .input('PasswordHash', sql.VarChar(255), passwordHash)
    .input('IdRol', sql.Int, idRolCliente)
    .query(`
      INSERT INTO Usuarios (IdPersona, NombreUsuario, PasswordHash, IdRol, RequiereCambioPassword)
      VALUES (@IdPersona, @NombreUsuario, @PasswordHash, @IdRol, 1)
    `);

  return { creado: true };
}

/**
 * Verificación rápida (contra nuestra propia BD, sin tocar apiperu.dev) de
 * si un DNI/RUC ya pertenece a una Persona registrada — como cliente o con
 * cualquier otro rol (Usuario). Pensada para que el formulario avise ANTES
 * de gastar una consulta paga a la API real, no después.
 */
async function verificarDocumento(req, res, next) {
  const { documento } = req.params;
  const { excluirIdPersona } = req.query;
  const documentoLimpio = String(documento || '').trim();

  if (!/^\d{8}$/.test(documentoLimpio) && !/^\d{11}$/.test(documentoLimpio)) {
    return res.status(400).json({ mensaje: 'Documento inválido' });
  }

  try {
    const pool = await getPool();
    const request = pool
      .request()
      .input('DNI', sql.VarChar(15), documentoLimpio)
      .input('ExcluirIdPersona', sql.Int, excluirIdPersona ? Number(excluirIdPersona) : null);

    const result = await request.query(`
      SELECT p.IdPersona, p.Nombres, p.ApellidoPaterno,
             CASE WHEN EXISTS (SELECT 1 FROM Clientes c WHERE c.IdPersona = p.IdPersona AND c.Estado = 1) THEN 1 ELSE 0 END AS EsCliente,
             CASE WHEN EXISTS (SELECT 1 FROM Usuarios u WHERE u.IdPersona = p.IdPersona) THEN 1 ELSE 0 END AS TieneUsuario
      FROM Personas p
      WHERE p.DNI = @DNI
        AND (@ExcluirIdPersona IS NULL OR p.IdPersona <> @ExcluirIdPersona)
    `);

    if (result.recordset.length === 0) {
      return res.status(200).json({ existe: false });
    }

    const fila = result.recordset[0];
    return res.status(200).json({
      existe: true,
      nombreCompleto: [fila.Nombres, fila.ApellidoPaterno].filter(Boolean).join(' ').trim(),
      esCliente: Boolean(fila.EsCliente),
      tieneUsuario: Boolean(fila.TieneUsuario),
    });
  } catch (err) {
    return next(err);
  }
}

/**
 * `?estado=activos` (por defecto, igual que antes) | `inactivos` | `todos`.
 * Los clientes desactivados no desaparecen para siempre — solo quedan
 * ocultos de la vista normal; este filtro es lo que permite encontrarlos
 * de nuevo para reactivarlos.
 */
async function listarClientes(req, res, next) {
  try {
    const estado = req.query.estado === 'inactivos' ? 'inactivos' : req.query.estado === 'todos' ? 'todos' : 'activos';
    const filtroEstado = estado === 'activos' ? 'WHERE c.Estado = 1' : estado === 'inactivos' ? 'WHERE c.Estado = 0' : '';

    const pool = await getPool();
    const result = await pool.request().query(`
      SELECT c.IdCliente, c.DescripcionNegocio, c.NombreComercialOficial, c.PuntosFidelidad, c.Estado,
             p.IdPersona, p.DNI, p.Nombres, p.ApellidoPaterno, p.ApellidoMaterno,
             p.Telefono, p.Email, p.Direccion, p.OrigenValidacion, p.TelefonoVerificado, p.EmailVerificado
      FROM Clientes c
      INNER JOIN Personas p ON p.IdPersona = c.IdPersona
      ${filtroEstado}
      ORDER BY p.Nombres, p.ApellidoPaterno
    `);

    return res.status(200).json({ clientes: result.recordset.map(mapearCliente) });
  } catch (err) {
    return next(err);
  }
}

async function crearCliente(req, res, next) {
  const {
    dni,
    nombres,
    apellidoPaterno,
    apellidoMaterno,
    telefono,
    email,
    direccion,
    descripcionNegocio,
    nombreComercialOficial,
    origenValidacion,
    dniVerificadoApiReal,
  } = req.body;
  const dniLimpio = dni ? String(dni).trim() : null;

  const pool = await getPool();
  const transaction = new sql.Transaction(pool);

  try {
    await transaction.begin();

    let idPersona = null;

    if (dniLimpio) {
      const existente = await new sql.Request(transaction)
        .input('DNI', sql.VarChar(15), dniLimpio)
        .query('SELECT IdPersona FROM Personas WHERE DNI = @DNI');

      if (existente.recordset.length > 0) {
        idPersona = existente.recordset[0].IdPersona;

        const clienteExistente = await new sql.Request(transaction)
          .input('IdPersona', sql.Int, idPersona)
          .query('SELECT IdCliente FROM Clientes WHERE IdPersona = @IdPersona');

        if (clienteExistente.recordset.length > 0) {
          await transaction.rollback();
          return res.status(409).json({ mensaje: 'Ya existe un cliente registrado con ese DNI' });
        }
      }
    }

    if (!idPersona) {
      const esEmpresa = esRucPersonaJuridica(dniLimpio);
      const nuevaPersona = await new sql.Request(transaction)
        .input('DNI', sql.VarChar(15), dniLimpio)
        .input('Nombres', sql.NVarChar(100), mayuscula(nombres))
        .input('ApellidoPaterno', sql.NVarChar(100), esEmpresa ? '' : mayuscula(apellidoPaterno || ''))
        .input('ApellidoMaterno', sql.NVarChar(100), esEmpresa ? null : mayuscula(apellidoMaterno))
        .input('Telefono', sql.VarChar(20), telefono ? telefono.trim() : null)
        .input('Email', sql.VarChar(150), email ? email.trim() : null)
        .input('Direccion', sql.NVarChar(250), mayuscula(direccion))
        .input('OrigenValidacion', sql.VarChar(20), origenValidacion === 'RENIEC' ? 'RENIEC' : 'MANUAL')
        .query(`
          INSERT INTO Personas (DNI, Nombres, ApellidoPaterno, ApellidoMaterno, Telefono, Email, Direccion, OrigenValidacion)
          OUTPUT INSERTED.IdPersona
          VALUES (@DNI, @Nombres, @ApellidoPaterno, @ApellidoMaterno, @Telefono, @Email, @Direccion, @OrigenValidacion)
        `);
      idPersona = nuevaPersona.recordset[0].IdPersona;
    }

    const nuevoCliente = await new sql.Request(transaction)
      .input('IdPersona', sql.Int, idPersona)
      .input('DescripcionNegocio', sql.NVarChar(300), mayuscula(descripcionNegocio))
      .input('NombreComercialOficial', sql.Bit, nombreComercialOficial === true)
      .query(`
        INSERT INTO Clientes (IdPersona, DescripcionNegocio, NombreComercialOficial)
        OUTPUT INSERTED.IdCliente
        VALUES (@IdPersona, @DescripcionNegocio, @NombreComercialOficial)
      `);
    const idCliente = nuevoCliente.recordset[0].IdCliente;

    const rolResult = await new sql.Request(transaction).query("SELECT IdRol FROM Roles WHERE NombreRol = 'CLIENTE'");
    const idRolCliente = rolResult.recordset[0].IdRol;

    // "IF NOT EXISTS (...) INSERT ..." era T-SQL puro (control de flujo fuera
    // de un procedimiento almacenado) — MariaDB no lo soporta y tira error de
    // sintaxis. INSERT...SELECT...WHERE NOT EXISTS es el equivalente
    // portable (no depende de que exista una constraint UNIQUE, a diferencia
    // de INSERT IGNORE).
    await new sql.Request(transaction)
      .input('IdPersona', sql.Int, idPersona)
      .input('IdRol', sql.Int, idRolCliente)
      .query(`
        INSERT INTO PersonaRoles (IdPersona, IdRol)
        SELECT @IdPersona, @IdRol
        WHERE NOT EXISTS (SELECT 1 FROM PersonaRoles WHERE IdPersona = @IdPersona AND IdRol = @IdRol)
      `);

    let clonacion = { creado: false, motivo: 'No verificado con datos reales de la API' };
    if (dniVerificadoApiReal === true && dniLimpio) {
      clonacion = await intentarClonarUsuarioCliente(transaction, idPersona, dniLimpio);
    }

    await transaction.commit();

    await registrarAuditoria({
      idUsuario: req.usuario.idUsuario,
      accion: 'CREAR_CLIENTE',
      tablaAfectada: 'Clientes',
      registroAfectadoId: String(idCliente),
      datosNuevos: { ...req.body, cuentaClonada: clonacion.creado },
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    if (clonacion.creado) {
      await registrarAuditoria({
        accion: 'CLONACION_AUTOMATICA_USUARIO',
        tablaAfectada: 'Usuarios',
        registroAfectadoId: dniLimpio,
        datosNuevos: { idPersona, origen: 'verificacion_api_real' },
        ip: req.ip,
        userAgent: req.headers['user-agent'],
      });
    }

    return res.status(201).json({
      mensaje: 'Cliente creado correctamente',
      idCliente,
      idPersona,
      cuentaClonada: clonacion.creado,
    });
  } catch (err) {
    await transaction.rollback();
    return next(err);
  }
}

async function actualizarCliente(req, res, next) {
  const { id } = req.params;
  const {
    dni,
    nombres,
    apellidoPaterno,
    apellidoMaterno,
    telefono,
    email,
    direccion,
    descripcionNegocio,
    nombreComercialOficial,
    origenValidacion,
    dniVerificadoApiReal,
  } = req.body;

  const pool = await getPool();
  const transaction = new sql.Transaction(pool);

  try {
    await transaction.begin();

    const clienteResult = await new sql.Request(transaction)
      .input('IdCliente', sql.Int, id)
      .query(`
        SELECT c.IdPersona, c.DescripcionNegocio, c.NombreComercialOficial,
               p.DNI, p.OrigenValidacion, p.Nombres, p.ApellidoPaterno, p.ApellidoMaterno
        FROM Clientes c
        INNER JOIN Personas p ON p.IdPersona = c.IdPersona
        WHERE c.IdCliente = @IdCliente AND c.Estado = 1
      `);

    if (clienteResult.recordset.length === 0) {
      await transaction.rollback();
      return res.status(404).json({ mensaje: 'Cliente no encontrado' });
    }

    const cliente = clienteResult.recordset[0];
    const yaVerificadoPermanente = cliente.OrigenValidacion === 'RENIEC';
    const nuevoApellidoPaterno = mayuscula(apellidoPaterno || '');
    const nuevoApellidoMaterno = mayuscula(apellidoMaterno);
    const intentaCambiarNombre =
      mayuscula(nombres) !== mayuscula(cliente.Nombres) ||
      nuevoApellidoPaterno !== mayuscula(cliente.ApellidoPaterno || '') ||
      nuevoApellidoMaterno !== mayuscula(cliente.ApellidoMaterno);

    if (yaVerificadoPermanente && intentaCambiarNombre) {
      await transaction.rollback();
      return res.status(403).json({
        mensaje: 'Los datos de este cliente fueron validados por RENIEC/SUNAT y no se pueden editar manualmente',
      });
    }

    // El nombre comercial oficial de SUNAT se bloquea igual que los nombres:
    // una vez que vino de una búsqueda real, no se puede pisar a mano.
    const descripcionNegocioNueva = mayuscula(descripcionNegocio);
    if (cliente.NombreComercialOficial && descripcionNegocioNueva !== mayuscula(cliente.DescripcionNegocio)) {
      await transaction.rollback();
      return res.status(403).json({
        mensaje: 'El nombre comercial de este cliente fue validado por SUNAT y no se puede editar manualmente',
      });
    }
    // Se bloquea a partir de ahora si esta actualización trae uno oficial
    // (nueva búsqueda de RUC exitosa) y aún no estaba bloqueado; si ya lo
    // estaba, se queda así para siempre.
    const nombreComercialOficialFinal = cliente.NombreComercialOficial || nombreComercialOficial === true;

    // Transición de "registro rápido" (manual/sin documento) a verificado:
    // solo se permite mientras el cliente no esté ya bloqueado permanentemente.
    // A partir de aquí OrigenValidacion pasa a RENIEC y queda fijo para siempre.
    let dniFinal = cliente.DNI;
    let origenFinal = cliente.OrigenValidacion;
    const dniNuevo = dni !== undefined && dni !== null && String(dni).trim() !== '' ? String(dni).trim() : null;

    // Se usa origenValidacion (no dniVerificadoApiReal) como disparador: una
    // búsqueda exitosa por API simulada también debe congelar y actualizar
    // el DNI, igual que en crearCliente. dniVerificadoApiReal solo decide si
    // además se clona una cuenta de acceso (eso sí exige la API real).
    if (!yaVerificadoPermanente && origenValidacion === 'RENIEC' && dniNuevo) {
      if (dniNuevo !== cliente.DNI) {
        const dniTomado = await new sql.Request(transaction)
          .input('DNI', sql.VarChar(15), dniNuevo)
          .input('IdPersonaActual', sql.Int, cliente.IdPersona)
          .query('SELECT IdPersona FROM Personas WHERE DNI = @DNI AND IdPersona <> @IdPersonaActual');

        if (dniTomado.recordset.length > 0) {
          await transaction.rollback();
          return res.status(409).json({ mensaje: 'Ya existe otra persona registrada con ese DNI' });
        }
      }

      dniFinal = dniNuevo;
      origenFinal = 'RENIEC';
    }

    const esEmpresa = esRucPersonaJuridica(dniFinal);
    const apellidoPaternoFinal = esEmpresa ? '' : nuevoApellidoPaterno;
    const apellidoMaternoFinal = esEmpresa ? null : nuevoApellidoMaterno;

    await new sql.Request(transaction)
      .input('IdPersona', sql.Int, cliente.IdPersona)
      .input('DNI', sql.VarChar(15), dniFinal)
      .input('Nombres', sql.NVarChar(100), mayuscula(nombres))
      .input('ApellidoPaterno', sql.NVarChar(100), apellidoPaternoFinal)
      .input('ApellidoMaterno', sql.NVarChar(100), apellidoMaternoFinal)
      .input('Telefono', sql.VarChar(20), telefono ? telefono.trim() : null)
      .input('Email', sql.VarChar(150), email ? email.trim() : null)
      .input('Direccion', sql.NVarChar(250), mayuscula(direccion))
      .input('OrigenValidacion', sql.VarChar(20), origenFinal)
      .query(`
        UPDATE Personas
        SET DNI = @DNI, Nombres = @Nombres, ApellidoPaterno = @ApellidoPaterno, ApellidoMaterno = @ApellidoMaterno,
            Telefono = @Telefono, Email = @Email, Direccion = @Direccion, OrigenValidacion = @OrigenValidacion
        WHERE IdPersona = @IdPersona
      `);

    await new sql.Request(transaction)
      .input('IdCliente', sql.Int, id)
      .input('DescripcionNegocio', sql.NVarChar(300), descripcionNegocioNueva)
      .input('NombreComercialOficial', sql.Bit, nombreComercialOficialFinal)
      .query(
        'UPDATE Clientes SET DescripcionNegocio = @DescripcionNegocio, NombreComercialOficial = @NombreComercialOficial WHERE IdCliente = @IdCliente',
      );

    let clonacion = { creado: false, motivo: 'No verificado con datos reales de la API' };
    if (dniVerificadoApiReal === true && origenFinal === 'RENIEC' && dniFinal) {
      clonacion = await intentarClonarUsuarioCliente(transaction, cliente.IdPersona, dniFinal);
    }

    await transaction.commit();

    await registrarAuditoria({
      idUsuario: req.usuario.idUsuario,
      accion: 'ACTUALIZAR_CLIENTE',
      tablaAfectada: 'Clientes',
      registroAfectadoId: String(id),
      datosNuevos: { ...req.body, cuentaClonada: clonacion.creado },
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    return res.status(200).json({ mensaje: 'Cliente actualizado correctamente', cuentaClonada: clonacion.creado });
  } catch (err) {
    await transaction.rollback();
    return next(err);
  }
}

async function desactivarCliente(req, res, next) {
  const { id } = req.params;

  try {
    const pool = await getPool();
    const result = await pool
      .request()
      .input('IdCliente', sql.Int, id)
      .query('UPDATE Clientes SET Estado = 0 WHERE IdCliente = @IdCliente AND Estado = 1');

    if (result.rowsAffected[0] === 0) {
      return res.status(404).json({ mensaje: 'Cliente no encontrado o ya estaba desactivado' });
    }

    await registrarAuditoria({
      idUsuario: req.usuario.idUsuario,
      accion: 'DESACTIVAR_CLIENTE',
      tablaAfectada: 'Clientes',
      registroAfectadoId: String(id),
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    return res.status(200).json({ mensaje: 'Cliente desactivado correctamente' });
  } catch (err) {
    return next(err);
  }
}

async function reactivarCliente(req, res, next) {
  const { id } = req.params;

  try {
    const pool = await getPool();
    const result = await pool
      .request()
      .input('IdCliente', sql.Int, id)
      .query('UPDATE Clientes SET Estado = 1 WHERE IdCliente = @IdCliente AND Estado = 0');

    if (result.rowsAffected[0] === 0) {
      return res.status(404).json({ mensaje: 'Cliente no encontrado o ya estaba activo' });
    }

    await registrarAuditoria({
      idUsuario: req.usuario.idUsuario,
      accion: 'REACTIVAR_CLIENTE',
      tablaAfectada: 'Clientes',
      registroAfectadoId: String(id),
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    return res.status(200).json({ mensaje: 'Cliente reactivado correctamente' });
  } catch (err) {
    return next(err);
  }
}

/**
 * Autoservicio: el propio cliente autenticado consulta SU cliente asociado
 * (por IdPersona del JWT, nunca por :id de la URL, así es imposible que
 * consulte el perfil de alguien más).
 */
async function obtenerMiPerfil(req, res, next) {
  try {
    const pool = await getPool();
    const result = await pool
      .request()
      .input('IdPersona', sql.Int, req.usuario.idPersona)
      .query(`
        SELECT c.IdCliente, c.DescripcionNegocio, c.NombreComercialOficial, c.PuntosFidelidad,
               p.IdPersona, p.DNI, p.Nombres, p.ApellidoPaterno, p.ApellidoMaterno,
               p.Telefono, p.Email, p.Direccion, p.OrigenValidacion, p.TelefonoVerificado, p.EmailVerificado
        FROM Clientes c
        INNER JOIN Personas p ON p.IdPersona = c.IdPersona
        WHERE c.IdPersona = @IdPersona AND c.Estado = 1
      `);

    if (result.recordset.length === 0) {
      return res.status(404).json({ mensaje: 'No tienes un perfil de cliente asociado a tu cuenta' });
    }

    return res.status(200).json({ cliente: mapearCliente(result.recordset[0]) });
  } catch (err) {
    return next(err);
  }
}

/**
 * Autoservicio: el cliente solo puede actualizar su dirección de entrega
 * aquí. Nombres/apellidos/DNI están fuera de alcance a propósito — esos
 * requieren el candado de verificación de clientesController.actualizarCliente,
 * mediado por el personal. Teléfono y correo TAMPOCO se tocan aquí desde que
 * existe verificación por SMS/PIN — ver solicitarCodigoCelular/Correo y
 * confirmarCodigoCelular/Correo más abajo: cambiarlos ahora es un flujo
 * propio con código de un solo uso, no un simple guardado de formulario.
 */
async function actualizarMiPerfil(req, res, next) {
  const { direccion } = req.body;

  try {
    const pool = await getPool();
    const clienteResult = await pool
      .request()
      .input('IdPersona', sql.Int, req.usuario.idPersona)
      .query('SELECT c.IdCliente FROM Clientes c WHERE c.IdPersona = @IdPersona AND c.Estado = 1');

    if (clienteResult.recordset.length === 0) {
      return res.status(404).json({ mensaje: 'No tienes un perfil de cliente asociado a tu cuenta' });
    }

    await pool
      .request()
      .input('IdPersona', sql.Int, req.usuario.idPersona)
      .input('Direccion', sql.NVarChar(250), mayuscula(direccion))
      .query('UPDATE Personas SET Direccion = @Direccion WHERE IdPersona = @IdPersona');

    await registrarAuditoria({
      idUsuario: req.usuario.idUsuario,
      accion: 'ACTUALIZAR_MI_PERFIL',
      tablaAfectada: 'Personas',
      registroAfectadoId: String(req.usuario.idPersona),
      datosNuevos: req.body,
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    return res.status(200).json({ mensaje: 'Perfil actualizado correctamente' });
  } catch (err) {
    return next(err);
  }
}

async function obtenerClientePropio(idPersona) {
  const pool = await getPool();
  const result = await pool
    .request()
    .input('IdPersona', sql.Int, idPersona)
    .query(`
      SELECT c.IdCliente, p.Telefono, p.Email, p.TelefonoVerificado, p.EmailVerificado
      FROM Clientes c
      INNER JOIN Personas p ON p.IdPersona = c.IdPersona
      WHERE c.IdPersona = @IdPersona AND c.Estado = 1
    `);
  return result.recordset[0] || null;
}

/**
 * Mapea un OtpError a una respuesta HTTP clara. AUTORIZACION_REQUERIDA usa
 * 403 (el cliente está autenticado, pero le falta un paso extra); COOLDOWN
 * usa 429; el resto (código inválido/expirado/demasiados intentos) usa 400.
 */
function manejarOtpError(err, res, next) {
  if (err instanceof OtpError) {
    const status = err.tipo === 'COOLDOWN' ? 429 : err.tipo === 'AUTORIZACION_REQUERIDA' ? 403 : 400;
    return res.status(status).json({ mensaje: err.message, tipo: err.tipo });
  }
  return next(err);
}

/**
 * Si el cliente ya tiene AL MENOS un canal verificado (celular o correo),
 * cualquier cambio sensible (celular, correo o contraseña) exige
 * autorizarlo primero con un código enviado a ESE canal ya verificado. Así,
 * si alguien más usa la sesión del dueño (ej. le prestó la cuenta a un
 * trabajador), no puede tocar estos datos sin tener acceso real al celular
 * o correo del dueño — la autorización, no la contraseña de sesión, es la
 * barrera real.
 */
async function exigirAutorizacionSiCorresponde({ idPersona, cliente, canalAutorizacion, codigoAutorizacion }) {
  const requiereAutorizacion = Boolean(cliente.TelefonoVerificado) || Boolean(cliente.EmailVerificado);
  if (!requiereAutorizacion) return;

  if (!canalAutorizacion || !codigoAutorizacion) {
    throw new OtpError(
      'AUTORIZACION_REQUERIDA',
      'Debes autorizar este cambio primero con un código enviado a tu celular o correo verificado.',
    );
  }
  if (canalAutorizacion === 'SMS' && !cliente.TelefonoVerificado) {
    throw new OtpError('AUTORIZACION_REQUERIDA', 'Tu celular no está verificado. Autoriza con tu correo verificado.');
  }
  if (canalAutorizacion === 'EMAIL' && !cliente.EmailVerificado) {
    throw new OtpError('AUTORIZACION_REQUERIDA', 'Tu correo no está verificado. Autoriza con tu celular verificado.');
  }

  const destino = canalAutorizacion === 'SMS' ? cliente.Telefono : cliente.Email;
  await verificarCodigo({ idPersona, proposito: 'AUTORIZAR_CAMBIO', destino, codigo: codigoAutorizacion });
}

async function solicitarCodigoCelular(req, res, next) {
  const { telefonoNuevo, canalAutorizacion, codigoAutorizacion } = req.body;
  const idPersona = req.usuario.idPersona;

  try {
    const cliente = await obtenerClientePropio(idPersona);
    if (!cliente) return res.status(404).json({ mensaje: 'No tienes un perfil de cliente asociado a tu cuenta' });

    await exigirAutorizacionSiCorresponde({ idPersona, cliente, canalAutorizacion, codigoAutorizacion });
    await solicitarCodigo({ idPersona, canal: 'SMS', proposito: 'VERIFICAR_TELEFONO', destino: telefonoNuevo.trim() });

    return res.status(200).json({ mensaje: 'Código enviado por SMS' });
  } catch (err) {
    return manejarOtpError(err, res, next);
  }
}

async function confirmarCodigoCelular(req, res, next) {
  const { telefonoNuevo, codigo } = req.body;
  const idPersona = req.usuario.idPersona;

  try {
    const cliente = await obtenerClientePropio(idPersona);
    if (!cliente) return res.status(404).json({ mensaje: 'No tienes un perfil de cliente asociado a tu cuenta' });

    await verificarCodigo({ idPersona, proposito: 'VERIFICAR_TELEFONO', destino: telefonoNuevo.trim(), codigo });

    const pool = await getPool();
    await pool
      .request()
      .input('IdPersona', sql.Int, idPersona)
      .input('Telefono', sql.VarChar(20), telefonoNuevo.trim())
      .query('UPDATE Personas SET Telefono = @Telefono, TelefonoVerificado = 1 WHERE IdPersona = @IdPersona');

    await registrarAuditoria({
      idUsuario: req.usuario.idUsuario,
      accion: 'VERIFICAR_TELEFONO',
      tablaAfectada: 'Personas',
      registroAfectadoId: String(idPersona),
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    return res.status(200).json({ mensaje: 'Celular verificado correctamente' });
  } catch (err) {
    return manejarOtpError(err, res, next);
  }
}

async function solicitarCodigoCorreo(req, res, next) {
  const { emailNuevo, canalAutorizacion, codigoAutorizacion } = req.body;
  const idPersona = req.usuario.idPersona;

  try {
    const cliente = await obtenerClientePropio(idPersona);
    if (!cliente) return res.status(404).json({ mensaje: 'No tienes un perfil de cliente asociado a tu cuenta' });

    await exigirAutorizacionSiCorresponde({ idPersona, cliente, canalAutorizacion, codigoAutorizacion });
    await solicitarCodigo({
      idPersona,
      canal: 'EMAIL',
      proposito: 'VERIFICAR_EMAIL',
      destino: emailNuevo.trim().toLowerCase(),
    });

    return res.status(200).json({ mensaje: 'Código enviado por correo' });
  } catch (err) {
    return manejarOtpError(err, res, next);
  }
}

async function confirmarCodigoCorreo(req, res, next) {
  const { emailNuevo, codigo } = req.body;
  const idPersona = req.usuario.idPersona;

  try {
    const cliente = await obtenerClientePropio(idPersona);
    if (!cliente) return res.status(404).json({ mensaje: 'No tienes un perfil de cliente asociado a tu cuenta' });

    await verificarCodigo({
      idPersona,
      proposito: 'VERIFICAR_EMAIL',
      destino: emailNuevo.trim().toLowerCase(),
      codigo,
    });

    const pool = await getPool();
    await pool
      .request()
      .input('IdPersona', sql.Int, idPersona)
      .input('Email', sql.VarChar(150), emailNuevo.trim().toLowerCase())
      .query('UPDATE Personas SET Email = @Email, EmailVerificado = 1 WHERE IdPersona = @IdPersona');

    await registrarAuditoria({
      idUsuario: req.usuario.idUsuario,
      accion: 'VERIFICAR_EMAIL',
      tablaAfectada: 'Personas',
      registroAfectadoId: String(idPersona),
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    return res.status(200).json({ mensaje: 'Correo verificado correctamente' });
  } catch (err) {
    return manejarOtpError(err, res, next);
  }
}

/** Envía el código que autoriza un cambio sensible (celular, correo o
 * contraseña) al canal YA verificado que el cliente elija. */
async function solicitarAutorizacion(req, res, next) {
  const { canal } = req.body;
  const idPersona = req.usuario.idPersona;

  try {
    const cliente = await obtenerClientePropio(idPersona);
    if (!cliente) return res.status(404).json({ mensaje: 'No tienes un perfil de cliente asociado a tu cuenta' });

    if (canal === 'SMS' && !cliente.TelefonoVerificado) {
      return res.status(400).json({ mensaje: 'Tu celular no está verificado.' });
    }
    if (canal === 'EMAIL' && !cliente.EmailVerificado) {
      return res.status(400).json({ mensaje: 'Tu correo no está verificado.' });
    }

    const destino = canal === 'SMS' ? cliente.Telefono : cliente.Email;
    await solicitarCodigo({ idPersona, canal, proposito: 'AUTORIZAR_CAMBIO', destino });

    return res.status(200).json({
      mensaje: `Código de autorización enviado por ${canal === 'SMS' ? 'SMS' : 'correo'}`,
    });
  } catch (err) {
    return manejarOtpError(err, res, next);
  }
}

/**
 * Valida el código de autorización EN EL MOMENTO (sin gastarlo — ver
 * `consumir: false` en `verificarCodigo`), para que el paso de "autoriza
 * este cambio" en la app pueda mostrar el error ahí mismo si el código es
 * incorrecto, en vez de dejarlo avanzar en silencio y recién fallar más
 * adelante al intentar el cambio real (confuso: parece que un código
 * cualquiera "funciona" cuando en realidad solo se pospuso el rechazo).
 */
async function validarAutorizacion(req, res, next) {
  const { canal, codigo } = req.body;
  const idPersona = req.usuario.idPersona;

  try {
    const cliente = await obtenerClientePropio(idPersona);
    if (!cliente) return res.status(404).json({ mensaje: 'No tienes un perfil de cliente asociado a tu cuenta' });

    if (canal === 'SMS' && !cliente.TelefonoVerificado) {
      return res.status(400).json({ mensaje: 'Tu celular no está verificado.' });
    }
    if (canal === 'EMAIL' && !cliente.EmailVerificado) {
      return res.status(400).json({ mensaje: 'Tu correo no está verificado.' });
    }

    const destino = canal === 'SMS' ? cliente.Telefono : cliente.Email;
    await verificarCodigo({ idPersona, proposito: 'AUTORIZAR_CAMBIO', destino, codigo, consumir: false });

    return res.status(200).json({ mensaje: 'Código válido' });
  } catch (err) {
    return manejarOtpError(err, res, next);
  }
}

/**
 * Cambio de contraseña autoservicio (distinto del cambio obligatorio de
 * primer login en authController.cambiarPassword): no pide la contraseña
 * actual — la pide el propio código de autorización, que es lo que de
 * verdad protege esta acción si alguien más usa la sesión del dueño.
 */
async function cambiarPasswordSeguro(req, res, next) {
  const { passwordNueva, canalAutorizacion, codigoAutorizacion } = req.body;
  const idPersona = req.usuario.idPersona;
  const idUsuario = req.usuario.idUsuario;

  try {
    const cliente = await obtenerClientePropio(idPersona);
    if (!cliente) return res.status(404).json({ mensaje: 'No tienes un perfil de cliente asociado a tu cuenta' });

    if (!cliente.TelefonoVerificado && !cliente.EmailVerificado) {
      return res.status(400).json({
        mensaje: 'Verifica tu celular o correo antes de poder cambiar tu contraseña.',
      });
    }

    await exigirAutorizacionSiCorresponde({ idPersona, cliente, canalAutorizacion, codigoAutorizacion });

    const passwordHash = await bcrypt.hash(passwordNueva, SALT_ROUNDS);
    const pool = await getPool();
    await pool
      .request()
      .input('IdUsuario', sql.Int, idUsuario)
      .input('PasswordHash', sql.VarChar(255), passwordHash)
      .query('UPDATE Usuarios SET PasswordHash = @PasswordHash, FechaActualizacion = SYSUTCDATETIME() WHERE IdUsuario = @IdUsuario');

    await registrarAuditoria({
      idUsuario,
      accion: 'CAMBIO_PASSWORD_AUTOSERVICIO',
      tablaAfectada: 'Usuarios',
      registroAfectadoId: String(idUsuario),
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    });

    return res.status(200).json({ mensaje: 'Contraseña actualizada correctamente' });
  } catch (err) {
    return manejarOtpError(err, res, next);
  }
}

module.exports = {
  listarClientes,
  crearCliente,
  actualizarCliente,
  desactivarCliente,
  reactivarCliente,
  obtenerMiPerfil,
  actualizarMiPerfil,
  verificarDocumento,
  solicitarCodigoCelular,
  confirmarCodigoCelular,
  solicitarCodigoCorreo,
  confirmarCodigoCorreo,
  solicitarAutorizacion,
  validarAutorizacion,
  cambiarPasswordSeguro,
  obtenerPerfilCliente,
  listarNotasCliente,
  crearNotaCliente,
  canjearPuntos,
  enviarCampaniaReactivacion,
  obtenerResumenSegmentos,
  // Reexportadas para pruebas unitarias (__tests__/clientesController.test.js)
  // — son funciones puras, no dependen de la base de datos.
  calcularCalidadDato,
  calcularSegmento,
  esRucPersonaJuridica,
  resumirSegmentosClientes,
  // Reexportado para publicoController.js (pedido web sin login) — mismo
  // clonado de cuenta (usuario=DNI, password=DNI) que ya dispara un
  // registro de cliente hecho por el personal con DNI real verificado.
  intentarClonarUsuarioCliente,
};
