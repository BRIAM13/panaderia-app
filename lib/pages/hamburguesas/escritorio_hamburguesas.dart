import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';

// ---------------------------------------------------------------------------
// Kit compartido de escritorio
// ---------------------------------------------------------------------------
//
// La app está diseñada mobile-first, pero también corre como web
// (app.panaderiaronceros.com) donde el personal la usa desde una
// computadora con 1400px+ de ancho. Estirar el mismo árbol de widgets a
// esa ventana da un resultado pobre: líneas de texto de 1800px, un
// formulario de un solo campo ocupando toda la pantalla, listas de una
// sola columna con dos tercios de la ventana vacíos.
//
// Este archivo concentra las piezas que se repiten en ese rediseño, para
// que TODAS las pantallas de escritorio se vean como una sola app y no
// como diez soluciones distintas al mismo problema. Regla de oro: nada de
// acá cambia el árbol de widgets por debajo de [Breakpoints.escritorio] —
// el layout de celular queda intacto.

/// La ventana es lo bastante ancha para un layout de escritorio real
/// (2+ columnas, paneles laterales, tablas).
bool esEscritorio(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= Breakpoints.escritorio;

/// Ventana de laptop en adelante — entra un panel lateral fijo junto al
/// contenido principal, o una tercera columna de tarjetas.
bool esEscritorioComodo(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= Breakpoints.escritorioComodo;

/// Monitor grande / maximizado — acá conviene topar el ancho del contenido
/// en vez de seguir estirándolo.
bool esEscritorioAncho(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= Breakpoints.escritorioAncho;

/// AppBar de las pantallas de gestión (las que usa el personal desde la
/// computadora). En celular es el AppBar centrado de siempre; en
/// escritorio el título se alinea a la izquierda, gana un subtítulo de
/// contexto y las acciones quedan al borde derecho — como el header de
/// cualquier panel de administración.
PreferredSizeWidget appBarGestion(
  BuildContext context, {
  required String titulo,
  String? subtitulo,
  List<Widget> acciones = const [],
  Widget? leading,
  PreferredSizeWidget? bottom,
}) {
  final escritorio = esEscritorio(context);
  final theme = Theme.of(context);

  if (!escritorio) {
    return AppBar(
      title: Text(titulo),
      leading: leading,
      actions: acciones,
      bottom: bottom,
    );
  }

  return AppBar(
    centerTitle: false,
    titleSpacing: 20,
    toolbarHeight: subtitulo == null ? 68 : 76,
    leading: leading,
    title: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: theme.textTheme.titleLarge?.copyWith(fontSize: 22)),
        if (subtitulo != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitulo,
            style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
          ),
        ],
      ],
    ),
    actions: [...acciones, const SizedBox(width: 12)],
    bottom: bottom,
  );
}

/// Topa el ancho del contenido y lo centra. Sin esto, en un monitor de
/// 1920px una lista de una columna se estira hasta ser ilegible.
///
/// [ancho] por defecto es [Breakpoints.escritorioAncho]; los formularios
/// usan [ContenidoCentrado.formulario] que es bastante más angosto.
class ContenidoCentrado extends StatelessWidget {
  const ContenidoCentrado({
    super.key,
    required this.child,
    this.ancho = Breakpoints.escritorioAncho,
    this.padding,
  });

  /// Ancho máximo cómodo para un FORMULARIO en escritorio: se lee como un
  /// panel/modal centrado, no como una hoja de cálculo.
  const ContenidoCentrado.formulario({
    super.key,
    required this.child,
    this.padding,
  }) : ancho = 620;

  /// Ancho intermedio — listas de tarjetas, detalles de una sola columna.
  const ContenidoCentrado.lectura({
    super.key,
    required this.child,
    this.padding,
  }) : ancho = 900;

  final Widget child;
  final double ancho;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    // En celular no se topa nada: el ancho disponible YA es el correcto y
    // meter un ConstrainedBox de más solo agrega una capa inútil.
    if (!esEscritorio(context)) return child;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: ancho),
        child: padding == null
            ? child
            : Padding(padding: padding!, child: child),
      ),
    );
  }
}

