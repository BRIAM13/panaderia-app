import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/app_theme.dart';
import '../theme/breakpoints.dart';
import 'contador_animado.dart';

/// Kit de piezas compartidas para las ramas de ESCRITORIO de las pantallas
/// de gestión (Dashboard, Analítica, Clientes, Trabajadores…).
///
/// Todo lo de acá se usa SOLO dentro de un `if (esEscritorio(context))`:
/// el árbol de widgets de celular/tablet queda exactamente como estaba. La
/// idea es que las tres tiendas (Hamburguesas, Horneados, Panadería)
/// compartan el mismo lenguaje visual en pantalla grande sin copiar y pegar
/// el mismo `Container` decorado en cada archivo.
///
/// Convenciones que respeta este kit:
/// - Superficie: `AppColors.surface` con borde suave y sombra baja; el color
///   fuerte se reserva para acentos (íconos, valores, bordes en hover).
/// - Radio: 22 en tarjetas, 24 en paneles de sección.
/// - Hover: la web SÍ tiene mouse — cada elemento accionable se levanta, se
///   le enciende el borde y cambia el cursor. En celular no hay puntero, así
///   que estos estados nunca se disparan ahí.

/// Ventana lo bastante ancha como para un layout de 2 columnas o un panel
/// lateral fijo.
bool esEscritorio(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= Breakpoints.escritorio;

/// Ventana donde además caben densidades altas (fila de 4 KPIs, tablas)
/// incluso descontando el panel lateral fijo del Hub.
bool esEscritorioComodo(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= Breakpoints.escritorioComodo;

/// Monitor grande: entran tres columnas de contenido a la vez.
bool esEscritorioAncho(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= Breakpoints.escritorioAncho;

/// Ancho máximo de lectura cómoda para un tablero. Sin este tope, en un
/// monitor de 2560 px una fila de 4 KPIs deja tarjetas de 600 px de ancho
/// con un número de 30 px adentro: espacio desperdiciado y ojo obligado a
/// barrer toda la pantalla. Se centra el contenido y el resto queda de aire.
const double anchoMaximoTablero = 1560;

/// Separación estándar entre columnas/paneles en escritorio.
const double espacioEscritorio = 24;

/// Barra superior de una pantalla de gestión abierta como ruta completa
/// (Clientes, Analítica, Trabajadores…).
///
/// En celular devuelve EXACTAMENTE el `AppBar` de siempre (título centrado
/// por tema, sin decoración extra). En escritorio el título se alinea a la
/// izquierda junto al botón de volver, gana una línea de contexto debajo y
/// se separa del contenido con un borde fino: un título centrado en una
/// barra de 1900 px queda flotando en el vacío y no ancla nada.
PreferredSizeWidget appBarGestion(
  BuildContext context, {
  required String titulo,
  String? subtitulo,
  List<Widget> acciones = const [],
}) {
  if (!esEscritorio(context)) {
    return AppBar(title: Text(titulo), actions: acciones);
  }

  final theme = Theme.of(context);
  return AppBar(
    centerTitle: false,
    titleSpacing: 8,
    toolbarHeight: 72,
    shape: const Border(
      bottom: BorderSide(color: AppColors.surfaceMuted, width: 1.2),
    ),
    title: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          titulo,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            height: 1.15,
          ),
        ),
        if (subtitulo != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitulo,
            style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12.5),
          ),
        ],
      ],
    ),
    actions: [...acciones, const SizedBox(width: 20)],
  );
}

/// Centra el contenido y le pone un techo de ancho para que no se estire
/// hasta el infinito en monitores grandes.
class ContenidoCentrado extends StatelessWidget {
  const ContenidoCentrado({
    super.key,
    required this.child,
    this.anchoMaximo = anchoMaximoTablero,
  });

  final Widget child;
  final double anchoMaximo;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: anchoMaximo),
        child: child,
      ),
    );
  }
}

/// Envoltura que expone el estado de hover del puntero a su hijo. En un
/// dispositivo táctil nunca entra un puntero, así que [builder] siempre
/// recibe `false` y el resultado es idéntico al de antes.
class ZonaHover extends StatefulWidget {
  const ZonaHover({
    super.key,
    required this.builder,
    this.cursor = SystemMouseCursors.click,
  });

  final Widget Function(BuildContext context, bool hover) builder;
  final MouseCursor cursor;

