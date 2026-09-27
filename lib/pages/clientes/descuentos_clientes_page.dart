import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../models/tienda_model.dart';
import '../../services/api_client.dart';
import '../../services/configuraciones_service.dart';
import '../../services/tiendas_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/escritorio.dart';
import '../../widgets/estado_error.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/premium_button.dart';

// Mismas claves de Configuraciones que lee el backend en
// utils/descuentosCliente.js — se leen de la BD en cada pedido, así que un
// cambio hecho acá aplica en la página web de inmediato, sin redeploy.
const _claveDescuentoNuevo = 'DESCUENTO_SEGMENTO_NUEVO';
const _claveDescuentoRegular = 'DESCUENTO_SEGMENTO_REGULAR';
const _claveDescuentoEnRiesgo = 'DESCUENTO_SEGMENTO_EN_RIESGO';
const _claveDescuentoFrecuente = 'DESCUENTO_SEGMENTO_FRECUENTE';
const _claveDescuentoVip = 'DESCUENTO_SEGMENTO_VIP';
const _claveTiendasHabilitadas = 'DESCUENTOS_TIENDAS_HABILITADAS';

/// El interruptor del cobro por adelantado con tarjeta (Culqi) del pedido web
/// de Panadería — misma clave que lee `utils/pagoAdelanto.js` en CADA pedido.
///
/// Vive en esta pantalla y no en una propia porque es la otra mitad de la
/// misma conversación: acá se decide qué se le descuenta al cliente cuando
/// pide por la web, y acá también si tiene que pagarlo antes de que el pedido
/// se confirme. Son las dos condiciones comerciales del pedido web, y el dueño
/// las ajusta en la misma sesión.
const _claveExigePagoAdelantado = 'EXIGE_PAGO_ADELANTADO_PANADERIA';

const _verdeExito = Color(0xFF16A34A);
const _porcentajeMaximo = 100.0;

/// Un segmento del CRM y todo lo que la pantalla necesita para dibujarlo:
/// su clave de Configuraciones, cómo se llama en cristiano y qué significa.
/// La lista es fija y su orden es el del recorrido natural del cliente
/// (llega nuevo, compra, se vuelve frecuente, gasta más, o se aleja).
class _Segmento {
  const _Segmento({
    required this.clave,
    required this.titulo,
    required this.descripcion,
    required this.icono,
  });

  final String clave;
  final String titulo;
  final String descripcion;
  final IconData icono;
}

final _segmentos = <_Segmento>[
  _Segmento(
    clave: _claveDescuentoNuevo,
    titulo: 'Nuevo',
    descripcion:
        'Nunca se le entregó un pedido. Su primer pedido también recibe '
        'descuento — es lo que lo anima a probar.',
    icono: PhosphorIconsRegular.sparkle,
  ),
  _Segmento(
    clave: _claveDescuentoRegular,
    titulo: 'Regular',
    descripcion:
        'Ya compró, pero todavía no llega al umbral de pedidos frecuentes '
        'ni al de gasto VIP.',
    icono: PhosphorIconsRegular.user,
  ),
  _Segmento(
    clave: _claveDescuentoFrecuente,
    titulo: 'Frecuente',
    descripcion:
        'Llegó al umbral de pedidos entregados del CRM. Compra seguido, '
        'aunque cada pedido sea chico.',
    icono: PhosphorIconsRegular.repeat,
  ),
  _Segmento(
    clave: _claveDescuentoVip,
    titulo: 'VIP',
    descripcion:
        'Llegó al umbral de gasto acumulado del CRM. Es quien más plata '
        'deja en el negocio.',
    icono: PhosphorIconsRegular.crown,
  ),
  _Segmento(
    clave: _claveDescuentoEnRiesgo,
    titulo: 'En riesgo',
    descripcion:
        'Ya compró antes, pero hace más días que el umbral de riesgo que no '
        'vuelve. Un descuento más alto acá es una forma de recuperarlo.',
    icono: PhosphorIconsRegular.clockCountdown,
  ),
];

