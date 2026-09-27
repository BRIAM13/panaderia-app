/**
 * Utilidades puras para el formulario de pago con tarjeta (Culqi). Todo lo
 * de acá es lógica de formato/validación del lado del cliente — nada habla
 * con Culqi.js ni con el backend, así que se puede probar sin DOM ni red.
 *
 * La validación real de que la tarjeta "existe" y tiene fondos la hace el
 * banco emisor cuando Culqi la procesa; el checklist de acá (Luhn,
 * expiración, largo de CVC) solo atrapa el error de tecleo obvio ANTES de
 * gastar un viaje a Culqi — misma idea que `revisarMontoDeclarado` en
 * `pagoAdelanto.ts` para el pago por Yape.
 */

export type MarcaTarjeta = "VISA" | "MASTERCARD" | "AMEX" | "DESCONOCIDA";

/** Deja solo dígitos — la misma limpieza que ya usan el DNI y el celular en
 * el resto del proyecto. */
export function soloDigitos(valor: string): string {
  return valor.replace(/\D/g, "");
}

/** Detección de marca a nivel visual únicamente (qué logo/etiqueta mostrar
 * en la vista previa de la tarjeta): Visa arranca en 4, Mastercard en 51-55
 * o 22-27, Amex en 34/37. No hace falta más precisión que esta — Culqi (y
 * el banco emisor) son quienes de verdad validan la tarjeta. */
export function detectarMarca(numero: string): MarcaTarjeta {
  const limpio = soloDigitos(numero);
  if (/^4/.test(limpio)) return "VISA";
  if (/^(5[1-5]|2[2-7])/.test(limpio)) return "MASTERCARD";
  if (/^3[47]/.test(limpio)) return "AMEX";
  return "DESCONOCIDA";
}

/** Amex tiene 15 dígitos; el resto de marcas que soportamos a nivel visual
 * (y la gran mayoría de tarjetas en general) usan 16. */
function largoNumero(marca: MarcaTarjeta): number {
  return marca === "AMEX" ? 15 : 16;
}

/** Lo que de verdad queda escrito en el campo mientras el cliente teclea:
 * solo dígitos, cortado al largo que le corresponde a la marca detectada. */
export function limpiarNumeroTarjeta(valor: string): string {
  const limpio = soloDigitos(valor);
  return limpio.slice(0, largoNumero(detectarMarca(limpio)));
}

/** Formato "en vivo" mientras se teclea: grupos de 4 dígitos (Visa/Mastercard,
 * "4242 4242 4242 4242") o 4-6-5 en Amex ("3782 822463 10005"), que es como
 * esas tarjetas vienen impresas de fábrica. */
export function formatearNumeroTarjeta(valor: string): string {
  const limpio = limpiarNumeroTarjeta(valor);
  if (detectarMarca(limpio) === "AMEX") {
    const partes = [limpio.slice(0, 4), limpio.slice(4, 10), limpio.slice(10, 15)].filter(Boolean);
    return partes.join(" ");
  }
  return limpio.replace(/(\d{4})(?=\d)/g, "$1 ");
}

/**
 * Cómo se ve el número en la vista previa de la tarjeta mientras se escribe:
 * los últimos 4 dígitos ya tecleados quedan visibles y todo lo anterior se
 * tapa con "•" — igual que cualquier checkout real ("•••• •••• •••• 4242").
 * Lo que todavía no se escribió también se muestra como relleno, para que la
 * tarjeta nunca se vea "vacía a medias" mientras el cliente teclea.
 */
export function numeroTarjetaEnmascarado(valor: string): string {
  const limpio = soloDigitos(valor);
  const marca = detectarMarca(limpio);
  const largo = largoNumero(marca);
  const comienzoVisible = Math.max(limpio.length - 4, 0);
  const caracteres: string[] = [];
  for (let i = 0; i < largo; i++) {
    if (i < limpio.length && i >= comienzoVisible) {
      caracteres.push(limpio[i]);
    } else {
      caracteres.push("•");
    }
  }
  const completo = caracteres.join("");
  if (marca === "AMEX") {
    return `${completo.slice(0, 4)} ${completo.slice(4, 10)} ${completo.slice(10, 15)}`;
  }
  return completo.replace(/(.{4})(?=.)/g, "$1 ");
}

/**
 * Algoritmo de Luhn: el chequeo de forma que ya hace cualquier lector de
 * tarjetas antes de mandar nada al banco. Atrapa el típico dígito
 * transpuesto o mal tecleado — no confirma que la tarjeta exista ni tenga
 * fondos, eso lo resuelve Culqi/el banco emisor.
 */
export function numeroTarjetaValidoLuhn(numero: string): boolean {
  const limpio = soloDigitos(numero);
  if (limpio.length < 12) return false;
  let suma = 0;
  let duplicar = false;
  for (let i = limpio.length - 1; i >= 0; i--) {
    let digito = Number(limpio[i]);
    if (duplicar) {
      digito *= 2;
      if (digito > 9) digito -= 9;
    }
    suma += digito;
    duplicar = !duplicar;
  }
  return suma % 10 === 0;
}

/** Autoformato de la fecha de expiración mientras se teclea: "MM/AA". */
export function formatearExpiracion(valor: string): string {
  const limpio = soloDigitos(valor).slice(0, 4);
  if (limpio.length <= 2) return limpio;
  return `${limpio.slice(0, 2)}/${limpio.slice(2)}`;
}

/** El mes y el año (de 2 cifras) sueltos, tal como los pide Culqi en sus
 * dos campos separados (`card[exp_month]` / `card[exp_year]`) — el
 * formulario los muestra juntos ("MM/AA") pero Culqi los necesita aparte. */
