import { describe, expect, test } from "vitest";
import type { ProductoPublico } from "../../services/api";
import { filtrarProductosDelMenu, nombresSinCoincidencia } from "../catalogoMenu";

// Los nombres son los reales del catálogo (Productos.Nombre), tal como los
// devuelve GET /publico/catalogo.
const CATALOGO: ProductoPublico[] = [
  { idProducto: 1, nombre: "Pan de Hamburguesa Clásico", precioUnitario: 3.5, esPaquete: true },
  { idProducto: 3, nombre: "Pan de Agua", precioUnitario: 0.2, esPaquete: false },
  { idProducto: 4, nombre: "Pan Francés", precioUnitario: 0.2, esPaquete: false },
  { idProducto: 5, nombre: "Pan de Yema", precioUnitario: 0.25, esPaquete: false },
];

const CONFIGURADOS = ["Pan de Hamburguesa Clásico", "Pan de Agua", "Pan Francés"];

describe("filtrarProductosDelMenu", () => {
  test("deja solo los panes configurados en el menú, con su precio real", () => {
    const resultado = filtrarProductosDelMenu(CATALOGO, CONFIGURADOS);
    expect(resultado.map((p) => p.nombre)).toEqual([
      "Pan de Hamburguesa Clásico",
      "Pan de Agua",
      "Pan Francés",
    ]);
    expect(resultado.find((p) => p.nombre === "Pan de Agua")?.precioUnitario).toBe(0.2);
  });

  test("un pan del catálogo que no está configurado no se ofrece en la web", () => {
    const nombres = filtrarProductosDelMenu(CATALOGO, CONFIGURADOS).map((p) => p.nombre);
    expect(nombres).not.toContain("Pan de Yema");
  });

  test("sin catálogo (el servidor no respondió) no se ofrece nada", () => {
    expect(filtrarProductosDelMenu([], CONFIGURADOS)).toEqual([]);
  });
});

describe("nombresSinCoincidencia", () => {
  test("cuando todos los nombres cruzan, no hay nada que avisar", () => {
    expect(nombresSinCoincidencia(CATALOGO, CONFIGURADOS)).toEqual([]);
  });

  test("delata el nombre que dejó de cruzar tras un renombrado en la app", () => {
    // Mismo pan, otra grafía: el cruce es por texto EXACTO, así que este
    // pan desaparecería del formulario sin ningún error visible.
    const catalogoRenombrado = CATALOGO.map((p) =>
      p.nombre === "Pan Francés" ? { ...p, nombre: "Pan frances" } : p,
    );
    expect(nombresSinCoincidencia(catalogoRenombrado, CONFIGURADOS)).toEqual(["Pan Francés"]);
  });

  test("con el catálogo vacío, todos los nombres configurados quedan sin cruzar", () => {
    expect(nombresSinCoincidencia([], CONFIGURADOS)).toEqual(CONFIGURADOS);
  });
});
