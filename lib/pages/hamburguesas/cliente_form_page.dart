import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../models/cliente_model.dart';
import '../../services/api_client.dart';
import '../../services/clientes_service.dart';
import '../../services/external_lookup_service.dart';
import '../../services/geolocation_service.dart';
import '../../utils/text_formatters.dart';
import '../../widgets/premium_button.dart';
import '../../widgets/segmented_switch.dart';

/// Alta o edición de un cliente aplicando el "Estándar Briam":
/// DNI y RUC son mutuamente excluyentes como identificador, revelado
/// progresivo animado de los campos secundarios, congelamiento de datos
/// (readOnly si viene de una fuente oficial) y auditoría de calidad del
/// dato (RENIEC/SUNAT / manual / sin documento).
///
/// Única condición obligatoria para guardar: que "Nombres" (o "Razón
/// social") no esté vacío — el resto de campos son opcionales.
class ClienteFormPage extends StatefulWidget {
  const ClienteFormPage({super.key, this.clienteExistente});

  final Cliente? clienteExistente;

  @override
  State<ClienteFormPage> createState() => _ClienteFormPageState();
}

enum _TipoDocumento { dni, ruc }

class _ClienteFormPageState extends State<ClienteFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _dniController = TextEditingController();
  final _rucController = TextEditingController();
  final _nombresController = TextEditingController();
  final _apellidoPaternoController = TextEditingController();
  final _apellidoMaternoController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _emailController = TextEditingController();
  final _direccionController = TextEditingController();
  final _descripcionNegocioController = TextEditingController();

  /// Domicilio fiscal declarado ante SUNAT (RUC): solo informativo, de solo
  /// lectura, NUNCA se envía al backend — existe para que el vendedor lo
  /// compare contra la "Dirección de Entrega" real, que puede ser distinta.
  final _domicilioFiscalController = TextEditingController();

  final _clientesService = ClientesService();
  final _externalLookup = ExternalLookupService();
  final _geolocationService = const GeolocationService();

  bool get _editando => widget.clienteExistente != null;

  /// Un cliente ya bloqueado permanentemente (verificado por RENIEC/SUNAT en
  /// una edición previa) nunca vuelve a mostrar el buscador de documento: no
  /// hay forma de "re-verificar" ni de tocar sus nombres. Un cliente nuevo,
  /// o uno editado que sigue siendo manual/sin documento, sí lo muestra.
  bool get _permiteReverificar =>
      !_editando || !widget.clienteExistente!.datosCongelados;

  _TipoDocumento _tipoDocumento = _TipoDocumento.dni;

  /// Controla si los campos secundarios (apellidos, contacto, dirección,
  /// negocio) están desplegados. En modo RUC también controla si el propio
  /// campo "Razón social" es visible: en ese modo nada se revela hasta que
  /// la búsqueda de RUC tenga éxito.
  bool _camposExpandidos = false;
  bool _soloLectura = false;
  String _origenValidacion = 'MANUAL';
  bool _documentoVerificadoApiReal = false;

  /// true si "Nombre comercial / Puesto" vino de una búsqueda RUC exitosa
  /// contra SUNAT — se bloquea (readOnly) para siempre, igual que los
  /// nombres verificados por RENIEC. Solo aplica a RUC: en DNI este campo
  /// siempre se escribe a mano y siempre queda editable.
  bool _nombreComercialBloqueado = false;

  /// Estado y condición SUNAT del RUC verificado (ej. "ACTIVO"/"HABIDO").
  /// Solo aplican a RUC; se muestran como badges informativos adicionales.
  String? _estadoRuc;
  String? _condicionRuc;

  /// Último documento (DNI o RUC) que efectivamente validó los nombres que
  /// se ven en pantalla. Si el usuario edita el campo de documento y el
  /// texto deja de coincidir con este valor, los nombres autocompletados ya
  /// no son confiables: se limpian y se bloquean hasta la próxima búsqueda
  /// exitosa (nunca se editan escribiendo directamente sobre ellos).
  String? _ultimoDocumentoVerificado;

  bool _buscando = false;
  bool _guardando = false;
  bool _obteniendoUbicacion = false;
  String? _error;

  /// Verificación local (contra nuestra propia BD, sin apiperu.dev) de si
  /// el documento ya pertenece a alguien registrado. Se dispara sola en
  /// cuanto el número llega a su largo completo, ANTES de que el vendedor
  /// llegue a tocar "Buscar" — así se evita gastar una consulta paga a la
  /// API real cuando el aviso ya deja claro que no hace falta. El botón
  /// "Buscar" permanece INACTIVO (no solo si ya se confirmó un duplicado,
  /// sino mientras la verificación no haya terminado) para blindar contra
  /// "manos rápidas" que tocan buscar antes de que el chequeo local alcance
  /// a completarse.
  Timer? _debounceVerificacion;
  bool _verificandoDocumento = false;
  bool _documentoYaRegistrado = false;

  /// true solo cuando ya se confirmó (para el texto actual del documento)
  /// que NO existe un duplicado. Cualquier cambio en el campo lo vuelve a
  /// poner en false hasta que se re-verifique.
  bool _documentoVerificado = false;

  @override
  void initState() {
    super.initState();
    _nombresController.addListener(_onNombresChanged);
    _dniController.addListener(_onDocumentoEditado);
    _rucController.addListener(_onDocumentoEditado);
    _dniController.addListener(_onDocumentoCambiadoParaVerificacion);
    _rucController.addListener(_onDocumentoCambiadoParaVerificacion);

    final cliente = widget.clienteExistente;
    if (cliente != null) {
      final dniPrevio = cliente.dni ?? '';
      if (dniPrevio.length == 11) {
        _tipoDocumento = _TipoDocumento.ruc;
        _rucController.text = dniPrevio;
      } else {
        _dniController.text = dniPrevio;
      }
      _nombresController.text = cliente.nombres.toUpperCase();
      _apellidoPaternoController.text = cliente.apellidoPaterno.toUpperCase();
      _apellidoMaternoController.text = (cliente.apellidoMaterno ?? '')
          .toUpperCase();
      _telefonoController.text = cliente.telefono ?? '';
      _emailController.text = cliente.email ?? '';
      _direccionController.text = (cliente.direccion ?? '').toUpperCase();
      _descripcionNegocioController.text = (cliente.descripcionNegocio ?? '')
          .toUpperCase();
      _origenValidacion = cliente.origenValidacion;
      _soloLectura = cliente.datosCongelados;
      _nombreComercialBloqueado = cliente.nombreComercialOficial;
      _camposExpandidos = true;
      if (cliente.datosCongelados && dniPrevio.isNotEmpty) {
        _ultimoDocumentoVerificado = dniPrevio;
      }
    }
  }

  @override
  void dispose() {
    _debounceVerificacion?.cancel();
    _nombresController.removeListener(_onNombresChanged);
    _dniController.removeListener(_onDocumentoEditado);
    _rucController.removeListener(_onDocumentoEditado);
    _dniController.removeListener(_onDocumentoCambiadoParaVerificacion);
    _rucController.removeListener(_onDocumentoCambiadoParaVerificacion);
    _dniController.dispose();
    _rucController.dispose();
    _nombresController.dispose();
    _apellidoPaternoController.dispose();
    _apellidoMaternoController.dispose();
    _telefonoController.dispose();
    _emailController.dispose();
    _direccionController.dispose();
    _descripcionNegocioController.dispose();
    _domicilioFiscalController.dispose();
    super.dispose();
  }

  // El botón "Registrar" reacciona en vivo a si ya hay un nombre escrito.
  void _onNombresChanged() => setState(() {});

  /// Si los nombres en pantalla vienen de una verificación exitosa y el
  /// usuario toca el número de documento (para corregirlo o borrarlo), esos
  /// nombres dejan de ser confiables: se limpian y quedan bloqueados
  /// (readOnly) hasta que una nueva búsqueda por API tenga éxito. Así la
  /// única forma de alterar un nombre autocompletado es corrigiendo el
  /// documento y volviendo a pulsar "Buscar", nunca escribiendo encima.
  void _onDocumentoEditado() {
    if (!_soloLectura) return;
    if (_documentoController.text == _ultimoDocumentoVerificado) return;
    setState(() {
      _nombresController.clear();
      _apellidoPaternoController.clear();
      _apellidoMaternoController.clear();
      if (_tipoDocumento == _TipoDocumento.ruc) {
        _descripcionNegocioController.clear();
        _domicilioFiscalController.clear();
        _nombreComercialBloqueado = false;
        _estadoRuc = null;
        _condicionRuc = null;
      }
      _origenValidacion = 'MANUAL';
      _documentoVerificadoApiReal = false;
      // _soloLectura se mantiene true a propósito: los campos siguen
      // bloqueados hasta la próxima búsqueda exitosa. "Dirección de
      // Entrega" no se toca: nunca vino de la API, es del vendedor.
    });
  }

  /// Se dispara con cada tecla en el campo de documento. Cuando el número
  /// alcanza su largo completo (8 para DNI, 11 para RUC) espera un breve
  /// instante (para no disparar una consulta por cada tecla mientras el
  /// vendedor sigue escribiendo) y recién ahí verifica localmente si ya
  /// pertenece a alguien registrado.
  void _onDocumentoCambiadoParaVerificacion() {
    _debounceVerificacion?.cancel();
    final texto = _documentoController.text.trim();
    final largoEsperado = _tipoDocumento == _TipoDocumento.dni ? 8 : 11;

    // Cualquier cambio en el número invalida la verificación anterior:
    // "Buscar" vuelve a quedar inactivo hasta confirmar de nuevo.
    if (_documentoVerificado || _documentoYaRegistrado) {
      setState(() {
        _documentoVerificado = false;
        _documentoYaRegistrado = false;
      });
    }

    if (texto.length != largoEsperado) return;

    _debounceVerificacion = Timer(
      const Duration(milliseconds: 400),
      () => _verificarDocumentoExistente(texto),
    );
  }

  Future<void> _verificarDocumentoExistente(String documento) async {
    setState(() => _verificandoDocumento = true);
    try {
      final resultado = await _clientesService.verificarDocumento(
        documento,
        excluirIdPersona: widget.clienteExistente?.idPersona,
      );
      if (!mounted || documento != _documentoController.text.trim()) return;
      setState(() {
        _documentoYaRegistrado = resultado.existe;
        _documentoVerificado = !resultado.existe;
      });
      if (resultado.existe) {
        await _mostrarDialogoDocumentoYaRegistrado(resultado);
      }
    } catch (_) {
      // Si la verificación local falla (ej. sin conexión), no atrapamos al
      // vendedor sin poder buscar nunca: se deja pasar (fail-open) y, si el
      // backend de verdad está caído, la búsqueda real lo dirá con su
      // propio mensaje de error.
      if (mounted && documento == _documentoController.text.trim()) {
        setState(() => _documentoVerificado = true);
      }
    } finally {
      if (mounted) setState(() => _verificandoDocumento = false);
    }
  }

  Future<void> _mostrarDialogoDocumentoYaRegistrado(
    DocumentoExistenteResult resultado,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final quien = resultado.nombreCompleto?.trim();
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          Icons.person_search_rounded,
          color: scheme.primary,
          size: 32,
        ),
        title: const Text('Documento ya registrado'),
        content: Text(
          quien != null && quien.isNotEmpty
              ? 'Este documento ya pertenece a $quien, quien ya está registrado en el sistema. Verifica antes de continuar.'
              : 'Este documento ya se encuentra registrado en el sistema. Verifica antes de continuar.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  bool get _puedeGuardar => _nombresController.text.trim().isNotEmpty;

  TextEditingController get _documentoController =>
      _tipoDocumento == _TipoDocumento.dni ? _dniController : _rucController;

  /// Tipo de contribuyente derivado del propio número de RUC (prefijo '10'
  /// = persona natural con negocio, '20' = persona jurídica), no de la
  /// respuesta de la API. Solo tiene sentido mostrarlo tras una búsqueda
  /// exitosa (ver el badge en build()).
  TipoContribuyenteRuc? get _tipoContribuyenteRuc {
    if (_tipoDocumento != _TipoDocumento.ruc) return null;
    final ruc = _rucController.text;
    if (ruc.startsWith('10')) return TipoContribuyenteRuc.personaNatural;
    if (ruc.startsWith('20')) return TipoContribuyenteRuc.personaJuridica;
    return null;
  }

  void _cambiarTipoDocumento(int index) {
    _debounceVerificacion?.cancel();
    setState(() {
      _origenValidacion = 'MANUAL';
      _documentoVerificadoApiReal = false;
      _soloLectura = false;
      _ultimoDocumentoVerificado = null;
      _tipoDocumento = index == 0 ? _TipoDocumento.dni : _TipoDocumento.ruc;
      _dniController.clear();
      _rucController.clear();
      _nombresController.clear();
      _camposExpandidos = false;
      _descripcionNegocioController.clear();
      _domicilioFiscalController.clear();
      _nombreComercialBloqueado = false;
      _estadoRuc = null;
      _condicionRuc = null;
      _documentoYaRegistrado = false;
      _documentoVerificado = false;
      _error = null;
    });
  }

  Future<void> _buscarDocumento() async {
    // Candado defensivo: el botón ya queda deshabilitado hasta que la
    // verificación local termine y confirme que no hay duplicado, pero esto
    // evita igual la llamada a la API real si algo lo dispara por otro
    // camino (p. ej. "manos rápidas" antes de que se actualice el estado).
    if (!_documentoVerificado || _documentoYaRegistrado) return;
    if (_tipoDocumento == _TipoDocumento.dni) {
      await _buscarDni();
    } else {
      await _buscarRucPrincipal();
    }
  }

  Future<void> _buscarDni() async {
    final dni = _dniController.text.trim();
    if (!RegExp(r'^\d{8}$').hasMatch(dni)) {
      setState(() => _error = 'Ingresa un DNI válido de 8 dígitos.');
      return;
    }

    setState(() {
      _buscando = true;
      _error = null;
    });

    try {
      final resultado = await _externalLookup.buscarPorDni(dni);
      setState(() {
        _nombresController.text = resultado.nombres.toUpperCase();
        _apellidoPaternoController.text = resultado.apellidoPaterno
            .toUpperCase();
        _apellidoMaternoController.text = resultado.apellidoMaterno
            .toUpperCase();
        _origenValidacion = 'RENIEC';
        _documentoVerificadoApiReal = resultado.esApiReal;
        _soloLectura = true;
        _ultimoDocumentoVerificado = dni;
        _camposExpandidos = true; // se despliega solo, sin pedir el ícono
      });
    } on ApiException catch (e) {
      if (e.statusCode == 404) {
        if (mounted) await _mostrarDialogoDocumentoNoEncontrado();
      } else {
        setState(() => _error = e.mensaje);
      }
    } finally {
      if (mounted) setState(() => _buscando = false);
    }
  }

  Future<void> _buscarRucPrincipal() async {
    final ruc = _rucController.text.trim();
    if (!RegExp(r'^\d{11}$').hasMatch(ruc)) {
      setState(() => _error = 'Ingresa un RUC válido de 11 dígitos.');
      return;
    }

    setState(() {
      _buscando = true;
      _error = null;
    });

    try {
      final resultado = await _externalLookup.buscarPorRuc(ruc);
      setState(() {
        _nombresController.text = resultado.razonSocial.toUpperCase();
        _apellidoPaternoController.clear();
        _apellidoMaternoController.clear();
        _origenValidacion = 'RENIEC';
        _documentoVerificadoApiReal = resultado.esApiReal;
        _soloLectura = true;
        _ultimoDocumentoVerificado = ruc;
        _camposExpandidos = true; // única forma de revelar el formulario RUC
        // Si SUNAT no tiene nombre comercial, se deja vacío y editable —
        // nunca se rellena con la razón social (el vendedor lo completa).
        // Si SÍ lo tiene, queda bloqueado (readOnly) para siempre.
        _descripcionNegocioController.text = resultado.nombreComercial
            .toUpperCase();
        _nombreComercialBloqueado = resultado.nombreComercial.isNotEmpty;
        // El domicilio fiscal es solo informativo (no se guarda); la
        // "Dirección de Entrega" la escribe el vendedor a mano, nunca se
        // autocompleta con el domicilio fiscal de SUNAT.
        _domicilioFiscalController.text = resultado.direccion.toUpperCase();
        _estadoRuc = resultado.estado.isNotEmpty ? resultado.estado : null;
        _condicionRuc = resultado.condicion.isNotEmpty
            ? resultado.condicion
            : null;
      });
    } on ApiException catch (e) {
      if (e.statusCode == 404) {
        if (mounted) await _mostrarDialogoDocumentoNoEncontrado();
      } else {
        setState(() => _error = e.mensaje);
      }
    } finally {
      if (mounted) setState(() => _buscando = false);
    }
  }

  Future<void> _mostrarDialogoDocumentoNoEncontrado() {
    final scheme = Theme.of(context).colorScheme;
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(Icons.search_off_rounded, color: scheme.error, size: 32),
        title: const Text('Documento no encontrado'),
        content: const Text(
          'El DNI/RUC ingresado no se encuentra registrado o es inválido. '
          'Por favor, verifique el número e intente de nuevo.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  void _expandirCampos() => setState(() => _camposExpandidos = true);

  Future<void> _autocompletarConGps() async {
    setState(() {
      _obteniendoUbicacion = true;
      _error = null;
    });
    try {
      final direccion = await _geolocationService.obtenerDireccionActual();
      setState(() => _direccionController.text = direccion.toUpperCase());
    } on GeolocationException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (_) {
      setState(
        () => _error = 'No se pudo obtener tu ubicación. Intenta nuevamente.',
      );
    } finally {
      if (mounted) setState(() => _obteniendoUbicacion = false);
    }
  }

  Future<void> _guardar() async {
    if (!_puedeGuardar) {
      setState(() => _error = 'Ingresa al menos los nombres para continuar.');
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _guardando = true;
      _error = null;
    });

    final input = ClienteInput(
      dni: _documentoController.text.trim().isEmpty
          ? null
          : _documentoController.text.trim(),
      nombres: _nombresController.text.trim(),
      apellidoPaterno: _apellidoPaternoController.text.trim(),
      apellidoMaterno: _apellidoMaternoController.text.trim().isEmpty
          ? null
          : _apellidoMaternoController.text.trim(),
      telefono: _telefonoController.text.trim().isEmpty
          ? null
          : _telefonoController.text.trim(),
      email: _emailController.text.trim().isEmpty
          ? null
          : _emailController.text.trim(),
      direccion: _direccionController.text.trim().isEmpty
          ? null
          : _direccionController.text.trim(),
      descripcionNegocio: _descripcionNegocioController.text.trim().isEmpty
          ? null
          : _descripcionNegocioController.text.trim(),
      nombreComercialOficial: _nombreComercialBloqueado,
      origenValidacion: _origenValidacion,
      dniVerificadoApiReal: _documentoVerificadoApiReal,
    );

    try {
      bool cuentaClonada = false;
      if (_editando) {
        cuentaClonada = await _clientesService.actualizar(
          widget.clienteExistente!.idCliente,
          input,
        );
      } else {
        cuentaClonada = await _clientesService.crear(input);
      }
      if (!mounted) return;
      if (cuentaClonada) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Se creó automáticamente una cuenta de acceso para el cliente (usuario: ${input.dni}).',
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (_) {
      setState(
        () => _error = 'Ocurrió un error inesperado. Intenta nuevamente.',
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Widget _badgeChip(String label, Color color) {
    return Chip(
      label: Text(label),
      backgroundColor: color,
      labelStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
      visualDensity: VisualDensity.compact,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final esRuc = _tipoDocumento == _TipoDocumento.ruc;
    // En modo RUC nada de "Razón social" en adelante se muestra hasta que
    // la búsqueda tenga éxito; en modo DNI, "Nombres" siempre es visible.
    final mostrarNombres = _editando || !esRuc || _camposExpandidos;
    final mostrarBotonExpandir = !_editando && !esRuc && !_camposExpandidos;
    final permiteReverificar = _permiteReverificar;

    return Scaffold(
      appBar: AppBar(
        title: Text(_editando ? 'Editar cliente' : 'Nuevo cliente'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (permiteReverificar) ...[
                  Text(
                    _editando
                        ? 'Este cliente aún no tiene un documento verificado. Puedes buscarlo para validar sus datos oficiales.'
                        : 'Elige el documento y búscalo para autocompletar y validar los datos',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  SegmentedSwitch(
                    opciones: const ['DNI', 'RUC'],
                    indiceSeleccionado: esRuc ? 1 : 0,
                    onChanged: _cambiarTipoDocumento,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: ValueKey(_tipoDocumento),
                          controller: _documentoController,
                          enabled: !_buscando,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          maxLength: esRuc ? 11 : 8,
                          decoration: InputDecoration(
                            labelText: esRuc ? 'RUC' : 'DNI',
                            counterText: '',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: FilledButton.icon(
                          onPressed: (_buscando || !_documentoVerificado)
                              ? null
                              : _buscarDocumento,
                          icon: _buscando
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.search_rounded, size: 18),
                          label: const Text('Buscar'),
                        ),
                      ),
                    ],
                  ),
                  if (_verificandoDocumento) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Verificando si ya está registrado...',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ],
                  if (_documentoYaRegistrado) ...[
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.person_search_rounded,
                          size: 16,
                          color: scheme.error,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Este documento ya está registrado en el sistema.',
                            style: TextStyle(
                              color: scheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (_origenValidacion == 'RENIEC' && _camposExpandidos) ...[
                    const SizedBox(height: 8),
                    Chip(
                      avatar: Icon(
                        _documentoVerificadoApiReal
                            ? Icons.verified_rounded
                            : Icons.wifi_off_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                      label: Text(
                        _documentoVerificadoApiReal
                            ? 'Validado por ${esRuc ? 'SUNAT' : 'RENIEC'} (API real)'
                            : 'Validado por ${esRuc ? 'SUNAT' : 'RENIEC'} (simulado)',
                      ),
                      backgroundColor: const Color(0xFF2563EB),
                      labelStyle: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_documentoVerificadoApiReal) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Se creará automáticamente una cuenta de acceso para este cliente.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                    if (esRuc) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (_tipoContribuyenteRuc ==
                              TipoContribuyenteRuc.personaNatural)
                            _badgeChip(
                              'Persona Natural con Negocio',
                              const Color(0xFFB08D57),
                            ),
                          if (_tipoContribuyenteRuc ==
                              TipoContribuyenteRuc.personaJuridica)
                            _badgeChip(
                              'Persona Jurídica / Empresa',
                              const Color(0xFF3E2723),
                            ),
                          if (_estadoRuc != null)
                            _badgeChip(
                              'Estado: $_estadoRuc',
                              _estadoRuc == 'ACTIVO'
                                  ? const Color(0xFF2E7D32)
                                  : const Color(0xFFC62828),
                            ),
                          if (_condicionRuc != null)
                            _badgeChip(
                              'Condición: $_condicionRuc',
                              _condicionRuc == 'HABIDO'
                                  ? const Color(0xFF2E7D32)
                                  : const Color(0xFFC62828),
                            ),
                        ],
                      ),
                    ],
                  ],
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: scheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (mostrarNombres) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _nombresController,
                    readOnly: _soloLectura,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: const [UpperCaseTextFormatter()],
                    decoration: InputDecoration(
                      labelText: esRuc ? 'Razón social' : 'Nombres',
                      prefixIcon: Icon(
                        esRuc
                            ? Icons.storefront_outlined
                            : Icons.person_outline_rounded,
                      ),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Ingresa ${esRuc ? 'la razón social' : 'los nombres'}'
                        : null,
                  ),
                ],
                if (mostrarBotonExpandir) ...[
                  const SizedBox(height: 12),
                  Center(
                    child:
                        Material(
                              color: scheme.secondaryContainer,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: _expandirCampos,
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Icon(
                                    Icons.keyboard_double_arrow_down_rounded,
                                    color: scheme.primary,
                                    size: 26,
                                  ),
                                ),
                              ),
                            )
                            .animate(onPlay: (c) => c.repeat(reverse: true))
                            .moveY(
                              begin: 0,
                              end: 6,
                              duration: 700.ms,
                              curve: Curves.easeInOut,
                            ),
                  ),
                  Center(
                    child: Text('Más datos', style: theme.textTheme.bodyMedium),
                  ),
                ],
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  alignment: Alignment.topCenter,
                  child: !_camposExpandidos
                      ? const SizedBox(width: double.infinity)
                      : Column(
                          key: const ValueKey('campos-expandidos'),
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (!esRuc) ...[
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _apellidoPaternoController,
                                readOnly: _soloLectura,
                                textCapitalization:
                                    TextCapitalization.characters,
                                inputFormatters: const [
                                  UpperCaseTextFormatter(),
                                ],
                                decoration: const InputDecoration(
                                  labelText: 'Apellido paterno',
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _apellidoMaternoController,
                                readOnly: _soloLectura,
                                textCapitalization:
                                    TextCapitalization.characters,
                                inputFormatters: const [
                                  UpperCaseTextFormatter(),
                                ],
                                decoration: const InputDecoration(
                                  labelText: 'Apellido materno',
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _telefonoController,
                              keyboardType: TextInputType.phone,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Teléfono',
                                prefixIcon: Icon(Icons.phone_outlined),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                prefixIcon: Icon(Icons.email_outlined),
                              ),
                            ),
                            if (esRuc &&
                                _domicilioFiscalController.text.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _domicilioFiscalController,
                                readOnly: true,
                                decoration: const InputDecoration(
                                  labelText: 'Domicilio Fiscal (SUNAT)',
                                  prefixIcon: Icon(
                                    Icons.account_balance_outlined,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _direccionController,
                              textCapitalization: TextCapitalization.characters,
                              inputFormatters: const [UpperCaseTextFormatter()],
                              decoration: InputDecoration(
                                labelText: 'Dirección de Entrega',
                                prefixIcon: const Icon(Icons.place_outlined),
                                suffixIcon:
                                    IconButton(
                                          tooltip: 'Usar mi ubicación GPS',
                                          onPressed: _obteniendoUbicacion
                                              ? null
                                              : _autocompletarConGps,
                                          icon: _obteniendoUbicacion
                                              ? const SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                )
                                              : Icon(
                                                  Icons.my_location_rounded,
                                                  color: scheme.primary,
                                                ),
                                        )
                                        .animate(
                                          onPlay: (c) =>
                                              c.repeat(reverse: true),
                                        )
                                        .scale(
                                          begin: const Offset(1, 1),
                                          end: const Offset(1.12, 1.12),
                                          duration: 900.ms,
                                          curve: Curves.easeInOut,
                                        ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _descripcionNegocioController,
                              // En DNI siempre se escribe a mano. En RUC se
                              // bloquea SOLO si el nombre comercial vino de
                              // una búsqueda exitosa contra SUNAT — si SUNAT
                              // no tenía uno registrado, sigue editable.
                              readOnly: esRuc && _nombreComercialBloqueado,
                              textCapitalization: TextCapitalization.characters,
                              inputFormatters: const [UpperCaseTextFormatter()],
                              decoration: InputDecoration(
                                labelText: 'Nombre comercial / Puesto',
                                prefixIcon: const Icon(
                                  Icons.storefront_outlined,
                                ),
                                suffixIcon: esRuc && _nombreComercialBloqueado
                                    ? Icon(
                                        Icons.lock_outline_rounded,
                                        color: scheme.primary,
                                        size: 18,
                                      )
                                    : null,
                              ),
                              maxLines: 2,
                            ),
                          ],
                        ).animate().fadeIn(duration: 250.ms),
                ),
                const SizedBox(height: 24),
                PremiumButton(
                  label: _editando ? 'Guardar cambios' : 'Registrar cliente',
                  icono: Icons.check_rounded,
                  cargando: _guardando,
                  onPressed: _puedeGuardar ? _guardar : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
