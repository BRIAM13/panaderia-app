import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:video_player/video_player.dart';

/// Qué combinación de clips reproduce [MascotaVideo].
enum ModoMascota {
  /// Solo el reposo, en loop continuo — pantallas transitorias (splash) o
  /// donde no interesa un gesto puntual.
  reposo,

  /// El saludo se reproduce una sola vez al aparecer y después se asienta
  /// en el reposo en loop — pensado para pantallas donde el usuario se
  /// queda mirando un rato, pero sin que el saludo se repita para siempre.
  saludarAlInicio,

  /// Solo el saludo, en loop continuo — el personaje saluda una y otra
  /// vez, sin pasar nunca a reposo. Login: el usuario está mirando la
  /// pantalla activamente, así que el gesto constante tiene sentido acá.
  soloSaludo,
}

/// La mascota (panadero 3D animado) recortada de cintura para arriba y
/// compuesta con transparencia REAL sobre lo que haya detrás.
///
/// Un MP4 no puede llevar canal alfa, así que cada clip viene "empaquetado"
/// en un cuadro de 1400x900: la mitad izquierda es el color y la derecha es
/// el alfa en escala de grises (con una banda de separación en el medio).
/// Un fragment shader ([_rutaShader]) vuelve a unir las dos mitades en cada
/// frame y entrega el resultado con alfa premultiplicado, así que el clip
/// deja de traer un rectángulo de fondo propio que tenía que "adivinar" el
/// color exacto de la pantalla que lo muestra.
///
/// Detrás del video se pinta además una silueta desenfocada del personaje
/// ([_rutaSombra]) que le da separación y profundidad contra el crema de la
/// app — el uniforme blanco casi no contrastaba contra el fondo.
class MascotaVideo extends StatefulWidget {
  const MascotaVideo({
    super.key,
    this.modo = ModoMascota.reposo,
    this.width,
    this.height,
    this.mostrarSombra = true,
  });

  final ModoMascota modo;
  final double? width;
  final double? height;

  /// La silueta desenfocada detrás del personaje. Se puede apagar en
  /// pantallas donde el fondo no sea el crema de la app.
  final bool mostrarSombra;

  @override
  State<MascotaVideo> createState() => _MascotaVideoState();
}

