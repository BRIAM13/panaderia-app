/// Kit ÚNICO de piezas compartidas para las ramas de ESCRITORIO de todas las
/// pantallas de gestión (Dashboard, Analítica, Clientes, Trabajadores,
/// Pedidos, Horneados, Panadería…).
///
/// Durante un tiempo hubo cuatro copias casi idénticas de este archivo (una
/// en `lib/widgets/` y una por tienda) porque cada frente avanzaba en
/// paralelo. El resultado fue que `appBarGestion` tenía dos alturas y dos
/// bordes distintos y el encabezado saltaba al navegar entre pantallas. Este
/// archivo es la unificación: **no se vuelve a copiar**, se extiende acá.
///
/// Todo lo de acá se usa SOLO dentro de un `if (esEscritorio(context))`:
/// el árbol de widgets de celular/tablet queda exactamente como estaba.
///
/// Convenciones que respeta este kit:
/// - Superficie: `AppColors.surface` con borde suave y sombra baja; el color
///   fuerte se reserva para acentos (íconos, valores, bordes en hover).
/// - Radio: 22 en tarjetas, 24 en paneles de sección.
/// - Hover: la web SÍ tiene mouse — cada elemento accionable se levanta, se
///   le enciende el borde y cambia el cursor. En celular no hay puntero, así
///   que estos estados nunca se disparan ahí.
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../theme/app_theme.dart';
import '../theme/breakpoints.dart';
import 'contador_animado.dart';

/// Ventana lo bastante ancha como para un layout de 2 columnas o un panel
/// lateral fijo.
bool esEscritorio(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= Breakpoints.escritorio;

/// Franja de TABLET (600–900): ya no es un celular — entran grillas de 2–3
/// columnas, dos controles en la misma fila y dos listas lado a lado — pero
/// todavía no hay ancho para un panel lateral fijo ni para las densidades
/// de escritorio. Hasta que existió este helper, todo lo de menos de 900 px
/// renderizaba el MISMO árbol pensado para 375 px, así que una tablet de
/// 820 px mostraba tarjetas de 780 px de ancho con un número adentro.
bool esTablet(BuildContext context) {
  final ancho = MediaQuery.sizeOf(context).width;
  return ancho >= Breakpoints.tablet && ancho < Breakpoints.escritorio;
}

/// Ancho de la ventana. Atajo para las pantallas que necesitan comparar
/// contra un umbral propio (720 para partir dos gráficos, 760 para abrir el
/// maestro-detalle…) y no contra uno de los puntos de quiebre del kit.
double anchoVentana(BuildContext context) => MediaQuery.sizeOf(context).width;

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

/// Barra superior de una pantalla de gestión abierta como ruta completa
/// (Clientes, Analítica, Trabajadores, Pedidos de Horneados…).
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
    // Cada acción se libera de la restricción de ALTO de la barra. Sin
    // esto, el `Row` con el que `AppBar` arma sus `actions` usa
    // `CrossAxisAlignment.stretch` y le pasa a cada hijo una altura
    // APRETADA de 72 px: un `IconButton` la ignora (se centra solo), pero
    // cualquier widget con fondo propio —un `PremiumButton`, un chip— se
    // estira de borde a borde y aparece como un bloque enorme pegado al
    // filo superior de la barra. Ese era el "el botón se ve enooooorme y
    // choca con la parte de arriba" reportado en producción: no era el
    // padding del botón, era la barra estirándolo.
    //
    // Un `Center` NO alcanza (afloja el mínimo pero deja el máximo en 72, y
    // un `Container` con `alignment` se come todo el alto disponible que le
    // ofrezcan). `UnconstrainedBox` sobre el eje vertical sí: mide al hijo
    // sin límite de alto, se queda con el tamaño de la ranura y lo centra
    // adentro. Como los botones de acción rondan los 40 px, nunca desborda.
    actions: [
      for (final accion in acciones)
        UnconstrainedBox(constrainedAxis: Axis.horizontal, child: accion),
      const SizedBox(width: 20),
    ],
  );
}

