import { describe, expect, test } from "vitest";
import {
  cvcEnmascarado,
  cvcValido,
  detectarMarca,
  emailValido,
  expiracionValida,
  formatearExpiracion,
  formatearNombreTitular,
  formatearNumeroTarjeta,
  limpiarCvc,
  limpiarEmail,
  limpiarNumeroTarjeta,
  nombreTitularValido,
  numeroTarjetaEnmascarado,
  numeroTarjetaValidoLuhn,
  partesExpiracion,
  soloDigitos,
} from "../tarjeta";

describe("soloDigitos", () => {
  test("deja solo dígitos, sin importar qué se haya tecleado alrededor", () => {
    expect(soloDigitos("4242 4242 4242 4242")).toBe("4242424242424242");
    expect(soloDigitos("ab12-34cd")).toBe("1234");
    expect(soloDigitos("")).toBe("");
  });
});

describe("detectarMarca — solo a nivel visual, Culqi/el banco validan el resto", () => {
  test("Visa arranca en 4", () => {
    expect(detectarMarca("4242424242424242")).toBe("VISA");
    expect(detectarMarca("4111 1111 1111 1111")).toBe("VISA");
  });

  test("Mastercard arranca en 51-55 o 22-27", () => {
    expect(detectarMarca("5555555555554444")).toBe("MASTERCARD");
    expect(detectarMarca("5111111111111118")).toBe("MASTERCARD");
    expect(detectarMarca("2223000048400011")).toBe("MASTERCARD");
  });

  test("Amex arranca en 34 o 37", () => {
    expect(detectarMarca("378282246310005")).toBe("AMEX");
    expect(detectarMarca("341111111111111")).toBe("AMEX");
  });

  test("cualquier otro prefijo (o vacío) es desconocida", () => {
    expect(detectarMarca("6011111111111117")).toBe("DESCONOCIDA");
    expect(detectarMarca("")).toBe("DESCONOCIDA");
  });
});

describe("limpiarNumeroTarjeta — corta al largo real de la marca mientras se teclea", () => {
  test("Visa/Mastercard se cortan en 16 dígitos", () => {
    expect(limpiarNumeroTarjeta("42424242424242424242")).toHaveLength(16);
    expect(limpiarNumeroTarjeta("42424242424242424242")).toBe("4242424242424242");
  });

  test("Amex se corta en 15 dígitos", () => {
    expect(limpiarNumeroTarjeta("3782822463100059999")).toHaveLength(15);
    expect(limpiarNumeroTarjeta("3782822463100059999")).toBe("378282246310005");
  });

  test("una letra pegada por error no llega a escribirse", () => {
    expect(limpiarNumeroTarjeta("4242 abcd 4242")).toBe("42424242");
  });
});

describe("formatearNumeroTarjeta — grupos como viene impresa la tarjeta", () => {
  test("Visa/Mastercard en grupos de 4, sin espacio colgando al final", () => {
    expect(formatearNumeroTarjeta("4242424242424242")).toBe("4242 4242 4242 4242");
    expect(formatearNumeroTarjeta("42424")).toBe("4242 4");
    expect(formatearNumeroTarjeta("4242")).toBe("4242");
  });

  test("Amex en grupos 4-6-5", () => {
    expect(formatearNumeroTarjeta("378282246310005")).toBe("3782 822463 10005");
    expect(formatearNumeroTarjeta("3782822")).toBe("3782 822");
  });

  test("acepta el valor ya formateado (re-tecleo) sin duplicar espacios", () => {
    expect(formatearNumeroTarjeta("4242 4242 4242 4242")).toBe("4242 4242 4242 4242");
  });
});

describe("numeroTarjetaEnmascarado — la vista previa en vivo de la tarjeta", () => {
  test("sin nada tecleado, todo relleno", () => {
    expect(numeroTarjetaEnmascarado("")).toBe("•••• •••• •••• ••••");
  });

  test("con menos de 4 dígitos, esos quedan visibles (no hay nada más que tapar)", () => {
    expect(numeroTarjetaEnmascarado("42")).toBe("42•• •••• •••• ••••");
  });

  test("con el número completo, solo los últimos 4 quedan visibles", () => {
    expect(numeroTarjetaEnmascarado("4242424242424242")).toBe("•••• •••• •••• 4242");
  });

  test("a mitad de tecleo, se tapa todo menos los últimos 4 ya escritos", () => {
    // 12 dígitos tecleados: los primeros 8 se tapan, los siguientes 4 quedan
    // visibles, y los 4 que todavía no se escriben se muestran de relleno.
    expect(numeroTarjetaEnmascarado("424212345678")).toBe("•••• •••• 5678 ••••");
  });

  test("Amex respeta su agrupación 4-6-5", () => {
    expect(numeroTarjetaEnmascarado("378282246310005")).toBe("•••• •••••• •0005");
  });
});

