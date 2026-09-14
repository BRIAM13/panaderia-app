import { describe, expect, test } from "vitest";
import type { PedidoPublicoConsultaItem } from "../../services/api";
import {
  CLAVE_PAGO_PENDIENTE,
  LARGO_MAXIMO_CODIGO,
  avisoPagoAdelanto,
  borrarPagoPendiente,
  codigoOperacionValido,
  esperaCodigoDePago,
  guardarPagoPendiente,
  leerPagoPendiente,
  limpiarCodigoOperacion,
  limpiarMonto,
  montoSugerido,
  pagoPendienteVigente,
  revisarMontoDeclarado,
  textoAjuste,
  type PagoPendienteGuardado,
} from "../pagoAdelanto";

/** Un pedido de la consulta pública, con lo mínimo que mira este módulo. */
function pedido(extra: Partial<PedidoPublicoConsultaItem> = {}): PedidoPublicoConsultaItem {
  return {
    idPedido: 900,
    numeroPedidoDia: 3,
    tienda: "Panadería",
    items: [{ producto: "PAN FRANCES", cantidad: 50, precioUnitario: 0.35, subtotal: 17.5 }],
    productoResumen: "PAN FRANCES x50",
    total: 17.5,
    estado: "SOLICITADO",
    fechaCreacion: "2026-09-14T15:00:00Z",
    fechaEntrega: null,
    ...extra,
  };
}

/** localStorage de mentira: los tests corren en Node, sin ventana. */
function crearAlmacen(inicial: Record<string, string> = {}): Storage {
  const datos = new Map(Object.entries(inicial));
  return {
    get length() {
      return datos.size;
    },
    clear: () => datos.clear(),
    getItem: (clave: string) => datos.get(clave) ?? null,
    key: (indice: number) => [...datos.keys()][indice] ?? null,
    removeItem: (clave: string) => void datos.delete(clave),
    setItem: (clave: string, valor: string) => void datos.set(clave, valor),
  } as Storage;
}

const PENDIENTE: PagoPendienteGuardado = {
  idPedido: 900,
  token: "tokenbueno123",
  numeroPedidoDia: 3,
  total: 17.5,
  producto: "PAN FRANCES",
  cantidad: "50",
  documento: "DNI 12345678",
  telefono: "987654321",
  fechaRecojo: "2026-09-15",
  horaRecojo: "08:00",
  notas: "",
  guardadoEn: Date.now(),
};

describe("código de operación", () => {
  test("deja solo dígitos: una letra pegada por error no llega a escribirse", () => {
    expect(limpiarCodigoOperacion("12a34b5")).toBe("12345");
    expect(limpiarCodigoOperacion("  1234567 ")).toBe("1234567");
    expect(limpiarCodigoOperacion("abc")).toBe("");
  });

  test("corta en el tope, sin exigir un largo exacto", () => {
    // El largo real ronda los 7 dígitos, pero exigirlo dejaría fuera un pago
    // legítimo si alguna constancia trae uno más — mismo criterio que el
    // backend (LARGO_MAXIMO_CODIGO).
    expect(codigoOperacionValido("123456")).toBe(true);
    expect(codigoOperacionValido("1234567")).toBe(true);
    expect(codigoOperacionValido("12345678")).toBe(true);
    expect(limpiarCodigoOperacion("9".repeat(20))).toHaveLength(LARGO_MAXIMO_CODIGO);
  });

  test("un código vacío no es válido", () => {
    expect(codigoOperacionValido("")).toBe(false);
    expect(codigoOperacionValido("   ")).toBe(false);
  });
});