  @override
  State<ZonaHover> createState() => _ZonaHoverState();
}

class _ZonaHoverState extends State<ZonaHover> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: widget.builder(context, _hover),
    );
  }
}

/// Tarjeta base de escritorio: superficie con borde fino y sombra baja que,
/// al pasar el mouse por encima, se levanta 3 px, profundiza la sombra y
/// enciende el borde con su color de acento.
///
/// Es el reemplazo en escritorio de [Tarjeta3D] (cuyo gesto es "hundirse al
/// tocar", pensado para el dedo): con mouse, el feedback útil llega ANTES
/// del clic, no durante.
class TarjetaEscritorio extends StatelessWidget {
  const TarjetaEscritorio({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(20),
    this.radio = 22,
    this.acento,
    this.gradiente,
    this.alto,
    this.bordeVisible = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double radio;

  /// Color con el que se enciende el borde y se tiñe la sombra en hover.
  final Color? acento;

  /// Si se pasa, reemplaza el color de superficie (tarjetas "héroe").
  final Gradient? gradiente;

  /// Alto fijo — útil para filas de KPIs, donde todas las tarjetas deben
  /// medir lo mismo sin depender de cuánto texto traiga cada una.
  final double? alto;

  final bool bordeVisible;

  @override
  Widget build(BuildContext context) {
    final acento = this.acento ?? AppColors.primary;
    final interactiva = onTap != null;

    return ZonaHover(
      cursor: interactiva ? SystemMouseCursors.click : MouseCursor.defer,
      builder: (context, hover) {
        final activo = hover && interactiva;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: alto,
          transform: Matrix4.translationValues(0, activo ? -3 : 0, 0),
          decoration: BoxDecoration(
            color: gradiente == null ? AppColors.surface : null,
            gradient: gradiente,
            borderRadius: BorderRadius.circular(radio),
            border: bordeVisible
                ? Border.all(
                    color: activo
                        ? acento.withValues(alpha: 0.45)
                        : AppColors.surfaceMuted,
                    width: 1.2,
                  )
                : null,
            boxShadow: [
              BoxShadow(
                color: (gradiente != null ? acento : Colors.black).withValues(
                  alpha: activo ? 0.18 : 0.07,
                ),
                blurRadius: activo ? 26 : 14,
                offset: Offset(0, activo ? 12 : 6),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              hoverColor: acento.withValues(alpha: 0.03),
              splashColor: acento.withValues(alpha: 0.08),
              child: Padding(padding: padding, child: child),
            ),
          ),
        );
      },
    );
  }
}

/// Contenedor de sección con encabezado propio (ícono + título + subtítulo +
/// acción opcional). Le da a cada bloque del tablero un marco explícito, en
/// vez de dejar títulos sueltos flotando sobre el fondo.
class PanelEscritorio extends StatelessWidget {
  const PanelEscritorio({
    super.key,
    required this.child,
    this.titulo,
    this.subtitulo,
    this.icono,
    this.accion,
    this.padding = const EdgeInsets.all(24),
  });

  final Widget child;
  final String? titulo;
  final String? subtitulo;
  final IconData? icono;
  final Widget? accion;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.surfaceMuted, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (titulo != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (icono != null) ...[
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icono, size: 19, color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(titulo!, style: theme.textTheme.titleMedium),
                      if (subtitulo != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitulo!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                ?accion,
              ],
            ),
            const SizedBox(height: 18),
          ],
          child,
        ],
      ),
    );
  }
}

/// Encabezado de pantalla en escritorio: título grande a la izquierda y las
/// acciones/selectores alineados a la derecha, en la MISMA fila. En celular
/// esas acciones van apiladas debajo del título (no hay ancho para otra
/// cosa) y se comen la mitad del alto útil antes de mostrar un solo dato.
class EncabezadoEscritorio extends StatelessWidget {
  const EncabezadoEscritorio({
    super.key,
    required this.titulo,
    this.anteTitulo,
    this.subtitulo,
    this.acciones = const [],
  });

  final String titulo;

