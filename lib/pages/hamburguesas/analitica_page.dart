import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../models/analitica_model.dart';
import '../../models/perfil_cliente_model.dart';
import '../../models/prediccion_demanda_model.dart';
import '../../models/tienda_model.dart';
import '../../models/usuario_sesion.dart';
import '../../services/api_client.dart';
import '../../services/clientes_service.dart';
import '../../services/pedidos_service.dart' show ProductoAutoservicio;
import '../../services/prediccion_demanda_service.dart';
import '../../services/tiendas_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import '../../utils/segmento_utils.dart';
import '../../widgets/escritorio.dart';
import '../../widgets/estado_error.dart';
import '../../widgets/estado_vacio.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/page_transitions.dart';
import '../../widgets/selector_desplegable.dart';
import '../../widgets/tarjeta_3d.dart';
import 'cliente_perfil_page.dart';

/// Cuántos días hacia adelante se predicen: una semana es el horizonte con
/// el que de verdad se compra harina y se planifica el horno.
const _diasAPredecir = 7;

/// Panel estratégico del negocio, aparte del Dashboard operativo (que es
/// del día a día: cobros, deudas, pedidos pendientes). Junta las dos piezas
/// de inteligencia que hasta ahora vivían separadas y sin lugar donde
/// mirarse: en qué estado está la cartera de clientes (CRM) y cuánto se
/// espera vender los próximos días (modelo de predicción).
class AnaliticaPage extends StatefulWidget {
  const AnaliticaPage({super.key, required this.usuario});

  final UsuarioSesion usuario;

  @override
  State<AnaliticaPage> createState() => _AnaliticaPageState();
}

class _AnaliticaPageState extends State<AnaliticaPage> {
  final _clientesService = ClientesService();
  final _tiendasService = TiendasService();
  final _prediccionService = PrediccionDemandaService();

  bool _cargandoClientes = true;
  String? _errorClientes;
  ResumenSegmentos? _resumen;

  List<Tienda> _tiendas = const [];
  Tienda? _tienda;
  List<ProductoAutoservicio> _productos = const [];
  ProductoAutoservicio? _producto;

  bool _cargandoPrediccion = true;
  String? _errorPrediccion;

  /// Mensaje del backend cuando el microservicio de predicción todavía no
  /// está desplegado. Se guarda aparte de [_errorPrediccion] porque no es un
  /// error: se muestra como estado vacío explicativo, sin botón de
  /// reintentar (reintentar no lo va a desplegar).
  String? _prediccionNoDisponible;
  PrediccionDemanda? _prediccion;

  @override
  void initState() {
    super.initState();
    _cargarClientes();
    _cargarTiendas();
  }

