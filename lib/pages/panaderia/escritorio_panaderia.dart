/// Kit visual de escritorio para las pantallas de **Panadería**.
///
/// Es el mismo lenguaje que ya usa la tienda de Hamburguesas (contenido
/// centrado con ancho máximo, tarjetas con borde tenue + hover que levanta,
/// paneles titulados, encabezado de página con ícono grande y KPIs): acá vive
/// una copia local porque `lib/widgets/` lo está tocando otro frente en
/// paralelo. Cuando `lib/widgets/escritorio.dart` esté disponible, este
/// archivo se puede borrar y reemplazar los imports — la API está pensada con
/// los mismos nombres a propósito.
///
/// Todo lo de acá **solo** se usa a partir de [anchoEscritorio]; por debajo de
/// ese ancho las pantallas siguen renderizando exactamente el mismo árbol
/// mobile de siempre.
library;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';

/// A partir de acá hay espacio para 2+ columnas y paneles laterales.
const double anchoEscritorio = Breakpoints.escritorio; // 900

/// Ventana cómoda: caben 3 columnas de tarjetas sin apretarse.
const double anchoEscritorioComodo = 1100;

/// Monitor ancho: 4 columnas / tablas con columnas extra.
const double anchoEscritorioAncho = 1400;

bool esEscritorio(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= anchoEscritorio;

bool esEscritorioComodo(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= anchoEscritorioComodo;

bool esEscritorioAncho(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= anchoEscritorioAncho;

/// Ancho de cada ítem para repartir [disponible] en [columnas] con
/// [espacio] de separación — evita repetir la misma cuentita en cada grilla.
double anchoColumna(double disponible, int columnas, [double espacio = 20]) {
  if (columnas <= 1) return disponible;
  return (disponible - espacio * (columnas - 1)) / columnas;
}

/// Cuántas columnas usar para una grilla de tarjetas según el ancho
/// disponible del contenedor (no de la ventana).
int columnasGrilla(double disponible, {int maximo = 3, double minimo = 340}) {
  final cabe = (disponible / minimo).floor();
  return cabe.clamp(1, maximo);
}

/// AppBar de pantalla de gestión: en escritorio gana altura y aire lateral
/// (se ve como una barra de herramientas de app de escritorio); en móvil es
/// exactamente el `AppBar(title: Text(...))` de siempre.
PreferredSizeWidget appBarGestion(
  BuildContext context, {
  required String titulo,
  List<Widget> acciones = const [],
}) {
  final escritorio = esEscritorio(context);
  return AppBar(
    title: Text(titulo),
    toolbarHeight: escritorio ? 72 : null,
    titleSpacing: escritorio ? 28 : null,
    actions: acciones.isEmpty
        ? null
        : [
            ...acciones,
            SizedBox(width: escritorio ? 20 : 4),
          ],
  );
}

/// Centra el contenido y le pone un techo de ancho, para que en un monitor
/// de 27" el texto no se estire de borde a borde.
class ContenidoCentrado extends StatelessWidget {
  const ContenidoCentrado({
    super.key,
    required this.child,
    this.maxAncho = 1240,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final double maxAncho;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxAncho),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Envuelve cualquier cosa y le avisa si el mouse está encima — la base de
/// las micro-interacciones de escritorio (el móvil no tiene puntero, así que
/// `hover` simplemente nunca se prende).
class ZonaHover extends StatefulWidget {
  const ZonaHover({super.key, required this.builder, this.cursor});

  final Widget Function(BuildContext context, bool hover) builder;
  final MouseCursor? cursor;

  @override
  State<ZonaHover> createState() => _ZonaHoverState();
}

class _ZonaHoverState extends State<ZonaHover> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.cursor ?? MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: widget.builder(context, _hover),
    );
  }
}

/// Tarjeta base de escritorio: superficie crema, borde tenue del color de
/// acento, y al pasar el mouse se levanta unos píxeles con sombra más suave
/// y borde más marcado.
class TarjetaEscritorio extends StatelessWidget {
  const TarjetaEscritorio({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(18),
    this.radio = 20,
    this.acento,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double radio;
  final Color? acento;

  @override
  Widget build(BuildContext context) {
    final color = acento ?? AppColors.primary;

    return ZonaHover(
      cursor: onTap != null ? SystemMouseCursors.click : null,
      builder: (context, hover) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, hover ? -3 : 0, 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radio),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: hover ? 0.16 : 0.07),
                blurRadius: hover ? 26 : 14,
                offset: Offset(0, hover ? 10 : 5),
              ),
            ],
          ),
          child: Material(
            color: AppColors.surface,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radio),
              side: BorderSide(
                color: color.withValues(alpha: hover ? 0.38 : 0.14),
                width: 1.3,
              ),
            ),
            child: InkWell(
              onTap: onTap,
              splashColor: color.withValues(alpha: 0.08),
              highlightColor: color.withValues(alpha: 0.04),
              child: Padding(padding: padding, child: child),
            ),
          ),
        );
      },
    );
  }
}

/// Chip circular con degradado de marca + ícono — el mismo que ya usan las
/// tarjetas de la app, extraído para no repetirlo en cada pantalla.
class ChipIcono extends StatelessWidget {
  const ChipIcono({
    super.key,
    required this.icono,
    this.tamano = 44,
    this.tamanoIcono = 20,
    this.color,
    this.apagado = false,
  });

  final IconData icono;
  final double tamano;
  final double tamanoIcono;
  final Color? color;
  final bool apagado;

