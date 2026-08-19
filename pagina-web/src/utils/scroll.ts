/** Lleva el scroll suavemente a una sección de la página sin tocar la URL
 * — evita que la barra de direcciones muestre "#nosotros", "#menu", etc.
 * en cada clic de navegación (a diferencia de dejar que el navegador siga
 * el href="#..." de forma nativa). */
export function desplazarASeccion(id: string) {
  document.getElementById(id)?.scrollIntoView({ behavior: "smooth", block: "start" });
}
