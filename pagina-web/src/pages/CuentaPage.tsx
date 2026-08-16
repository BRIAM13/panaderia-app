import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { motion } from "framer-motion";
import {
  ArrowLeft,
  LogOut,
  Loader2,
  PackageCheck,
  Clock,
  CheckCircle2,
  Wallet,
} from "lucide-react";
import {
  ApiError,
  cambiarPasswordPrimerIngreso,
  login,
  obtenerMisPedidos,
  type PedidoCliente,
  type UsuarioSesion,
} from "../services/api";
import {
  cerrarSesion,
  guardarSesion,
  obtenerAccessToken,
  obtenerUsuarioGuardado,
} from "../services/sesion";
import { SITE } from "../data/config";

const EASE_PREMIUM = [0.16, 1, 0.3, 1] as const;

export function CuentaPage() {
  const [usuario, setUsuario] = useState<UsuarioSesion | null>(null);
  const [accessToken, setAccessToken] = useState<string | null>(null);
  const [listo, setListo] = useState(false);

  useEffect(() => {
    setUsuario(obtenerUsuarioGuardado());
    setAccessToken(obtenerAccessToken());
    setListo(true);
  }, []);

  function alIniciarSesion(token: string, u: UsuarioSesion) {
    guardarSesion(token, u);
    setAccessToken(token);
    setUsuario(u);
  }

  function alCerrarSesion() {
    cerrarSesion();
    setAccessToken(null);
    setUsuario(null);
  }

  return (
    <div className="min-h-screen bg-pan-crema">
      <header className="border-b border-pan-bronce-suave/60 bg-pan-crema/85 px-6 py-4 backdrop-blur-md">
        <div className="mx-auto flex max-w-xl items-center justify-between">
          <Link
            to="/"
            className="inline-flex items-center gap-2 text-sm font-medium text-pan-carbon-suave hover:text-pan-terracota"
          >
            <ArrowLeft className="h-4 w-4" />
            Volver a la página
          </Link>
          {usuario && (
            <button
              onClick={alCerrarSesion}
              className="inline-flex items-center gap-2 text-sm font-medium text-pan-carbon-suave hover:text-pan-terracota"
            >
              Cerrar sesión
              <LogOut className="h-4 w-4" />
            </button>
          )}
        </div>
      </header>

      <main className="mx-auto max-w-xl px-6 py-16">
        {!listo ? null : !usuario || !accessToken ? (
          <FormularioLogin onExito={alIniciarSesion} />
        ) : usuario.requiereCambioPassword ? (
          <CambiarPasswordPrimerIngreso
            accessToken={accessToken}
            onListo={() => setUsuario({ ...usuario, requiereCambioPassword: false })}
          />
        ) : (
          <ListaDePedidos accessToken={accessToken} usuario={usuario} onSesionInvalida={alCerrarSesion} />
        )}
      </main>
    </div>
  );
}

function FormularioLogin({
  onExito,
}: {
  onExito: (accessToken: string, usuario: UsuarioSesion) => void;
}) {
  const [dni, setDni] = useState("");
  const [password, setPassword] = useState("");
  const [enviando, setEnviando] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function enviar(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setEnviando(true);
    try {
      const resultado = await login(dni.trim(), password);
      onExito(resultado.accessToken, resultado.usuario);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "No pudimos conectar. Intenta de nuevo en un momento.");
    } finally {
      setEnviando(false);
    }
  }

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.5, ease: EASE_PREMIUM }}
    >
      <div className="text-center">
        <h1 className="font-[family-name:var(--font-display-panaderia)] text-3xl font-semibold text-pan-carbon">
          Inicia sesión
        </h1>
        <p className="mt-3 text-pan-carbon-suave">
          Usa tu DNI como usuario. Si pediste pan desde esta página alguna vez, tu contraseña por defecto
          también es tu DNI, y te pediremos cambiarla al entrar.
        </p>
      </div>

      <form onSubmit={enviar} className="mt-8 space-y-5 rounded-3xl bg-pan-crema-suave p-6 shadow-sm shadow-pan-carbon/5 sm:p-8">
        <div>
          <label htmlFor="usuario" className="mb-1.5 block text-sm font-medium text-pan-carbon">
            Usuario (tu DNI)
          </label>
          <input
            id="usuario"
            inputMode="numeric"
            value={dni}
            onChange={(e) => setDni(e.target.value)}
            placeholder="12345678"
            required
            className="w-full rounded-xl border border-pan-bronce-suave bg-pan-crema px-4 py-3 text-pan-carbon outline-none focus:border-pan-terracota"
          />
        </div>
        <div>
          <label htmlFor="password" className="mb-1.5 block text-sm font-medium text-pan-carbon">
            Contraseña
          </label>
          <input
            id="password"
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
            className="w-full rounded-xl border border-pan-bronce-suave bg-pan-crema px-4 py-3 text-pan-carbon outline-none focus:border-pan-terracota"
          />
        </div>

        {error && <p className="text-sm font-medium text-red-700">{error}</p>}

        <button
          type="submit"
          disabled={enviando}
          className="flex w-full items-center justify-center gap-2 rounded-full bg-pan-terracota px-6 py-3.5 font-semibold text-pan-crema shadow-lg shadow-pan-terracota/20 transition-transform hover:scale-[1.02] disabled:opacity-60 disabled:hover:scale-100"
        >
          {enviando ? <Loader2 className="h-4 w-4 animate-spin" /> : "Iniciar sesión"}
        </button>

        <p className="text-center text-sm text-pan-carbon-suave">
          ¿Todavía no pediste con nosotros? Haz tu primer pedido desde{" "}
          <Link to="/#pedido" className="font-semibold text-pan-terracota hover:underline">
            la página principal
          </Link>{" "}
          y tu cuenta se crea sola.
        </p>
      </form>
    </motion.div>
  );
}