describe("revisarMontoDeclarado — la misma red blanda que el servidor", () => {
  test("pagar el total exacto o de más está bien", () => {
    expect(revisarMontoDeclarado(17.5, "17.50")).toBeNull();
    expect(revisarMontoDeclarado(17.5, "20")).toBeNull();
  });

  test("pagar de menos se avisa antes de enviar, con el total a la vista", () => {
    const aviso = revisarMontoDeclarado(17.5, "5");
    expect(aviso).toContain("S/ 17.50");
  });

  test("un centavo de menos también se avisa (la cuenta es en céntimos)", () => {
    expect(revisarMontoDeclarado(17.5, "17.49")).not.toBeNull();
    // Y un total con decimales "sucios" en punto flotante no debe dar un
    // falso negativo: 0.1 + 0.2 === 0.30000000000000004.
    expect(revisarMontoDeclarado(0.1 + 0.2, "0.30")).toBeNull();
  });

  test("vacío, cero o texto se avisan como monto faltante", () => {
    expect(revisarMontoDeclarado(17.5, "")).toBe("Indica cuánto pagaste por Yape.");
    expect(revisarMontoDeclarado(17.5, "0")).not.toBeNull();
    expect(revisarMontoDeclarado(17.5, "mucho")).not.toBeNull();
  });
});

describe("campo de monto", () => {
  test("arranca con el total exacto, que es lo que casi todos van a pagar", () => {
    expect(montoSugerido(17.5)).toBe("17.50");
    expect(montoSugerido(50)).toBe("50.00");
  });

  test("solo deja escribir un importe: dígitos y un punto con 2 decimales", () => {
    expect(limpiarMonto("17.50")).toBe("17.50");
    expect(limpiarMonto("17,50")).toBe("1750");
    expect(limpiarMonto("17.5.9")).toBe("17.59");
    expect(limpiarMonto("abc17.5")).toBe("17.5");
    expect(limpiarMonto("17.5999")).toBe("17.59");
  });
});

describe("pendiente guardado — retomar el pago tras una pestaña muerta", () => {
  test("se guarda y se lee tal cual", () => {
    const almacen = crearAlmacen();
    guardarPagoPendiente(PENDIENTE, almacen);
    expect(leerPagoPendiente(almacen)).toEqual(PENDIENTE);
  });

  test("sin nada guardado devuelve null", () => {
    expect(leerPagoPendiente(crearAlmacen())).toBeNull();
  });

  test("un pendiente de hace más de un día se descarta y se limpia solo", () => {
    // Si no, un pedido abandonado hace semanas secuestraría el formulario de
    // alguien que solo quiere pedir de nuevo.
    const viejo = { ...PENDIENTE, guardadoEn: Date.now() - 25 * 60 * 60 * 1000 };
    const almacen = crearAlmacen({ [CLAVE_PAGO_PENDIENTE]: JSON.stringify(viejo) });
    expect(leerPagoPendiente(almacen)).toBeNull();
    expect(almacen.getItem(CLAVE_PAGO_PENDIENTE)).toBeNull();
    expect(pagoPendienteVigente(viejo)).toBe(false);
    expect(pagoPendienteVigente(PENDIENTE)).toBe(true);
  });

  test("un contenido corrupto o incompleto no rompe nada: devuelve null", () => {
    expect(leerPagoPendiente(crearAlmacen({ [CLAVE_PAGO_PENDIENTE]: "{no es json" }))).toBeNull();
    expect(
      leerPagoPendiente(crearAlmacen({ [CLAVE_PAGO_PENDIENTE]: JSON.stringify({ idPedido: 9 }) })),
    ).toBeNull();
  });

  test("borrarlo lo saca del almacén", () => {
    const almacen = crearAlmacen();
    guardarPagoPendiente(PENDIENTE, almacen);
    borrarPagoPendiente(almacen);
    expect(leerPagoPendiente(almacen)).toBeNull();
  });

  test("sin localStorage disponible no lanza (incógnito, permisos bloqueados)", () => {
    expect(() => guardarPagoPendiente(PENDIENTE, undefined)).not.toThrow();
    expect(leerPagoPendiente(undefined)).toBeNull();
    expect(() => borrarPagoPendiente(undefined)).not.toThrow();
  });
});

