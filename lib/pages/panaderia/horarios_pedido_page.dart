import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../services/api_client.dart';
import '../../services/configuraciones_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/estado_error.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/premium_button.dart';
import 'escritorio_panaderia.dart';

const _claveHoraLimite = 'PANADERIA_HORA_LIMITE_PEDIDO';
const _claveHoraMismoDia = 'PANADERIA_HORA_RECOJO_MISMO_DIA';
const _claveHoraDiaSiguiente = 'PANADERIA_HORA_RECOJO_DIA_SIGUIENTE';
const _claveMinutosTolerancia = 'PANADERIA_MINUTOS_TOLERANCIA';
const _claveHoraTopeRecojo = 'PANADERIA_HORA_TOPE_RECOJO';
const _claveHoraApertura = 'PANADERIA_HORA_APERTURA';
const _claveHoraCierre = 'PANADERIA_HORA_CIERRE';
const _claveHoraInicioPedidoTarde = 'PANADERIA_HORA_INICIO_PEDIDO_TARDE';
const _claveDomingoHoraLimite = 'PANADERIA_DOMINGO_HORA_LIMITE_PEDIDO';
const _claveFranjaMananaActiva = 'PANADERIA_FRANJA_MANANA_ACTIVA';
const _claveFranjaTardeActiva = 'PANADERIA_FRANJA_TARDE_ACTIVA';
const _minutosTolerenciaMinimo = 5;
const _minutosToleranciaMaximo = 120;
const _minutosToleranciaPaso = 5;

const _verdeExito = Color(0xFF16A34A);

TimeOfDay _horaDesdeTexto(String texto) {
  final partes = texto.split(':');
  return TimeOfDay(hour: int.parse(partes[0]), minute: int.parse(partes[1]));
}

String _horaATexto(TimeOfDay hora) =>
    '${hora.hour.toString().padLeft(2, '0')}:${hora.minute.toString().padLeft(2, '0')}';

/// Horario de pedido/recojo de Panadería (pan de agua y francés, vendidos
/// por unidad — el pan de hamburguesa por paquete no tiene esta
/// restricción): hasta la hora límite, el cliente puede recoger su pedido
/// el mismo día desde la hora de "mismo día"; después de esa hora, el
/// pedido pasa para el día siguiente desde la hora de "día siguiente". Lo
/// usa tanto la página web pública (formulario de pedido) como el backend,
/// que vuelve a validar el rango con la hora real del servidor — esto solo
/// cambia los valores en Configuraciones, no hace falta ningún redeploy.
///
/// Visible para ADMIN o SUPERADMIN (ver app_drawer.dart, sección
/// Panadería) — mismo permiso que "Ajustar precios".
///
/// Es la pantalla con más controles del sistema, así que en escritorio
/// (>= [anchoEscritorio]) deja de ser una sola columna de ~700px de scroll:
/// los 5 bloques de configuración se reparten en dos columnas de paneles
/// ([PanelEscritorio]) y el guardado queda fijo arriba, en la barra de la
/// página, para no tener que bajar hasta el final cada vez. Por debajo del
/// umbral el árbol es exactamente el de siempre.
class HorariosPedidoPage extends StatefulWidget {
  const HorariosPedidoPage({super.key});

  @override
  State<HorariosPedidoPage> createState() => _HorariosPedidoPageState();
}

class _HorariosPedidoPageState extends State<HorariosPedidoPage> {
  final _configuracionesService = ConfiguracionesService();

  bool _cargando = true;
  bool _guardando = false;
  String? _error;
  String? _mensajeExito;