function CambiarPasswordPrimerIngreso({
  accessToken,
  onListo,
}: {
  accessToken: string;
  onListo: () => void;
}) {
  const [passwordNueva, setPasswordNueva] = useState("");
  const [confirmacion, setConfirmacion] = useState("");
  const [enviando, setEnviando] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function enviar(e: React.FormEvent) {
    e.preventDefault();
    setError(null);

    if (passwordNueva.length < 8) {
      setError("La contraseña debe tener al menos 8 caracteres.");
      return;
    }
    if (passwordNueva !== confirmacion) {
      setError("Las contraseñas no coinciden.");
      return;
    }

    setEnviando(true);
    try {
      await cambiarPasswordPrimerIngreso(accessToken, passwordNueva);
      onListo();
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "No pudimos conectar. Intenta de nuevo en un momento.");
    } finally {
      setEnviando(false);
    }
  }

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.5, ease: EASE_PREMIUM }}
    >
      <div className="text-center">
        <h1 className="font-[family-name:var(--font-display-panaderia)] text-3xl font-semibold text-pan-carbon">
          Elige una contraseña nueva
        </h1>
        <p className="mt-3 text-pan-carbon-suave">
          Es tu primer ingreso, así que por seguridad te pedimos cambiar la contraseña por defecto antes de
          continuar.
        </p>
      </div>

      <form onSubmit={enviar} className="mt-8 space-y-5 rounded-3xl bg-pan-crema-suave p-6 shadow-sm shadow-pan-carbon/5 sm:p-8">
        <div>
          <label htmlFor="passwordNueva" className="mb-1.5 block text-sm font-medium text-pan-carbon">
            Contraseña nueva
          </label>
          <input
            id="passwordNueva"
            type="password"
            value={passwordNueva}
            onChange={(e) => setPasswordNueva(e.target.value)}
            required
            className="w-full rounded-xl border border-pan-bronce-suave bg-pan-crema px-4 py-3 text-pan-carbon outline-none focus:border-pan-terracota"
          />
          <p className="mt-1 text-xs text-pan-carbon-suave">Al menos 8 caracteres.</p>
        </div>
        <div>
          <label htmlFor="confirmacion" className="mb-1.5 block text-sm font-medium text-pan-carbon">
            Confírmala
          </label>
          <input
            id="confirmacion"
            type="password"
            value={confirmacion}
            onChange={(e) => setConfirmacion(e.target.value)}
            required
            className="w-full rounded-xl border border-pan-bronce-suave bg-pan-crema px-4 py-3 text-pan-carbon outline-none focus:border-pan-terracota"
          />
        </div>

        {error && <p className="text-sm font-medium text-red-700">{error}</p>}

        <button
          type="submit"
          disabled={enviando}
          className="flex w-full items-center justify-center gap-2 rounded-full bg-pan-terracota px-6 py-3.5 font-semibold text-pan-crema shadow-lg shadow-pan-terracota/20 transition-transform hover:scale-[1.02] disabled:opacity-60 disabled:hover:scale-100"
        >
          {enviando ? <Loader2 className="h-4 w-4 animate-spin" /> : "Guardar y continuar"}
        </button>
      </form>
    </motion.div>
  );
}