  @override
  Widget build(BuildContext context) {
    final base = apagado
        ? Theme.of(context).colorScheme.outline
        : (color ?? AppColors.primary);

    return Container(
      width: tamano,
      height: tamano,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(tamano / 2.6),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            base.withValues(alpha: apagado ? 0.18 : 0.20),
            base.withValues(alpha: apagado ? 0.06 : 0.08),
          ],
        ),
        border: Border.all(
          color: base.withValues(alpha: apagado ? 0.30 : 0.35),
          width: 1.4,
        ),
      ),
      // PhosphorIcon (y no Icon) para que las variantes duotone dibujen sus
      // dos capas — con un IconData plano se comporta igual que Icon.
      child: PhosphorIcon(icono, color: base, size: tamanoIcono),
    );
  }
}

/// Encabezado de página de escritorio: ícono grande, título, bajada y
/// acciones a la derecha (los botones primarios de la pantalla).
class EncabezadoEscritorio extends StatelessWidget {
  const EncabezadoEscritorio({
    super.key,
    required this.icono,
    required this.titulo,
    this.descripcion,
    this.acciones = const [],
    this.acento,
  });

  final IconData icono;
  final String titulo;
  final String? descripcion;
  final List<Widget> acciones;
  final Color? acento;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final descripcion = this.descripcion;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ChipIcono(
          icono: icono,
          tamano: 60,
          tamanoIcono: 28,
          color: acento,
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (descripcion != null) ...[
                const SizedBox(height: 4),
                Text(
                  descripcion,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ],
          ),
        ),
        if (acciones.isNotEmpty) ...[
          const SizedBox(width: 24),
          Wrap(spacing: 12, runSpacing: 8, children: acciones),
        ],
      ],
    );
  }
}

/// Bloque de configuración/contenido con título propio — la unidad con la
/// que se arman los layouts de 2 columnas.
class PanelEscritorio extends StatelessWidget {
  const PanelEscritorio({
    super.key,
    required this.titulo,
    required this.hijos,
    this.icono,
    this.descripcion,
    this.separacion = 12,
    this.acento,
  });

  final String titulo;
  final List<Widget> hijos;
  final IconData? icono;
  final String? descripcion;
  final double separacion;
  final Color? acento;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = acento ?? AppColors.primary;
    final descripcion = this.descripcion;
    final icono = this.icono;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withValues(alpha: 0.14), width: 1.3),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (icono != null) ...[
                ChipIcono(
                  icono: icono,
                  tamano: 34,
                  tamanoIcono: 17,
                  color: color,
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  titulo,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (descripcion != null) ...[
            const SizedBox(height: 6),
            Text(descripcion, style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: 16),
          for (var i = 0; i < hijos.length; i++) ...[
            if (i > 0) SizedBox(height: separacion),
            hijos[i],
          ],
        ],
      ),
    );
  }
}

/// Tarjeta de indicador (total adeudado, cantidad de clientes, etc.) para la
/// fila de KPIs que abre las pantallas de escritorio.
class TarjetaKpi extends StatelessWidget {
  const TarjetaKpi({
    super.key,
    required this.icono,
    required this.etiqueta,
    required this.valor,
    this.detalle,
    this.color,
  });

  final IconData icono;
  final String etiqueta;
  final String valor;
  final String? detalle;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = this.color ?? AppColors.primary;
    final detalle = this.detalle;

    return TarjetaEscritorio(
      acento: color,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Row(
        children: [
          ChipIcono(icono: icono, tamano: 44, tamanoIcono: 21, color: color),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  etiqueta.toUpperCase(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 11,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  valor,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (detalle != null)
                  Text(
                    detalle,
                    style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Encabezado de una tabla de escritorio — se usa junto con [FilaTabla].
class EncabezadoTabla extends StatelessWidget {
  const EncabezadoTabla({super.key, required this.celdas});

  /// Cada celda es `(texto, flex)`; usa flex 0 para un ancho fijo mínimo.
  final List<(String, int)> celdas;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted.withValues(alpha: 0.55),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < celdas.length; i++) ...[
            if (i > 0) const SizedBox(width: 16),
            Expanded(
              flex: celdas[i].$2,
              child: Text(
                celdas[i].$1.toUpperCase(),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 11,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Fila de tabla de escritorio con realce al pasar el mouse.
class FilaTabla extends StatelessWidget {
  const FilaTabla({
    super.key,
    required this.celdas,
    this.onTap,
    this.ultima = false,
  });

  /// Cada celda es `(widget, flex)` — misma repartición que [EncabezadoTabla].
  final List<(Widget, int)> celdas;
  final VoidCallback? onTap;
  final bool ultima;

  @override
  Widget build(BuildContext context) {
    return ZonaHover(
      cursor: onTap != null ? SystemMouseCursors.click : null,
      builder: (context, hover) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: hover
                ? AppColors.primary.withValues(alpha: 0.05)
                : Colors.transparent,
            border: ultima
                ? null
                : Border(
                    bottom: BorderSide(
                      color: AppColors.primary.withValues(alpha: 0.10),
                    ),
                  ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              splashColor: AppColors.primary.withValues(alpha: 0.08),
              highlightColor: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                child: Row(
                  children: [
                    for (var i = 0; i < celdas.length; i++) ...[
                      if (i > 0) const SizedBox(width: 16),
                      Expanded(flex: celdas[i].$2, child: celdas[i].$1),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Contenedor con borde que agrupa [EncabezadoTabla] + varias [FilaTabla].
class TablaEscritorio extends StatelessWidget {
  const TablaEscritorio({super.key, required this.encabezado, required this.filas});

  final EncabezadoTabla encabezado;
  final List<Widget> filas;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.14),
          width: 1.3,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(children: [encabezado, ...filas]),
    );
  }
}