describe("numeroTarjetaValidoLuhn", () => {
  test("tarjetas de prueba conocidas pasan Luhn", () => {
    expect(numeroTarjetaValidoLuhn("4242424242424242")).toBe(true);
    expect(numeroTarjetaValidoLuhn("5555555555554444")).toBe(true);
    expect(numeroTarjetaValidoLuhn("378282246310005")).toBe(true);
  });

  test("un dígito mal tecleado rompe el chequeo", () => {
    expect(numeroTarjetaValidoLuhn("4242424242424243")).toBe(false);
  });

  test("un número demasiado corto no es válido", () => {
    expect(numeroTarjetaValidoLuhn("4242")).toBe(false);
    expect(numeroTarjetaValidoLuhn("")).toBe(false);
  });
});

describe("expiración — autoformato y partes sueltas para Culqi", () => {
  test("formatearExpiracion agrega la barra al llegar al tercer dígito", () => {
    expect(formatearExpiracion("1")).toBe("1");
    expect(formatearExpiracion("12")).toBe("12");
    expect(formatearExpiracion("122")).toBe("12/2");
    expect(formatearExpiracion("1225")).toBe("12/25");
    expect(formatearExpiracion("12/25")).toBe("12/25");
    expect(formatearExpiracion("122599")).toBe("12/25");
  });

  test("partesExpiracion separa mes y año como los pide Culqi", () => {
    expect(partesExpiracion("12/25")).toEqual({ mes: "12", anio: "25" });
    expect(partesExpiracion("1")).toEqual({ mes: "1", anio: "" });
    expect(partesExpiracion("")).toEqual({ mes: "", anio: "" });
  });
});

describe("expiracionValida — vence al terminar el mes impreso, no antes", () => {
  const mismoDia = new Date(2026, 8, 15); // 15 de septiembre de 2026

  test("un mes futuro es válido", () => {
    expect(expiracionValida("12/26", mismoDia)).toBe(true);
  });

  test("el mes actual sigue siendo válido mientras no termine", () => {
    expect(expiracionValida("09/26", mismoDia)).toBe(true);
  });

  test("un mes ya pasado no es válido", () => {
    expect(expiracionValida("08/26", mismoDia)).toBe(false);
  });

  test("justo al empezar el día 1 del mes siguiente, ya venció", () => {
    expect(expiracionValida("09/26", new Date(2026, 9, 1, 0, 0, 0))).toBe(false);
  });

  test("un segundo antes de que empiece el mes siguiente, todavía es válida", () => {
    expect(expiracionValida("09/26", new Date(2026, 8, 30, 23, 59, 59))).toBe(true);
  });

  test("una fecha incompleta o un mes fuera de rango no son válidos", () => {
    expect(expiracionValida("1/26", mismoDia)).toBe(false);
    expect(expiracionValida("13/26", mismoDia)).toBe(false);
    expect(expiracionValida("00/26", mismoDia)).toBe(false);
    expect(expiracionValida("", mismoDia)).toBe(false);
  });
});

describe("CVC", () => {
  test("limpiarCvc deja solo dígitos, hasta 4", () => {
    expect(limpiarCvc("12a3")).toBe("123");
    expect(limpiarCvc("99999")).toBe("9999");
  });

  test("cvcEnmascarado pone un punto por dígito tecleado y nunca el número real", () => {
    expect(cvcEnmascarado("")).toBe("");
    expect(cvcEnmascarado("1")).toBe("•");
    expect(cvcEnmascarado("123")).toBe("•••");
    expect(cvcEnmascarado("1234")).toBe("••••");
    // Misma limpieza que el campo: letras fuera, y nunca más de 4.
    expect(cvcEnmascarado("12a3")).toBe("•••");
    expect(cvcEnmascarado("99999")).toBe("••••");
    expect(cvcEnmascarado("123")).not.toContain("1");
  });

  test("cvcValido acepta 3 o 4 dígitos y nada más", () => {
    expect(cvcValido("123")).toBe(true);
    expect(cvcValido("1234")).toBe(true);
    expect(cvcValido("12")).toBe(false);
    expect(cvcValido("12345")).toBe(false);
    expect(cvcValido("")).toBe(false);
    expect(cvcValido("12a")).toBe(false);
  });
});

