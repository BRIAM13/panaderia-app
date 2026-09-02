import type { ProductoPublico } from "../services/api";

/** Los panes que la web ofrece son los que están en PRODUCTOS
 * (data/config.ts) y además existen en el catálogo real del servidor. El
 * cruce se hace por nombre EXACTO (`nombreEnCatalogo` contra
 * Productos.Nombre), porque acá no se guarda ningún IdProducto.
 *
 * El resto del catálogo (pan de yema, de maíz, integral…) sigue existiendo
 * en el sistema, pero todavía no se vende desde la página: le falta su
 * foto. */
export function filtrarProductosDelMenu(
  catalogo: ProductoPublico[],
  nombresConfigurados: readonly string[],
): ProductoPublico[] {
  const nombres = new Set(nombresConfigurados);
  return catalogo.filter((producto) => nombres.has(producto.nombre));
}

/** Los nombres configurados en PRODUCTOS que NO aparecen en el catálogo
 * que devolvió el servidor.
 *
 * Este cruce por texto exacto es frágil a propósito (es lo que evita
 * guardar ids en el repo), pero falla en silencio: si alguien renombra un
 * producto en la app —"Pan Francés" -> "Pan francés"— ese pan simplemente
 * desaparece del formulario y nadie se entera hasta que un cliente
 * pregunta. Se usa para avisar en consola durante el desarrollo, ver
 * `useCatalogoPublico`. */
export function nombresSinCoincidencia(
  catalogo: ProductoPublico[],
  nombresConfigurados: readonly string[],
): string[] {
  const nombresCatalogo = new Set(catalogo.map((producto) => producto.nombre));
  return nombresConfigurados.filter((nombre) => !nombresCatalogo.has(nombre));
}