/// Realce al pasar el mouse — en escritorio el cursor existe y la falta de
/// respuesta al hover hace que todo se sienta muerto. En táctil el widget
/// se comporta igual que su [child] a secas (no hay evento de hover).
class ZonaHover extends StatefulWidget {
  const ZonaHover({
    super.key,
    required this.builder,
    this.onTap,
    this.cursor = SystemMouseCursors.click,
  });

  /// Recibe si el mouse está encima, para que cada llamador decida cómo se
  /// nota (elevación, borde, color de fondo...).
  final Widget Function(BuildContext context, bool hover) builder;
  final VoidCallback? onTap;
  final MouseCursor cursor;

  @override
  State<ZonaHover> createState() => _ZonaHoverState();
}

class _ZonaHoverState extends State<ZonaHover> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final contenido = widget.builder(context, _hover);
    final envuelto = widget.onTap == null
        ? contenido
        : GestureDetector(onTap: widget.onTap, child: contenido);

    return MouseRegion(
      cursor: widget.onTap == null ? MouseCursor.defer : widget.cursor,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: envuelto,
    );
  }
}

/// Tarjeta base de escritorio: superficie clara, borde sutil, sombra que
/// crece al pasar el mouse. Es la unidad con la que se arman las grillas y
/// los paneles de las pantallas de gestión.
class TarjetaEscritorio extends StatelessWidget {
  const TarjetaEscritorio({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(20),
    this.borderRadius = 20,
    this.colorAcento,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  /// Tiñe el borde y la sombra (ej. rojo para deuda, ámbar para pendiente).
  final Color? colorAcento;

  @override
  Widget build(BuildContext context) {
    final acento = colorAcento ?? AppColors.primary;

    return ZonaHover(
      onTap: onTap,
      builder: (context, hover) => AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: padding,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(
            color: hover
                ? acento.withValues(alpha: 0.40)
                : AppColors.surfaceMuted,
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: acento.withValues(alpha: hover ? 0.14 : 0.05),
              blurRadius: hover ? 22 : 10,
              offset: Offset(0, hover ? 8 : 3),
            ),
          ],
        ),
        transform: Matrix4.translationValues(
          0,
          hover && onTap != null ? -2 : 0,
          0,
        ),
        child: child,
      ),
    );
  }
}

/// Panel de una columna lateral (filtros, resumen, detalle del ítem
/// seleccionado). Igual que [TarjetaEscritorio] pero sin hover y con un
/// título opcional arriba — es contenedor, no elemento clicable.
class PanelEscritorio extends StatelessWidget {
  const PanelEscritorio({
    super.key,
    required this.child,
    this.titulo,
    this.icono,
    this.padding = const EdgeInsets.all(20),
    this.acciones = const [],
  });

  final Widget child;
  final String? titulo;
  final IconData? icono;
  final EdgeInsetsGeometry padding;
  final List<Widget> acciones;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tituloTexto = titulo;

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.surfaceMuted, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (tituloTexto != null) ...[
            Row(
              children: [
                if (icono != null) ...[
                  PhosphorIcon(icono!, size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(tituloTexto, style: theme.textTheme.titleMedium),
                ),
                ...acciones,
              ],
            ),
            const SizedBox(height: 14),
          ],
          child,
        ],
      ),
    );
  }
}

/// Envoltura estándar de un FORMULARIO. En escritorio topa el ancho a
/// [ContenidoCentrado.formulario], lo centra y lo mete en una tarjeta con
/// borde y sombra — se lee como un panel/modal de captura, no como una
/// pantalla vacía con un campo estirado de 1600px. En celular devuelve el
/// hijo tal cual: el árbol de widgets queda idéntico al de siempre.
class FormularioEscritorio extends StatelessWidget {
  const FormularioEscritorio({
    super.key,
    required this.child,
    this.ancho = 620,
    this.padding = const EdgeInsets.all(32),
  });