  TimeOfDay _horaLimite = const TimeOfDay(hour: 10, minute: 0);
  TimeOfDay _horaMismoDia = const TimeOfDay(hour: 15, minute: 30);
  TimeOfDay _horaDiaSiguiente = const TimeOfDay(hour: 4, minute: 0);
  int _minutosTolerancia = 30;
  TimeOfDay _horaTopeRecojo = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay _horaApertura = const TimeOfDay(hour: 4, minute: 0);
  TimeOfDay _horaCierre = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay _horaInicioPedidoTarde = const TimeOfDay(hour: 18, minute: 0);
  TimeOfDay _domingoHoraLimite = const TimeOfDay(hour: 7, minute: 0);
  bool _franjaMananaActiva = true;
  bool _franjaTardeActiva = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final valores = await Future.wait([
        _configuracionesService.obtener(_claveHoraLimite),
        _configuracionesService.obtener(_claveHoraMismoDia),
        _configuracionesService.obtener(_claveHoraDiaSiguiente),
        _configuracionesService.obtener(_claveMinutosTolerancia),
        _configuracionesService.obtener(_claveHoraTopeRecojo),
        _configuracionesService.obtener(_claveHoraApertura),
        _configuracionesService.obtener(_claveHoraCierre),
        _configuracionesService.obtener(_claveHoraInicioPedidoTarde),
        _configuracionesService.obtener(_claveDomingoHoraLimite),
        _configuracionesService.obtener(_claveFranjaMananaActiva),
        _configuracionesService.obtener(_claveFranjaTardeActiva),
      ]);
      setState(() {
        _horaLimite = _horaDesdeTexto(valores[0]);
        _horaMismoDia = _horaDesdeTexto(valores[1]);
        _horaDiaSiguiente = _horaDesdeTexto(valores[2]);
        _minutosTolerancia = int.tryParse(valores[3]) ?? _minutosTolerancia;
        _horaTopeRecojo = _horaDesdeTexto(valores[4]);
        _horaApertura = _horaDesdeTexto(valores[5]);
        _horaCierre = _horaDesdeTexto(valores[6]);
        _horaInicioPedidoTarde = _horaDesdeTexto(valores[7]);
        _domingoHoraLimite = _horaDesdeTexto(valores[8]);
        _franjaMananaActiva = valores[9] == 'true';
        _franjaTardeActiva = valores[10] == 'true';
      });
    } on ApiException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (_) {
      setState(() => _error = 'No se pudo cargar el horario actual.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _elegirHora({
    required String titulo,
    required TimeOfDay valorActual,
    required ValueChanged<TimeOfDay> onElegida,
  }) async {
    final elegida = await showTimePicker(
      context: context,
      initialTime: valorActual,
      helpText: titulo.toUpperCase(),
    );
    if (elegida != null) {
      setState(() {
        onElegida(elegida);
        _mensajeExito = null;
      });
    }
  }

  void _cambiarMinutosTolerancia(int delta) {
    final nuevo = (_minutosTolerancia + delta).clamp(_minutosTolerenciaMinimo, _minutosToleranciaMaximo);
    setState(() {
      _minutosTolerancia = nuevo;
      _mensajeExito = null;
    });
  }

  void _cambiarFranjaManana(bool valor) {
    setState(() {
      _franjaMananaActiva = valor;
      _mensajeExito = null;
    });
  }

  void _cambiarFranjaTarde(bool valor) {
    setState(() {
      _franjaTardeActiva = valor;
      _mensajeExito = null;
    });
  }

  Future<void> _guardar() async {
    setState(() {
      _guardando = true;
      _error = null;
      _mensajeExito = null;
    });
    try {
      await _configuracionesService.actualizar(_claveHoraLimite, _horaATexto(_horaLimite));
      await _configuracionesService.actualizar(_claveHoraMismoDia, _horaATexto(_horaMismoDia));
      await _configuracionesService.actualizar(_claveHoraDiaSiguiente, _horaATexto(_horaDiaSiguiente));
      await _configuracionesService.actualizar(_claveMinutosTolerancia, _minutosTolerancia.toString());
      await _configuracionesService.actualizar(_claveHoraTopeRecojo, _horaATexto(_horaTopeRecojo));
      await _configuracionesService.actualizar(_claveHoraApertura, _horaATexto(_horaApertura));
      await _configuracionesService.actualizar(_claveHoraCierre, _horaATexto(_horaCierre));
      await _configuracionesService.actualizar(_claveHoraInicioPedidoTarde, _horaATexto(_horaInicioPedidoTarde));
      await _configuracionesService.actualizar(_claveDomingoHoraLimite, _horaATexto(_domingoHoraLimite));
      await _configuracionesService.actualizar(_claveFranjaMananaActiva, _franjaMananaActiva.toString());
      await _configuracionesService.actualizar(_claveFranjaTardeActiva, _franjaTardeActiva.toString());
      setState(() {
        _mensajeExito = 'Horario actualizado. Los próximos pedidos desde la página web ya lo usan.';
      });
    } on ApiException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (_) {
      setState(() => _error = 'Ocurrió un error inesperado. Intenta nuevamente.');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final escritorio = esEscritorio(context);

    return Scaffold(
      appBar: appBarGestion(
        context,
        titulo: 'Horarios de pedido',
        acciones: escritorio && !_cargando && _error == null
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
            : _error != null
            ? EstadoError(mensaje: _error!, onReintentar: _cargar)
            : escritorio
            ? _construirEscritorio(context)
            : _construirFormulario(context),
      ),
    );
  }

  // ------------------------------------------------- tarjetas reutilizadas
  // Las mismas piezas alimentan el layout móvil (columna única) y el de
  // escritorio (dos columnas de paneles) — lo único que cambia es dónde se
  // acomodan.

  Widget _tarjetaApertura() => _TarjetaHora(
    icono: PhosphorIconsRegular.sun,
    titulo: 'Apertura',
    descripcion: 'Hora desde la que la tienda atiende — ningún pedido se recoge antes de esta hora.',
    valor: _horaApertura,
    onTap: () => _elegirHora(
      titulo: 'Apertura',
      valorActual: _horaApertura,
      onElegida: (h) => _horaApertura = h,
    ),
  );

  Widget _tarjetaCierre() => _TarjetaHora(
    icono: PhosphorIconsRegular.moonStars,
    titulo: 'Cierre',
    descripcion: 'Hora hasta la que la tienda atiende — ningún pedido se recoge después de esta hora.',
    valor: _horaCierre,
    onTap: () => _elegirHora(
      titulo: 'Cierre',
      valorActual: _horaCierre,
      onElegida: (h) => _horaCierre = h,
    ),
  );

  Widget _tarjetaHoraLimite() => _TarjetaHora(
    icono: PhosphorIconsRegular.timer,
    titulo: 'Hora límite de pedido',
    descripcion:
        'Hasta esta hora, un pedido registrado en la página web se '
        'puede recoger el mismo día. Después, pasa para el día '
        'siguiente.',
    valor: _horaLimite,
    onTap: () => _elegirHora(
      titulo: 'Hora límite de pedido',
      valorActual: _horaLimite,
      onElegida: (h) => _horaLimite = h,
    ),
  );

  Widget _tarjetaMismoDia() => _TarjetaHora(
    icono: PhosphorIconsRegular.sunDim,
    titulo: 'Recojo el mismo día',
    descripcion:
        'Hora desde la que se puede recoger un pedido que llegó '
        'dentro del plazo (la tanda de la tarde).',
    valor: _horaMismoDia,
    onTap: () => _elegirHora(
      titulo: 'Recojo el mismo día',
      valorActual: _horaMismoDia,
      onElegida: (h) => _horaMismoDia = h,
    ),
  );

  Widget _tarjetaDiaSiguiente() => _TarjetaHora(
    icono: PhosphorIconsRegular.sunHorizon,
    titulo: 'Recojo al día siguiente',
    descripcion:
        'Hora desde la que se puede recoger un pedido fuera de '
        'plazo, o cualquier fecha posterior (la tanda normal de la '
        'mañana).',
    valor: _horaDiaSiguiente,
    onTap: () => _elegirHora(
      titulo: 'Recojo al día siguiente',
      valorActual: _horaDiaSiguiente,
      onElegida: (h) => _horaDiaSiguiente = h,
    ),
  );

  Widget _tarjetaTolerancia() => _TarjetaMinutos(
    icono: PhosphorIconsRegular.hourglassMedium,
    titulo: 'Minutos de tolerancia',
    descripcion:
        'Para un pedido de hoy, el cliente no puede elegir un '
        'recojo a menos de estos minutos desde ahora — es el '
        'margen para confirmar stock antes de que llegue la hora.',
    valor: _minutosTolerancia,
    onDecrementar: () => _cambiarMinutosTolerancia(-_minutosToleranciaPaso),
    onIncrementar: () => _cambiarMinutosTolerancia(_minutosToleranciaPaso),
  );

  Widget _tarjetaTopeRecojo() => _TarjetaHora(
    icono: PhosphorIconsRegular.moon,
    titulo: 'Hora tope de recojo',
    descripcion:
        'Última hora del día en la que se puede recoger un pedido '
        'de hoy — después de esta hora, aunque alcance la '
        'tolerancia, el recojo pasa directo para el día siguiente.',
    valor: _horaTopeRecojo,
    onTap: () => _elegirHora(
      titulo: 'Hora tope de recojo',
      valorActual: _horaTopeRecojo,
      onElegida: (h) => _horaTopeRecojo = h,
    ),
  );

  Widget _tarjetaTurnoTarde() => _TarjetaHora(
    icono: PhosphorIconsRegular.moon,
    titulo: 'Inicio turno tarde/noche',
    descripcion: 'Desde esta hora, un pedido nuevo se considera del turno tarde/noche.',
    valor: _horaInicioPedidoTarde,
    onTap: () => _elegirHora(
      titulo: 'Inicio turno tarde/noche',
      valorActual: _horaInicioPedidoTarde,
      onElegida: (h) => _horaInicioPedidoTarde = h,
    ),
  );

  Widget _tarjetaDomingo() => _TarjetaHora(
    icono: PhosphorIconsRegular.calendarStar,
    titulo: 'Corte de pedido (domingo)',
    descripcion: 'Reemplaza a "Hora límite de pedido" solo los domingos.',
    valor: _domingoHoraLimite,
    onTap: () => _elegirHora(
      titulo: 'Corte de pedido (domingo)',
      valorActual: _domingoHoraLimite,
      onElegida: (h) => _domingoHoraLimite = h,
    ),
  );

  Widget _tarjetaFranjaManana() => _TarjetaInterruptor(
    icono: PhosphorIconsRegular.sun,
    titulo: 'Turno mañana',
    descripcion:
        'Activo: se pueden registrar pedidos para recoger el pan '
        'que sale a las 4:00am. Desactívalo si se acabó ese stock '
        '— los pedidos nuevos pasarán directo al turno tarde.',
    valor: _franjaMananaActiva,
    onCambiar: _cambiarFranjaManana,
  );

  Widget _tarjetaFranjaTarde() => _TarjetaInterruptor(
    icono: PhosphorIconsRegular.moon,
    titulo: 'Turno tarde',
    descripcion:
        'Activo: se pueden registrar pedidos para recoger el pan '
        'que sale a las 3:00pm. Desactívalo si se acabó ese stock '
        '— los pedidos nuevos pasarán directo al turno mañana del '
        'día siguiente.',
    valor: _franjaTardeActiva,
    onCambiar: _cambiarFranjaTarde,
  );

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
                child: PhosphorIcon(PhosphorIconsRegular.clock, color: scheme.primary, size: 32),
              )
              .animate()
              .fadeIn(duration: 300.ms)
              .scale(begin: const Offset(0.85, 0.85), end: const Offset(1, 1)),
          const SizedBox(height: 16),
          Text(
            'Horario de atención',
            style: theme.textTheme.titleLarge,
          ).animate().fadeIn(delay: 80.ms, duration: 250.ms),
          const SizedBox(height: 6),
          Text(
            'Ningún pedido, de ningún día, se puede recoger fuera de este '
            'rango — se suma a las demás restricciones de abajo, no las '
            'reemplaza.',
            style: theme.textTheme.bodyMedium,
          ).animate().fadeIn(delay: 100.ms, duration: 250.ms),
          const SizedBox(height: 20),
          _tarjetaApertura().animate().fadeIn(delay: 130.ms, duration: 250.ms),
          const SizedBox(height: 12),
          _tarjetaCierre().animate().fadeIn(delay: 160.ms, duration: 250.ms),
          const SizedBox(height: 28),
          Text(
            'Recojo de Pan de Agua y Francés',
            style: theme.textTheme.titleLarge,
          ).animate().fadeIn(delay: 190.ms, duration: 250.ms),
          const SizedBox(height: 6),
          Text(
            'Solo aplica a los panes que se venden por unidad. El pan de '
            'hamburguesa (por paquete) no usa este horario.',
            style: theme.textTheme.bodyMedium,
          ).animate().fadeIn(delay: 220.ms, duration: 250.ms),
          const SizedBox(height: 20),
          _tarjetaHoraLimite().animate().fadeIn(delay: 260.ms, duration: 250.ms),
          const SizedBox(height: 12),
          _tarjetaMismoDia().animate().fadeIn(delay: 300.ms, duration: 250.ms),
          const SizedBox(height: 12),
          _tarjetaDiaSiguiente().animate().fadeIn(delay: 340.ms, duration: 250.ms),
          const SizedBox(height: 12),
          _tarjetaTolerancia().animate().fadeIn(delay: 380.ms, duration: 250.ms),
          const SizedBox(height: 12),
          _tarjetaTopeRecojo().animate().fadeIn(delay: 420.ms, duration: 250.ms),
          const SizedBox(height: 28),
          Text(
            'Turnos de pedido',
            style: theme.textTheme.titleLarge,
          ).animate().fadeIn(delay: 450.ms, duration: 250.ms),
          const SizedBox(height: 6),
          Text(
            'Un pedido hecho antes de la hora límite de arriba se recoge '
            'hoy mismo; después de esta hora de acá, ya se considera del '
            'turno tarde/noche (informativo, no bloquea nada por sí solo).',
            style: theme.textTheme.bodyMedium,
          ).animate().fadeIn(delay: 470.ms, duration: 250.ms),
          const SizedBox(height: 20),
          _tarjetaTurnoTarde().animate().fadeIn(delay: 500.ms, duration: 250.ms),
          const SizedBox(height: 28),
          Text(
            'Domingo',
            style: theme.textTheme.titleLarge,
          ).animate().fadeIn(delay: 530.ms, duration: 250.ms),
          const SizedBox(height: 6),
          Text(
            'Los domingos usan esta hora en vez de la "hora límite de '
            'pedido" de arriba — el resto del horario se comparte con el '
            'resto de la semana.',
            style: theme.textTheme.bodyMedium,
          ).animate().fadeIn(delay: 550.ms, duration: 250.ms),
          const SizedBox(height: 20),
          _tarjetaDomingo().animate().fadeIn(delay: 580.ms, duration: 250.ms),
          const SizedBox(height: 28),
          Text(
            'Control de stock en vivo',
            style: theme.textTheme.titleLarge,
          ).animate().fadeIn(delay: 610.ms, duration: 250.ms),
          const SizedBox(height: 6),
          Text(
            'Si se acaba el stock de una hornada, apaga su interruptor: '
            'los pedidos nuevos saltan directo a la otra franja. Vuelve a '
            'activarlo tú mismo cuando llegue la siguiente hornada — no se '
            'reactiva solo.',
            style: theme.textTheme.bodyMedium,
          ).animate().fadeIn(delay: 630.ms, duration: 250.ms),
          const SizedBox(height: 20),
          _tarjetaFranjaManana().animate().fadeIn(delay: 660.ms, duration: 250.ms),
          const SizedBox(height: 12),
          _tarjetaFranjaTarde().animate().fadeIn(delay: 690.ms, duration: 250.ms),
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // Columna izquierda: lo que define CUÁNDO abre la tienda y cuándo se
    // puede recoger. Columna derecha: turnos, la excepción del domingo y el
    // control de stock en vivo (lo que se toca durante el día).
    final izquierda = <Widget>[
      PanelEscritorio(
        icono: PhosphorIconsRegular.storefront,
        titulo: 'Horario de atención',
        descripcion:
            'Ningún pedido, de ningún día, se puede recoger fuera de este '
            'rango — se suma a las demás restricciones, no las reemplaza.',
        hijos: [_tarjetaApertura(), _tarjetaCierre()],
      ),
      PanelEscritorio(
        icono: PhosphorIconsRegular.bread,
        titulo: 'Recojo de Pan de Agua y Francés',
        descripcion:
            'Solo aplica a los panes que se venden por unidad. El pan de '
            'hamburguesa (por paquete) no usa este horario.',
        hijos: [
          _tarjetaHoraLimite(),
          _tarjetaMismoDia(),
          _tarjetaDiaSiguiente(),
          _tarjetaTolerancia(),
          _tarjetaTopeRecojo(),
        ],
      ),
    ];

    final derecha = <Widget>[
      PanelEscritorio(
        icono: PhosphorIconsRegular.clockAfternoon,
        titulo: 'Turnos de pedido',
        descripcion:
            'Un pedido hecho antes de la hora límite se recoge hoy mismo; '
            'después de esta hora ya se considera del turno tarde/noche '
            '(informativo, no bloquea nada por sí solo).',
        hijos: [_tarjetaTurnoTarde()],
      ),
      PanelEscritorio(
        icono: PhosphorIconsRegular.calendarStar,
        titulo: 'Domingo',
        descripcion:
            'Los domingos usan esta hora en vez de la "hora límite de '
            'pedido" — el resto del horario se comparte con la semana.',
        hijos: [_tarjetaDomingo()],
      ),
      PanelEscritorio(
        icono: PhosphorIconsRegular.lightning,
        titulo: 'Control de stock en vivo',
        acento: AppColors.secondary,
        descripcion:
            'Si se acaba el stock de una hornada, apaga su interruptor: los '
            'pedidos nuevos saltan directo a la otra franja. Vuelve a '
            'activarlo tú mismo cuando llegue la siguiente hornada — no se '
            'reactiva solo.',
        hijos: [_tarjetaFranjaManana(), _tarjetaFranjaTarde()],
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
        maxAncho: 1400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const EncabezadoEscritorio(
                  icono: PhosphorIconsDuotone.clock,
                  titulo: 'Horarios de pedido',
                  descripcion:
                      'Todo lo que decide cuándo se puede pedir y recoger pan '
                      'desde la página web. Los cambios se aplican al guardar, '
                      'sin necesidad de volver a publicar la web.',
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
            // El botón de la barra superior es el principal, pero al final
            // del scroll también hay uno: si el dueño repasó todo de arriba
            // a abajo, no tiene que volver a subir.
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
/// escritorio el mensaje queda lejos del control que lo produjo, así que
/// necesita destacarse.
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

class _TarjetaHora extends StatelessWidget {
  const _TarjetaHora({
    required this.icono,
    required this.titulo,
    required this.descripcion,
    required this.valor,
    required this.onTap,
  });

  final IconData icono;
  final String titulo;
  final String descripcion;
  final TimeOfDay valor;
  final VoidCallback onTap;

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
        const SizedBox(width: 8),
        Chip(
          label: Text(valor.format(context)),
          labelStyle: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 13),
          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
          side: BorderSide.none,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ],
    );

    // En escritorio la fila vive dentro de un PanelEscritorio, así que en vez
    // de otra superficie crema usa un realce sutil con hover y cursor de
    // clic — se nota que es tocable sin cargar el panel de sombras.
    if (esEscritorio(context)) {
      return ZonaHover(
        cursor: SystemMouseCursors.click,
        builder: (context, hover) => AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: hover ? 0.07 : 0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: hover ? 0.28 : 0.10),
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              splashColor: AppColors.primary.withValues(alpha: 0.08),
              highlightColor: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                child: contenido,
              ),
            ),
          ),
        ),
      );
    }

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        splashColor: AppColors.primary.withValues(alpha: 0.08),
        highlightColor: AppColors.primary.withValues(alpha: 0.04),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: contenido,
        ),
      ),
    );
  }
}