  Future<void> _cargarClientes() async {
    setState(() {
      _cargandoClientes = true;
      _errorClientes = null;
    });
    try {
      final resumen = await _clientesService.obtenerResumenSegmentos();
      if (!mounted) return;
      setState(() => _resumen = resumen);
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorClientes = e.mensaje);
    } catch (_) {
      if (mounted) {
        setState(() => _errorClientes = 'No se pudo cargar la analítica de clientes.');
      }
    } finally {
      if (mounted) setState(() => _cargandoClientes = false);
    }
  }

  Future<void> _cargarTiendas() async {
    try {
      final tiendas = await _tiendasService.misTiendas();
      if (!mounted) return;
      setState(() {
        _tiendas = tiendas;
        _tienda = tiendas.isNotEmpty ? tiendas.first : null;
      });
      if (_tienda == null) {
        setState(() {
          _cargandoPrediccion = false;
          _errorPrediccion = 'No tienes tiendas asignadas todavía.';
        });
        return;
      }
      await _cargarProductos();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _cargandoPrediccion = false;
          _errorPrediccion = e.mensaje;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _cargandoPrediccion = false;
          _errorPrediccion = 'No se pudieron cargar tus tiendas.';
        });
      }
    }
  }

  /// El catálogo se pide SIEMPRE por tienda (`/tiendas/:id/productos`), no
  /// con el listado global de productos: cada tienda vende lo suyo a su
  /// propio precio, y predecir la demanda de un producto que esa tienda ni
  /// siquiera ofrece no significa nada.
  Future<void> _cargarProductos() async {
    final tienda = _tienda;
    if (tienda == null) return;

    setState(() {
      _cargandoPrediccion = true;
      _errorPrediccion = null;
      _prediccionNoDisponible = null;
      _prediccion = null;
    });
    try {
      final productos = await _tiendasService.listarProductos(tienda.idTienda);
      if (!mounted) return;
      setState(() {
        _productos = productos;
        _producto = productos.isNotEmpty ? productos.first : null;
      });
      if (_producto == null) {
        setState(() {
          _cargandoPrediccion = false;
          _errorPrediccion = 'Esta tienda todavía no tiene productos en su catálogo.';
        });
        return;
      }
      await _cargarPrediccion();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _cargandoPrediccion = false;
          _errorPrediccion = e.mensaje;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _cargandoPrediccion = false;
          _errorPrediccion = 'No se pudo cargar el catálogo de la tienda.';
        });
      }
    }
  }

  Future<void> _cargarPrediccion() async {
    final tienda = _tienda;
    final producto = _producto;
    if (tienda == null || producto == null) return;

    setState(() {
      _cargandoPrediccion = true;
      _errorPrediccion = null;
      _prediccionNoDisponible = null;
    });
    try {
      final prediccion = await _prediccionService.predecir(
        idTienda: tienda.idTienda,
        idProducto: producto.idProducto,
        fechas: PrediccionDemandaService.proximosDias(_diasAPredecir),
      );
      if (!mounted) return;
      setState(() => _prediccion = prediccion);
    } on PrediccionNoDisponibleException catch (e) {
      if (mounted) setState(() => _prediccionNoDisponible = e.mensaje);
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorPrediccion = e.mensaje);
    } catch (_) {
      if (mounted) {
        setState(() => _errorPrediccion = 'No se pudo obtener la predicción de demanda.');
      }
    } finally {
      if (mounted) setState(() => _cargandoPrediccion = false);
    }
  }

  Future<void> _refrescar() async {
    await Future.wait([_cargarClientes(), _cargarPrediccion()]);
  }

  void _abrirPerfil(ClienteResumenLigero cliente) {
    pushSlideUpFade(
      context,
      (_) => ClientePerfilPage.porId(idCliente: cliente.idCliente),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: appBarGestion(
        context,
        titulo: 'Analítica',
        subtitulo: 'Segmentación de la cartera y predicción de demanda',
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refrescar,
          // El panel estratégico es la pantalla que más gana con una ventana
          // ancha: en celular las dos secciones (CRM y predicción) son un
          // rollo vertical de ~5 pantallazos; en escritorio caben lado a
          // lado y se pueden comparar de un vistazo, que es justo el punto
          // de un panel de inteligencia.
          child: esEscritorio(context)
              ? _cuerpoEscritorio(context)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                  children: [
                    Text(
                      'Hola, ${widget.usuario.nombreCompleto}',
                      style: theme.textTheme.bodyMedium,
                    ).animate().fadeIn(duration: 250.ms),
                    const SizedBox(height: 4),
                    Text(
                      'Inteligencia de tu negocio',
                      style: theme.textTheme.titleLarge,
                    ).animate().fadeIn(delay: 60.ms, duration: 250.ms),
                    const SizedBox(height: 20),
                    const _TituloSeccion(
                      icono: Icons.groups_2_rounded,
                      texto: 'Tus clientes',
                    ),
                    const SizedBox(height: 12),
                    _construirSeccionClientes(),
                    const SizedBox(height: 32),
                    const _TituloSeccion(
                      icono: Icons.insights_rounded,
                      texto: 'Predicción de demanda',
                    ),
                    const SizedBox(height: 12),
                    _construirSeccionPrediccion(),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _construirSeccionClientes() {
    if (_cargandoClientes && _resumen == null) {
      return const SizedBox(height: 220, child: Center(child: AppLoadingIndicator()));
    }
    if (_errorClientes != null && _resumen == null) {
      return SizedBox(
        height: 260,
        child: EstadoError(mensaje: _errorClientes!, onReintentar: _cargarClientes),
      );
    }

    final resumen = _resumen!;
    if (resumen.sinDatos) {
      return const SizedBox(
        height: 260,
        child: EstadoVacio(
          icono: Icons.groups_2_rounded,
          titulo: 'Todavía no hay clientes registrados',
          subtitulo: 'En cuanto registres clientes y pedidos, acá vas a ver cómo se reparten.',
        ),
      );
    }

    final ancho = anchoVentana(context);
    // Los 5 segmentos en una grilla de 2 columnas dejan 3 filas con una
    // celda huérfana al final. Desde 600 px se usan las MISMAS tarjetas
    // bajas del escritorio: 3+2 en una tablet angosta y las 5 en una sola
    // fila desde 760, que es donde de verdad entran sin apretarse.
    final columnasSegmentos = ancho >= 760
        ? 5
        : ancho >= Breakpoints.tablet
        ? 3
        : 2;

    final enRiesgo = _ListaClientes(
      titulo: 'Hay que reactivarlos',
      subtitulo:
          'Compraban y dejaron de hacerlo. Ordenados por los que más tiempo llevan sin volver.',
      icono: Icons.warning_amber_rounded,
      clientes: resumen.enRiesgo,
      mensajeVacio: 'Ningún cliente está en riesgo ahora mismo. Buen trabajo.',
      onTapCliente: _abrirPerfil,
      mostrarDias: true,
    );

    final topGasto = _ListaClientes(
      titulo: 'Los que más te compran',
      subtitulo: 'Top 10 por gasto acumulado en pedidos ya entregados.',
      icono: Icons.workspace_premium_rounded,
      clientes: resumen.topPorGasto,
      mensajeVacio: 'Todavía no hay compras entregadas para armar un top.',
      onTapCliente: _abrirPerfil,
      mostrarDias: false,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (columnasSegmentos == 2)
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: [
              for (var i = 0; i < ordenSegmentos.length; i++)
                _TarjetaSegmento(
                  segmento: ordenSegmentos[i],
                  cantidad: resumen.conteoDe(ordenSegmentos[i]),
                  total: resumen.totalClientes,
                  delay: 80 + (i * 40),
                ),
            ],
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final anchoTarjeta = anchoColumna(
                constraints.maxWidth,
                columnasSegmentos,
                12,
              );
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (var i = 0; i < ordenSegmentos.length; i++)
                    SizedBox(
                      width: anchoTarjeta,
                      child: _tarjetaSegmentoEscritorio(
                        segmento: ordenSegmentos[i],
                        cantidad: resumen.conteoDe(ordenSegmentos[i]),
                        total: resumen.totalClientes,
                        delay: 80 + (i * 40),
                      ),
                    ),
                ],
              );
            },
          ),
        const SizedBox(height: 24),
        Text(
          'Cómo se reparte tu cartera',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        _GraficoSegmentos(resumen: resumen)
            .animate()
            .fadeIn(delay: 260.ms, duration: 400.ms)
            .moveY(begin: 16, end: 0),
        const SizedBox(height: 24),
        // Las dos listas accionables entran lado a lado bastante antes de
        // los 900 px: a 700 quedan ~330 px cada una, igual que una lista a
        // pantalla completa en celular, y se dejan de leer como un rollo
        // vertical de dos pantallazos.
        if (ancho >= 700)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: enRiesgo),
                const SizedBox(width: 20),
                Expanded(child: topGasto),
              ],
            ),
          )
        else ...[
          enRiesgo,
          const SizedBox(height: 20),
          topGasto,
        ],
      ],
    );
  }

  Widget _construirSeccionPrediccion() {
    // Desde 600 px los dos selectores comparten fila: apilados eran dos
    // filas completas de controles empujando el gráfico —el contenido real
    // de la sección— fuera de la pantalla.
    final enFila = anchoVentana(context) >= Breakpoints.tablet;

    final selectorTienda = _tiendas.length > 1
        ? SelectorDesplegable<Tienda>(
            valor: _tienda,
            opciones: _tiendas,
            etiqueta: (t) => t.nombre,
            label: 'Tienda',
            icono: PhosphorIconsRegular.storefront,
            onChanged: (t) {
              if (t == null) return;
              setState(() => _tienda = t);
              _cargarProductos();
            },
          )
        : null;

    final selectorProducto = _productos.isNotEmpty
        ? SelectorDesplegable<ProductoAutoservicio>(
            valor: _producto,
            opciones: _productos,
            etiqueta: (p) => p.nombre,
            label: 'Producto',
            icono: PhosphorIconsFill.bread,
            onChanged: (p) {
              if (p == null) return;
              setState(() => _producto = p);
              _cargarPrediccion();
            },
          )
        : null;

    final selectores = <Widget>[?selectorTienda, ?selectorProducto];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selectores.isNotEmpty) ...[
          if (enFila)
            Row(
              children: [
                for (var i = 0; i < selectores.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: selectores[i]),
                ],
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < selectores.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  selectores[i],
                ],
              ],
            ),
          const SizedBox(height: 16),
        ],
        _construirResultadoPrediccion(),
      ],
    );
  }

  Widget _construirResultadoPrediccion() {
    if (_cargandoPrediccion) {
      return const SizedBox(height: 200, child: Center(child: AppLoadingIndicator()));
    }
    if (_prediccionNoDisponible != null) {
      return SizedBox(
        height: 280,
        child: EstadoVacio(
          icono: Icons.rocket_launch_rounded,
          titulo: 'La predicción se activa sola',
          subtitulo:
              '$_prediccionNoDisponible\n\nEl modelo ya está entrenado y listo: en cuanto el servidor de predicción esté desplegado, este gráfico aparece sin tocar la app.',
        ),
      );
    }
    if (_errorPrediccion != null) {
      return SizedBox(
        height: 260,
        child: EstadoError(mensaje: _errorPrediccion!, onReintentar: _cargarPrediccion),
      );
    }

    final prediccion = _prediccion;
    if (prediccion == null || prediccion.predicciones.isEmpty) {
      return const SizedBox(
        height: 200,
        child: EstadoVacio(
          icono: Icons.query_stats_rounded,
          titulo: 'Sin predicción para estos días',
        ),
      );
    }

    return _ResultadoPrediccion(prediccion: prediccion);
  }

  // ---------------------------------------------------------------------
  // ESCRITORIO
  // ---------------------------------------------------------------------

  Widget _cuerpoEscritorio(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 56),
      children: [
        ContenidoCentrado(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EncabezadoEscritorio(
                anteTitulo: 'HOLA, ${widget.usuario.nombreCompleto}',
                titulo: 'Inteligencia de tu negocio',
                subtitulo:
                    'Cómo se reparte tu cartera de clientes y cuánto se '
                    'espera vender los próximos $_diasAPredecir días.',
              ),
              const SizedBox(height: 28),
              _seccionClientesEscritorio(context),
              const SizedBox(height: espacioEscritorio),
              _seccionPrediccionEscritorio(context),
            ],
          ),
        ),
      ],
    );
  }

  Widget _seccionClientesEscritorio(BuildContext context) {
    if (_cargandoClientes && _resumen == null) {
      return const PanelEscritorio(
        icono: Icons.groups_2_rounded,
        titulo: 'Tus clientes',
        child: SizedBox(height: 220, child: Center(child: AppLoadingIndicator())),
      );
    }
    if (_errorClientes != null && _resumen == null) {
      return PanelEscritorio(
        icono: Icons.groups_2_rounded,
        titulo: 'Tus clientes',
        child: SizedBox(
          height: 240,
          child: EstadoError(
            mensaje: _errorClientes!,
            onReintentar: _cargarClientes,
          ),
        ),
      );
    }

    final resumen = _resumen!;
    if (resumen.sinDatos) {
      return const PanelEscritorio(
        icono: Icons.groups_2_rounded,
        titulo: 'Tus clientes',
        child: SizedBox(
          height: 240,
          child: EstadoVacio(
            icono: Icons.groups_2_rounded,
            titulo: 'Todavía no hay clientes registrados',
            subtitulo:
                'En cuanto registres clientes y pedidos, acá vas a ver cómo se reparten.',
          ),
        ),
      );
    }

    final grafico = PanelEscritorio(
      icono: Icons.donut_large_rounded,
      titulo: 'Cómo se reparte tu cartera',
      subtitulo: '${resumen.totalClientes} cliente(s) en total.',
      child: _GraficoSegmentos(
        resumen: resumen,
        alto: 300,
        conMarco: false,
        detallado: true,
      ).animate().fadeIn(delay: 260.ms, duration: 400.ms).moveY(begin: 16, end: 0),
    );

    final enRiesgo = PanelEscritorio(
      icono: Icons.warning_amber_rounded,
      titulo: 'Hay que reactivarlos',
      subtitulo: 'Los que más tiempo llevan sin volver.',
      accion: _Contador(cantidad: resumen.enRiesgo.length),
      child: _ListaClientes(
        titulo: 'Hay que reactivarlos',
        subtitulo: '',
        icono: Icons.warning_amber_rounded,
        clientes: resumen.enRiesgo,
        mensajeVacio: 'Ningún cliente está en riesgo ahora mismo. Buen trabajo.',
        onTapCliente: _abrirPerfil,
        mostrarDias: true,
        estiloEscritorio: true,
      ),
    );

    final topGasto = PanelEscritorio(
      icono: Icons.workspace_premium_rounded,
      titulo: 'Los que más te compran',
      subtitulo: 'Top 10 por gasto en pedidos entregados.',
      accion: _Contador(cantidad: resumen.topPorGasto.length),
      child: _ListaClientes(
        titulo: 'Los que más te compran',
        subtitulo: '',
        icono: Icons.workspace_premium_rounded,
        clientes: resumen.topPorGasto,
        mensajeVacio: 'Todavía no hay compras entregadas para armar un top.',
        onTapCliente: _abrirPerfil,
        mostrarDias: false,
        estiloEscritorio: true,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Los 5 segmentos en una sola fila de tarjetas bajas: en celular es
        // una grilla 2x3 con una celda huérfana al final, y hay que
        // desplazarse para ver el último segmento.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < ordenSegmentos.length; i++) ...[
              if (i > 0) const SizedBox(width: 16),
              Expanded(
                child: _tarjetaSegmentoEscritorio(
                  segmento: ordenSegmentos[i],
                  cantidad: resumen.conteoDe(ordenSegmentos[i]),
                  total: resumen.totalClientes,
                  delay: 80 + (i * 40),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: espacioEscritorio),
        // A partir de [Breakpoints.escritorioAncho] entran las tres piezas
        // del CRM a la vez (gráfico + las dos listas accionables); por
        // debajo, el gráfico va arriba a lo ancho y las listas se reparten
        // la fila de abajo.
        if (esEscritorioAncho(context))
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 4, child: grafico),
                const SizedBox(width: espacioEscritorio),
                Expanded(flex: 3, child: enRiesgo),
                const SizedBox(width: espacioEscritorio),
                Expanded(flex: 3, child: topGasto),
              ],
            ),
          )
        else ...[
          grafico,
          const SizedBox(height: espacioEscritorio),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: enRiesgo),
                const SizedBox(width: espacioEscritorio),
                Expanded(child: topGasto),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _tarjetaSegmentoEscritorio({
    required SegmentoCliente segmento,
    required int cantidad,
    required int total,
    required int delay,
  }) {
    final etiqueta = etiquetaSegmento(segmento);
    final porcentaje = total == 0 ? 0 : (cantidad * 100 / total).round();
    return TarjetaKpi(
      icono: etiqueta.icono,
      color: etiqueta.color,
      titulo: etiqueta.texto,
      valor: '$cantidad',
      subtitulo: '$porcentaje%',
      subtituloColor: etiqueta.color,
      delay: delay,
      alto: 124,
    );
  }

  Widget _seccionPrediccionEscritorio(BuildContext context) {
    // Los dos selectores dejan de ser dos filas apiladas encima del gráfico
    // y pasan al encabezado del panel: son los controles DE ese gráfico, y
    // así se lee como un widget de tablero y no como un formulario.
    final selectores = <Widget>[
      if (_tiendas.length > 1)
        SizedBox(
          width: 200,
          child: SelectorDesplegable<Tienda>(
            valor: _tienda,
            opciones: _tiendas,
            etiqueta: (t) => t.nombre,
            label: 'Tienda',
            icono: PhosphorIconsRegular.storefront,
            denso: true,
            onChanged: (t) {
              if (t == null) return;
              setState(() => _tienda = t);
              _cargarProductos();
            },
          ),
        ),
      if (_productos.isNotEmpty)
        SizedBox(
          width: 240,
          child: SelectorDesplegable<ProductoAutoservicio>(
            valor: _producto,
            opciones: _productos,
            etiqueta: (p) => p.nombre,
            label: 'Producto',
            icono: PhosphorIconsFill.bread,
            denso: true,
            onChanged: (p) {
              if (p == null) return;
              setState(() => _producto = p);
              _cargarPrediccion();
            },
          ),
        ),
    ];

    return PanelEscritorio(
      icono: Icons.insights_rounded,
      titulo: 'Predicción de demanda',
      subtitulo: 'Próximos $_diasAPredecir días, según el modelo entrenado.',
      accion: selectores.isEmpty
          ? null
          : Wrap(spacing: 12, runSpacing: 12, children: selectores),
      child: _resultadoPrediccionEscritorio(),
    );
  }

  Widget _resultadoPrediccionEscritorio() {
    if (_cargandoPrediccion) {
      return const SizedBox(
        height: 320,
        child: Center(child: AppLoadingIndicator()),
      );
    }
    if (_prediccionNoDisponible != null) {
      return SizedBox(
        height: 320,
        child: EstadoVacio(
          icono: Icons.rocket_launch_rounded,
          titulo: 'La predicción se activa sola',
          subtitulo:
              '$_prediccionNoDisponible\n\nEl modelo ya está entrenado y listo: en cuanto el servidor de predicción esté desplegado, este gráfico aparece sin tocar la app.',
        ),
      );
    }
    if (_errorPrediccion != null) {
      return SizedBox(
        height: 300,
        child: EstadoError(
          mensaje: _errorPrediccion!,
          onReintentar: _cargarPrediccion,
        ),
      );
    }

    final prediccion = _prediccion;
    if (prediccion == null || prediccion.predicciones.isEmpty) {
      return const SizedBox(
        height: 260,
        child: EstadoVacio(
          icono: Icons.query_stats_rounded,
          titulo: 'Sin predicción para estos días',
        ),
      );
    }

    // El total de la semana pasa a ser un dato destacado a la izquierda del
    // gráfico (con la advertencia del modelo debajo, nunca escondida) en vez
    // de una línea de texto perdida encima de las barras.
    final resumenLateral = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primary, AppColors.secondary],
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Se esperan',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                '${prediccion.demandaTotal}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                  height: 1.05,
                ),
              ),
              Text(
                '${prediccion.unidad} en $_diasAPredecir días',
                style: const TextStyle(color: Colors.white70, fontSize: 12.5),
              ),
            ],
          ),
        ),
        if (prediccion.advertencia.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.secondaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    prediccion.advertencia,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 240, child: resumenLateral),
        const SizedBox(width: espacioEscritorio),
        Expanded(
          child:
              _GraficoPrediccion(
                    prediccion: prediccion,
                    alto: 320,
                    conMarco: false,
                    detallado: true,
                  )
                  .animate()
                  .fadeIn(duration: 400.ms)
                  .moveY(begin: 16, end: 0),
        ),
      ],
    );
  }
}

