function notFoundHandler(req, res) {
  res.status(404).json({ mensaje: 'Recurso no encontrado' });
}

function errorHandler(err, req, res, next) {
  console.error(err);
  const status = err.status || 500;
  res.status(status).json({
    mensaje: status === 500 ? 'Error interno del servidor' : err.message,
  });
}

module.exports = { notFoundHandler, errorHandler };
