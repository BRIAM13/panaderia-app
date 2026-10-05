import { Navbar } from "./Navbar";
import { Footer } from "./Footer";
import { SITE, UBICACION, CONTACTO, CANTIDAD_MINIMA_UNIDAD } from "../data/config";

/**
 * Términos y condiciones de compra. Igual que PaginaPrivacidad, es una
 * página nueva pedida por Culqi para aprobar el cobro con tarjeta: su
 * revisión pide ver claramente el flujo de compra, los precios y la
 * información legal del comercio en un solo lugar.
 */
export function PaginaTerminos() {
  return (
    <div className="min-h-screen bg-pan-crema">
      <Navbar />
      <main className="mx-auto max-w-3xl px-6 py-16">
        <h1 className="font-[family-name:var(--font-display-panaderia)] text-3xl font-semibold text-pan-carbon">
          Términos y condiciones de compra
        </h1>
        <p className="mt-2 text-sm text-pan-carbon-suave">
          {SITE.nombreComercial}, RUC {SITE.ruc}
        </p>

        <div className="mt-8 space-y-6 text-sm leading-relaxed text-pan-carbon-suave">
          <section>
            <h2 className="mb-2 text-base font-semibold text-pan-carbon">Cómo funciona un pedido</h2>
            <p>
              Eliges el pan y la cantidad en la página, escribes tu documento y tus datos de
              contacto, y confirmas el pedido. El pan de agua y el pan francés se piden por unidad,
              con un mínimo de {CANTIDAD_MINIMA_UNIDAD} unidades, eligiendo además el día y la hora
              en que lo recogerás. El pan de hamburguesa se pide por paquete de 12 unidades. Los
              precios que ves en la página son los precios finales, ya con cualquier descuento por
              fidelidad aplicado.
            </p>
          </section>

          <section>
            <h2 className="mb-2 text-base font-semibold text-pan-carbon">El pago</h2>
            <p>
              Según el momento, algunos pedidos se pagan al recoger el pan y otros requieren un
              pago por adelantado con tarjeta o con Yape para quedar separados; la página siempre te
              avisa cuál aplica a tu pedido antes de pedirte pagar. Cuando el pago es por
              adelantado, puedes elegir pagar desde la mitad del total hasta el total completo; lo
              que no pagues en ese momento se cobra al recoger. Si el pago se hace con tarjeta o
              Yape, la pasarela Culqi cobra una comisión por procesar el cobro, que se suma al monto
              y se te muestra claramente antes de confirmar.
            </p>
          </section>

          <section>
            <h2 className="mb-2 text-base font-semibold text-pan-carbon">Cancelaciones y devoluciones</h2>
            <p>
              Puedes cancelar tu pedido escribiéndonos por WhatsApp al {CONTACTO.telefonoVisible}{" "}
              mientras todavía no hayamos empezado a prepararlo. Si ya pagaste por adelantado y la
              cancelación se hace a tiempo, te devolvemos el dinero por el mismo medio con el que
              pagaste. Si encuentras un problema con tu pedido al recogerlo, dínoslo ahí mismo o
              escríbenos apenas puedas para resolverlo.
            </p>
          </section>

          <section>
            <h2 className="mb-2 text-base font-semibold text-pan-carbon">Dónde recoger tu pedido</h2>
            <p>
              {UBICACION.direccion}, {UBICACION.ciudad}. {UBICACION.referencia}
            </p>
          </section>

          <section>
            <h2 className="mb-2 text-base font-semibold text-pan-carbon">Tus datos</h2>
            <p>
              El tratamiento de tus datos personales se explica en nuestra{" "}
              <a href="/privacidad/" className="font-medium text-pan-terracota hover:underline">
                política de privacidad
              </a>
              .
            </p>
          </section>
        </div>
      </main>
      <Footer />
    </div>
  );
}
