import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../theme/app_theme.dart';
import 'escritorio.dart';

/// Selector desplegable con el lenguaje visual del resto de la app, TANTO
/// cerrado como abierto.
///
/// El campo cerrado es el mismo de antes: borde redondeado de 14, ícono en
/// una placa de color (como en [PanelEscritorio]/[TarjetaKpi]) y etiqueta
/// flotante de Material.
///
/// Lo que cambia es el MENÚ. Antes esto era un `DropdownButtonFormField` y
/// el menú lo dibujaba Material: una caja plana, sin relación visual con el
/// campo, con el resaltado gris genérico y sin transición de entrada. Ese
/// menú no se puede personalizar lo suficiente (no expone el hover, ni la
/// animación, ni el contenido de cada ítem más allá de un widget suelto),
/// así que acá se reconstruye a mano:
///
/// - [SelectorDesplegable] extiende `FormField<T>` — el mismo patrón que usa
///   `DropdownButtonFormField` internamente. Así se conserva GRATIS toda la
///   integración con `Form`: `validator`, `Form.of(context).validate()`,
///   `reset()`, `save()`, y el estado de error compartido con los
///   `TextFormField` de al lado.
/// - El menú vive en un `OverlayEntry` anclado al campo con
///   `CompositedTransformTarget` + `CompositedTransformFollower`. Ese par es
///   el patrón robusto para esto en Flutter: el menú SIGUE al campo aunque
///   haya `Transform` de por medio (el bug de "ventanas emergentes atrapadas
///   por transform" que ya se arregló en otras pantallas) y no depende de
///   coordenadas absolutas congeladas.
///
/// La API pública es exactamente la de antes: `valor`, `opciones`,
/// `etiqueta`, `onChanged`, `label`, `icono`, `validator`, `denso`.
class SelectorDesplegable<T> extends FormField<T> {
  SelectorDesplegable({
    super.key,
    required this.valor,
    required this.opciones,
    required this.etiqueta,
    required this.onChanged,
    this.label,
    this.icono,
    super.validator,
    this.denso = false,
  }) : super(
         initialValue: valor,
         builder: (FormFieldState<T> estado) {
           final selector = estado.widget as SelectorDesplegable<T>;
           return _CampoSelector<T>(
             estado: estado,
             opciones: selector.opciones,
             etiqueta: selector.etiqueta,
             label: selector.label,
             icono: selector.icono,
             denso: selector.denso,
           );
         },
       );

  final T? valor;
  final List<T> opciones;

  /// Cómo mostrar cada opción como texto (ej. `(t) => t.nombre`).
  final String Function(T opcion) etiqueta;

  final ValueChanged<T?> onChanged;
  final String? label;
  final IconData? icono;

  /// Reduce el alto interno — para cuando el selector vive en una banda de
  /// controles apretada (encabezado de escritorio) en vez de un formulario.
  final bool denso;

  @override
  FormFieldState<T> createState() => _SelectorDesplegableState<T>();
}

class _SelectorDesplegableState<T> extends FormFieldState<T> {
  SelectorDesplegable<T> get _selector => widget as SelectorDesplegable<T>;

  /// El padre es la fuente de verdad: si vuelve a construir con otro [valor]
  /// (el caso normal — `onChanged` hace `setState`), el `FormField` tiene que
  /// enterarse, si no el mensaje de error se quedaría pegado después de
  /// elegir una opción válida.
  @override
  void didUpdateWidget(covariant SelectorDesplegable<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selector.valor != oldWidget.valor) {
      setValue(_selector.valor);
    }
  }

  /// Un solo camino para el cambio de valor: el menú llama a `didChange`, y
  /// desde acá sale el `onChanged` público. Así el `Form` y el padre quedan
  /// siempre sincronizados, sin importar quién dispare el cambio.
  @override
  void didChange(T? valor) {
    super.didChange(valor);
    _selector.onChanged(valor);
  }
}

// ---------------------------------------------------------------------------
// Medidas compartidas entre el campo y el menú.
// ---------------------------------------------------------------------------

/// Aire entre el borde del campo y el borde del menú.
const double _separacionMenu = 6;

/// Aire mínimo entre el menú y el borde de la ventana.
const double _margenPantalla = 12;

const double _radioMenu = 16;
const double _radioCampo = 14;
const double _paddingLista = 6;
const double _paddingItem = 10;
const double _ladoPlacaItem = 30;

