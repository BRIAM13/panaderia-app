import { Navbar } from "./Navbar";
import { Footer } from "./Footer";
import { SITE, UBICACION, CONTACTO } from "../data/config";

/**
 * Política de privacidad. Vive en su propia URL (/privacidad) porque el
 * pie de página ya enlazaba ahí desde antes, sin que la página existiera
 * de verdad — Culqi la pidió como requisito para aprobar el cobro con
 * tarjeta. Usa el mismo Navbar/Footer que el resto del sitio para que se
 * sienta parte de él, no una página suelta.
 */
export function PaginaPrivacidad() {
  return (
    <div className="min-h-screen bg-pan-crema">
      <Navbar />
      <main className="mx-auto max-w-3xl px-6 py-16">
        <h1 className="font-[family-name:var(--font-display-panaderia)] text-3xl font-semibold text-pan-carbon">
          Política de privacidad
        </h1>
        <p className="mt-2 text-sm text-pan-carbon-suave">
          {SITE.nombreComercial}, RUC {SITE.ruc}
        </p>

        <div className="mt-8 space-y-6 text-sm leading-relaxed text-pan-carbon-suave">
          <section>
            <h2 className="mb-2 text-base font-semibold text-pan-carbon">Qué datos pedimos</h2>
            <p>
              Para registrar un pedido te pedimos tu documento (DNI o RUC), tu nombre, tu celular y
              tu correo. Usamos esos datos únicamente para confirmar tu pedido, avisarte sobre su
              estado y reconocerte como cliente cuando vuelves a pedir, de modo que puedas recibir
              los descuentos por fidelidad que ofrecemos.
            </p>
          </section>

          <section>
            <h2 className="mb-2 text-base font-semibold text-pan-carbon">Pagos con tarjeta o Yape</h2>
            <p>
              Cuando pagas por adelantado con tarjeta o con Yape, el número de tu tarjeta y tus
              datos de pago nunca pasan por nuestros servidores. Los recibe directamente Culqi, la
              pasarela de pago que procesa el cobro, bajo su propio certificado de seguridad
              PCI-DSS. Nosotros solo recibimos la confirmación de que el pago se realizó y el monto
              correspondiente.
            </p>
          </section>

          <section>
            <h2 className="mb-2 text-base font-semibold text-pan-carbon">Con quién compartimos tus datos</h2>
            <p>
              No vendemos ni compartimos tus datos con terceros, salvo con Culqi para procesar un
              pago, o cuando una autoridad peruana nos lo exige por ley.
            </p>
          </section>

          <section>
            <h2 className="mb-2 text-base font-semibold text-pan-carbon">Cuánto tiempo guardamos tus datos</h2>
            <p>
              Guardamos tu información mientras sigas siendo cliente de la panadería, para llevar tu
              historial de pedidos y tus puntos de fidelidad. Puedes pedirnos en cualquier momento
              que corrijamos o eliminemos tus datos escribiéndonos por WhatsApp al{" "}
              {CONTACTO.telefonoVisible}.
            </p>
          </section>

          <section>
            <h2 className="mb-2 text-base font-semibold text-pan-carbon">Dónde encontrarnos</h2>
            <p>
              {UBICACION.direccion}, {UBICACION.ciudad}.
            </p>
          </section>
        </div>
      </main>
      <Footer />
    </div>
  );
}
