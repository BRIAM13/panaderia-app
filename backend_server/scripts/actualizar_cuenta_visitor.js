// Actualiza (en vez de recrear) la cuenta de solo lectura DNI 00000000 al
// nuevo diseño: rol VISITOR real (ver Roles/authMiddleware.js), nombre y
// contraseña definitivos. No se puede borrar y recrear porque ya tiene
// filas en Auditoria_Log referenciando su IdUsuario.
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const bcrypt = require('bcryptjs');
const { getPool, sql } = require('../config/db');

const SALT_ROUNDS = Number(process.env.BCRYPT_SALT_ROUNDS) || 12;
const DNI = '00000000';
const PASSWORD = 'RoncerosLabs2026!';
const NOMBRES = 'USUARIO';
const APELLIDO_PATERNO = 'VISITANTE';

async function main() {
  const pool = await getPool();

  const persona = await pool.request().input('DNI', sql.VarChar(15), DNI).query('SELECT IdPersona FROM Personas WHERE DNI = @DNI');
  if (persona.recordset.length === 0) {
    console.error('No existe la Persona con ese DNI — nada que actualizar.');
    process.exit(1);
  }
  const idPersona = persona.recordset[0].IdPersona;

  await pool.request()
    .input('IdPersona', sql.Int, idPersona)
    .input('Nombres', sql.NVarChar(100), NOMBRES)
    .input('ApellidoPaterno', sql.NVarChar(100), APELLIDO_PATERNO)
    .query('UPDATE Personas SET Nombres = @Nombres, ApellidoPaterno = @ApellidoPaterno, ApellidoMaterno = NULL WHERE IdPersona = @IdPersona');

  const trabajador = await pool.request().input('IdPersona', sql.Int, idPersona).query('SELECT IdTrabajador FROM Trabajadores WHERE IdPersona = @IdPersona');
  let idTrabajador = trabajador.recordset[0]?.IdTrabajador;
  if (idTrabajador) {
    await pool.request().input('IdTrabajador', sql.Int, idTrabajador).query("UPDATE Trabajadores SET Cargo = 'VISITOR', Estado = 1, FechaCese = NULL WHERE IdTrabajador = @IdTrabajador");
  } else {
    const nuevo = await pool.request()
      .input('IdPersona', sql.Int, idPersona)
      .input('Cargo', sql.NVarChar(100), 'VISITOR')
      .query('INSERT INTO Trabajadores (IdPersona, Cargo) OUTPUT INSERTED.IdTrabajador VALUES (@IdPersona, @Cargo)');
    idTrabajador = nuevo.recordset[0].IdTrabajador;
    for (const slug of ['panaderia', 'hamburguesas']) {
      const tienda = await pool.request().input('Slug', sql.VarChar(50), slug).query('SELECT IdTienda FROM Tiendas WHERE Slug = @Slug');
      await pool.request()
        .input('IdTrabajador', sql.Int, idTrabajador)
        .input('IdTienda', sql.Int, tienda.recordset[0].IdTienda)
        .query('INSERT INTO TrabajadorTiendas (IdTrabajador, IdTienda) VALUES (@IdTrabajador, @IdTienda)');
    }
  }

  const rolVisitor = await pool.request().query("SELECT IdRol FROM Roles WHERE NombreRol = 'VISITOR'");
  const idRolVisitor = rolVisitor.recordset[0].IdRol;
  const passwordHash = await bcrypt.hash(PASSWORD, SALT_ROUNDS);

  await pool.request()
    .input('IdPersona', sql.Int, idPersona)
    .input('PasswordHash', sql.VarChar(255), passwordHash)
    .input('IdRol', sql.Int, idRolVisitor)
    .query('UPDATE Usuarios SET PasswordHash = @PasswordHash, IdRol = @IdRol, RequiereCambioPassword = 0 WHERE IdPersona = @IdPersona');

  const tiendas = await pool.request().input('IdTrabajador', sql.Int, idTrabajador).query('SELECT IdTienda FROM TrabajadorTiendas WHERE IdTrabajador = @IdTrabajador');

  console.log('Cuenta actualizada correctamente.');
  console.log('Usuario (DNI):', DNI);
  console.log('Contraseña:', PASSWORD);
  console.log('Nombre:', NOMBRES, APELLIDO_PATERNO);
  console.log('Rol: VISITOR, tiendas asignadas (IdTienda):', tiendas.recordset.map((r) => r.IdTienda));
  process.exit(0);
}
main().catch((e) => { console.error('ERROR:', e.message); process.exit(1); });
