import { describe, expect, test } from "vitest";
import {
  MONTO_MAXIMO_YAPE,
  MONTO_MINIMO_YAPE,
  celularParaVistaPrevia,
  celularPeruanoValido,
  codigoYapeValido,
  formatearCelular,
  limpiarCelular,
  limpiarCodigoYape,
  motivoYapeNoDisponible,
} from "../yape";

describe("limpiarCelular / formatearCelular", () => {
  test("deja solo dígitos y corta a 9", () => {
    expect(limpiarCelular("987-654-321")).toBe("987654321");
    expect(limpiarCelular("9876543210000")).toBe("987654321");
    expect(limpiarCelular("+51 987 654 321")).toBe("519876543");
    expect(limpiarCelular("")).toBe("");
  });

  test("formatea en grupos de 3 mientras se teclea, sin espacio colgando", () => {
    expect(formatearCelular("9")).toBe("9");
    expect(formatearCelular("987")).toBe("987");
    expect(formatearCelular("9876")).toBe("987 6");
    expect(formatearCelular("987654321")).toBe("987 654 321");
    // Lo que venga ya formateado (o con basura) se normaliza igual.
    expect(formatearCelular("987 654 321")).toBe("987 654 321");
    expect(formatearCelular("98a76b54")).toBe("987 654");
  });
});

describe("celularPeruanoValido", () => {
  test("acepta 9 dígitos que empiezan con 9, con o sin formato", () => {
    expect(celularPeruanoValido("987654321")).toBe(true);
    expect(celularPeruanoValido("987 654 321")).toBe(true);
    // El celular oficial de prueba de Culqi para Yape.
    expect(celularPeruanoValido("900000001")).toBe(true);
  });

  test("rechaza largos distintos de 9 y números que no empiezan con 9", () => {
    expect(celularPeruanoValido("98765432")).toBe(false);
    expect(celularPeruanoValido("9876543210")).toBe(false);
    expect(celularPeruanoValido("812345678")).toBe(false);
    expect(celularPeruanoValido("012345678")).toBe(false);
    expect(celularPeruanoValido("")).toBe(false);
  });
});

describe("limpiarCodigoYape / codigoYapeValido", () => {
  test("el código solo lleva dígitos y se corta a 6", () => {
    expect(limpiarCodigoYape("12 34 56")).toBe("123456");
    expect(limpiarCodigoYape("1234567")).toBe("123456");
    expect(limpiarCodigoYape("ab1c2")).toBe("12");
  });

  test("válido solo con exactamente 6 dígitos", () => {
    expect(codigoYapeValido("123456")).toBe(true);
    expect(codigoYapeValido("000000")).toBe(true);
    expect(codigoYapeValido("12345")).toBe(false);
    expect(codigoYapeValido("1234567")).toBe(false);
    expect(codigoYapeValido("12345a")).toBe(false);
    expect(codigoYapeValido("")).toBe(false);
  });
});

describe("celularParaVistaPrevia", () => {
  test("rellena con • lo que falta y agrupa de a 3, sin tapar lo tecleado", () => {
    expect(celularParaVistaPrevia("")).toBe("••• ••• •••");
    expect(celularParaVistaPrevia("98")).toBe("98• ••• •••");
    expect(celularParaVistaPrevia("98765")).toBe("987 65• •••");
    expect(celularParaVistaPrevia("987654321")).toBe("987 654 321");
  });
});

describe("motivoYapeNoDisponible", () => {
  test("un pedido de pan normal se puede pagar con Yape", () => {
    expect(motivoYapeNoDisponible(17.5)).toBeNull();
    expect(motivoYapeNoDisponible(MONTO_MINIMO_YAPE)).toBeNull();
    expect(motivoYapeNoDisponible(MONTO_MAXIMO_YAPE)).toBeNull();
  });

  test("por encima del límite de Yape avisa y manda a la tarjeta", () => {
    const motivo = motivoYapeNoDisponible(MONTO_MAXIMO_YAPE + 0.01);
    expect(motivo).not.toBeNull();
    expect(motivo).toMatch(/tarjeta/i);
    expect(motivo).toMatch(/2[.,]?000/);
  });

  test("por debajo del mínimo de Culqi para Yape también avisa", () => {
    expect(motivoYapeNoDisponible(MONTO_MINIMO_YAPE - 0.01)).toMatch(/al menos/i);
  });

  test("un total no cobrable se rechaza en vez de mandarlo a Culqi", () => {
    expect(motivoYapeNoDisponible(0)).not.toBeNull();
    expect(motivoYapeNoDisponible(-3)).not.toBeNull();
    expect(motivoYapeNoDisponible(Number.NaN)).not.toBeNull();
  });
});