class _MascotaVideoState extends State<MascotaVideo>
    with SingleTickerProviderStateMixin {
  VideoPlayerController? _reposo;
  VideoPlayerController? _saludo;
  ui.FragmentProgram? _programa;
  Ticker? _reloj;
  bool _mostrandoSaludo = false;
  bool _listo = false;

  bool get _necesitaReposo => widget.modo != ModoMascota.soloSaludo;
  bool get _necesitaSaludo => widget.modo != ModoMascota.reposo;

  static const _rutaShader = 'shaders/mascota_alfa.frag';

  // Una silueta por clip: el panadero no está encuadrado igual en los dos
  // (en el saludo aparece un poco más chico y más abajo), así que una sola
  // sombra compartida se veía corrida respecto del personaje.
  static const _rutaSombraReposo = 'assets/mascota/sombra_panadero.png';
  static const _rutaSombraSaludo =
      'assets/mascota/sombra_panadero_saludo.png';

  // Flutter Web pinta `video_player` como un <video> del DOM (no como una
  // textura Skia/Impeller), así que `AnimatedSampler` no puede capturarlo
  // para recomponer el alfa — el resultado es un cuadro vacío o basura, no
  // el personaje. Un WebP animado tampoco sirve: CanvasKit lo decodifica
  // pero `Image` solo pinta su primer cuadro en Web (no hay bug que
  // resolver, es una limitación de esa combinación). La versión web anima
  // a mano: los fotogramas del clip como WebP estático uno por archivo, con
  // el mismo matte de alfa del video y un contorno fino ya horneados,
  // ciclados con el reloj de vsync.
  //
  // 24fps y no menos: es exactamente la tasa del mp4 original (240 cuadros
  // en 10s), así que cada WebP corresponde 1:1 con un cuadro del video y
  // no hay remuestreo. A 8fps la duración total del gesto era correcta
  // pero el movimiento se leía a saltos; bajar a 16 habría obligado a
  // descartar 1 de cada 3 cuadros, con un espaciado irregular que se ve
  // peor que un 16 parejo. Los cuadros se consumen todos, sin saltear: un
  // subconjunto salteado acorta el gesto y el personaje se ve acelerado
  // respecto de Android/iOS, donde sí hay una textura capturable por
  // AnimatedSampler.
  //
  // Las carpetas NO traen los 240 cuadros del mp4, sino el tramo que cierra
  // el ciclo sobre sí mismo. El clip original no es un loop: entre su último
  // cuadro y el primero el personaje está desplazado casi 20px (el render
  // tiene un leve vaivén de cámara/cuerpo a lo largo de los 10s), y ese salto
  // de golpe al reiniciar es exactamente lo que delataba que era un video que
  // terminaba y volvía a empezar. Comparando cada cuadro contra todos los
  // demás por diferencia cuadrática media sobre el RGBA premultiplicado se
  // buscó el par (primero, último) cuya transición se pareciera lo más
  // posible a un paso entre dos cuadros consecutivos cualesquiera — que es el
  // nivel de salto que el ojo ya no distingue:
  //
  //   saludo: cuadros 20..198 del mp4 -> 179 archivos (7.46s). El salto de
  //           cierre pasó de 11.7x a 2.8x la diferencia entre consecutivos.
  //           No se pudo bajar más: donde el cuerpo calzaba mejor (cuadro
  //           195) el personaje está en mitad de un parpadeo (190-197) y los
  //           ojos cerrados chocaban contra los abiertos del arranque, y un
  //           crossfade sobre ese tramo disolvía las pupilas — se veía peor
  //           que el corte.
  //   reposo: cuadros 4..228 del mp4 -> 225 archivos (9.38s). El salto quedó
  //           en 1.1x el de dos consecutivos, o sea indistinguible.
  //
  // Los cuadros sobrantes de cada clip no se copiaron a assets/: los archivos
  // están renumerados desde f_000 y las carpetas contienen exactamente el
  // ciclo. El mp4 completo sigue en assets/mascota/ para Android/iOS.
  static const _cantidadFotogramasWebSaludo = 179;
  static const _cantidadFotogramasWebReposo = 225;
  static const _fpsWeb = 24;
  static const _carpetaFotogramasReposo = 'assets/mascota/frames_reposo';
  static const _carpetaFotogramasSaludo = 'assets/mascota/frames_saludo';

  // Lienzo de la variante web, SEPARADO de _anchoClip/_altoClip (que son del
  // cuadro empaquetado del video y las usa la rama de Android/iOS).
  //
  // Los fotogramas web ya vienen recortados al mínimo rectángulo que contiene
  // el personaje en TODOS los cuadros del ciclo (la unión de los 240 bounding
  // boxes, no un cuadro suelto: la mano en movimiento cambia el contorno
  // fotograma a fotograma) más ~6px de aire para que el contorno mocha no
  // roce el borde. Los 680x900 del video traían mucho vacío alrededor —
  // 160px muertos arriba en el saludo, 79 arriba y 39/76 a los lados en el
  // reposo — y con `BoxFit.contain` ese vacío se comía escala: el personaje
  // se dibujaba bastante más chico que el hueco que se le reservaba.
  //
  // Las medidas son distintas por clip a propósito. El panadero no está
  // encuadrado igual en los dos (mismo motivo por el que hay una silueta por
  // clip, ver _rutaSombraReposo/_rutaSombraSaludo): en el saludo el brazo
  // extendido lo hace más ancho y más bajo. Un lienzo común del tamaño del
  // mayor devolvería justo el margen vacío que este cambio saca. En web solo
  // se anima una secuencia por vez (no hay crossfade entre clips), así que
  // elegir el par según el modo no cuesta nada.
  static const _anchoClipWebSaludo = 583.0;
  static const _altoClipWebSaludo = 746.0;
  static const _anchoClipWebReposo = 577.0;
  static const _altoClipWebReposo = 826.0;

  // Origen de cada ventana de recorte dentro del cuadro original de 680x900.
  // Solo se usa para reubicar la silueta de fondo, que está dibujada en las
  // coordenadas del cuadro completo. El saludo arranca en -6 porque la mano
  // llega a tocar x=0 en once cuadros del gesto (el mp4 fuente ya trae el
  // meñique cortado contra el borde del lienzo de color) y esa columna extra
  // le deja lugar al contorno para cerrar ese borde.
  static const _origenXWebSaludo = -6.0;
  static const _origenYWebSaludo = 154.0;
  static const _origenXWebReposo = 33.0;
  static const _origenYWebReposo = 73.0;

  bool get _saludandoWeb => widget.modo != ModoMascota.reposo;

  /// Cada clip cierra su ciclo en un cuadro distinto (ver el comentario de
  /// _cantidadFotogramasWebSaludo), así que el largo del loop es por clip.
  /// En web solo se anima una secuencia por instancia, así que alcanza con
  /// elegirla una vez según el modo.
  int get _cantidadFotogramasWeb => _saludandoWeb
      ? _cantidadFotogramasWebSaludo
      : _cantidadFotogramasWebReposo;

  double get _anchoLienzoWeb =>
      _saludandoWeb ? _anchoClipWebSaludo : _anchoClipWebReposo;

  double get _altoLienzoWeb =>
      _saludandoWeb ? _altoClipWebSaludo : _altoClipWebReposo;

  static String _rutaFotogramaWeb(String carpeta, int indice) =>
      '$carpeta/f_${indice.toString().padLeft(3, '0')}.webp';

  int _fotogramaWeb = 0;

  /// El programa se compila una sola vez por proceso: el splash y el login
  /// montan la mascota uno detrás del otro y no tiene sentido recompilar.
  static Future<ui.FragmentProgram>? _programaCache;

  static Future<ui.FragmentProgram> _cargarPrograma() =>
      _programaCache ??= ui.FragmentProgram.fromAsset(_rutaShader);

  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  Future<void> _inicializar() async {
    // En web no se inicializa video ni shader: se precargan los fotogramas
    // sueltos y se cicla entre ellos con un Ticker (ver comentario de
    // _carpetaFotogramasReposo/_carpetaFotogramasSaludo más arriba).
    if (kIsWeb) {
      await _inicializarWeb();
      return;
    }

    VideoPlayerController? reposo;
    VideoPlayerController? saludo;

    if (_necesitaReposo) {
      reposo = VideoPlayerController.asset(
        'assets/mascota/panadero_reposo.mp4',
      )..setLooping(true);
      await reposo.initialize();
    }
    if (_necesitaSaludo) {
      saludo = VideoPlayerController.asset(
        'assets/mascota/panadero_saludo.mp4',
      );
      if (widget.modo == ModoMascota.soloSaludo) saludo.setLooping(true);
      await saludo.initialize();
    }

    // Si el shader no compilara (driver raro, plataforma sin soporte de
    // FragmentProgram), el widget igual muestra el personaje: sin recomponer
    // el alfa se ve la mitad de color tal cual, con su fondo crema de set.
    // Es peor visualmente pero nunca deja un hueco en blanco en el login.
    ui.FragmentProgram? programa;
    try {
      programa = await _cargarPrograma();
    } catch (_) {
      programa = null;
    }

    if (!mounted) {
      await reposo?.dispose();
      await saludo?.dispose();
      return;
    }

    setState(() {
      _reposo = reposo;
      _saludo = saludo;
      _programa = programa;
      _mostrandoSaludo = widget.modo != ModoMascota.reposo;
      _listo = true;
    });

    if (widget.modo == ModoMascota.saludarAlInicio) {
      saludo!.addListener(() => _alTerminarSaludo(saludo!));
    }

    // Sin esto el personaje se queda congelado en su primer frame.
    //
    // `AnimatedSampler` no captura el video en cada cuadro: guarda la imagen
    // dentro de una capa de composición y solo la vuelve a tomar cuando esa
    // capa se marca sucia. En Android el video vive en una textura de
    // plataforma que el motor refresca por su cuenta, sin tocar el árbol de
    // widgets — así que nada marca la capa como sucia y el shader reusa para
    // siempre la primera captura. Reconstruir en cada vsync entrega un
    // callback nuevo al sampler, que es lo que lo obliga a recapturar.
    if (programa != null) {
      _reloj = createTicker((_) {
        if (mounted) setState(() {});
      })..start();
    }

    await (saludo ?? reposo)!.play();
  }

  /// Precarga los fotogramas de la carpeta correspondiente al modo y arranca
  /// el Timer que los cicla. `soloSaludo`/`saludarAlInicio` animan el saludo;
  /// `reposo` anima el reposo — a diferencia de la variante con video, acá
  /// no hay crossfade entre ambos clips, es uno u otro fijo por simplicidad.
  ///
  /// Solo se espera el primer segundo de animación (`_fpsWeb` fotogramas) y
  /// el resto se sigue descargando de fondo: son ~200 archivos, y esperarlos
  /// todos dejaba la mascota en blanco varios segundos en la primera carga.
  /// El reloj avanza a 24 cuadros por segundo mientras la descarga va muy
  /// por delante, y si algún archivo llegara tarde `gaplessPlayback` mantiene
  /// el cuadro anterior en pantalla en vez de parpadear.
  Future<void> _inicializarWeb() async {
    final saludando = widget.modo != ModoMascota.reposo;
    final carpeta = saludando
        ? _carpetaFotogramasSaludo
        : _carpetaFotogramasReposo;

    // El cache de imágenes de Flutter guarda 100MB por defecto y la secuencia
    // decodificada entera ocupa ~110-140MB, así que con el límite de
    // fábrica el ciclo desalojaba y volvía a decodificar cada cuadro: el
    // reloj avanzaba a 24fps pero solo llegaban a pintarse ~12 imágenes por
    // segundo, con saltos de hasta medio segundo — justo la sensación de
    // tirones. Con la secuencia entera residente, después de la primera
    // vuelta no se decodifica nada más.
    final cache = PaintingBinding.instance.imageCache;
    const necesario = 200 << 20;
    if (cache.maximumSizeBytes < necesario) {
      cache.maximumSizeBytes = necesario;
    }

    Future<void> precargar(int desde, int hasta) => Future.wait([
      for (var i = desde; i < hasta; i++)
        precacheImage(AssetImage(_rutaFotogramaWeb(carpeta, i)), context),
    ]);

    // El resto va en lotes chicos y encadenados, no todos de una: cada
    // `precacheImage` decodifica el WebP en el hilo principal, y lanzar todos
    // los restantes juntos lo dejaba ocupado varios segundos seguidos — el
    // personaje recién aparecía a los ~9s aunque sus fotogramas ya
    // estuvieran descargados. Entre lote y lote el hilo queda libre para
    // pintar. La descarga va muy por delante del consumo (un lote de 8 se
    // decodifica bastante más rápido que el tercio de segundo que tarda la
    // animación en atravesarlo).
    Future<void> precargarResto(int desde) async {
      for (var i = desde; i < _cantidadFotogramasWeb; i += 8) {
        if (!mounted) return;
        final hasta = i + 8;
        await precargar(
          i,
          hasta > _cantidadFotogramasWeb ? _cantidadFotogramasWeb : hasta,
        );
      }
    }

    if (mounted) {
      const inicial = _fpsWeb;
      await precargar(0, inicial);
      if (mounted) {
        unawaited(precargarResto(inicial));
      }
    }

    if (!mounted) return;

    setState(() => _listo = true);

    // El fotograma se deduce del tiempo transcurrido en cada vsync, en vez
    // de avanzar de a uno con un Timer.periodic: 1000/24 = 41.6ms no es
    // múltiplo del vsync, así que un Timer redondeado a 42ms además de
    // atrasarse medio segundo por vuelta dejaba cada cuadro en pantalla un
    // número desparejo de refrescos (2 o 3), que es justamente la sensación
    // de tirones. Con el reloj de vsync la cadencia es la misma que la de
    // cualquier video de 24fps en una pantalla de 60Hz.
    _reloj = createTicker((transcurrido) {
      if (!mounted) return;
      final indice =
          (transcurrido.inMicroseconds * _fpsWeb ~/ Duration.microsecondsPerSecond) %
          _cantidadFotogramasWeb;
      if (indice != _fotogramaWeb) setState(() => _fotogramaWeb = indice);
    })..start();
  }

  /// El listener de `video_player` dispara en cada tick de progreso, no
  /// solo al terminar — `_mostrandoSaludo` evita repetir la transición en
  /// las llamadas siguientes una vez que ya se disparó la primera vez.
  /// Solo aplica al modo `saludarAlInicio` (el saludo no está en loop ahí).
  void _alTerminarSaludo(VideoPlayerController saludo) {
    final valor = saludo.value;
    if (!valor.isInitialized || valor.isPlaying) return;
    if (valor.position < valor.duration) return;
    if (!_mostrandoSaludo) return;

    setState(() => _mostrandoSaludo = false);
    _reposo!.play();
    // Se libera un instante después de que el crossfade ya terminó
    // visualmente, no apenas cambia el flag — si se destruyera antes, el
    // último frame visible durante el fundido desaparecería de golpe.
    Future.delayed(const Duration(milliseconds: 400), () {
      saludo.dispose();
      if (mounted) setState(() => _saludo = null);
    });
  }

  @override
  void dispose() {
    _reloj?.dispose();
    _reposo?.dispose();
    _saludo?.dispose();
    super.dispose();
  }

  // Medidas del cuadro empaquetado que produce el pipeline de generación
  // (ver `shaders/mascota_alfa.frag`): 680 de color + 40 de banda + 680 de
  // alfa. Son fijas y conocidas, no hace falta leerlas del controlador.
  static const _anchoClip = 680.0;
  static const _altoClip = 900.0;
  static const _anchoEmpaquetado = 1400.0;

  /// Un clip: su silueta desenfocada al fondo y encima el video empaquetado
  /// dibujado a 1400x900, recortado a la mitad de color y pasado por el
  /// shader que le devuelve el alfa. Sombra y video van juntos en la misma
  /// capa para que el crossfade entre saludo y reposo los funda a la vez.
  Widget _capa(VideoPlayerController controlador, String rutaSombra) {
    Widget video = VideoPlayer(controlador);

    final programa = _programa;
    if (programa != null) {
      video = AnimatedSampler((imagen, tamano, canvas) {
        final shader = programa.fragmentShader()
          ..setFloat(0, tamano.width)
          ..setFloat(1, tamano.height)
          ..setImageSampler(0, imagen);
        canvas.drawRect(Offset.zero & tamano, Paint()..shader = shader);
      }, child: video);
    }

    // El Stack de arriba da restricciones ajustadas de 680x900; el
    // OverflowBox obliga al video a dibujarse a su ancho empaquetado real y
    // lo alinea a la izquierda, y el ClipRect se queda solo con la mitad de
    // color (la de alfa y la banda quedan fuera del recorte).
    final recortado = ClipRect(
      child: OverflowBox(
        alignment: Alignment.centerLeft,
        minWidth: _anchoEmpaquetado,
        maxWidth: _anchoEmpaquetado,
        minHeight: _altoClip,
        maxHeight: _altoClip,
        child: video,
      ),
    );

    if (!widget.mostrarSombra) return recortado;

    return Stack(
      fit: StackFit.expand,
      children: [
        // La silueta va un poco más grande y desplazada hacia abajo, como si
        // la luz viniera de arriba: separa al personaje del fondo crema sin
        // leerse como una mancha aparte.
        Positioned(
          left: -9,
          top: 4,
          width: _anchoClip * 1.05,
          height: _altoClip * 1.05,
          child: Image.asset(
            rutaSombra,
            fit: BoxFit.fill,
            excludeFromSemantics: true,
          ),
        ),
        recortado,
      ],
    );
  }

  /// Contenido del Stack central para la variante web: el fotograma que toca
  /// según el modo, con la misma silueta de fondo que usa la variante con
  /// video, para que ambas plataformas se vean parejas.
  Widget _contenidoWeb() {
    final saludando = _saludandoWeb;
    final carpeta = saludando
        ? _carpetaFotogramasSaludo
        : _carpetaFotogramasReposo;
    final rutaSombra = saludando ? _rutaSombraSaludo : _rutaSombraReposo;

    final foto = Image.asset(
      _rutaFotogramaWeb(carpeta, _fotogramaWeb),
      fit: BoxFit.fill,
      excludeFromSemantics: true,
      gaplessPlayback: true,
    );

    if (!widget.mostrarSombra) return foto;

    // La silueta está dibujada en las coordenadas del cuadro completo de
    // 680x900, así que se la corre por el origen de la ventana de recorte
    // para que siga cayendo exactamente detrás del personaje. El -9/+4 es el
    // mismo desfase de "luz desde arriba" que usa la rama con video.
    final origenX = saludando ? _origenXWebSaludo : _origenXWebReposo;
    final origenY = saludando ? _origenYWebSaludo : _origenYWebReposo;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: -9 - origenX,
          top: 4 - origenY,
          width: _anchoClip * 1.05,
          height: _altoClip * 1.05,
          child: Image.asset(
            rutaSombra,
            fit: BoxFit.fill,
            excludeFromSemantics: true,
          ),
        ),
        foto,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_listo) return SizedBox(width: widget.width, height: widget.height);

    if (kIsWeb) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: _anchoLienzoWeb,
            height: _altoLienzoWeb,
            child: _contenidoWeb(),
          ),
        ),
      );
    }

    // FittedBox + un tamaño intrínseco fijo (en vez de Stack/StackFit.expand
    // directo sobre VideoPlayer) preserva la proporción real del recorte
    // sin estirarlo ni recortarlo de más, sea cual sea el tamaño que pida
    // quien use el widget.
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: _anchoClip,
          height: _altoClip,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_reposo != null)
                AnimatedOpacity(
                  opacity: _mostrandoSaludo ? 0 : 1,
                  duration: const Duration(milliseconds: 350),
                  child: _capa(_reposo!, _rutaSombraReposo),
                ),
              if (_saludo != null)
                AnimatedOpacity(
                  opacity: _mostrandoSaludo ? 1 : 0,
                  duration: const Duration(milliseconds: 350),
                  child: _capa(_saludo!, _rutaSombraSaludo),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
