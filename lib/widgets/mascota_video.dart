import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Qué combinación de clips reproduce [MascotaVideo].
enum ModoMascota {
  /// Solo el reposo, en loop continuo — pantallas transitorias (splash) o
  /// donde no interesa un gesto puntual.
  reposo,

  /// Pensado para que el saludo se reprodujera una vez y después pasara a
  /// reposo. No se usa en ninguna pantalla hoy, y el mecanismo de
  /// fotogramas anima una sola secuencia por instancia (no hay crossfade
  /// entre clips), así que acá se comporta igual que [soloSaludo]: se deja
  /// en el enum para no romper la API pública del widget.
  saludarAlInicio,

  /// Solo el saludo, en loop continuo — el personaje saluda una y otra
  /// vez, sin pasar nunca a reposo. Login: el usuario está mirando la
  /// pantalla activamente, así que el gesto constante tiene sentido acá.
  soloSaludo,
}

/// La mascota (panadero 3D animado) recortada de cintura para arriba y
/// compuesta con transparencia REAL sobre lo que haya detrás.
///
/// El personaje se anima a mano: cada clip es una secuencia de fotogramas
/// WebP estáticos (uno por archivo) con el matte de alfa y un contorno fino
/// de separación ya horneados, ciclados con el reloj de vsync. Es el mismo
/// mecanismo y los mismos archivos en TODAS las plataformas (Android, iOS y
/// Web), justamente para que el personaje se vea idéntico en todos lados.
///
/// Antes Android/iOS reproducían el MP4 original recomponiendo su canal alfa
/// empaquetado con un fragment shader, mientras que Web —donde `video_player`
/// pinta un `<video>` del DOM que el shader no puede capturar— ya usaba estos
/// fotogramas. Eran dos pipelines distintos sobre el mismo material y se
/// notaba: el video salía más amarillento, el personaje más chico (el cuadro
/// del video trae mucho vacío alrededor) y con un salto visible al reiniciar
/// el loop. Unificar sobre los fotogramas elimina esas tres diferencias de
/// raíz, y de paso saca del proyecto el video, el shader y sus dependencias.
///
/// La separación contra el fondo claro de la app la da el contorno mocha
/// semitransparente que los propios fotogramas ya traen horneado. Antes había
/// además una silueta desenfocada pintada por detrás, pero con el contorno ya
/// alcanza para que el uniforme blanco no se funda con el fondo, así que se
/// sacó.
class MascotaVideo extends StatefulWidget {
  const MascotaVideo({
    super.key,
    this.modo = ModoMascota.reposo,
    this.width,
    this.height,
  });

  final ModoMascota modo;
  final double? width;
  final double? height;

  @override
  State<MascotaVideo> createState() => _MascotaVideoState();
}

