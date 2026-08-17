// Bus de eventos mínimo para que componentes que no tienen relación directa
// (ej. PedidoForm y Mascota) se puedan avisar cosas sin pasar props por
// media página ni montar un Context solo para esto.
export const EVENTO_PEDIDO_ENVIADO = "panaderia:pedido-enviado";