/// Alto de un ítem con escala de texto 1.0.
const double _altoItemBase = 46;

/// A partir de acá se considera que el menú "entra cómodo" hacia abajo; si no
/// llega ni a esto y arriba hay más lugar, se abre hacia arriba.
const double _altoPreferidoMenu = 260;

/// Techo duro: más alto que esto el menú deja de sentirse un menú.
const double _altoMaximoMenu = 340;

const Color _colorError = Color(0xFFC62828);

/// Dónde y de qué tamaño se dibuja el menú. Se calcula UNA vez, al abrir, con
/// la geometría real del campo y del `Overlay`.
@immutable
class _GeometriaMenu {
  const _GeometriaMenu({
    required this.ancho,
    required this.altoMaximo,
    required this.altoItem,
    required this.haciaArriba,
  });

  final double ancho;
  final double altoMaximo;
  final double altoItem;

  /// `true` cuando no había espacio suficiente debajo del campo y el menú se
  /// despliega hacia arriba en vez de cortarse contra el borde inferior.
  final bool haciaArriba;
}

// ---------------------------------------------------------------------------
// Campo cerrado.
// ---------------------------------------------------------------------------

class _CampoSelector<T> extends StatefulWidget {
  const _CampoSelector({
    required this.estado,
    required this.opciones,
    required this.etiqueta,
    required this.label,
    required this.icono,
    required this.denso,
  });

  final FormFieldState<T> estado;
  final List<T> opciones;
  final String Function(T opcion) etiqueta;
  final String? label;
  final IconData? icono;
  final bool denso;

  @override
  State<_CampoSelector<T>> createState() => _CampoSelectorState<T>();
}