class _MascotaVideoState extends State<MascotaVideo>
    with SingleTickerProviderStateMixin {
  Ticker? _reloj;
  bool _listo = false;
  int _fotograma = 0;

  // 24fps y no menos: es exactamente la tasa del mp4 original del que se
  // extrajeron los cuadros (240 en 10s), así que cada WebP corresponde 1:1
  // con un cuadro del render y no hay remuestreo. A 8fps la duración total
  // del gesto era correcta pero el movimiento se leía a saltos; bajar a 16
  // habría obligado a descartar 1 de cada 3 cuadros, con un espaciado
  // irregular que se ve peor que un 16 parejo. Los cuadros se consumen
  // todos, sin saltear: un subconjunto salteado acorta el gesto y acelera al
  // personaje.
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
  // ciclo.
  static const _cantidadFotogramasSaludo = 179;
  static const _cantidadFotogramasReposo = 225;
  static const _fps = 24;
  static const _carpetaFotogramasReposo = 'assets/mascota/frames_reposo';
  static const _carpetaFotogramasSaludo = 'assets/mascota/frames_saludo';

  // Lienzo de cada secuencia.
  //
  // Los fotogramas ya vienen recortados al mínimo rectángulo que contiene al
  // personaje en TODOS los cuadros del ciclo (la unión de los bounding boxes,
  // no un cuadro suelto: la mano en movimiento cambia el contorno fotograma a
  // fotograma) más ~6px de aire para que el contorno mocha no roce el borde.
  // Los 680x900 del cuadro original traían mucho vacío alrededor — 160px
  // muertos arriba en el saludo, 79 arriba y 39/76 a los lados en el reposo —
  // y con `BoxFit.contain` ese vacío se comía escala: el personaje se
  // dibujaba bastante más chico que el hueco que se le reservaba.
  //
  // Las medidas son distintas por clip a propósito. El panadero no está
  // encuadrado igual en los dos: en el saludo el brazo
  // extendido lo hace más ancho y más bajo. Un lienzo común del tamaño del
  // mayor devolvería justo el margen vacío que este recorte saca. Solo se
  // anima una secuencia por instancia, así que elegir el par según el modo no
  // cuesta nada.
  static const _anchoClipSaludo = 583.0;
  static const _altoClipSaludo = 746.0;
  static const _anchoClipReposo = 577.0;
  static const _altoClipReposo = 826.0;

  /// `saludarAlInicio` no se usa hoy y se trata igual que `soloSaludo`
  /// (ver el comentario del enum).
  bool get _saludando => widget.modo != ModoMascota.reposo;

  String get _carpeta =>
      _saludando ? _carpetaFotogramasSaludo : _carpetaFotogramasReposo;

  /// Cada clip cierra su ciclo en un cuadro distinto (ver el comentario de
  /// _cantidadFotogramasSaludo), así que el largo del loop es por clip.
  int get _cantidadFotogramas =>
      _saludando ? _cantidadFotogramasSaludo : _cantidadFotogramasReposo;

  double get _anchoLienzo => _saludando ? _anchoClipSaludo : _anchoClipReposo;

  double get _altoLienzo => _saludando ? _altoClipSaludo : _altoClipReposo;

  static String _rutaFotograma(String carpeta, int indice) =>
      '$carpeta/f_${indice.toString().padLeft(3, '0')}.webp';

  @override
  void initState() {
    super.initState();
    _inicializar();
  }

  /// Precarga los fotogramas de la carpeta correspondiente al modo y arranca
  /// el reloj que los cicla.
  ///
  /// Solo se espera el primer segundo de animación (`_fps` fotogramas) y el
  /// resto se sigue cargando de fondo: son ~200 archivos, y esperarlos todos
  /// dejaba la mascota en blanco varios segundos en la primera carga. El
  /// reloj avanza a 24 cuadros por segundo mientras la carga va muy por
  /// delante, y si algún archivo llegara tarde `gaplessPlayback` mantiene el
  /// cuadro anterior en pantalla en vez de parpadear.
  Future<void> _inicializar() async {
    final carpeta = _carpeta;

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
        precacheImage(AssetImage(_rutaFotograma(carpeta, i)), context),
    ]);

    // El resto va en lotes chicos y encadenados, no todos de una: cada
    // `precacheImage` decodifica el WebP en el hilo principal, y lanzar todos
    // los restantes juntos lo dejaba ocupado varios segundos seguidos — el
    // personaje recién aparecía a los ~9s aunque sus fotogramas ya
    // estuvieran cargados. Entre lote y lote el hilo queda libre para
    // pintar. La carga va muy por delante del consumo (un lote de 8 se
    // decodifica bastante más rápido que el tercio de segundo que tarda la
    // animación en atravesarlo).
    Future<void> precargarResto(int desde) async {
      for (var i = desde; i < _cantidadFotogramas; i += 8) {
        if (!mounted) return;
        final hasta = i + 8;
        await precargar(
          i,
          hasta > _cantidadFotogramas ? _cantidadFotogramas : hasta,
        );
      }
    }

    if (mounted) {
      const inicial = _fps;
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
    // cualquier video de 24fps.
    _reloj = createTicker((transcurrido) {
      if (!mounted) return;
      final indice =
          (transcurrido.inMicroseconds *
              _fps ~/
              Duration.microsecondsPerSecond) %
          _cantidadFotogramas;
      if (indice != _fotograma) setState(() => _fotograma = indice);
    })..start();
  }

  @override
  void dispose() {
    _reloj?.dispose();
    super.dispose();
  }

  /// El fotograma que toca según el modo. `gaplessPlayback` deja el cuadro
  /// anterior en pantalla si el próximo todavía no terminó de decodificarse,
  /// en vez de parpadear en blanco.
  Widget _contenido() => Image.asset(
    _rutaFotograma(_carpeta, _fotograma),
    fit: BoxFit.fill,
    excludeFromSemantics: true,
    gaplessPlayback: true,
  );

  @override
  Widget build(BuildContext context) {
    if (!_listo) return SizedBox(width: widget.width, height: widget.height);

    // FittedBox + un tamaño intrínseco fijo preserva la proporción real del
    // recorte sin estirarlo ni recortarlo de más, sea cual sea el tamaño que
    // pida quien use el widget.
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: _anchoLienzo,
          height: _altoLienzo,
          child: _contenido(),
        ),
      ),
    );
  }
}