/// Las condiciones comerciales del pedido web público, todas en una pantalla:
///
///   * el descuento por fidelidad — qué porcentaje recibe cada segmento del
///     CRM (el mismo que ya se ve en la ficha de cada cliente y en Analítica)
///     y en qué tiendas está activo;
///   * el cobro por adelantado con tarjeta — si el pedido de pan se confirma
///     recién cuando la pasarela cobra, o si se registra al instante y se paga
///     al recoger (ver [_claveExigePagoAdelantado]).
///
/// Los dos viven juntos porque son la misma conversación ("cómo le cobro al
/// que pide por la web") y el dueño los ajusta en la misma sesión. La
/// EXCEPCIÓN por cliente del cobro por adelantado no está acá: es un atributo
/// de cada cliente y vive en su perfil (ver `ClientePerfilVista`).
///
/// Todo vive en `Configuraciones`, así que esta pantalla no tiene ningún
/// endpoint propio: usa el genérico `GET/PUT /configuraciones/:clave` — el
/// backend vuelve a leer esos valores en CADA pedido, de modo que guardar
/// acá cambia el precio que ve el cliente en la web en el acto, sin volver
/// a publicar nada.
///
/// NO es una pantalla de Panadería aunque hoy Panadería sea la única tienda
/// habilitada: el interruptor de abajo puede habilitar cualquier tienda, así
/// que vive en el menú general (ADMIN/SUPERADMIN, junto a Analítica) y no
/// dentro de una tienda concreta.
///
/// El servidor sigue siendo la última palabra: recalcula el descuento con el
/// historial real del cliente al crear cada pedido, nunca confía en lo que
/// le mande la web.
class DescuentosClientesPage extends StatefulWidget {
  const DescuentosClientesPage({super.key});

  @override
  State<DescuentosClientesPage> createState() => _DescuentosClientesPageState();
}

class _DescuentosClientesPageState extends State<DescuentosClientesPage> {
  final _configuracionesService = ConfiguracionesService();
  final _tiendasService = TiendasService();

  bool _cargando = true;
  bool _guardando = false;
  String? _error;
  String? _mensajeExito;

  /// true solo cuando el error viene de NO haber podido cargar: ahí la
  /// pantalla se reemplaza entera por [EstadoError] (no hay nada que editar
  /// ni que guardar). Un error de guardado, en cambio, deja el formulario en
  /// pie con lo que el dueño escribió y el botón de guardar disponible para
  /// reintentar — perder sus cambios por un timeout sería peor que el error.
  bool _falloCarga = false;

  /// Un controlador por segmento, indexado por su clave de Configuraciones.
  final Map<String, TextEditingController> _porcentajes = {
    for (final segmento in _segmentos) segmento.clave: TextEditingController(),
  };

  List<Tienda> _tiendas = const [];

  /// Slugs con descuento activo. Incluye a propósito los que vinieron
  /// guardados pero ya no están en `_tiendas` (una tienda desactivada, o un
  /// slug escrito a mano): así guardar desde acá nunca los borra en
  /// silencio.
  final Set<String> _slugsHabilitados = {};

  /// El interruptor del cobro por adelantado con tarjeta (ver
  /// [_claveExigePagoAdelantado]).
  bool _exigePagoAdelantado = false;

  /// true cuando [_claveExigePagoAdelantado] todavía NO existe en la base (o
  /// sea, falta correr `2026_09_excepcion_pago_adelanto.sql`).
  ///
  /// Se guarda aparte en vez de dejar que el 404 tumbe la pantalla entera: los
  /// descuentos son un feature viejo y ya funcionando, y no pueden quedar
  /// ineditables porque falte la clave de un feature nuevo. Con esto, la
  /// tarjeta del interruptor se dibuja deshabilitada y explicando qué falta,
  /// mientras el resto de la pantalla sigue en pie.
  bool _faltaClavePagoAdelantado = false;