describe("esperaCodigoDePago — a qué pedidos se les ofrece meter el código", () => {
  test("Panadería sin código todavía: sí", () => {
    expect(
      esperaCodigoDePago(pedido({ estadoPagoAdelanto: "VERIFICANDO", codigoOperacionYape: null })),
    ).toBe(true);
  });

  test("ya mandó su código: no (una sola vez por pedido)", () => {
    expect(
      esperaCodigoDePago(pedido({ estadoPagoAdelanto: "VERIFICANDO", codigoOperacionYape: "1234567" })),
    ).toBe(false);
  });

  test("un pedido de hamburguesa nunca lo pide", () => {
    expect(esperaCodigoDePago(pedido({ estadoPagoAdelanto: "NO_APLICA" }))).toBe(false);
    // Backend viejo (sin el campo) se comporta igual que NO_APLICA.
    expect(esperaCodigoDePago(pedido())).toBe(false);
  });

  test("un pedido cancelado o rechazado ya no acepta pagos", () => {
    expect(
      esperaCodigoDePago(
        pedido({ estadoPagoAdelanto: "VERIFICANDO", codigoOperacionYape: null, estado: "CANCELADO" }),
      ),
    ).toBe(false);
    expect(
      esperaCodigoDePago(
        pedido({ estadoPagoAdelanto: "VERIFICANDO", codigoOperacionYape: null, estado: "RECHAZADO" }),
      ),
    ).toBe(false);
  });
});

describe("avisoPagoAdelanto — qué se le dice al cliente sobre su pago", () => {
  test("un pedido que no se paga por adelantado no muestra ningún aviso", () => {
    expect(avisoPagoAdelanto(pedido({ estadoPagoAdelanto: "NO_APLICA" }))).toBeNull();
    expect(avisoPagoAdelanto(pedido())).toBeNull();
  });

  test("falta el código: se le pide, en tono de que hay algo por hacer", () => {
    const aviso = avisoPagoAdelanto(pedido({ estadoPagoAdelanto: "VERIFICANDO", codigoOperacionYape: null }));
    expect(aviso).toEqual({
      texto: "Falta tu código de operación de Yape para confirmar el pedido.",
      tono: "atencion",
    });
  });

  test("código mandado, sin verificar todavía: solo informa", () => {
    const aviso = avisoPagoAdelanto(
      pedido({ estadoPagoAdelanto: "VERIFICANDO", codigoOperacionYape: "1234567" }),
    );
    expect(aviso?.tono).toBe("espera");
  });

  test("pago verificado exacto: nada pendiente", () => {
    const aviso = avisoPagoAdelanto(pedido({ estadoPagoAdelanto: "PAGADO", estado: "CONFIRMADO" }));
    expect(aviso?.tono).toBe("bien");
  });

  test("pagó de menos: se dice cuánto debe, con la cifra", () => {
    const aviso = avisoPagoAdelanto(
      pedido({
        estadoPagoAdelanto: "DEUDA_PARCIAL",
        estado: "CONFIRMADO",
        ajustePago: { tipo: "DEUDA", monto: 2, estado: "PENDIENTE" },
      }),
    );
    expect(aviso?.texto).toContain("aún debes S/ 2.00");
    expect(aviso?.tono).toBe("atencion");
  });

  test("pagó de más: se dice cuánto se le debe de vuelto", () => {
    const aviso = avisoPagoAdelanto(
      pedido({
        estadoPagoAdelanto: "VUELTO_PENDIENTE",
        estado: "CONFIRMADO",
        ajustePago: { tipo: "VUELTO", monto: 3, estado: "PENDIENTE" },
      }),
    );
    expect(aviso?.texto).toContain("te debemos S/ 3.00 de vuelto");
  });

  test("si la tienda ya resolvió el saldo/vuelto no se inventa un monto", () => {
    // El backend solo manda los ajustes PENDIENTE: una vez resuelto llega
    // null, y decir "te debemos S/ 0.00" sería peor que decir la verdad.
    expect(textoAjuste(null, "VUELTO")).toBe("Tu vuelto ya quedó devuelto.");
    expect(textoAjuste(null, "DEUDA")).toBe("Tu saldo pendiente ya quedó cobrado.");
    const aviso = avisoPagoAdelanto(
      pedido({ estadoPagoAdelanto: "VUELTO_PENDIENTE", estado: "ENTREGADO", ajustePago: null }),
    );
    expect(aviso?.texto).toBe("Tu vuelto ya quedó devuelto.");
  });
});
