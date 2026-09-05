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
  // a mano: los 80 fotogramas del clip completo (10s a 8fps — la misma
  // tasa a la que se extrajeron del video original), WebP estático uno por
  // archivo, con el mismo matte de alfa del video y un contorno fino ya
  // horneados, ciclados con un Timer. 80 y no un subconjunto: reproducir
  // menos fotogramas a 8fps acorta la duración real del gesto y el
  // personaje se ve acelerado — acá la cantidad de fotogramas coincide con
  // la duración real del clip para que la velocidad sea la misma que en
  // Android/iOS, donde sí hay una textura capturable por AnimatedSampler.
  static const _cantidadFotogramasWeb = 80;
  static const _fpsWeb = 8;
  static const _carpetaFotogramasReposo = 'assets/mascota/frames_reposo';
  static const _carpetaFotogramasSaludo = 'assets/mascota/frames_saludo';

  static String _rutaFotogramaWeb(String carpeta, int indice) =>
      '$carpeta/f_${indice.toString().padLeft(3, '0')}.webp';

  int _fotogramaWeb = 0;
  Timer? _temporizadorWeb;

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
    // sueltos y se cicla entre ellos con un Timer (ver comentario de
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

  /// Precarga los 20 fotogramas de la carpeta correspondiente al modo (para
  /// que el primer loop no parpadee esperando cada descarga) y arranca el
  /// Timer que los cicla. `soloSaludo`/`saludarAlInicio` animan el saludo;
  /// `reposo` anima el reposo — a diferencia de la variante con video, acá
  /// no hay crossfade entre ambos clips, es uno u otro fijo por simplicidad.
  Future<void> _inicializarWeb() async {
    final saludando = widget.modo != ModoMascota.reposo;
    final carpeta = saludando
        ? _carpetaFotogramasSaludo
        : _carpetaFotogramasReposo;

    if (mounted) {
      await Future.wait([
        for (var i = 0; i < _cantidadFotogramasWeb; i++)
          precacheImage(
            AssetImage(_rutaFotogramaWeb(carpeta, i)),
            context,
          ),
      ]);
    }

    if (!mounted) return;

    setState(() => _listo = true);

    _temporizadorWeb = Timer.periodic(
      Duration(milliseconds: (1000 / _fpsWeb).round()),
      (_) {
        if (!mounted) return;
        setState(
          () => _fotogramaWeb =
              (_fotogramaWeb + 1) % _cantidadFotogramasWeb,
        );
      },
    );
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
    _temporizadorWeb?.cancel();
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

  /// Contenido del Stack central (680x900) para la variante web: la foto
  /// fija correspondiente al modo, con la misma silueta de fondo que usa
  /// la variante con video, para que ambas plataformas se vean parejas.
  Widget _contenidoWeb() {
    final saludando = widget.modo != ModoMascota.reposo;
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

    return Stack(
      fit: StackFit.expand,
      children: [
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
            width: _anchoClip,
            height: _altoClip,
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