  @override
  void dispose() {
    for (final controlador in _porcentajes.values) {
      controlador.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
      _falloCarga = false;
      _mensajeExito = null;
    });
    try {
      final claves = [..._segmentos.map((s) => s.clave), _claveTiendasHabilitadas];
      final valores = await Future.wait([
        ...claves.map(_configuracionesService.obtener),
      ]);
      final tiendas = await _tiendasService.listar();

      // El interruptor del cobro por adelantado se lee APARTE y tolerando el
      // 404, a propósito: si se metiera en el `Future.wait` de arriba, una base
      // donde todavía no se corrió `2026_09_excepcion_pago_adelanto.sql`
      // dejaría los descuentos —un feature viejo y funcionando— sin poder
      // editarse. Ver [_faltaClavePagoAdelantado].
      var exigePago = false;
      var faltaClave = false;
      try {
        exigePago = (await _configuracionesService.obtener(_claveExigePagoAdelantado)).trim() == '1';
      } on ApiException catch (e) {
        if (e.statusCode == 404) {
          faltaClave = true;
        } else {
          rethrow;
        }
      }

      setState(() {
        for (var i = 0; i < _segmentos.length; i++) {
          _porcentajes[_segmentos[i].clave]!.text = _textoPorcentaje(valores[i]);
        }
        _tiendas = tiendas;
        _slugsHabilitados
          ..clear()
          ..addAll(
            valores.last
                .split(',')
                .map((slug) => slug.trim())
                .where((slug) => slug.isNotEmpty),
          );
        _exigePagoAdelantado = exigePago;
        _faltaClavePagoAdelantado = faltaClave;
      });
    } on ApiException catch (e) {
      setState(() {
        _falloCarga = true;
        // 404 = alguna de las 6 claves todavía no existe en la base. No es
        // un fallo de red ni un permiso: es que falta correr el seed, y
        // decirlo con esas palabras ahorra un rato de búsqueda a ciegas.
        _error = e.statusCode == 404
            ? 'Faltan las configuraciones de descuento en la base de datos. '
                  'Hay que correr el script de siembra '
                  '(scripts/seed_descuentos_clientes.js) una sola vez, después '
                  'de aplicar la migración de la columna DescuentoPorcentaje.'
            : e.mensaje;
      });
    } catch (_) {
      setState(() {
        _falloCarga = true;
        _error = 'No se pudieron cargar los descuentos actuales.';
      });
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  /// "5" se muestra "5", no "5.0" — pero un "7.5" configurado se conserva.
  String _textoPorcentaje(String valor) {
    final numero = double.tryParse(valor.trim());
    if (numero == null) return valor.trim();
    return numero == numero.roundToDouble()
        ? numero.toStringAsFixed(0)
        : numero.toString();
  }

  /// null = el texto no es un porcentaje válido. Se valida acá y no solo en
  /// el backend porque `PUT /configuraciones/:clave` acepta cualquier texto
  /// de hasta 200 caracteres: un "diez" guardado dejaría a ese segmento
  /// cayendo al valor por defecto sin que nadie se entere.
  double? _porcentajeValido(String texto) {
    final numero = double.tryParse(texto.trim().replaceAll(',', '.'));
    if (numero == null || numero.isNaN) return null;
    if (numero < 0 || numero > _porcentajeMaximo) return null;
    return numero;
  }

  void _alEditar() {
    if (_mensajeExito != null || _error != null) {
      setState(() {
        _mensajeExito = null;
        _error = null;
      });
    }
  }

  void _alternarTienda(String slug, bool activa) {
    setState(() {
      if (activa) {
        _slugsHabilitados.add(slug);
      } else {
        _slugsHabilitados.remove(slug);
      }
      _mensajeExito = null;
      _error = null;
    });
  }

  void _alternarPagoAdelantado(bool activa) {
    setState(() {
      _exigePagoAdelantado = activa;
      _mensajeExito = null;
      _error = null;
    });
  }

  Future<void> _guardar() async {
    // Se validan TODOS los campos antes de mandar el primero: guardar a
    // medias dejaría tres segmentos con el valor nuevo y dos con el viejo,
    // sin forma de saber cuáles.
    final aGuardar = <String, String>{};
    for (final segmento in _segmentos) {
      final valor = _porcentajeValido(_porcentajes[segmento.clave]!.text);
      if (valor == null) {
        setState(() {
          _mensajeExito = null;
          _error =
              'El descuento de "${segmento.titulo}" tiene que ser un número '
              'entre 0 y ${_porcentajeMaximo.toStringAsFixed(0)}.';
        });
        return;
      }
      aGuardar[segmento.clave] = _textoPorcentaje(valor.toString());
    }
    // Lista ordenada y sin espacios: es un valor que también se lee a mano
    // desde la base, así que conviene que se vea siempre igual.
    final slugsOrdenados = _slugsHabilitados.toList()..sort();
    aGuardar[_claveTiendasHabilitadas] = slugsOrdenados.join(',');

    // El interruptor solo se manda si la clave existe: si falta, el PUT
    // respondería 404 y tumbaría el guardado de los descuentos, que sí se
    // pueden guardar.
    if (!_faltaClavePagoAdelantado) {
      aGuardar[_claveExigePagoAdelantado] = _exigePagoAdelantado ? '1' : '0';
    }

    setState(() {
      _guardando = true;
      _error = null;
      _mensajeExito = null;
    });
    try {
      for (final entrada in aGuardar.entries) {
        await _configuracionesService.actualizar(entrada.key, entrada.value);
      }
      setState(() {
        _mensajeExito = _mensajeGuardado(slugsOrdenados);
      });
    } on ApiException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (_) {
      setState(() => _error = 'Ocurrió un error inesperado. Intenta nuevamente.');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  /// Qué se le dice al dueño después de guardar.
  ///
  /// Lo que se prioriza es lo que puede sorprenderlo. Encender el cobro por
  /// adelantado es el cambio de más consecuencia de esta pantalla —a partir de
  /// ese momento NINGÚN pedido web de pan se confirma sin tarjeta— así que ese
  /// aviso va primero y nombra explícitamente la excepción por cliente, que es
  /// el escape que va a necesitar en cuanto una bodega le reclame.
  String _mensajeGuardado(List<String> slugsOrdenados) {
    if (!_faltaClavePagoAdelantado && _exigePagoAdelantado) {
      return 'Guardado. Desde ahora los pedidos de pan de la página web NO se '
          'registran hasta que el cliente los pague con tarjeta. Los clientes '
          'que te pagan por semana o por mes los marcas uno por uno en su '
          'perfil, con "Puede pedir sin pagar primero".';
    }
    if (slugsOrdenados.isEmpty) {
      return 'Guardado. Ojo: no dejaste ninguna tienda con descuento, así que '
          'por ahora la página web no descuenta nada.';
    }
    return 'Guardado. Los próximos pedidos desde la página web ya usan estos '
        'descuentos, y se siguen pagando al recoger.';
  }

  /// La tarjeta del interruptor global del cobro por adelantado. Es una lista
  /// de un solo elemento para poder alimentar igual el layout de celular
  /// (columna) y el de escritorio (paneles), como las otras dos.
  List<Widget> _tarjetasPagoAdelantado() {
    if (_faltaClavePagoAdelantado) {
      return const [
        _AvisoSuave(
          texto:
              'Todavía no se puede usar: falta correr la migración '
              'database_migrations/2026_09_excepcion_pago_adelanto.sql en la '
              'base de datos. Esa migración crea esta configuración y la '
              'columna del permiso por cliente.',
        ),
      ];
    }
    return [
      _TarjetaInterruptorPago(
        valor: _exigePagoAdelantado,
        onCambiar: _alternarPagoAdelantado,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final escritorio = esEscritorio(context);

    return Scaffold(
      appBar: appBarGestion(
        context,
        titulo: 'Descuentos por cliente',
        acciones: escritorio && !_cargando && !_falloCarga
            ? [
                FilledButton.icon(
                  onPressed: _guardando ? null : _guardar,
                  icon: _guardando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const PhosphorIcon(PhosphorIconsBold.check, size: 18),
                  label: const Text('Guardar cambios'),
                ),
              ]
            : const [],
      ),
      body: SafeArea(
        child: _cargando
            ? const Center(child: AppLoadingIndicator())
            : _falloCarga
            ? EstadoError(mensaje: _error!, onReintentar: _cargar)
            : escritorio
            ? _construirEscritorio(context)
            : _construirFormulario(context),
      ),
    );
  }

  // ------------------------------------------------- tarjetas reutilizadas
  // Las mismas piezas alimentan el layout móvil (columna única) y el de
  // escritorio (dos columnas de paneles).

  List<Widget> _tarjetasSegmentos() => [
    for (final segmento in _segmentos)
      _TarjetaPorcentaje(
        icono: segmento.icono,
        titulo: segmento.titulo,
        descripcion: segmento.descripcion,
        controlador: _porcentajes[segmento.clave]!,
        onEditar: _alEditar,
      ),
  ];

  List<Widget> _tarjetasTiendas() {
    if (_tiendas.isEmpty) {
      return const [
        _AvisoSuave(
          texto:
              'No se pudo listar ninguna tienda. Vuelve a entrar a esta '
              'pantalla para intentarlo de nuevo.',
        ),
      ];
    }

    // Los slugs guardados que ya no corresponden a ninguna tienda del
    // catálogo igual se muestran: si no, guardar desde acá los borraría sin
    // que nadie lo haya pedido.
    final slugsConocidos = _tiendas.map((t) => t.slug).toSet();
    final huerfanos = _slugsHabilitados.where((s) => !slugsConocidos.contains(s)).toList()..sort();

    return [
      for (final tienda in _tiendas)
        _TarjetaInterruptorTienda(
          titulo: tienda.nombre,
          descripcion: tienda.disponible
              ? 'Slug: ${tienda.slug}'
              : 'Slug: ${tienda.slug} — esta tienda todavía no está operativa.',
          valor: _slugsHabilitados.contains(tienda.slug),
          onCambiar: (activa) => _alternarTienda(tienda.slug, activa),
        ),
      for (final slug in huerfanos)
        _TarjetaInterruptorTienda(
          titulo: slug,
          descripcion: 'Guardado en la configuración, pero ya no existe como tienda.',
          valor: true,
          onCambiar: (activa) => _alternarTienda(slug, activa),
        ),
    ];
  }

  // ---------------------------------------------------------------- móvil

  Widget _construirFormulario(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.secondaryContainer,
                ),
                child: PhosphorIcon(
                  PhosphorIconsRegular.percent,
                  color: scheme.primary,
                  size: 32,
                ),
              )
              .animate()
              .fadeIn(duration: 300.ms)
              .scale(begin: const Offset(0.85, 0.85), end: const Offset(1, 1)),
          const SizedBox(height: 16),
          Text(
            'Descuento por segmento',
            style: theme.textTheme.titleLarge,
          ).animate().fadeIn(delay: 80.ms, duration: 250.ms),
          const SizedBox(height: 6),
          Text(
            'Cuánto se le descuenta a cada tipo de cliente cuando pide desde '
            'la página web. El segmento lo calcula solo el sistema con el '
            'historial de pedidos entregados — es el mismo que aparece en la '
            'ficha del cliente y en Analítica.',
            style: theme.textTheme.bodyMedium,
          ).animate().fadeIn(delay: 100.ms, duration: 250.ms),
          const SizedBox(height: 20),
          for (final (i, tarjeta) in _tarjetasSegmentos().indexed) ...[
            if (i > 0) const SizedBox(height: 12),
            tarjeta.animate().fadeIn(delay: (130 + i * 40).ms, duration: 250.ms),
          ],
          const SizedBox(height: 28),
          Text(
            'Tiendas con descuento',
            style: theme.textTheme.titleLarge,
          ).animate().fadeIn(delay: 340.ms, duration: 250.ms),
          const SizedBox(height: 6),
          Text(
            'Solo las tiendas encendidas acá aplican el descuento. Si las '
            'apagas todas, la página web cobra el precio completo a todo el '
            'mundo.',
            style: theme.textTheme.bodyMedium,
          ).animate().fadeIn(delay: 360.ms, duration: 250.ms),
          const SizedBox(height: 20),
          for (final (i, tarjeta) in _tarjetasTiendas().indexed) ...[
            if (i > 0) const SizedBox(height: 12),
            tarjeta.animate().fadeIn(delay: (400 + i * 40).ms, duration: 250.ms),
          ],
          const SizedBox(height: 28),
          Text(
            'Pago por adelantado',
            style: theme.textTheme.titleLarge,
          ).animate().fadeIn(delay: 480.ms, duration: 250.ms),
          const SizedBox(height: 6),
          Text(
            'Si lo enciendes, los pedidos de pan hechos desde la página web no '
            'se registran hasta que el cliente los pague con tarjeta. Apagado, '
            'se registran al instante y se pagan al recoger, como siempre.',
            style: theme.textTheme.bodyMedium,
          ).animate().fadeIn(delay: 500.ms, duration: 250.ms),
          const SizedBox(height: 20),
          for (final (i, tarjeta) in _tarjetasPagoAdelantado().indexed) ...[
            if (i > 0) const SizedBox(height: 12),
            tarjeta.animate().fadeIn(delay: (540 + i * 40).ms, duration: 250.ms),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600),
            ),
          ],
          if (_mensajeExito != null) ...[
            const SizedBox(height: 16),
            Text(
              _mensajeExito!,
              style: const TextStyle(color: _verdeExito, fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 24),
          PremiumButton(
            label: 'Guardar cambios',
            icono: PhosphorIconsBold.check,
            cargando: _guardando,
            onPressed: _guardar,
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------- escritorio

  Widget _construirEscritorio(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final izquierda = <Widget>[
      PanelEscritorio(
        icono: PhosphorIconsRegular.percent,
        titulo: 'Descuento por segmento',
        subtitulo:
            'Cuánto se le descuenta a cada tipo de cliente cuando pide desde '
            'la página web. El segmento lo calcula solo el sistema con el '
            'historial de pedidos entregados — el mismo que ves en la ficha '
            'del cliente y en Analítica.',
        hijos: _tarjetasSegmentos(),
      ),
    ];

    final derecha = <Widget>[
      PanelEscritorio(
        icono: PhosphorIconsRegular.storefront,
        titulo: 'Tiendas con descuento',
        acento: AppColors.secondary,
        subtitulo:
            'Solo las tiendas encendidas acá aplican el descuento. Si las '
            'apagas todas, la página web cobra el precio completo a todo el '
            'mundo.',
        hijos: _tarjetasTiendas(),
      ),
      // Panel propio y no una tarjeta más dentro de "Tiendas con descuento":
      // es otra decisión (cuándo se cobra, no cuánto se descuenta) y mezclarla
      // ahí invitaría a leerla como si fuera algo por tienda, cuando es un
      // interruptor único de todo el pedido web de pan.
      PanelEscritorio(
        icono: PhosphorIconsRegular.creditCard,
        titulo: 'Pago por adelantado',
        acento: AppColors.primary,
        subtitulo:
            'Si lo enciendes, los pedidos de pan hechos desde la página web no '
            'se registran hasta que el cliente los pague con tarjeta. Apagado, '
            'se registran al instante y se pagan al recoger, como siempre.',
        hijos: _tarjetasPagoAdelantado(),
      ),
    ];

    Widget columna(List<Widget> paneles, int desfase) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < paneles.length; i++) ...[
          if (i > 0) const SizedBox(height: 22),
          paneles[i]
              .animate(delay: (80 * (desfase + i)).ms)
              .fadeIn(duration: 280.ms)
              .moveY(begin: 12, end: 0),
        ],
      ],
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 48),
      child: ContenidoCentrado(
        anchoMaximo: 1400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const EncabezadoEscritorio(
                  icono: PhosphorIconsDuotone.percent,
                  titulo: 'Descuentos por cliente',
                  subtitulo:
                      'Las dos condiciones del pedido web: cuánto se le '
                      'descuenta a cada cliente según su segmento, y si tiene '
                      'que pagar por adelantado con tarjeta o al recoger. Los '
                      'cambios se aplican al guardar, sin necesidad de volver '
                      'a publicar la web.',
                )
                .animate()
                .fadeIn(duration: 300.ms)
                .moveY(begin: 10, end: 0),
            const SizedBox(height: 30),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: columna(izquierda, 1)),
                const SizedBox(width: 24),
                Expanded(child: columna(derecha, 2)),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 22),
              _AvisoEscritorio(
                icono: PhosphorIconsFill.warningCircle,
                texto: _error!,
                color: scheme.error,
              ),
            ],
            if (_mensajeExito != null) ...[
              const SizedBox(height: 22),
              _AvisoEscritorio(
                icono: PhosphorIconsFill.checkCircle,
                texto: _mensajeExito!,
                color: _verdeExito,
              ),
            ],
            const SizedBox(height: 26),
            // Igual que en "Horarios de pedido": el botón principal vive en
            // la barra de arriba, pero al final del scroll hay otro para no
            // obligar a volver a subir.
            Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: 280,
                child: PremiumButton(
                  label: 'Guardar cambios',
                  icono: PhosphorIconsBold.check,
                  cargando: _guardando,
                  onPressed: _guardar,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Aviso de error/éxito con más presencia que un texto suelto — en
/// escritorio el mensaje queda lejos del control que lo produjo.
class _AvisoEscritorio extends StatelessWidget {
  const _AvisoEscritorio({
    required this.icono,
    required this.texto,
    required this.color,
  });

  final IconData icono;
  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          PhosphorIcon(icono, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms).moveY(begin: 6, end: 0);
  }
}

/// Texto informativo dentro de un panel, para cuando no hay nada que
/// configurar (ej. no se pudo listar ninguna tienda).
class _AvisoSuave extends StatelessWidget {
  const _AvisoSuave({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
      ),
      child: Text(texto, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

/// Una fila "segmento + campo de porcentaje". El campo es de texto (y no un
/// stepper de ±1 como los minutos de tolerancia de Horarios) porque acá se
/// salta de 5 a 20 de una sola vez: con un stepper eso serían 15 toques.
class _TarjetaPorcentaje extends StatelessWidget {
  const _TarjetaPorcentaje({
    required this.icono,
    required this.titulo,
    required this.descripcion,
    required this.controlador,
    required this.onEditar,
  });

  final IconData icono;
  final String titulo;
  final String descripcion;
  final TextEditingController controlador;
  final VoidCallback onEditar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final contenido = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.primary.withValues(alpha: 0.20),
                AppColors.primary.withValues(alpha: 0.08),
              ],
            ),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.35),
              width: 1.4,
            ),
          ),
          child: PhosphorIcon(icono, color: AppColors.primary, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo, style: theme.textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(descripcion, style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 96,
          child: TextField(
            controller: controlador,
            onChanged: (_) => onEditar(),
            textAlign: TextAlign.end,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            // Solo dígitos y un punto/coma decimal: nada de signos ni letras
            // que después habría que rechazar al guardar.
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              LengthLimitingTextInputFormatter(6),
            ],
            style: theme.textTheme.titleMedium?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
            decoration: const InputDecoration(
              isDense: true,
              suffixText: '%',
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ),
      ],
    );