describe("formatearNombreTitular — lo que queda escrito mientras se teclea", () => {
  test("pasa todo a mayúscula, como viene impreso en la tarjeta", () => {
    expect(formatearNombreTitular("juan perez")).toBe("JUAN PEREZ");
    expect(formatearNombreTitular("Juan Perez")).toBe("JUAN PEREZ");
  });

  test("las tildes y la Ñ sí son letras válidas", () => {
    expect(formatearNombreTitular("josé muñoz")).toBe("JOSÉ MUÑOZ");
    expect(formatearNombreTitular("ñañez agüero")).toBe("ÑAÑEZ AGÜERO");
  });

  test("un número o un símbolo no llegan a escribirse", () => {
    expect(formatearNombreTitular("juan4 perez")).toBe("JUAN PEREZ");
    expect(formatearNombreTitular("juan.perez@")).toBe("JUANPEREZ");
    expect(formatearNombreTitular("o'brien-lopez")).toBe("OBRIENLOPEZ");
  });

  test("no deja empezar con espacio", () => {
    expect(formatearNombreTitular(" ")).toBe("");
    expect(formatearNombreTitular("   juan")).toBe("JUAN");
  });

  test("dos espacios seguidos se colapsan en uno", () => {
    expect(formatearNombreTitular("juan   perez")).toBe("JUAN PEREZ");
    // El número del medio se va primero, así que los espacios que deja
    // pegados tampoco quedan duplicados.
    expect(formatearNombreTitular("juan 1 perez")).toBe("JUAN PEREZ");
  });

  test("el espacio simple al final se respeta: el cliente sigue tecleando el apellido", () => {
    expect(formatearNombreTitular("juan ")).toBe("JUAN ");
    expect(formatearNombreTitular("juan  ")).toBe("JUAN ");
  });

  test("acepta el valor ya formateado (re-tecleo) sin cambiarlo", () => {
    expect(formatearNombreTitular("JUAN PEREZ")).toBe("JUAN PEREZ");
    expect(formatearNombreTitular("")).toBe("");
  });
});

describe("nombreTitularValido — al menos un nombre y un apellido", () => {
  test("nombre y apellido alcanzan", () => {
    expect(nombreTitularValido("JUAN PEREZ")).toBe(true);
    expect(nombreTitularValido("JOSÉ MUÑOZ")).toBe(true);
    expect(nombreTitularValido("JUAN CARLOS PEREZ DE LA CRUZ")).toBe(true);
  });

  test("una sola palabra no alcanza — falta el apellido", () => {
    expect(nombreTitularValido("JUAN")).toBe(false);
    expect(nombreTitularValido("")).toBe(false);
    expect(nombreTitularValido("   ")).toBe(false);
  });

  test("los espacios sueltos de los costados no cuentan como palabra", () => {
    expect(nombreTitularValido("JUAN ")).toBe(false);
    expect(nombreTitularValido("  JUAN PEREZ  ")).toBe(true);
  });

  test("una inicial suelta no reemplaza al apellido, pero tampoco lo invalida", () => {
    expect(nombreTitularValido("JUAN P")).toBe(false);
    expect(nombreTitularValido("JOSÉ L GARCÍA")).toBe(true);
  });

  test("lo que el campo ni deja escribir tampoco pasa la validación", () => {
    expect(nombreTitularValido("JUAN 4242")).toBe(false);
    expect(nombreTitularValido("1234 5678")).toBe(false);
  });
});

describe("limpiarEmail — el correo nunca lleva espacios", () => {
  test("saca los espacios de los costados y de en medio", () => {
    expect(limpiarEmail("  cliente@correo.com  ")).toBe("cliente@correo.com");
    expect(limpiarEmail("cliente @correo.com")).toBe("cliente@correo.com");
    expect(limpiarEmail("")).toBe("");
  });

  test("no toca nada más del correo", () => {
    expect(limpiarEmail("cliente.perez+pan@correo.com.pe")).toBe("cliente.perez+pan@correo.com.pe");
  });
});

describe("emailValido — mismo chequeo de forma que el resto del proyecto", () => {
  test("acepta un correo con forma válida", () => {
    expect(emailValido("cliente@correo.com")).toBe(true);
    expect(emailValido("  cliente@correo.com  ")).toBe(true);
  });

  test("rechaza lo que obviamente no es un correo", () => {
    expect(emailValido("cliente")).toBe(false);
    expect(emailValido("cliente@")).toBe(false);
    expect(emailValido("cliente@correo")).toBe(false);
    expect(emailValido("cliente@correo.")).toBe(false);
    expect(emailValido("@correo.com")).toBe(false);
    expect(emailValido("")).toBe(false);
  });
});