/// Insignia con la cantidad de elementos de una lista, para el encabezado de
/// su panel en escritorio.
class _Contador extends StatelessWidget {
  const _Contador({required this.cantidad});

  final int cantidad;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$cantidad',
        style: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _TituloSeccion extends StatelessWidget {
  const _TituloSeccion({required this.icono, required this.texto});

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icono, color: AppColors.primary, size: 22),
        const SizedBox(width: 8),
        Text(texto, style: Theme.of(context).textTheme.titleLarge),
      ],
    ).animate().fadeIn(duration: 300.ms).moveX(begin: -8, end: 0);
  }
}

/// Cuántos clientes hay en un segmento y qué porcentaje de la cartera son —
/// el porcentaje es lo que convierte "3 en riesgo" en una señal accionable
/// (3 de 8 es una alarma; 3 de 400, ruido).
class _TarjetaSegmento extends StatelessWidget {
  const _TarjetaSegmento({
    required this.segmento,
    required this.cantidad,
    required this.total,
    required this.delay,
  });

  final SegmentoCliente segmento;
  final int cantidad;
  final int total;
  final int delay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final etiqueta = etiquetaSegmento(segmento);
    final porcentaje = total == 0 ? 0 : (cantidad * 100 / total).round();

    return Tarjeta3D(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: etiqueta.color.withValues(alpha: 0.28)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(etiqueta.icono, color: etiqueta.color, size: 20),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    etiqueta.texto,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: etiqueta.color,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '$cantidad',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              '$porcentaje% de tu cartera',
              style: theme.textTheme.bodyMedium?.copyWith(fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    ).animate(delay: delay.ms).fadeIn(duration: 350.ms).moveY(begin: 14, end: 0);
  }
}