  final Widget child;
  final double ancho;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    if (!esEscritorio(context)) return child;

    return ContenidoCentrado(
      ancho: ancho,
      child: PanelEscritorio(padding: padding, child: child),
    );
  }
}

/// Encabezado de una pantalla de escritorio: título grande, bajada
/// explicativa y acciones a la derecha en la misma línea (en vez del
/// título centrado + FAB flotante que tiene sentido en celular).
class EncabezadoEscritorio extends StatelessWidget {
  const EncabezadoEscritorio({
    super.key,
    required this.titulo,
    this.subtitulo,
    this.acciones = const [],
    this.icono,
  });

  final String titulo;
  final String? subtitulo;
  final List<Widget> acciones;
  final IconData? icono;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bajada = subtitulo;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (icono != null) ...[
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.18),
                  AppColors.secondary.withValues(alpha: 0.10),
                ],
              ),
            ),
            child: PhosphorIcon(icono!, size: 24, color: AppColors.primary),
          ),
          const SizedBox(width: 14),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: theme.textTheme.titleLarge?.copyWith(fontSize: 24),
              ),
              if (bajada != null) ...[
                const SizedBox(height: 3),
                Text(bajada, style: theme.textTheme.bodyMedium),
              ],
            ],
          ),
        ),
        ...acciones,
      ],
    );
  }
}

/// Tarjeta de indicador (KPI) — número grande, etiqueta y un ícono
/// teñido. Se usa en las filas de métricas del tope de las pantallas de
/// gestión en escritorio.
class TarjetaKpi extends StatelessWidget {
  const TarjetaKpi({
    super.key,
    required this.icono,
    required this.etiqueta,
    required this.valor,
    this.color,
    this.detalle,
    this.onTap,
  });

  final IconData icono;
  final String etiqueta;
  final String valor;
  final Color? color;
  final String? detalle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tinte = color ?? AppColors.primary;
    final extra = detalle;

    return TarjetaEscritorio(
      onTap: onTap,
      colorAcento: tinte,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tinte.withValues(alpha: 0.12),
            ),
            child: PhosphorIcon(icono, size: 21, color: tinte),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  etiqueta,
                  style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  valor,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontSize: 21,
                    color: tinte,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (extra != null)
                  Text(
                    extra,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
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

/// Fila de encabezado de una tabla de escritorio. [flex] define el reparto
/// de ancho de cada columna y debe coincidir con el de las [FilaTabla] que
/// van debajo.
class EncabezadoTabla extends StatelessWidget {
  const EncabezadoTabla({
    super.key,
    required this.columnas,
    required this.flex,
    this.padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
  });

  final List<String> columnas;
  final List<int> flex;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          for (var i = 0; i < columnas.length; i++)
            Expanded(
              flex: i < flex.length ? flex[i] : 1,
              child: Text(
                columnas[i].toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Fila de datos de una tabla de escritorio, con realce al pasar el mouse
/// y separador inferior. [flex] debe coincidir con el del
/// [EncabezadoTabla] correspondiente.
class FilaTabla extends StatelessWidget {
  const FilaTabla({
    super.key,
    required this.celdas,
    required this.flex,
    this.onTap,
    this.colorAcento,
    this.padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
  });

  final List<Widget> celdas;
  final List<int> flex;
  final VoidCallback? onTap;
  final Color? colorAcento;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final acento = colorAcento ?? AppColors.primary;

    return ZonaHover(
      onTap: onTap,
      builder: (context, hover) => AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: padding,
        decoration: BoxDecoration(
          color: hover ? acento.withValues(alpha: 0.05) : Colors.transparent,
          border: const Border(
            bottom: BorderSide(color: AppColors.surfaceMuted, width: 1),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < celdas.length; i++)
              Expanded(flex: i < flex.length ? flex[i] : 1, child: celdas[i]),
          ],
        ),
      ),
    );
  }
}
