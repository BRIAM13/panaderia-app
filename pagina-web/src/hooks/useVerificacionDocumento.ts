import { useEffect, useState } from "react";
import {
  verificarDocumentoPublico,
  type ContactoDocumento,
  type DescuentoCliente,
} from "../services/api";

export type { ContactoDocumento, DescuentoCliente, EstadoContacto } from "../services/api";

export type TipoDocumento = "DNI" | "RUC";

export const LONGITUD_DOCUMENTO: Record<TipoDocumento, number> = { DNI: 8, RUC: 11 };

/** Ningún dato guardado: el punto de partida mientras no hay un documento
 * verificado, y también lo que aplica a un documento que nunca pidió por
 * acá. Con esto el formulario nunca tiene que preguntar por `undefined`. */
export const CONTACTO_VACIO: ContactoDocumento = {
  email: { enArchivo: false, verificado: false, mascara: null },
  telefono: { enArchivo: false, verificado: false, mascara: null },
};

export interface VerificacionDocumento {
  /** null = todavía no se completó/verificó (o la verificación misma
   * falló); true/false = lo que respondió RENIEC/SUNAT. */
  valido: boolean | null;
  verificando: boolean;
  /** Texto ya listo para mostrarle al cliente cuando algo no cuadra. */
  aviso: string | null;
  /** Correo/celular que ya tenemos de este documento, enmascarados — para
   * no volver a pedírselos a quien ya pidió antes. Siempre CONTACTO_VACIO
   * mientras el documento no esté verificado. */
  contacto: ContactoDocumento;
  /** Descuento por fidelidad de este documento en la tienda que se pasó en
   * `tiendaSlug`. null mientras no se sepa, cuando esa tienda no lo tiene
   * habilitado, o cuando el documento no existe.
   *
   * Es un anticipo para que el cliente vea lo que va a pagar ANTES de
   * enviar: el monto real lo recalcula el servidor al crear el pedido. */
  descuento: DescuentoCliente | null;
  /** Para qué tienda se pidió el `descuento` de arriba. Si el visitante
   * cambia de pan después de escribir su documento, el formulario necesita
   * saber que ese descuento era de la tienda anterior (ver
   * `descuentoVigente` en utils/descuentos.ts). */
  tiendaSlugConsultada: string | undefined;
}

/** Verifica el documento contra RENIEC/SUNAT apenas llega al largo
 * esperado (8 dígitos DNI, 11 RUC), sin esperar a que el cliente envíe
 * nada: así se entera de entrada si escribió mal el número, en vez de
 * descubrirlo recién al mandar todo el formulario.
 *
 * Si borra un dígito o cambia de DNI a RUC, el resultado anterior ya no
 * aplica y todo vuelve a "sin verificar" hasta completar el número nuevo.
 * Una respuesta que llega tarde, cuando el número ya cambió, se descarta
 * (`cancelado`) para que nunca pise a la verificación vigente.
 *
 * `tiendaSlug` (opcional) es la tienda del pan que el visitante tiene
 * elegido: se manda para que el backend devuelva además el descuento que le
 * corresponde ahí. Cambiarla vuelve a verificar — el descuento depende de la
 * tienda, así que una respuesta vieja no sirve. */
export function useVerificacionDocumento(
  numeroDocumento: string,
  tipoDocumento: TipoDocumento,
  tiendaSlug?: string,
): VerificacionDocumento {
  const [valido, setValido] = useState<boolean | null>(null);
  const [verificando, setVerificando] = useState(false);
  const [aviso, setAviso] = useState<string | null>(null);
  const [contacto, setContacto] = useState<ContactoDocumento>(CONTACTO_VACIO);
  const [descuento, setDescuento] = useState<DescuentoCliente | null>(null);
  const [tiendaSlugConsultada, setTiendaSlugConsultada] = useState<string | undefined>(undefined);

  useEffect(() => {
    if (numeroDocumento.length !== LONGITUD_DOCUMENTO[tipoDocumento]) {
      setValido(null);
      setAviso(null);
      setContacto(CONTACTO_VACIO);
      setDescuento(null);
      setTiendaSlugConsultada(undefined);
      return;
    }
    let cancelado = false;
    setVerificando(true);
    setAviso(null);
    // El contacto del documento anterior no aplica al que se está
    // escribiendo ahora: se limpia de entrada, no cuando llega la respuesta.
    // Lo mismo con el descuento, que además depende de la tienda.
    setContacto(CONTACTO_VACIO);
    setDescuento(null);
    setTiendaSlugConsultada(undefined);
    verificarDocumentoPublico(numeroDocumento, tiendaSlug)
      .then((resultado) => {
        if (cancelado) return;
        setValido(resultado.existe);
        setContacto(resultado.existe ? (resultado.contacto ?? CONTACTO_VACIO) : CONTACTO_VACIO);
        setDescuento(resultado.existe ? (resultado.descuentoCliente ?? null) : null);
        setTiendaSlugConsultada(resultado.existe ? tiendaSlug : undefined);
        if (!resultado.existe) {
          setAviso(resultado.mensaje ?? textoNoEncontrado(tipoDocumento));
        }
      })
      .catch(() => {
        if (cancelado) return;
        setValido(null);
        setContacto(CONTACTO_VACIO);
        setDescuento(null);
        setTiendaSlugConsultada(undefined);
        setAviso("No pudimos verificar el documento. Intenta de nuevo en un momento.");
      })
      .finally(() => {
        if (!cancelado) setVerificando(false);
      });
    return () => {
      cancelado = true;
    };
  }, [numeroDocumento, tipoDocumento, tiendaSlug]);

  return { valido, verificando, aviso, contacto, descuento, tiendaSlugConsultada };
}

export function textoNoEncontrado(tipoDocumento: TipoDocumento): string {
  return tipoDocumento === "DNI" ? "DNI no encontrado." : "RUC no encontrado.";
}