/// Distribución de la cartera por segmento — mismo estilo de barras que el
/// Dashboard operativo, para que las dos pantallas se lean igual.
class _GraficoSegmentos extends StatelessWidget {
  const _GraficoSegmentos({
    required this.resumen,
    this.alto = 220,
    this.conMarco = true,
    this.detallado = false,
  });

  final ResumenSegmentos resumen;

  /// Alto del área de dibujo (300 en escritorio: las barras se leen).
  final double alto;

  /// false cuando ya va dentro de un [PanelEscritorio].
  final bool conMarco;

  /// Eje de valores + guías horizontales + tooltip con el nombre del
  /// segmento. Solo en escritorio, donde hay alto y ancho para sostenerlo.
  final bool detallado;

  @override
  Widget build(BuildContext context) {
    final maximo = ordenSegmentos.fold<int>(
      0,
      (acc, s) => resumen.conteoDe(s) > acc ? resumen.conteoDe(s) : acc,
    );
    final techo = maximo <= 0 ? 5.0 : maximo * 1.3;

    final grafico = Container(
      height: alto,
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 8),
      color: conMarco ? AppColors.surface : null,
      child: BarChart(
        BarChartData(
          maxY: techo,
          alignment: BarChartAlignment.spaceAround,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                  BarTooltipItem(
                    detallado
                        ? '${etiquetaSegmento(ordenSegmentos[group.x]).texto}\n${rod.toY.toInt()} cliente(s)'
                        : '${rod.toY.toInt()} cliente(s)',
                    const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: detallado,
                reservedSize: 32,
                getTitlesWidget: (value, meta) => value % 1 != 0
                    ? const SizedBox.shrink()
                    : Text(
                        value.toStringAsFixed(0),
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
              ),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: detallado ? 34 : 22,
                getTitlesWidget: (value, meta) {
                  final indice = value.toInt();
                  if (indice < 0 || indice >= ordenSegmentos.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      etiquetaSegmento(ordenSegmentos[indice]).texto,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: detallado ? 11 : 10,
                        fontWeight: detallado
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          gridData: FlGridData(
            show: detallado,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (value) => FlLine(
              color: AppColors.surfaceMuted,
              strokeWidth: 1,
              dashArray: const [4, 6],
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: [
            for (var i = 0; i < ordenSegmentos.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: resumen.conteoDe(ordenSegmentos[i]).toDouble(),
                    color: etiquetaSegmento(ordenSegmentos[i]).color,
                    width: detallado ? 30 : 22,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ],
              ),
          ],
        ),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
      ),
    );

    return conMarco ? Tarjeta3D(child: grafico) : grafico;
  }
}

/// Lista corta de clientes con su segmento y el dato que justifica que estén
/// ahí (días sin comprar, o cuánto gastaron). Al tocar uno se abre su perfil
/// completo del CRM.
class _ListaClientes extends StatelessWidget {
  const _ListaClientes({
    required this.titulo,
    required this.subtitulo,
    required this.icono,
    required this.clientes,
    required this.mensajeVacio,
    required this.onTapCliente,
    required this.mostrarDias,
    this.estiloEscritorio = false,
  });

  final String titulo;
  final String subtitulo;
  final IconData icono;
  final List<ClienteResumenLigero> clientes;
  final String mensajeVacio;
  final void Function(ClienteResumenLigero) onTapCliente;

  /// true: el dato de la derecha son los días sin comprar (lista "en
  /// riesgo"); false: el gasto acumulado (lista "top por gasto").
  final bool mostrarDias;

  /// En escritorio la lista vive dentro de un [PanelEscritorio] que ya pone
  /// título, subtítulo y contador: acá se omite ese encabezado (si no, se
  /// duplica) y las filas pasan a ser planas con resaltado al pasar el mouse,
  /// en vez de tarjetas con sombra apiladas dentro de otra tarjeta.
  final bool estiloEscritorio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!estiloEscritorio) ...[
          Row(
            children: [
              Icon(icono, size: 20, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Expanded(child: Text(titulo, style: theme.textTheme.titleMedium)),
              if (clientes.isNotEmpty)
                Text(
                  '${clientes.length}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitulo,
            style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
          ),
          const SizedBox(height: 10),
        ],
        if (clientes.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(mensajeVacio, style: theme.textTheme.bodyMedium),
          )
        else
          for (var i = 0; i < clientes.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: estiloEscritorio ? 2 : 10),
              child: _FilaCliente(
                cliente: clientes[i],
                mostrarDias: mostrarDias,
                plana: estiloEscritorio,
                onTap: () => onTapCliente(clientes[i]),
              ).animate(delay: (60 * i).ms).fadeIn(duration: 300.ms).moveX(begin: 10, end: 0),
            ),
      ],
    );
  }
}

class _FilaCliente extends StatelessWidget {
  const _FilaCliente({
    required this.cliente,
    required this.mostrarDias,
    required this.onTap,
    this.plana = false,
  });

