import { describe, expect, test } from "vitest";
import {
  GEO_PERMISO_DENEGADO,
  GEO_POSICION_NO_DISPONIBLE,
  GEO_TIEMPO_AGOTADO,
  LARGO_MAXIMO_DIRECCION,
  LARGO_MAXIMO_REFERENCIA,
  armarDireccionEntrega,
  coordenadasValidas,
  esRechazoPorZona,
  etiquetaTipoEntrega,
  normalizarTexto,
  revisarDatosDelivery,
  textoErrorGeolocalizacion,
  textoPrecisionUbicacion,
  totalConEnvio,
} from "../entrega";

const PIN_PISCO = { latitud: -13.7103, longitud: -76.2054 };

describe("normalizarTexto", () => {
  test("colapsa espacios y recorta los bordes, igual que el backend", () => {
    expect(normalizarTexto("  Calle   Ayacucho \n 475  ")).toBe("Calle Ayacucho 475");
  });
});

describe("armarDireccionEntrega", () => {
  test("pega dirección y referencia en un solo texto legible", () => {
    expect(armarDireccionEntrega("Calle Ayacucho 475", "casa celeste, al lado de la bodega")).toBe(
      "Calle Ayacucho 475 — Referencia: casa celeste, al lado de la bodega",
    );
  });

  test("sin referencia no deja el separador colgando", () => {
    expect(armarDireccionEntrega("Calle Ayacucho 475", "   ")).toBe("Calle Ayacucho 475");
  });

  // La columna del backend es VARCHAR(300): los topes de los dos campos
  // tienen que dejar lugar al separador o el servidor rechaza lo que el
  // formulario dejó escribir.
  test("con los dos campos al tope, el texto final no pasa de 300 caracteres", () => {
    const texto = armarDireccionEntrega("a".repeat(LARGO_MAXIMO_DIRECCION), "b".repeat(LARGO_MAXIMO_REFERENCIA));
    expect(texto.length).toBeLessThanOrEqual(300);
  });
});

describe("coordenadasValidas", () => {
  test("acepta una coordenada real del planeta", () => {
    expect(coordenadasValidas(PIN_PISCO)).toBe(true);
  });

  test("rechaza null, NaN y valores fuera de rango", () => {
    expect(coordenadasValidas(null)).toBe(false);
    expect(coordenadasValidas(undefined)).toBe(false);
    expect(coordenadasValidas({ latitud: NaN, longitud: -76 })).toBe(false);
    expect(coordenadasValidas({ latitud: 91, longitud: -76 })).toBe(false);
    expect(coordenadasValidas({ latitud: -13, longitud: 181 })).toBe(false);
  });
});

describe("revisarDatosDelivery", () => {
  const completo = {
    coordenadas: PIN_PISCO,
    direccion: "Calle Ayacucho 475",
    referencia: "casa celeste, al lado de la bodega",
  };

  test("con todo completo no hay nada que avisar", () => {
    expect(revisarDatosDelivery(completo)).toBeNull();
  });

  // El orden de los avisos es el del formulario: primero el mapa, después
  // la dirección, al final la referencia.
  test("sin pin, avisa el mapa primero aunque falte todo lo demás", () => {
    expect(revisarDatosDelivery({ coordenadas: null, direccion: "", referencia: "" })).toMatch(/mapa/i);
  });

  test("dirección vacía o demasiado corta", () => {
    expect(revisarDatosDelivery({ ...completo, direccion: "   " })).toMatch(/dirección/i);
    expect(revisarDatosDelivery({ ...completo, direccion: "Av 1" })).toMatch(/completa/i);
  });

  // Pedido explícito del dueño: la referencia no es opcional.
  test("la referencia es obligatoria", () => {
    expect(revisarDatosDelivery({ ...completo, referencia: "" })).toMatch(/referencia/i);
  });
});

describe("esRechazoPorZona", () => {
  test("reconoce el 400 del backend por pin fuera del radio", () => {
    expect(esRechazoPorZona({ mensaje: "Fuera de zona", fueraDeZona: true })).toBe(true);
  });

  // Un dato faltante también es 400 pero NO tiene el atajo de "recoger en
  // tienda": ahí hay que corregir el campo.
  test("un 400 por dato faltante no cuenta como fuera de zona", () => {
    expect(esRechazoPorZona({ mensaje: "Marca el mapa", fueraDeZona: false })).toBe(false);
    expect(esRechazoPorZona({ mensaje: "Otro error" })).toBe(false);
    expect(esRechazoPorZona({ fueraDeZona: "true" })).toBe(false);
  });

  test("tolera cuerpos vacíos o rotos", () => {
    expect(esRechazoPorZona(undefined)).toBe(false);
    expect(esRechazoPorZona(null)).toBe(false);
    expect(esRechazoPorZona("texto")).toBe(false);
  });
});

describe("textoErrorGeolocalizacion", () => {
  test("cada código tiene su explicación y todos ofrecen la salida a mano", () => {
    for (const codigo of [GEO_PERMISO_DENEGADO, GEO_POSICION_NO_DISPONIBLE, GEO_TIEMPO_AGOTADO, null, 99]) {
      expect(textoErrorGeolocalizacion(codigo)).toMatch(/pin/i);
    }
    expect(textoErrorGeolocalizacion(GEO_PERMISO_DENEGADO)).toMatch(/permiso/i);
    expect(textoErrorGeolocalizacion(null)).toMatch(/navegador/i);
  });
});

describe("textoPrecisionUbicacion", () => {
  test("no avisa nada con buena precisión", () => {
    expect(textoPrecisionUbicacion(12)).toBeNull();
    expect(textoPrecisionUbicacion(99.9)).toBeNull();
  });

  test("a partir de 100 m avisa en metros, y en km cuando es mucho", () => {
    expect(textoPrecisionUbicacion(250)).toMatch(/250 m/);
    expect(textoPrecisionUbicacion(1500)).toMatch(/1\.5 km/);
  });

  test("un valor roto no avisa", () => {
    expect(textoPrecisionUbicacion(NaN)).toBeNull();
  });
});

describe("totalConEnvio", () => {
  test("suma sin cola de punto flotante", () => {
    expect(totalConEnvio(48.1, 4)).toBe(52.1);
    expect(totalConEnvio(16.63, 4)).toBe(20.63);
  });

  test("un envío inválido o negativo cuenta como cero", () => {
    expect(totalConEnvio(50, 0)).toBe(50);
    expect(totalConEnvio(50, -4)).toBe(50);
    expect(totalConEnvio(50, NaN)).toBe(50);
  });
});

describe("etiquetaTipoEntrega", () => {
  test("traduce los dos valores del backend", () => {
    expect(etiquetaTipoEntrega("RECOJO")).toBe("Recojo en tienda");
    expect(etiquetaTipoEntrega("DELIVERY")).toBe("Delivery a domicilio");
  });
});
