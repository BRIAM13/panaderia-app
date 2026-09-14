import { describe, expect, test } from "vitest";
import type { DescuentoCliente } from "../../services/api";
import {
  descuentoVigente,
  etiquetaSegmento,
  formatearPorcentaje,
  montoDescontado,
  textoDescuento,
  totalConDescuento,
} from "../descuentos";

const VIP: DescuentoCliente = { segmento: "VIP", porcentaje: 15 };
const NUEVO: DescuentoCliente = { segmento: "NUEVO", porcentaje: 5 };

describe("etiquetaSegmento", () => {
  test("traduce cada segmento del CRM a algo que se le pueda decir al cliente", () => {
    expect(etiquetaSegmento("NUEVO")).toBe("cliente nuevo");
    expect(etiquetaSegmento("VIP")).toBe("cliente VIP");
  });

  // "EN_RIESGO" es una etiqueta de gestión: al cliente no se le dice eso.
  test("EN_RIESGO no se le muestra al cliente con su nombre interno", () => {
    expect(etiquetaSegmento("EN_RIESGO")).not.toContain("RIESGO");
  });
});

describe("formatearPorcentaje", () => {
  test("un porcentaje entero no muestra decimales", () => {
    expect(formatearPorcentaje(5)).toBe("5");
    expect(formatearPorcentaje(15)).toBe("15");
  });

  test("un porcentaje con decimales se conserva", () => {
    expect(formatearPorcentaje(7.5)).toBe("7.5");
  });
});

describe("textoDescuento", () => {
  test("arma la línea completa del desglose", () => {
    expect(textoDescuento(VIP)).toBe("Descuento cliente VIP (15%)");
    expect(textoDescuento(NUEVO)).toBe("Descuento cliente nuevo (5%)");
  });
});

describe("montoDescontado", () => {
  test("calcula cuánto se ahorra el cliente, con 2 decimales", () => {
    expect(montoDescontado(100, 15)).toBe(15);
    expect(montoDescontado(17.5, 5)).toBe(0.88);
  });

  test("sin porcentaje o sin subtotal, no se descuenta nada", () => {
    expect(montoDescontado(100, 0)).toBe(0);
    expect(montoDescontado(0, 15)).toBe(0);
  });
});

// Misma fórmula que `aplicarDescuento` en el backend
// (backend_server/utils/descuentosCliente.js): si estas dos se separan, la
// web le promete al cliente un número y el servidor le cobra otro.
describe("totalConDescuento", () => {
  test("coincide con el redondeo del backend", () => {
    expect(totalConDescuento(100, 15)).toBe(85);
    expect(totalConDescuento(33.33, 10)).toBe(30);
    expect(totalConDescuento(17.5, 5)).toBe(16.63);
  });

  test("sin descuento, el total es el subtotal tal cual", () => {
    expect(totalConDescuento(37.5, 0)).toBe(37.5);
  });
});

describe("descuentoVigente", () => {
  test("vale cuando el pan elegido es de la misma tienda por la que se consultó", () => {
    expect(descuentoVigente(VIP, "panaderia", "panaderia")).toEqual(VIP);
  });

  // El visitante puede escribir su DNI y DESPUÉS cambiar de pan: el
  // descuento de la consulta anterior ya no aplica hasta recalcularlo.
  test("no vale si el pan elegido cambió a otra tienda", () => {
    expect(descuentoVigente(VIP, "panaderia", "hamburguesas")).toBeNull();
  });

  test("no vale sin descuento, con porcentaje 0, o sin tienda", () => {
    expect(descuentoVigente(null, "panaderia", "panaderia")).toBeNull();
    expect(descuentoVigente(undefined, "panaderia", "panaderia")).toBeNull();
    expect(descuentoVigente({ segmento: "NUEVO", porcentaje: 0 }, "panaderia", "panaderia")).toBeNull();
    expect(descuentoVigente(VIP, undefined, "panaderia")).toBeNull();
    expect(descuentoVigente(VIP, "panaderia", undefined)).toBeNull();
  });
});