    if (esEscritorio(context)) {
      return Container(
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.10)),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: contenido,
      );
    }

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: contenido,
      ),
    );
  }
}

/// El interruptor del cobro por adelantado con tarjeta.
///
/// A diferencia de los interruptores de tienda, este dice en pantalla QUÉ VA A
/// PASAR en cada posición, con las palabras del negocio y no con las del
/// sistema. Es el ajuste de más consecuencia de toda la pantalla —encendido,
/// ningún pedido de pan de la web se confirma sin tarjeta— y el dueño tiene
/// que poder confirmar de un vistazo que entendió bien antes de guardar, sin
/// tener que probarlo con un pedido real.
class _TarjetaInterruptorPago extends StatelessWidget {
  const _TarjetaInterruptorPago({required this.valor, required this.onCambiar});

  final bool valor;
  final ValueChanged<bool> onCambiar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final acento = valor ? AppColors.primary : theme.colorScheme.outline;

    final contenido = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    acento.withValues(alpha: valor ? 0.20 : 0.18),
                    acento.withValues(alpha: valor ? 0.08 : 0.06),
                  ],
                ),
                border: Border.all(
                  color: acento.withValues(alpha: valor ? 0.35 : 0.30),
                  width: 1.4,
                ),
              ),
              child: PhosphorIcon(
                PhosphorIconsRegular.creditCard,
                color: acento,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    valor ? 'Cobrar antes de registrar' : 'Registrar y cobrar al recoger',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    valor
                        ? 'El pedido queda esperando y solo se confirma cuando '
                              'la pasarela cobra la tarjeta.'
                        : 'El pedido se registra al instante y el cliente paga '
                              'cuando viene a recogerlo.',
                    style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch(value: valor, onChanged: onCambiar),
          ],
        ),
        // La excepción por cliente solo se nombra cuando el cobro está
        // encendido: apagado no existe nada de lo que haya que exceptuar, y
        // decirlo igual sería ruido.
        if (valor) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.14)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PhosphorIcon(
                  PhosphorIconsRegular.userCheck,
                  color: AppColors.primary,
                  size: 16,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'A los clientes que te pagan por semana o por mes los '
                    'exceptúas uno por uno: entra a su perfil desde Clientes y '
                    'enciende "Puede pedir sin pagar primero". Esos siguen '
                    'pidiendo sin pagar antes, aunque este interruptor esté '
                    'encendido.',
                    style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );

    if (esEscritorio(context)) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: acento.withValues(alpha: valor ? 0.06 : 0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: acento.withValues(alpha: valor ? 0.30 : 0.14)),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: contenido,
      );
    }

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: contenido,
      ),
    );
  }
}