export function partesExpiracion(valorFormateado: string): { mes: string; anio: string } {
  const limpio = soloDigitos(valorFormateado).slice(0, 4);
  return { mes: limpio.slice(0, 2), anio: limpio.slice(2, 4) };
}

/**
 * ¿La fecha de expiración es válida y todavía no venció? Una tarjeta vence
 * al terminar el último día de su mes impreso, así que "válida" incluye
 * todo ese mes — se compara contra el primer día del mes SIGUIENTE.
 */
export function expiracionValida(valorFormateado: string, ahora: Date = new Date()): boolean {
  const { mes, anio } = partesExpiracion(valorFormateado);
  if (mes.length !== 2 || anio.length !== 2) return false;
  const mesNum = Number(mes);
  if (!Number.isInteger(mesNum) || mesNum < 1 || mesNum > 12) return false;
  const anioNum = 2000 + Number(anio);
  // `new Date(anioNum, mesNum, 1)`: como el mes de Date es base-0, pasarle
  // el mes tecleado (base-1) ya apunta al primer día del mes SIGUIENTE.
  const primerDiaSiguienteMes = new Date(anioNum, mesNum, 1);
  return primerDiaSiguienteMes.getTime() > ahora.getTime();
}

/** El CVC solo se limpia a dígitos — no lleva ningún otro formato. */
export function limpiarCvc(valor: string): string {
  return soloDigitos(valor).slice(0, 4);
}

/**
 * Cómo se ve el CVC en el reverso de la tarjeta de vista previa: un "•" por
 * cada dígito ya tecleado y NUNCA los números reales — ni acá ni en el
 * campo (que es `type="password"`). El dueño lo pidió explícito: los tres
 * dígitos de atrás son lo único que un mirón no debería poder leer por
 * encima del hombro, así que la pantalla no los muestra en ningún lado.
 */
export function cvcEnmascarado(cvc: string): string {
  return "•".repeat(limpiarCvc(cvc).length);
}

/** 3 dígitos en Visa/Mastercard, 4 en Amex — pero como esto es solo un
 * chequeo de forma (Culqi/el banco son quienes de verdad lo validan), basta
 * con aceptar cualquiera de los dos largos sin atarlo a la marca. */
export function cvcValido(cvc: string): boolean {
  return /^\d{3,4}$/.test(soloDigitos(cvc));
}

/** Lo único que acepta el nombre del titular: letras (con tilde y Ñ, que en
 * nombres peruanos son de todos los días — "JOSÉ", "MUÑOZ", "ÑAÑEZ") y el
 * espacio que separa nombre de apellido. Nada de números ni símbolos: la
 * tarjeta física no los imprime y Culqi tampoco los espera. */
const LETRAS_NO_VALIDAS_NOMBRE = /[^A-ZÁÉÍÓÚÑÜ ]/g;

/**
 * Lo que de verdad queda escrito en el campo "Nombre del titular" mientras
 * el cliente teclea: SIEMPRE en mayúscula (como viene impreso en relieve en
 * la tarjeta), sin nada que no sea letra o espacio, y con los espacios bajo
 * control — no deja empezar con espacio ni escribir dos seguidos.
 *
 * Ojo: el espacio simple al final NO se recorta, porque el cliente lo acaba
 * de teclear justamente para seguir con el apellido — recortarlo acá sería
 * pelearse con quien está escribiendo. Del recorte final se encarga
 * `nombreTitularValido` (y el `.trim()` de la vista previa).
 */
export function formatearNombreTitular(valor: string): string {
  return (
    valor
      // Un teclado de macOS (o un copiar/pegar) puede mandar la tilde como
      // carácter suelto ("e" + ´); normalizar la pega a su letra antes de
      // filtrar, así "José" no termina como "JOSE".
      .normalize("NFC")
      .toUpperCase()
      .replace(LETRAS_NO_VALIDAS_NOMBRE, "")
      .replace(/ {2,}/g, " ")
      .replace(/^ +/, "")
  );
}

/**
 * ¿El nombre alcanza para ser "un nombre y un apellido"? Es lo que pidió el
 * dueño: en la tarjeta nunca figura una sola palabra, así que una sola
 * palabra es casi siempre un cliente que se apuró y dejó el apellido afuera.
 *
 * El criterio es contar cuántas palabras de 2+ letras hay: tienen que haber
 * al menos dos. Se cuenta así (y no "todas las palabras de 2+ letras")
 * porque hay tarjetas emitidas con la inicial del segundo nombre — "JOSÉ L
 * GARCÍA" es un nombre real y bloquearlo sería un falso positivo.
 */
export function nombreTitularValido(nombre: string): boolean {
  const palabras = formatearNombreTitular(nombre).trim().split(" ").filter(Boolean);
  return palabras.filter((palabra) => palabra.length >= 2).length >= 2;
}

/** El correo no lleva espacios en ninguna parte — ni al costado ni en medio
 * — así que se le sacan mientras se teclea, igual que el número de tarjeta
 * solo deja pasar dígitos. Evita el espacio que mete el autocompletado del
 * celular y el que queda de un copiar/pegar. */
export function limpiarEmail(valor: string): string {
  return valor.replace(/\s+/g, "");
}

/** Mismo chequeo de forma que usa el resto del proyecto para el correo
 * (`EMAIL_REGEX` en `PedidoForm.tsx`) — Culqi exige el correo para poder
 * generar el token. */
export function emailValido(email: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim());
}