function infoEstado(pedido: PedidoCliente) {
  if (pedido.estado === "SOLICITADO") {
    return { texto: "Por confirmar", color: "#EA8C1B", Icono: Clock };
  }
  if (pedido.estado === "ENTREGADO") {
    return pedido.estadoPago === "DEUDA"
      ? { texto: "Entregado, con deuda pendiente", color: "#C62828", Icono: Wallet }
      : { texto: "Entregado y pagado", color: "#2E7D32", Icono: CheckCircle2 };
  }
  return { texto: "Confirmado, en camino a entregarse", color: "#2563EB", Icono: PackageCheck };
}

function ListaDePedidos({
  accessToken,
  usuario,
  onSesionInvalida,
}: {
  accessToken: string;
  usuario: UsuarioSesion;
  onSesionInvalida: () => void;
}) {
  const [pedidos, setPedidos] = useState<PedidoCliente[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    obtenerMisPedidos(accessToken)
      .then(setPedidos)
      .catch((err) => {
        if (err instanceof ApiError && err.message.toLowerCase().includes("token")) {
          onSesionInvalida();
          return;
        }
        setError(
          err instanceof ApiError
            ? err.message
            : "No pudimos cargar tus pedidos porque el servidor puede estar despertando. Intenta de nuevo en un momento.",
        );
      });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [accessToken]);

  const nombre = [usuario.nombres, usuario.apellidoPaterno].filter(Boolean).join(" ") || usuario.nombreUsuario;
  const pendientes = pedidos?.filter((p) => p.estado === "SOLICITADO" || p.estado === "PENDIENTE") ?? [];
  const historial = pedidos?.filter((p) => p.estado === "ENTREGADO") ?? [];

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.5, ease: EASE_PREMIUM }}
    >
      <div className="text-center">
        <h1 className="font-[family-name:var(--font-display-panaderia)] text-3xl font-semibold text-pan-carbon">
          Hola, {nombre}
        </h1>
        <p className="mt-2 text-pan-carbon-suave">Acá puedes ver el estado de tus pedidos en {SITE.nombre}.</p>
      </div>

      {error && (
        <p className="mt-8 rounded-2xl bg-red-50 px-4 py-3 text-center text-sm font-medium text-red-700">
          {error}
        </p>
      )}

      {!pedidos && !error && (
        <div className="mt-12 flex justify-center">
          <Loader2 className="h-6 w-6 animate-spin text-pan-terracota" />
        </div>
      )}

      {pedidos && pedidos.length === 0 && (
        <p className="mt-12 text-center text-pan-carbon-suave">Todavía no tienes pedidos registrados.</p>
      )}

      {pedidos && pedidos.length > 0 && (
        <div className="mt-10 space-y-8">
          <SeccionPedidos titulo="Pendientes" pedidos={pendientes} />
          <SeccionPedidos titulo="Historial" pedidos={historial} />
        </div>
      )}
    </motion.div>
  );
}

function SeccionPedidos({ titulo, pedidos }: { titulo: string; pedidos: PedidoCliente[] }) {
  if (pedidos.length === 0) return null;
  return (
    <div>
      <h2 className="font-[family-name:var(--font-display-panaderia)] text-xl font-semibold text-pan-carbon">
        {titulo}
      </h2>
      <div className="mt-4 space-y-3">
        {pedidos.map((pedido) => {
          const estado = infoEstado(pedido);
          return (
            <div
              key={pedido.idPedido}
              className="rounded-2xl bg-pan-crema-suave p-5 shadow-sm shadow-pan-carbon/5"
            >
              <div className="flex items-start justify-between gap-3">
                <div>
                  <p className="font-semibold text-pan-carbon">
                    {pedido.producto} · {pedido.tipoPedido === "PAQUETES" ? `${pedido.cantidad} paquete(s)` : `${pedido.cantidad} unidad(es)`}
                  </p>
                  <p className="text-sm text-pan-carbon-suave">
                    Pedido #{pedido.numeroPedidoDia} · {pedido.tienda ?? "Panadería Ronceros"}
                  </p>
                </div>
                <p className="shrink-0 font-semibold text-pan-terracota">S/ {pedido.total.toFixed(2)}</p>
              </div>
              <div
                className="mt-3 inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-semibold"
                style={{ backgroundColor: `${estado.color}20`, color: estado.color }}
              >
                <estado.Icono className="h-3.5 w-3.5" />
                {estado.texto}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
