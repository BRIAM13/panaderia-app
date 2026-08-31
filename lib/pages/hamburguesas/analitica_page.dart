import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

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
import '../../widgets/estado_error.dart';
import '../../widgets/estado_vacio.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/page_transitions.dart';
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
    final esEscritorio =
        MediaQuery.sizeOf(context).width >= Breakpoints.escritorio;

    return Scaffold(
      appBar: AppBar(title: const Text('Analítica')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refrescar,
          child: ListView(
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
              _construirSeccionClientes(esEscritorio),
              const SizedBox(height: 32),
              const _TituloSeccion(
                icono: Icons.insights_rounded,
                texto: 'Predicción de demanda',
              ),
              const SizedBox(height: 12),
              _construirSeccionPrediccion(esEscritorio),
            ],
          ),
        ),
      ),
    );
  }

  Widget _construirSeccionClientes(bool esEscritorio) {
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridView.count(
          crossAxisCount: esEscritorio ? 5 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: esEscritorio ? 1.1 : 1.5,
          children: [
            for (var i = 0; i < ordenSegmentos.length; i++)
              _TarjetaSegmento(
                segmento: ordenSegmentos[i],
                cantidad: resumen.conteoDe(ordenSegmentos[i]),
                total: resumen.totalClientes,
                delay: 80 + (i * 40),
              ),
          ],
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
        _ListaClientes(
          titulo: 'Hay que reactivarlos',
          subtitulo: 'Compraban y dejaron de hacerlo. Ordenados por los que más tiempo llevan sin volver.',
          icono: Icons.warning_amber_rounded,
          clientes: resumen.enRiesgo,
          mensajeVacio: 'Ningún cliente está en riesgo ahora mismo. Buen trabajo.',
          onTapCliente: _abrirPerfil,
          mostrarDias: true,
        ),
        const SizedBox(height: 20),
        _ListaClientes(
          titulo: 'Los que más te compran',
          subtitulo: 'Top 10 por gasto acumulado en pedidos ya entregados.',
          icono: Icons.workspace_premium_rounded,
          clientes: resumen.topPorGasto,
          mensajeVacio: 'Todavía no hay compras entregadas para armar un top.',
          onTapCliente: _abrirPerfil,
          mostrarDias: false,
        ),
      ],
    );
  }

  Widget _construirSeccionPrediccion(bool esEscritorio) {
    final anchoSelector = esEscritorio ? 320.0 : double.infinity;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_tiendas.length > 1) ...[
          SizedBox(
            width: anchoSelector,
            child: DropdownButtonFormField<Tienda>(
              initialValue: _tienda,
              items: _tiendas
                  .map((t) => DropdownMenuItem(value: t, child: Text(t.nombre)))
                  .toList(),
              onChanged: (t) {
                if (t == null) return;
                setState(() => _tienda = t);
                _cargarProductos();
              },
              decoration: const InputDecoration(
                labelText: 'Tienda',
                prefixIcon: Icon(Icons.storefront_rounded),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (_productos.isNotEmpty) ...[
          SizedBox(
            width: anchoSelector,
            child: DropdownButtonFormField<ProductoAutoservicio>(
              initialValue: _producto,
              items: _productos
                  .map((p) => DropdownMenuItem(value: p, child: Text(p.nombre)))
                  .toList(),
              onChanged: (p) {
                if (p == null) return;
                setState(() => _producto = p);
                _cargarPrediccion();
              },
              decoration: const InputDecoration(
                labelText: 'Producto',
                prefixIcon: Icon(Icons.bakery_dining_rounded),
              ),
            ),
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
  const _GraficoSegmentos({required this.resumen});

  final ResumenSegmentos resumen;

  @override
  Widget build(BuildContext context) {
    final maximo = ordenSegmentos.fold<int>(
      0,
      (acc, s) => resumen.conteoDe(s) > acc ? resumen.conteoDe(s) : acc,
    );
    final techo = maximo <= 0 ? 5.0 : maximo * 1.3;

    return Tarjeta3D(
      child: Container(
        height: 220,
        padding: const EdgeInsets.fromLTRB(12, 20, 12, 8),
        color: AppColors.surface,
        child: BarChart(
          BarChartData(
            maxY: techo,
            alignment: BarChartAlignment.spaceAround,
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                    BarTooltipItem(
                      '${rod.toY.toInt()} cliente(s)',
                      const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
              ),
            ),
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
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
                    if (indice < 0 || indice >= ordenSegmentos.length) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        etiquetaSegmento(ordenSegmentos[indice]).texto,
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            barGroups: [
              for (var i = 0; i < ordenSegmentos.length; i++)
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: resumen.conteoDe(ordenSegmentos[i]).toDouble(),
                      color: etiquetaSegmento(ordenSegmentos[i]).color,
                      width: 22,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ],
                ),
            ],
          ),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
        ),
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
        Text(subtitulo, style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12)),
        const SizedBox(height: 10),
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
              padding: const EdgeInsets.only(bottom: 10),
              child: _FilaCliente(
                cliente: clientes[i],
                mostrarDias: mostrarDias,
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
  });

  final ClienteResumenLigero cliente;
  final bool mostrarDias;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final etiqueta = etiquetaSegmento(cliente.segmento);
    final dias = cliente.diasDesdeUltimaCompra;
    final destacado = mostrarDias
        ? (dias == null ? 'Sin compras' : '$dias días')
        : 'S/ ${cliente.totalGastado.toStringAsFixed(2)}';

    return Tarjeta3D(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        color: AppColors.surface,
        child: Row(
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
        ),
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
  const _GraficoPrediccion({required this.prediccion});

  final PrediccionDemanda prediccion;

  @override
  Widget build(BuildContext context) {
    final dias = prediccion.predicciones;
    final maximo = dias.fold<int>(
      0,
      (acc, d) => d.demandaPredicha > acc ? d.demandaPredicha : acc,
    );
    final techo = maximo <= 0 ? 10.0 : maximo * 1.25;
    final formatoDia = DateFormat('EEE d', 'es');

    return Tarjeta3D(
      child: Container(
        height: 220,
        padding: const EdgeInsets.fromLTRB(12, 20, 12, 8),
        color: AppColors.surface,
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
                  return BarTooltipItem(
                    '${dia.demandaPredicha} ${prediccion.unidad}$feriado',
                    const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  );
                },
              ),
            ),
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
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
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        formatoDia.format(dias[indice].fecha),
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            gridData: const FlGridData(show: false),
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
                      width: 20,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ],
                ),
            ],
          ),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
        ),
      ),
    );
  }
}