/// Centra el contenido y le pone un techo de ancho para que no se estire
/// hasta el infinito en monitores grandes.
class ContenidoCentrado extends StatelessWidget {
  const ContenidoCentrado({
    super.key,
    required this.child,
    this.anchoMaximo = anchoMaximoTablero,
    this.padding,
  });

  final Widget child;

  /// Único nombre para este concepto en toda la app (antes convivían
  /// `ancho`, `anchoMaximo` y `maxAncho` con tres valores por defecto
  /// distintos, según de qué copia del kit venía la pantalla).
  final double anchoMaximo;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: anchoMaximo),
        child: padding == null
            ? child
            : Padding(padding: padding!, child: child),
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

/// Chip cuadrado con degradado de marca + ícono — la insignia que abre
/// encabezados, paneles y tarjetas de acción.
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

/// Contenedor de sección con encabezado propio (ícono + título + subtítulo +
/// acción opcional). Le da a cada bloque del tablero un marco explícito, en
/// vez de dejar títulos sueltos flotando sobre el fondo.
///
/// El contenido se pasa como [child] (un solo widget) o como [hijos] (varios
/// widgets separados por [separacion]); las dos formas existían en las
/// copias viejas del kit y las dos se siguen aceptando acá.
class PanelEscritorio extends StatelessWidget {
  const PanelEscritorio({
    super.key,
    this.child,
    this.hijos,
    this.separacion = 12,
    this.titulo,
    this.subtitulo,
    this.icono,
    this.accion,
    this.acento,
    this.padding = const EdgeInsets.all(24),
  }) : assert(
         child != null || hijos != null,
         'PanelEscritorio necesita child o hijos',
       );

  final Widget? child;

  /// Alternativa a [child]: varios bloques apilados con [separacion] entre
  /// uno y otro (formularios de escritorio, listas de ajustes…).
  final List<Widget>? hijos;
  final double separacion;

  final String? titulo;
  final String? subtitulo;
  final IconData? icono;
  final Widget? accion;

  /// Tiñe la insignia del encabezado (por defecto, el color de marca).
  final Color? acento;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = acento ?? AppColors.primary;
    final hijos = this.hijos;

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
                      color: color.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: PhosphorIcon(icono!, size: 19, color: color),
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
          if (hijos != null)
            for (var i = 0; i < hijos.length; i++) ...[
              if (i > 0) SizedBox(height: separacion),
              hijos[i],
            ]
          else
            child!,
        ],
      ),
    );
  }
}

/// Envoltura estándar de un FORMULARIO. En escritorio topa el ancho, lo
/// centra y lo mete en un panel con borde y sombra — se lee como un
/// panel/modal de captura, no como una pantalla vacía con un campo estirado
/// de 1600px. En celular devuelve el hijo tal cual: el árbol de widgets
/// queda idéntico al de siempre.
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
      anchoMaximo: ancho,
      child: PanelEscritorio(padding: padding, child: child),
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
    this.icono,
    this.acento,
    this.acciones = const [],
  });

  final String titulo;

  /// Línea chica arriba del título (ej. "Bienvenido, Briam").
  final String? anteTitulo;
  final String? subtitulo;

  /// Insignia grande a la izquierda del título. Opcional: las pantallas que
  /// no la pasan renderizan exactamente el mismo árbol de siempre.
  final IconData? icono;
  final Color? acento;
  final List<Widget> acciones;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icono = this.icono;

    return Row(
      crossAxisAlignment: icono == null
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.center,
      children: [
        if (icono != null) ...[
          ChipIcono(icono: icono, tamano: 60, tamanoIcono: 28, color: acento),
          const SizedBox(width: 18),
        ],
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

/// Marco con borde que agrupa un [EncabezadoTabla] + varias [FilaTabla] en
/// una sola superficie (data-grid completo).
class TablaEscritorio extends StatelessWidget {
  const TablaEscritorio({
    super.key,
    required this.encabezado,
    required this.filas,
  });

  final Widget encabezado;
  final List<Widget> filas;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.surfaceMuted, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(children: [encabezado, ...filas]),
    );
  }
}