  /// Línea chica arriba del título (ej. "Bienvenido, Briam").
  final String? anteTitulo;
  final String? subtitulo;
  final List<Widget> acciones;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (anteTitulo != null)
                Text(
                  anteTitulo!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.secondary,
                    letterSpacing: 0.3,
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                titulo,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  height: 1.1,
                ),
              ),
              if (subtitulo != null) ...[
                const SizedBox(height: 6),
                Text(subtitulo!, style: theme.textTheme.bodyMedium),
              ],
            ],
          ),
        ),
        if (acciones.isNotEmpty) ...[
          const SizedBox(width: espacioEscritorio),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: acciones,
          ),
        ],
      ],
    ).animate().fadeIn(duration: 300.ms).moveY(begin: -8, end: 0);
  }
}

/// KPI de escritorio: tarjeta ancha y baja (no el cuadrado de celular), con
/// la insignia de color arriba, el número grande y la etiqueta debajo. Alto
/// fijo para que una fila de KPIs quede perfectamente alineada.
class TarjetaKpi extends StatelessWidget {
  const TarjetaKpi({
    super.key,
    required this.icono,
    required this.color,
    required this.titulo,
    required this.valor,
    this.subtitulo,
    this.subtituloColor,
    this.onTap,
    this.delay = 0,
    this.alto = 132,
  });

  final IconData icono;
  final Color color;
  final String titulo;

  /// Texto ya formateado. Si es un número (o `S/ 123.45`), se anima con
  /// [ContadorAnimado] igual que en la versión de celular.
  final String valor;
  final String? subtitulo;
  final Color? subtituloColor;
  final VoidCallback? onTap;
  final int delay;
  final double alto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final esNumero = double.tryParse(valor.replaceAll(RegExp('[^0-9.]'), ''));
    final estiloValor = theme.textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w800,
      color: AppColors.textPrimary,
      height: 1.1,
    );

    return TarjetaEscritorio(
          onTap: onTap,
          acento: color,
          alto: alto,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icono, color: color, size: 20),
                  ),
                  const Spacer(),
                  if (onTap != null)
                    Icon(
                      Icons.arrow_outward_rounded,
                      size: 16,
                      color: AppColors.textSecondary.withValues(alpha: 0.5),
                    ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  esNumero != null
                      ? ContadorAnimado(
                          valor: esNumero,
                          formatear: (v) => valor.startsWith('S/')
                              ? 'S/ ${v.toStringAsFixed(2)}'
                              : v.toStringAsFixed(0),
                          estilo: estiloValor,
                        )
                      : Text(
                          valor,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: estiloValor,
                        ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          titulo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (subtitulo != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: (subtituloColor ?? color).withValues(
                              alpha: 0.12,
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            subtitulo!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: subtituloColor ?? color,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ],
          ),
        )
        .animate(delay: delay.ms)
        .fadeIn(duration: 350.ms)
        .moveY(begin: 14, end: 0, curve: Curves.easeOutCubic);
  }
}

/// Fila de encabezado de una tabla de escritorio: mayúsculas chicas,
/// espaciadas, sobre fondo apagado — el patrón de data-grid que la gente ya
/// reconoce de cualquier panel de administración.
class EncabezadoTabla extends StatelessWidget {
  const EncabezadoTabla({
    super.key,
    required this.columnas,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
  });

  /// (etiqueta, flex). Un flex de 0 significa ancho fijo mínimo (acciones).
  final List<(String, int)> columnas;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (final (etiqueta, flex) in columnas)
            if (flex <= 0)
              Text(etiqueta, style: _estiloEncabezado)
            else
              Expanded(
                flex: flex,
                child: Text(etiqueta, style: _estiloEncabezado),
              ),
        ],
      ),
    );
  }

  static const _estiloEncabezado = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.8,
    color: AppColors.textSecondary,
  );
}

/// Fila de datos de una tabla de escritorio, con resaltado al pasar el mouse
/// y estado "seleccionada" (para layouts maestro-detalle).
class FilaTabla extends StatelessWidget {
  const FilaTabla({
    super.key,
    required this.child,
    this.onTap,
    this.seleccionada = false,
    this.acento,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool seleccionada;
  final Color? acento;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final acento = this.acento ?? AppColors.primary;

    return ZonaHover(
      cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      builder: (context, hover) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: seleccionada
                ? acento.withValues(alpha: 0.09)
                : hover
                ? AppColors.surfaceMuted.withValues(alpha: 0.5)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: seleccionada
                  ? acento.withValues(alpha: 0.35)
                  : Colors.transparent,
              width: 1.2,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(14),
              child: Padding(padding: padding, child: child),
            ),
          ),
        );
      },
    );
  }
}
