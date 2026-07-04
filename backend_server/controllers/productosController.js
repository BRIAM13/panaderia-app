const { getPool } = require('../config/db');

async function listarProductos(req, res, next) {
  try {
    const pool = await getPool();
    const result = await pool.request().query(`
      SELECT p.IdProducto, p.Nombre, p.Descripcion, p.PrecioUnitario, p.Stock, p.UnidadMedida, c.Nombre AS Categoria
      FROM Productos p
      INNER JOIN Categorias c ON c.IdCategoria = p.IdCategoria
      WHERE p.Estado = 1
      ORDER BY c.Nombre, p.Nombre
    `);

    const productos = result.recordset.map((fila) => ({
      idProducto: fila.IdProducto,
      nombre: fila.Nombre,
      descripcion: fila.Descripcion,
      precioUnitario: fila.PrecioUnitario,
      stock: fila.Stock,
      unidadMedida: fila.UnidadMedida,
      categoria: fila.Categoria,
    }));

    return res.status(200).json({ productos });
  } catch (err) {
    return next(err);
  }
}

module.exports = { listarProductos };