class _TarjetaMinutos extends StatelessWidget {
  const _TarjetaMinutos({
    required this.icono,
    required this.titulo,
    required this.descripcion,
    required this.valor,
    required this.onDecrementar,
    required this.onIncrementar,
  });

  final IconData icono;
  final String titulo;
  final String descripcion;
  final int valor;
  final VoidCallback onDecrementar;
  final VoidCallback onIncrementar;

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
              const SizedBox(height: 10),
              Row(
                children: [
                  _BotonStepper(
                    icono: PhosphorIconsBold.minus,
                    onTap: valor > _minutosTolerenciaMinimo ? onDecrementar : null,
                  ),
                  SizedBox(
                    width: 68,
                    child: Text(
                      '$valor min',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _BotonStepper(
                    icono: PhosphorIconsBold.plus,
                    onTap: valor < _minutosToleranciaMaximo ? onIncrementar : null,
                  ),
                ],
              ),
            ],
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

class _TarjetaInterruptor extends StatelessWidget {
  const _TarjetaInterruptor({
    required this.icono,
    required this.titulo,
    required this.descripcion,
    required this.valor,
    required this.onCambiar,
  });

  final IconData icono;
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
            icono,
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

    // En escritorio el estado del interruptor se lee de un vistazo por el
    // color del recuadro: encendido = acento de marca, apagado = gris.
    if (esEscritorio(context)) {
      final acento = valor ? AppColors.primary : theme.colorScheme.outline;
      return AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: acento.withValues(alpha: valor ? 0.06 : 0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: acento.withValues(alpha: valor ? 0.30 : 0.14),
          ),
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

class _BotonStepper extends StatelessWidget {
  const _BotonStepper({required this.icono, required this.onTap});

  final IconData icono;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final habilitado = onTap != null;
    return Material(
      color: habilitado ? AppColors.primary.withValues(alpha: 0.1) : AppColors.primary.withValues(alpha: 0.04),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: PhosphorIcon(
            icono,
            size: 18,
            color: habilitado ? AppColors.primary : AppColors.primary.withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }
}