  final ClienteResumenLigero cliente;
  final bool mostrarDias;
  final VoidCallback onTap;

  /// Sin tarjeta 3D ni sombra: la fila se resalta al pasar el mouse. Se usa
  /// dentro de los paneles de escritorio.
  final bool plana;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final etiqueta = etiquetaSegmento(cliente.segmento);
    final dias = cliente.diasDesdeUltimaCompra;
    final destacado = mostrarDias
        ? (dias == null ? 'Sin compras' : '$dias días')
        : 'S/ ${cliente.totalGastado.toStringAsFixed(2)}';

    final contenido = Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: etiqueta.color.withValues(alpha: 0.14),
          ),
          child: Icon(etiqueta.icono, color: etiqueta.color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                cliente.nombre,
                style: theme.textTheme.titleMedium?.copyWith(fontSize: 15),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                cliente.telefono ?? 'Sin teléfono registrado',
                style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              destacado,
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 14,
                color: etiqueta.color,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              etiqueta.texto,
              style: theme.textTheme.bodyMedium?.copyWith(fontSize: 11),
            ),
          ],
        ),
        const Icon(
          Icons.chevron_right_rounded,
          color: AppColors.textSecondary,
        ),
      ],
    );

    if (plana) {
      return FilaTabla(
        onTap: onTap,
        acento: etiqueta.color,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: contenido,
      );
    }

    return Tarjeta3D(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        color: AppColors.surface,
        child: contenido,
      ),
    );
  }
}

