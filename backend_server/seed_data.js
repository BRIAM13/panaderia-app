/**
 * Script de siembra (seed) de usuarios de prueba, uno por rol de la
 * jerarquía familiar/comercial, más un usuario híbrido Cliente+Trabajador
 * (mismo DNI, dos perfiles) para probar la vista dual del frontend.
 *
 * Idempotente: se puede ejecutar varias veces sin duplicar datos.
 *
 * Uso: node seed_data.js
 */
require('dotenv').config();

const bcrypt = require('bcryptjs');
const { sql, getPool } = require('./config/db');

const SALT_ROUNDS = Number(process.env.BCRYPT_SALT_ROUNDS) || 12;

const SEED_USERS = [
  {
    dni: '00000001',
    nombres: 'Briam Luis',
    apellidoPaterno: 'Ronceros',
    apellidoMaterno: 'Corporación',
    email: 'briamronceros@gmail.com',
    nombreUsuario: 'briam.superadmin',
    password: 'SuperAdmin#2026',
    perfiles: ['TRABAJADOR'],
    rolPrincipal: 'SUPERADMIN',
    requiereCambioPassword: false,
    cargoTrabajador: 'Propietario / Super Administrador',
  },
  {
    dni: '00000002',
    nombres: 'Familiar Encargado',
    apellidoPaterno: 'Ronceros',
    apellidoMaterno: 'Demo',
    email: 'admin.demo@corporacionronceros.com',
    nombreUsuario: 'admin.demo',
    password: 'Admin#2026',
    perfiles: ['TRABAJADOR'],
    rolPrincipal: 'ADMIN',
    requiereCambioPassword: true,
    cargoTrabajador: 'Administrador de área',
  },
  {
    dni: '00000003',
    nombres: 'Trabajador',
    apellidoPaterno: 'Demo',
    apellidoMaterno: 'Panadería',
    email: 'trabajador.demo@corporacionronceros.com',
    nombreUsuario: 'trabajador.demo',
    password: 'Trabajador#2026',
    perfiles: ['TRABAJADOR'],
    rolPrincipal: 'TRABAJADOR',
    requiereCambioPassword: true,
    cargoTrabajador: 'Vendedor',
  },
  {
    dni: '00000004',
    nombres: 'Cliente',
    apellidoPaterno: 'Demo',
    apellidoMaterno: 'Panadería',
    email: 'cliente.demo@correo.com',
    nombreUsuario: 'cliente.demo',
    password: 'Cliente#2026',
    perfiles: ['CLIENTE'],
    rolPrincipal: 'CLIENTE',
    requiereCambioPassword: false,
  },
  {
    dni: '00000005',
    nombres: 'Híbrido',
    apellidoPaterno: 'ClienteTrabajador',
    apellidoMaterno: 'Demo',
    email: 'hibrido.demo@correo.com',
    nombreUsuario: 'hibrido.demo',
    password: 'Hibrido#2026',
    // Mismo DNI con dos perfiles: comenzó como Cliente y hoy también es Trabajador.
    perfiles: ['CLIENTE', 'TRABAJADOR'],
    rolPrincipal: 'TRABAJADOR',
    requiereCambioPassword: true,
    cargoTrabajador: 'Vendedor (antes cliente registrado)',
  },
];

async function obtenerMapaRoles(pool) {
  const result = await pool.request().query('SELECT IdRol, NombreRol FROM Roles');
  const mapa = {};
  for (const fila of result.recordset) {
    mapa[fila.NombreRol] = fila.IdRol;
  }
  return mapa;
}

async function obtenerOCrearPersona(pool, def) {
  const existente = await pool
    .request()
    .input('DNI', sql.VarChar(15), def.dni)
    .query('SELECT IdPersona FROM Personas WHERE DNI = @DNI');

  if (existente.recordset.length > 0) {
    return existente.recordset[0].IdPersona;
  }

  const insertado = await pool
    .request()
    .input('DNI', sql.VarChar(15), def.dni)
    .input('Nombres', sql.NVarChar(100), def.nombres)
    .input('ApellidoPaterno', sql.NVarChar(100), def.apellidoPaterno)
    .input('ApellidoMaterno', sql.NVarChar(100), def.apellidoMaterno || null)
    .input('Email', sql.VarChar(150), def.email || null)
    .query(`
      INSERT INTO Personas (DNI, Nombres, ApellidoPaterno, ApellidoMaterno, Email)
      OUTPUT INSERTED.IdPersona
      VALUES (@DNI, @Nombres, @ApellidoPaterno, @ApellidoMaterno, @Email)
    `);

  return insertado.recordset[0].IdPersona;
}