class _CampoSelectorState<T> extends State<_CampoSelector<T>>
    with SingleTickerProviderStateMixin {
  /// Ancla el menú al campo. Sobrevive a los rebuilds del `FormField`.
  final LayerLink _enlace = LayerLink();

  /// Sirve para medir SOLO la caja decorada del campo — la línea de error se
  /// dibuja aparte, debajo, justamente para que no ensucie esta medición.
  final GlobalKey _claveCaja = GlobalKey();

  final FocusNode _foco = FocusNode(debugLabel: 'SelectorDesplegable');

  late final AnimationController _animacion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 190),
    reverseDuration: const Duration(milliseconds: 130),
  );

  OverlayEntry? _entrada;
  _GeometriaMenu? _geometria;

  /// Estado lógico: el menú puede seguir montado un instante más mientras
  /// corre la animación de salida.
  bool _abierto = false;

  /// Ítem resaltado con las flechas del teclado. -1 = ninguno.
  ///
  /// Vive acá y no en el menú a propósito: el foco se queda SIEMPRE en el
  /// campo (el overlay no abre un scope de foco propio), así que las teclas
  /// llegan a este widget y el menú es puramente presentacional.
  int _indiceResaltado = -1;

  @override
  void didUpdateWidget(covariant _CampoSelector<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Si la lista o el valor cambian con el menú abierto (ej. llega la
    // respuesta del backend), el overlay tiene que repintarse. Se difiere un
    // frame porque `markNeedsBuild` es un `setState` sobre el `Overlay`, y
    // acá todavía estamos dentro de la fase de build.
    if (_entrada == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _entrada?.markNeedsBuild();
    });
  }

  @override
  void dispose() {
    // Sacar la entrada ANTES de morir: si el widget se destruye con el menú
    // abierto (navegar hacia atrás, cerrar un diálogo), sin esto quedaría un
    // `OverlayEntry` huérfano flotando sobre la pantalla siguiente.
    _quitarOverlay();
    _animacion.dispose();
    _foco.dispose();
    super.dispose();
  }

  // -- Apertura / cierre ----------------------------------------------------

  void _alternar() {
    if (_abierto) {
      _cerrar();
    } else {
      _abrir();
    }
  }

  void _abrir() {
    if (_abierto || widget.opciones.isEmpty) return;

    final geometria = _calcularGeometria();
    if (geometria == null) return;

    setState(() {
      _geometria = geometria;
      _abierto = true;
      _indiceResaltado = widget.opciones.indexWhere(
        (o) => o == widget.estado.value,
      );
    });

    // Si venía cerrándose, la entrada todavía existe: se reusa y la
    // animación simplemente vuelve hacia adelante desde donde estaba.
    if (_entrada == null) {
      _entrada = OverlayEntry(builder: _construirOverlay);
      Overlay.of(context, debugRequiredFor: widget).insert(_entrada!);
    } else {
      _entrada!.markNeedsBuild();
    }
    _animacion.forward();
  }

  void _cerrar() {
    if (!_abierto) return;
    setState(() => _abierto = false);
    _entrada?.markNeedsBuild();
    _animacion.reverse().whenComplete(() {
      // Puede haberse vuelto a abrir mientras corría la salida.
      if (mounted && !_abierto) _quitarOverlay();
    });
  }

  void _quitarOverlay() {
    _entrada?.remove();
    _entrada?.dispose();
    _entrada = null;
  }

  void _elegir(T opcion) {
    _cerrar();
    // Se avisa siempre, incluso si se reeligió la misma opción: es lo que
    // hacía `DropdownButtonFormField`, y hay pantallas (el Dashboard) que
    // usan `onChanged` para recargar datos.
    widget.estado.didChange(opcion);
  }

  // -- Geometría ------------------------------------------------------------

  /// Decide ancho, alto máximo y si el menú abre hacia arriba o hacia abajo.
  ///
  /// El caso que hay que resolver bien es el selector de tienda del Dashboard
  /// en escritorio: vive en la banda de acciones, pegado al borde derecho.
  /// Por eso el ancho puede crecer para acomodar nombres largos, pero nunca
  /// más allá del borde de la ventana.
  _GeometriaMenu? _calcularGeometria() {
    final cajaCampo =
        _claveCaja.currentContext?.findRenderObject() as RenderBox?;
    final overlay = Overlay.maybeOf(context);
    final cajaOverlay = overlay?.context.findRenderObject() as RenderBox?;

    if (cajaCampo == null ||
        !cajaCampo.hasSize ||
        cajaOverlay == null ||
        !cajaOverlay.hasSize) {
      return null;
    }

    final tamCampo = cajaCampo.size;
    final tamOverlay = cajaOverlay.size;
    final origen = cajaCampo.localToGlobal(Offset.zero, ancestor: cajaOverlay);

    // En celular el teclado puede estar tapando la mitad inferior: ese
    // espacio no existe para el menú.
    final teclado = MediaQuery.viewInsetsOf(context).bottom;

    final libreAbajo =
        tamOverlay.height -
        teclado -
        (origen.dy + tamCampo.height) -
        _separacionMenu -
        _margenPantalla;
    final libreArriba = origen.dy - _separacionMenu - _margenPantalla;

    final escalador = MediaQuery.textScalerOf(context);
    final escala = (escalador.scale(14) / 14).clamp(1.0, 1.6);
    final altoItem = _altoItemBase * escala;
    final altoIdeal = widget.opciones.length * altoItem + _paddingLista * 2;

    final haciaArriba =
        libreAbajo < math.min(altoIdeal, _altoPreferidoMenu) &&
        libreArriba > libreAbajo;

    final disponible = haciaArriba ? libreArriba : libreAbajo;
    final altoMaximo = math.max(
      altoItem, // aunque la pantalla sea diminuta, siempre se ve un ítem
      math.min(altoIdeal, math.min(disponible, _altoMaximoMenu)),
    );

    // Ancho: nunca menos que el campo; puede crecer hacia la derecha si las
    // etiquetas son largas, con tope en el borde de la ventana.
    final anchoDisponible = math.max(
      tamCampo.width,
      tamOverlay.width - _margenPantalla - origen.dx,
    );
    final anchoNecesario =
        _anchoTextoMasLargo(escalador) +
        _paddingLista * 2 +
        _paddingItem * 2 +
        (widget.icono == null ? 0 : _ladoPlacaItem + 10) +
        22 + // check del ítem seleccionado + su separación
        4;
    final ancho = anchoNecesario.clamp(tamCampo.width, anchoDisponible);

    return _GeometriaMenu(
      ancho: ancho,
      altoMaximo: altoMaximo,
      altoItem: altoItem,
      haciaArriba: haciaArriba,
    );
  }

  double _anchoTextoMasLargo(TextScaler escalador) {
    const estilo = TextStyle(fontSize: 14, fontWeight: FontWeight.w700);
    var maximo = 0.0;
    // Con listas muy largas (catálogo de productos) medir todo sería tirar
    // trabajo a la basura: con una muestra alcanza para acertar el ancho.
    final cantidad = math.min(widget.opciones.length, 60);
    for (var i = 0; i < cantidad; i++) {
      final pintor = TextPainter(
        text: TextSpan(
          text: widget.etiqueta(widget.opciones[i]),
          style: estilo,
        ),
        textDirection: Directionality.of(context),
        textScaler: escalador,
        maxLines: 1,
      )..layout();
      maximo = math.max(maximo, pintor.width);
      pintor.dispose();
    }
    return maximo;
  }

  // -- Overlay --------------------------------------------------------------

  Widget _construirOverlay(BuildContext context) {
    final geometria = _geometria;
    if (geometria == null) return const SizedBox.shrink();

    return Stack(
      children: [
        // Capa que se come el resto de la pantalla: tocar afuera cierra, y
        // además evita que se siga interactuando con lo de abajo mientras el
        // menú está abierto (mismo contrato que el menú de Material).
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _cerrar,
            child: const SizedBox.expand(),
          ),
        ),
        // `left`/`top` en 0 son solo el punto de partida: el
        // `CompositedTransformFollower` reubica el menú contra el campo real,
        // sea cual sea su posición y aunque haya transforms en el camino.
        Positioned(
          left: 0,
          top: 0,
          width: geometria.ancho,
          child: CompositedTransformFollower(
            link: _enlace,
            showWhenUnlinked: false,
            targetAnchor: geometria.haciaArriba
                ? Alignment.topLeft
                : Alignment.bottomLeft,
            followerAnchor: geometria.haciaArriba
                ? Alignment.bottomLeft
                : Alignment.topLeft,
            offset: Offset(
              0,
              geometria.haciaArriba ? -_separacionMenu : _separacionMenu,
            ),
            child: _MenuDesplegable<T>(
              animacion: _animacion,
              geometria: geometria,
              opciones: widget.opciones,
              etiqueta: widget.etiqueta,
              icono: widget.icono,
              seleccionada: widget.estado.value,
              indiceResaltado: _indiceResaltado,
              alElegir: _elegir,
            ),
          ),
        ),
      ],
    );
  }

  // -- Teclado --------------------------------------------------------------

  /// Todo el teclado se maneja acá, sobre el foco del campo: abrir, cerrar
  /// con Escape, recorrer con las flechas y confirmar con Enter.
  KeyEventResult _alTecla(FocusNode nodo, KeyEvent evento) {
    if (evento is! KeyDownEvent && evento is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final tecla = evento.logicalKey;
    final confirmar =
        tecla == LogicalKeyboardKey.enter ||
        tecla == LogicalKeyboardKey.numpadEnter ||
        tecla == LogicalKeyboardKey.space;

    if (!_abierto) {
      if (confirmar || tecla == LogicalKeyboardKey.arrowDown) {
        _abrir();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (tecla == LogicalKeyboardKey.escape) {
      _cerrar();
      return KeyEventResult.handled;
    }
    if (tecla == LogicalKeyboardKey.arrowDown) {
      _moverResaltado(1);
      return KeyEventResult.handled;
    }
    if (tecla == LogicalKeyboardKey.arrowUp) {
      _moverResaltado(-1);
      return KeyEventResult.handled;
    }
    if (confirmar) {
      if (_indiceResaltado >= 0 && _indiceResaltado < widget.opciones.length) {
        _elegir(widget.opciones[_indiceResaltado]);
      } else {
        _cerrar();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _moverResaltado(int paso) {
    final total = widget.opciones.length;
    if (total == 0) return;
    final destino = _indiceResaltado < 0
        ? (paso > 0 ? 0 : total - 1)
        : (_indiceResaltado + paso).clamp(0, total - 1);
    if (destino == _indiceResaltado) return;
    setState(() => _indiceResaltado = destino);
    _entrada?.markNeedsBuild();
  }

  // -- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final campo = widget.estado;
    final valor = campo.value;
    final hayError = campo.hasError;
    final vacio = valor == null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CompositedTransformTarget(
          key: _claveCaja,
          link: _enlace,
          child: Focus(
            focusNode: _foco,
            onKeyEvent: _alTecla,
            onFocusChange: (_) {
              if (mounted) setState(() {});
            },
            child: ZonaHover(
              builder: (context, hover) {
                final activo = _abierto || _foco.hasFocus;
                final (colorBorde, anchoBorde) = _bordeActual(
                  hover,
                  activo,
                  hayError,
                );
                final borde = OutlineInputBorder(
                  borderRadius: BorderRadius.circular(_radioCampo),
                  borderSide: BorderSide(color: colorBorde, width: anchoBorde),
                );
                final colorEtiqueta = hayError
                    ? _colorError
                    : activo
                    ? AppColors.primary
                    : AppColors.textSecondary;

                return Semantics(
                  button: true,
                  expanded: _abierto,
                  label: widget.label,
                  value: vacio ? null : widget.etiqueta(valor),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      _foco.requestFocus();
                      _alternar();
                    },
                    child: InputDecorator(
                      isEmpty: vacio,
                      isFocused: activo,
                      decoration: InputDecoration(
                        labelText: widget.label,
                        filled: true,
                        fillColor: AppColors.surface,
                        isDense: widget.denso,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: widget.denso ? 10 : 16,
                        ),
                        labelStyle: TextStyle(color: colorEtiqueta),
                        floatingLabelStyle: TextStyle(
                          color: colorEtiqueta,
                          fontWeight: FontWeight.w600,
                        ),
                        prefixIcon: widget.icono == null
                            ? null
                            : Padding(
                                padding: const EdgeInsets.all(10),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.16,
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: PhosphorIcon(
                                    widget.icono!,
                                    size: 16,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                        border: borde,
                        enabledBorder: borde,
                        focusedBorder: borde,
                        disabledBorder: borde,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              vacio ? '' : widget.etiqueta(valor),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          AnimatedRotation(
                            turns: _abierto ? 0.5 : 0,
                            duration: const Duration(milliseconds: 190),
                            curve: Curves.easeOutCubic,
                            child: PhosphorIcon(
                              PhosphorIconsBold.caretDown,
                              size: 15,
                              color: activo
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 2),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        // La línea de error va acá afuera, no dentro del `InputDecoration`,
        // para que la caja medida por `_claveCaja` sea siempre la del campo:
        // así el menú se ancla al mismo lugar haya error o no.
        if (hayError)
          Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                child: Text(
                  campo.errorText!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    color: _colorError,
                  ),
                ),
              )
              .animate()
              .fadeIn(duration: 160.ms)
              .moveY(begin: -3, end: 0, curve: Curves.easeOut),
      ],
    );
  }

  (Color, double) _bordeActual(bool hover, bool activo, bool hayError) {
    if (hayError) return (_colorError, 1.6);
    if (activo) return (AppColors.primary, 1.8);
    if (hover) return (AppColors.primary.withValues(alpha: 0.35), 1.4);
    // `surfaceMuted` es una superficie, no un borde: contra el fondo crema
    // del tablero el contorno del campo cerrado directamente no se veía.
    return (AppColors.borderSoft, 1.4);
  }
}

// ---------------------------------------------------------------------------
// Menú desplegado.
// ---------------------------------------------------------------------------

/// La tarjeta que aparece al abrir: misma familia visual que
/// [TarjetaEscritorio]/[PanelEscritorio] (superficie, borde suave, sombra
/// baja) y filas con el mismo resaltado en hover que [FilaTabla].
class _MenuDesplegable<T> extends StatefulWidget {
  const _MenuDesplegable({
    required this.animacion,
    required this.geometria,
    required this.opciones,
    required this.etiqueta,
    required this.icono,
    required this.seleccionada,
    required this.indiceResaltado,
    required this.alElegir,
  });

  final Animation<double> animacion;
  final _GeometriaMenu geometria;
  final List<T> opciones;
  final String Function(T opcion) etiqueta;
  final IconData? icono;
  final T? seleccionada;

  /// Ítem resaltado con las flechas del teclado (lo maneja el campo, que es
  /// quien conserva el foco). -1 = ninguno.
  final int indiceResaltado;

  final ValueChanged<T> alElegir;

  @override
  State<_MenuDesplegable<T>> createState() => _MenuDesplegableState<T>();
}

class _MenuDesplegableState<T> extends State<_MenuDesplegable<T>> {
  final ScrollController _scroll = ScrollController();

  late final CurvedAnimation _curva = CurvedAnimation(
    parent: widget.animacion,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeIn,
  );

  @override
  void initState() {
    super.initState();
    // Abrir mostrando la opción actual, no siempre el principio de la lista.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _desplazarHasta(widget.indiceResaltado);
    });
  }

  @override
  void didUpdateWidget(covariant _MenuDesplegable<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.indiceResaltado != oldWidget.indiceResaltado) {
      _desplazarHasta(widget.indiceResaltado);
    }
  }

  @override
  void dispose() {
    _curva.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Trae a la vista el ítem [indice] si se salió del área visible.
  void _desplazarHasta(int indice) {
    if (indice < 0) return;
    if (!_scroll.hasClients) return;
    final posicion = _scroll.position;
    final alto = widget.geometria.altoItem;
    final inicio = _paddingLista + indice * alto;
    final fin = inicio + alto;

    double? objetivo;
    if (inicio < posicion.pixels) {
      objetivo = inicio;
    } else if (fin > posicion.pixels + posicion.viewportDimension) {
      objetivo = fin - posicion.viewportDimension;
    }
    if (objetivo == null) return;

    _scroll.jumpTo(
      objetivo.clamp(posicion.minScrollExtent, posicion.maxScrollExtent),
    );
  }

  // -- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final haciaArriba = widget.geometria.haciaArriba;

    return AnimatedBuilder(
      animation: _curva,
      builder: (context, hijo) {
        final t = _curva.value;
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            // Entra deslizándose desde el campo: hacia abajo el menú "baja"
            // 8 px, hacia arriba "sube" 8 px. Corto y sutil, con la misma
            // curva (easeOutCubic) que usan las tarjetas del tablero.
            offset: Offset(0, (haciaArriba ? 8 : -8) * (1 - t)),
            child: Transform.scale(
              scale: 0.97 + 0.03 * t,
              alignment: haciaArriba
                  ? Alignment.bottomCenter
                  : Alignment.topCenter,
              child: hijo,
            ),
          ),
        );
      },
      child: _tarjeta(context),
    );
  }

  Widget _tarjeta(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(_radioMenu),
        border: Border.all(color: AppColors.borderSoft, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: widget.geometria.altoMaximo),
          child: Scrollbar(
            controller: _scroll,
            child: ListView.builder(
              controller: _scroll,
              shrinkWrap: true,
              padding: const EdgeInsets.all(_paddingLista),
              itemExtent: widget.geometria.altoItem,
              itemCount: widget.opciones.length,
              itemBuilder: _item,
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(BuildContext context, int indice) {
    final theme = Theme.of(context);
    final opcion = widget.opciones[indice];
    final elegida = opcion == widget.seleccionada;
    final icono = widget.icono;

    return ZonaHover(
      builder: (context, hover) {
        final resaltada = hover || indice == widget.indiceResaltado;
        final acentuada = elegida || resaltada;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(vertical: 1),
          decoration: BoxDecoration(
            color: elegida
                ? AppColors.primary.withValues(alpha: resaltada ? 0.16 : 0.10)
                : resaltada
                ? AppColors.primary.withValues(alpha: 0.06)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: InkWell(
            onTap: () => widget.alElegir(opcion),
            borderRadius: BorderRadius.circular(12),
            // El resaltado ya lo pinta el AnimatedContainer de arriba; el
            // InkWell solo aporta el toque táctil.
            hoverColor: Colors.transparent,
            splashColor: AppColors.primary.withValues(alpha: 0.10),
            highlightColor: AppColors.primary.withValues(alpha: 0.05),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: _paddingItem),
              child: Row(
                children: [
                  // Si el selector no tiene ícono, tampoco se reserva el
                  // espacio de la placa (mismo criterio que el campo cerrado).
                  if (icono != null) ...[
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 130),
                      curve: Curves.easeOut,
                      width: _ladoPlacaItem,
                      height: _ladoPlacaItem,
                      decoration: BoxDecoration(
                        color: acentuada
                            ? AppColors.primary.withValues(alpha: 0.14)
                            : AppColors.surfaceMuted,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: PhosphorIcon(
                        icono,
                        size: 15,
                        color: acentuada
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      widget.etiqueta(opcion),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 14,
                        fontWeight: elegida ? FontWeight.w700 : FontWeight.w600,
                        color: elegida
                            ? AppColors.primary
                            : AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (elegida) ...[
                    const SizedBox(width: 8),
                    const PhosphorIcon(
                      PhosphorIconsBold.check,
                      size: 14,
                      color: AppColors.primary,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