/// El gráfico de la predicción más el total de la semana y la advertencia
/// del modelo — esa advertencia se muestra siempre, no escondida: el modelo
/// se entrenó con datos sintéticos y quien lea el número tiene que saberlo.
class _ResultadoPrediccion extends StatelessWidget {
  const _ResultadoPrediccion({required this.prediccion});

  final PrediccionDemanda prediccion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Se esperan ${prediccion.demandaTotal} ${prediccion.unidad} en $_diasAPredecir días',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        _GraficoPrediccion(prediccion: prediccion)
            .animate()
            .fadeIn(duration: 400.ms)
            .moveY(begin: 16, end: 0),
        const SizedBox(height: 12),
        if (prediccion.advertencia.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.secondaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    prediccion.advertencia,
                    style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _GraficoPrediccion extends StatelessWidget {
  const _GraficoPrediccion({
    required this.prediccion,
    this.alto = 220,
    this.conMarco = true,
    this.detallado = false,
  });

  final PrediccionDemanda prediccion;
  final double alto;
  final bool conMarco;
  final bool detallado;

  @override
  Widget build(BuildContext context) {
    final dias = prediccion.predicciones;
    final maximo = dias.fold<int>(
      0,
      (acc, d) => d.demandaPredicha > acc ? d.demandaPredicha : acc,
    );
    final techo = maximo <= 0 ? 10.0 : maximo * 1.25;
    final formatoDia = DateFormat('EEE d', 'es');

    final grafico = Container(
      height: alto,
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 8),
      color: conMarco ? AppColors.surface : null,
      child: BarChart(
        BarChartData(
          maxY: techo,
          alignment: BarChartAlignment.spaceAround,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final dia = dias[group.x];
                final feriado = dia.esFeriado
                    ? '\n${dia.nombreFeriado ?? 'Feriado'}'
                    : '';
                final fecha = detallado
                    ? '${formatoDia.format(dia.fecha)}\n'
                    : '';
                return BarTooltipItem(
                  '$fecha${dia.demandaPredicha} ${prediccion.unidad}$feriado',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: detallado,
                reservedSize: 34,
                getTitlesWidget: (value, meta) => value % 1 != 0
                    ? const SizedBox.shrink()
                    : Text(
                        value.toStringAsFixed(0),
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
              ),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final indice = value.toInt();
                  if (indice < 0 || indice >= dias.length) {
                    return const SizedBox.shrink();
                  }
                  final dia = dias[indice];
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      formatoDia.format(dia.fecha),
                      style: TextStyle(
                        fontSize: detallado ? 11 : 10,
                        // En escritorio el día feriado se marca también en la
                        // etiqueta del eje, no solo con el color de la barra:
                        // así se entiende el pico sin tener que pasar el
                        // mouse por encima.
                        fontWeight: detallado && dia.esFeriado
                            ? FontWeight.w800
                            : FontWeight.normal,
                        color: detallado && dia.esFeriado
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          gridData: FlGridData(
            show: detallado,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (value) => FlLine(
              color: AppColors.surfaceMuted,
              strokeWidth: 1,
              dashArray: const [4, 6],
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: [
            for (var i = 0; i < dias.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: dias[i].demandaPredicha.toDouble(),
                    // Un feriado se pinta distinto: es la explicación más
                    // frecuente de un pico que si no parece un error.
                    color: dias[i].esFeriado
                        ? AppColors.primary
                        : AppColors.secondary.withValues(alpha: 0.55),
                    width: detallado ? 28 : 20,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ],
              ),
          ],
        ),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
      ),
    );

    return conMarco ? Tarjeta3D(child: grafico) : grafico;
  }
}