async function asegurarPersonaRol(pool, idPersona, idRol) {
  const existente = await pool
    .request()
    .input('IdPersona', sql.Int, idPersona)
    .input('IdRol', sql.Int, idRol)
    .query('SELECT IdPersonaRol FROM PersonaRoles WHERE IdPersona = @IdPersona AND IdRol = @IdRol');

  if (existente.recordset.length > 0) return;

  await pool
    .request()
    .input('IdPersona', sql.Int, idPersona)
    .input('IdRol', sql.Int, idRol)
    .query('INSERT INTO PersonaRoles (IdPersona, IdRol) VALUES (@IdPersona, @IdRol)');
}

async function asegurarPerfilCliente(pool, idPersona) {
  const existente = await pool
    .request()
    .input('IdPersona', sql.Int, idPersona)
    .query('SELECT IdCliente FROM Clientes WHERE IdPersona = @IdPersona');

  if (existente.recordset.length > 0) return;

  await pool
    .request()
    .input('IdPersona', sql.Int, idPersona)
    .query('INSERT INTO Clientes (IdPersona) VALUES (@IdPersona)');
}

async function asegurarPerfilTrabajador(pool, idPersona, cargo) {
  const existente = await pool
    .request()
    .input('IdPersona', sql.Int, idPersona)
    .query('SELECT IdTrabajador FROM Trabajadores WHERE IdPersona = @IdPersona');

  if (existente.recordset.length > 0) return;

  await pool
    .request()
    .input('IdPersona', sql.Int, idPersona)
    .input('Cargo', sql.NVarChar(100), cargo || 'Colaborador')
    .query('INSERT INTO Trabajadores (IdPersona, Cargo) VALUES (@IdPersona, @Cargo)');
}

async function asegurarUsuario(pool, idPersona, def, idRolPrincipal) {
  const existente = await pool
    .request()
    .input('NombreUsuario', sql.VarChar(50), def.nombreUsuario)
    .query('SELECT IdUsuario FROM Usuarios WHERE NombreUsuario = @NombreUsuario');

  if (existente.recordset.length > 0) {
    console.log(`  · Usuario "${def.nombreUsuario}" ya existía, se omite.`);
    return;
  }

  const passwordHash = await bcrypt.hash(def.password, SALT_ROUNDS);

  await pool
    .request()
    .input('IdPersona', sql.Int, idPersona)
    .input('NombreUsuario', sql.VarChar(50), def.nombreUsuario)
    .input('PasswordHash', sql.VarChar(255), passwordHash)
    .input('IdRol', sql.Int, idRolPrincipal)
    .input('RequiereCambioPassword', sql.Bit, def.requiereCambioPassword)
    .query(`
      INSERT INTO Usuarios (IdPersona, NombreUsuario, PasswordHash, IdRol, RequiereCambioPassword)
      VALUES (@IdPersona, @NombreUsuario, @PasswordHash, @IdRol, @RequiereCambioPassword)
    `);

  console.log(`  ✓ Usuario "${def.nombreUsuario}" creado (rol principal: ${def.rolPrincipal}, contraseña: ${def.password}).`);
}

async function sembrarUsuario(pool, rolesMap, def) {
  console.log(`\nSembrando "${def.nombreUsuario}" (DNI ${def.dni})...`);

  const idPersona = await obtenerOCrearPersona(pool, def);

  for (const perfil of def.perfiles) {
    if (perfil === 'CLIENTE') {
      await asegurarPerfilCliente(pool, idPersona);
    } else if (perfil === 'TRABAJADOR') {
      await asegurarPerfilTrabajador(pool, idPersona, def.cargoTrabajador);
    }
    await asegurarPersonaRol(pool, idPersona, rolesMap[perfil]);
  }

  // El rol principal (ej. SUPERADMIN, ADMIN) también queda registrado en el
  // historial de roles, aunque no tenga tabla de perfil propia.
  await asegurarPersonaRol(pool, idPersona, rolesMap[def.rolPrincipal]);

  await asegurarUsuario(pool, idPersona, def, rolesMap[def.rolPrincipal]);
}

async function main() {
  const pool = await getPool();
  const rolesMap = await obtenerMapaRoles(pool);

  const rolesFaltantes = SEED_USERS
    .flatMap((def) => [...def.perfiles, def.rolPrincipal])
    .filter((rol) => !rolesMap[rol]);

  if (rolesFaltantes.length > 0) {
    throw new Error(
      `Faltan roles en la tabla Roles: ${[...new Set(rolesFaltantes)].join(', ')}. ` +
      'Ejecuta database_schema.sql actualizado antes de sembrar datos.'
    );
  }

  for (const def of SEED_USERS) {
    await sembrarUsuario(pool, rolesMap, def);
  }

  console.log('\nSiembra completada. Credenciales de prueba:');
  console.table(
    SEED_USERS.map((u) => ({
      usuario: u.nombreUsuario,
      password: u.password,
      rolPrincipal: u.rolPrincipal,
      hibrido: u.perfiles.length > 1 ? 'sí (Cliente + Trabajador)' : 'no',
      requiereCambioPassword: u.requiereCambioPassword,
    }))
  );
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('\nError sembrando datos:', err.message);
    process.exit(1);
  });