/// Interruptor de una tienda: encendido = sus pedidos web reciben el
/// descuento del segmento del cliente.
class _TarjetaInterruptorTienda extends StatelessWidget {
  const _TarjetaInterruptorTienda({
    required this.titulo,
    required this.descripcion,
    required this.valor,
    required this.onCambiar,
  });

  final String titulo;
  final String descripcion;
  final bool valor;
  final ValueChanged<bool> onCambiar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final contenido = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: valor
                  ? [
                      AppColors.primary.withValues(alpha: 0.20),
                      AppColors.primary.withValues(alpha: 0.08),
                    ]
                  : [
                      theme.colorScheme.outline.withValues(alpha: 0.18),
                      theme.colorScheme.outline.withValues(alpha: 0.06),
                    ],
            ),
            border: Border.all(
              color: valor
                  ? AppColors.primary.withValues(alpha: 0.35)
                  : theme.colorScheme.outline.withValues(alpha: 0.30),
              width: 1.4,
            ),
          ),
          child: PhosphorIcon(
            PhosphorIconsRegular.storefront,
            color: valor ? AppColors.primary : theme.colorScheme.outline,
            size: 20,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo, style: theme.textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(descripcion, style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Switch(value: valor, onChanged: onCambiar),
      ],
    );

    if (esEscritorio(context)) {
      final acento = valor ? AppColors.primary : theme.colorScheme.outline;
      return AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: acento.withValues(alpha: valor ? 0.06 : 0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: acento.withValues(alpha: valor ? 0.30 : 0.14)),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: contenido,
      );
    }

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: contenido,
      ),
    );
  }
}
