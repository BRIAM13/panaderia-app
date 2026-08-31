import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../services/api_client.dart';
import '../services/clientes_service.dart';
import '../theme/app_theme.dart';

/// Debe calzar con `SEGUNDOS_COOLDOWN` en `otpService.js` (backend) — ahí
/// vive la regla real; esto solo evita mostrarle al usuario un botón de
/// reenviar que el backend va a rechazar con COOLDOWN de todas formas.
const _segundosCooldownReenvio = 60;

class _OpcionCanal extends StatelessWidget {
  const _OpcionCanal({
    required this.icono,
    required this.texto,
    required this.seleccionado,
    required this.onTap,
  });

  final IconData icono;
  final String texto;
  final bool seleccionado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = seleccionado ? AppColors.primary : AppColors.textSecondary;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: seleccionado
                ? AppColors.primary.withValues(alpha: 0.10)
                : Colors.transparent,
            border: Border.all(
              color: seleccionado
                  ? AppColors.primary.withValues(alpha: 0.35)
                  : AppColors.textSecondary.withValues(alpha: 0.20),
            ),
          ),
          child: Row(
            children: [
              PhosphorIcon(
                seleccionado
                    ? PhosphorIconsFill.radioButton
                    : PhosphorIconsRegular.circle,
                color: color,
                size: 20,
              ),
              const SizedBox(width: 10),
              PhosphorIcon(icono, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(texto, style: TextStyle(color: color)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Resultado de una autorización exitosa (código confirmado contra un canal
/// YA verificado) — se reenvía tal cual a los endpoints que la exigen para
/// completar un cambio sensible (celular, correo, contraseña).
class AutorizacionResultado {
  const AutorizacionResultado({required this.canal, required this.codigo});

  final String canal; // 'SMS' | 'EMAIL'
  final String codigo;
}

/// Campo de código de 6 dígitos con casillas individuales, pensado para que
/// completar el código sea lo más rápido posible:
/// - 6 `TextField` reales, uno por dígito, con auto-avance de foco al
///   escribir y retroceso al borrar en una casilla vacía.
/// - Pegar un código completo (en cualquier casilla, o con el botón
///   explícito) lo reparte solo en las 6 casillas.
/// - Al completarse el 6to dígito, notifica una sola vez vía [onCompletado]
///   — quien lo use puede auto-confirmar sin que el usuario toque un botón.
/// - Animación de sacudida cuando el código resulta inválido.
class _CodigoOtpInput extends StatefulWidget {
  const _CodigoOtpInput({
    required this.controller,
    required this.onCompletado,
    this.autofocus = false,
    this.tieneError = false,
    this.habilitado = true,
  });

  final TextEditingController controller;
  final ValueChanged<String> onCompletado;
  final bool autofocus;
  final bool tieneError;
  final bool habilitado;

  @override
  State<_CodigoOtpInput> createState() => _CodigoOtpInputState();
}

const _cantidadDigitos = 6;

class _CodigoOtpInputState extends State<_CodigoOtpInput>
    with SingleTickerProviderStateMixin {
  // 6 campos reales (uno por dígito) en vez de un campo invisible superpuesto
  // sobre casillas dibujadas encima: se probó esa versión en dispositivo
  // real (Samsung, backend Impeller/Vulkan) y el diálogo se renderizaba
  // completamente en blanco — un `Opacity(opacity:0)` + `Stack` con un
  // `TextField` enfocado autofocus encima de casillas pintadas puede estar
  // pisando el compositing en ese backend. Este patrón (campos reales) es
  // el estándar probado para OTP en Flutter, sin ese riesgo.
  late final List<TextEditingController> _subControllers;
  late final List<FocusNode> _subFocos;
  late final AnimationController _sacudidaController;
  bool _sincronizando = false;

  @override
  void initState() {
    super.initState();
    _subControllers = List.generate(
      _cantidadDigitos,
      (_) => TextEditingController(),
    );
    _subFocos = List.generate(_cantidadDigitos, (_) => FocusNode());
    _sacudidaController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _distribuirEnCampos(widget.controller.text);
    widget.controller.addListener(_alCambiarControladorExterno);
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _subFocos.first.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(covariant _CodigoOtpInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tieneError && !oldWidget.tieneError) {
      _sacudidaController.forward(from: 0);
    }
  }

  String get _codigoActual => _subControllers.map((c) => c.text).join();

  /// El controller externo es la fuente de verdad para quien use este
  /// widget desde afuera (ej. limpiarlo tras un código incorrecto). Cuando
  /// cambia por fuera, se refleja en los 6 campos sin volver a notificar
  /// hacia afuera (evita un ciclo infinito con [_notificarSiCompleto]).
  void _alCambiarControladorExterno() {
    if (_sincronizando) return;
    if (widget.controller.text == _codigoActual) return;
    _distribuirEnCampos(widget.controller.text);
  }

  void _distribuirEnCampos(String texto) {
    final digitos = texto.replaceAll(RegExp(r'[^0-9]'), '');
    setState(() {
      for (var i = 0; i < _cantidadDigitos; i++) {
        _subControllers[i].text = i < digitos.length ? digitos[i] : '';
      }
    });
  }

  void _notificarSiCompleto() {
    final codigo = _codigoActual;
    _sincronizando = true;
    widget.controller.text = codigo;
    _sincronizando = false;
    if (codigo.length == _cantidadDigitos) {
      widget.onCompletado(codigo);
    }
  }

  /// Pegar puede llegar de dos formas: el usuario pega dentro de un solo
  /// campo (Android suele meter todo el texto ahí) o usa el botón "Pegar
  /// código" explícito — ambos casos terminan aquí.
  void _alCambiarCampo(int indice, String valor) {
    final soloDigitos = valor.replaceAll(RegExp(r'[^0-9]'), '');

    if (soloDigitos.length > 1) {
      // Se pegó más de un dígito en este campo: se reparte desde acá.
      setState(() {
        var cursor = indice;
        for (final digito in soloDigitos.split('')) {
          if (cursor >= _cantidadDigitos) break;
          _subControllers[cursor].text = digito;
          cursor++;
        }
      });
      final siguiente = (indice + soloDigitos.length).clamp(
        0,
        _cantidadDigitos - 1,
      );
      _subFocos[siguiente].requestFocus();
      _notificarSiCompleto();
      return;
    }

    setState(() => _subControllers[indice].text = soloDigitos);
    if (soloDigitos.isNotEmpty && indice < _cantidadDigitos - 1) {
      _subFocos[indice + 1].requestFocus();
    }
    _notificarSiCompleto();
  }

  void _alPresionarBackspaceVacio(int indice) {
    if (indice == 0) return;
    _subFocos[indice - 1].requestFocus();
    setState(() => _subControllers[indice - 1].text = '');
    _notificarSiCompleto();
  }

  Future<void> _pegarDesdePortapapeles() async {
    final datos = await Clipboard.getData(Clipboard.kTextPlain);
    final texto = datos?.text;
    if (texto == null) return;
    final soloDigitos = texto.replaceAll(RegExp(r'[^0-9]'), '');
    if (soloDigitos.isEmpty) return;
    final codigo = soloDigitos.length > _cantidadDigitos
        ? soloDigitos.substring(0, _cantidadDigitos)
        : soloDigitos;
    _distribuirEnCampos(codigo);
    _notificarSiCompleto();
    final siguiente = (codigo.length).clamp(0, _cantidadDigitos - 1);
    _subFocos[siguiente].requestFocus();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_alCambiarControladorExterno);
    for (final c in _subControllers) {
      c.dispose();
    }
    for (final f in _subFocos) {
      f.dispose();
    }
    _sacudidaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AnimatedBuilder(
          animation: _sacudidaController,
          builder: (context, child) {
            // Sacudida horizontal amortiguada: rápida al inicio, se apaga
            // hacia el final — señal clara de "código incorrecto" sin
            // necesidad de leer el texto de error para entenderlo.
            final t = _sacudidaController.value;
            final desplazamiento = math.sin(t * math.pi * 6) * (1 - t) * 10;
            return Transform.translate(
              offset: Offset(desplazamiento, 0),
              child: child,
            );
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_cantidadDigitos, (i) {
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
                  child: _CasillaDigito(
                    controller: _subControllers[i],
                    focusNode: _subFocos[i],
                    habilitado: widget.habilitado,
                    tieneError: widget.tieneError,
                    onChanged: (valor) => _alCambiarCampo(i, valor),
                    onBackspaceVacio: () => _alPresionarBackspaceVacio(i),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: widget.habilitado ? _pegarDesdePortapapeles : null,
          icon: const PhosphorIcon(
            PhosphorIconsRegular.clipboardText,
            size: 18,
          ),
          label: const Text('Pegar código'),
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            foregroundColor: AppColors.secondary,
          ),
        ),
      ],
    );
  }
}

/// Una sola casilla del código — campo de texto real (no dibujo encima de
/// otro campo), con su propio borde que reacciona a foco/error.
class _CasillaDigito extends StatelessWidget {
  const _CasillaDigito({
    required this.controller,
    required this.focusNode,
    required this.habilitado,
    required this.tieneError,
    required this.onChanged,
    required this.onBackspaceVacio,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool habilitado;
  final bool tieneError;
  final ValueChanged<String> onChanged;
  final VoidCallback onBackspaceVacio;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 0.8,
      child: KeyboardListener(
        focusNode: FocusNode(skipTraversal: true, canRequestFocus: false),
        onKeyEvent: (event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.backspace &&
              controller.text.isEmpty) {
            onBackspaceVacio();
          }
        },
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          enabled: habilitado,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          maxLength: _cantidadDigitos, // permite que llegue un pegado largo
          onChanged: onChanged,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            counterText: '',
            contentPadding: EdgeInsets.zero,
            filled: true,
            fillColor: tieneError
                ? AppColors.error.withValues(alpha: 0.06)
                : AppColors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: AppColors.textSecondary.withValues(alpha: 0.25),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: tieneError
                    ? AppColors.error
                    : controller.text.isNotEmpty
                    ? AppColors.primary.withValues(alpha: 0.45)
                    : AppColors.textSecondary.withValues(alpha: 0.25),
                width: tieneError ? 2 : 1.2,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: tieneError ? AppColors.error : AppColors.primary,
                width: 2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paso compartido de "ingresa el código de 6 dígitos", reutilizado por los
/// dos flujos (verificar canal / autorizar cambio) para no duplicar la
/// lógica de auto-envío, temporizador de reenvío y sacudida de error.
class _PasoIngresarCodigo extends StatelessWidget {
  const _PasoIngresarCodigo({
    required this.canalTexto,
    required this.controller,
    required this.cargando,
    required this.tieneError,
    required this.segundosParaReenviar,
    required this.onReenviar,
    required this.onCompletado,
  });

  final String canalTexto; // 'correo' | 'SMS'
  final TextEditingController controller;
  final bool cargando;
  final bool tieneError;
  final int segundosParaReenviar;
  final VoidCallback onReenviar;
  final ValueChanged<String> onCompletado;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Ingresa el código de 6 dígitos enviado por $canalTexto.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        _CodigoOtpInput(
          controller: controller,
          onCompletado: onCompletado,
          autofocus: true,
          tieneError: tieneError,
          habilitado: !cargando,
        ),
        const SizedBox(height: 4),
        if (cargando)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
          )
        else if (segundosParaReenviar > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Reenviar en ${segundosParaReenviar}s',
              style: TextStyle(
                color: AppColors.textSecondary.withValues(alpha: 0.8),
                fontSize: 13,
              ),
            ),
          )
        else
          TextButton(
            onPressed: onReenviar,
            child: const Text('Reenviar código'),
          ),
      ],
    );
  }
}

/// Pide autorización para un cambio sensible: envía un código al canal YA
/// verificado que el cliente elija (o al único disponible), lo confirma, y
/// devuelve el [AutorizacionResultado] listo para pasar al endpoint real.
/// Devuelve `null` si el cliente cancela en cualquier paso.
Future<AutorizacionResultado?> mostrarAutorizacionCambio(
  BuildContext context, {
  required bool telefonoVerificado,
  required bool emailVerificado,
  required ClientesService clientesService,
  String titulo = 'Autoriza este cambio',
}) {
  return showDialog<AutorizacionResultado>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _AutorizacionCambioDialog(
      telefonoVerificado: telefonoVerificado,
      emailVerificado: emailVerificado,
      clientesService: clientesService,
      titulo: titulo,
    ),
  );
}

class _AutorizacionCambioDialog extends StatefulWidget {
  const _AutorizacionCambioDialog({
    required this.telefonoVerificado,
    required this.emailVerificado,
    required this.clientesService,
    required this.titulo,
  });

  final bool telefonoVerificado;
  final bool emailVerificado;
  final ClientesService clientesService;
  final String titulo;

  @override
  State<_AutorizacionCambioDialog> createState() =>
      _AutorizacionCambioDialogState();
}

class _AutorizacionCambioDialogState extends State<_AutorizacionCambioDialog> {
  final _codigoController = TextEditingController();
  String? _canalElegido;
  bool _codigoEnviado = false;
  bool _cargando = false;
  bool _confirmando = false;
  bool _tieneError = false;
  String? _error;
  Timer? _timerReenvio;
  int _segundosParaReenviar = 0;

  @override
  void initState() {
    super.initState();
    // Si solo tiene un canal verificado, se elige automáticamente — no
    // tiene sentido preguntar cuando no hay elección real.
    if (widget.telefonoVerificado && !widget.emailVerificado) {
      _canalElegido = 'SMS';
    } else if (!widget.telefonoVerificado && widget.emailVerificado) {
      _canalElegido = 'EMAIL';
    }
  }

  @override
  void dispose() {
    _timerReenvio?.cancel();
    _codigoController.dispose();
    super.dispose();
  }

  void _iniciarCooldownReenvio() {
    _timerReenvio?.cancel();
    setState(() => _segundosParaReenviar = _segundosCooldownReenvio);
    _timerReenvio = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _segundosParaReenviar--;
        if (_segundosParaReenviar <= 0) timer.cancel();
      });
    });
  }

  Future<void> _enviarCodigo() async {
    if (_canalElegido == null) return;
    setState(() {
      _cargando = true;
      _error = null;
      _tieneError = false;
    });
    try {
      await widget.clientesService.solicitarAutorizacion(canal: _canalElegido!);
      setState(() => _codigoEnviado = true);
      _iniciarCooldownReenvio();
    } on ApiException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (_) {
      setState(
        () => _error = 'Ocurrió un error inesperado. Intenta nuevamente.',
      );
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _confirmar([String? codigoCompletado]) async {
    final codigo = (codigoCompletado ?? _codigoController.text).trim();
    if (codigo.length != 6) {
      setState(() {
        _error = 'Ingresa el código de 6 dígitos.';
        _tieneError = true;
      });
      return;
    }
    setState(() {
      _confirmando = true;
      _error = null;
      _tieneError = false;
    });
    try {
      // Se valida YA (sin gastar el código: el endpoint real que lo
      // consume es el que hace el cambio de verdad, más adelante) — así,
      // si el código es incorrecto, el error se ve aquí mismo en vez de
      // dejar avanzar cualquier código y recién fallar en el siguiente
      // paso, que se sentía como "aceptó un código cualquiera".
      await widget.clientesService.validarAutorizacion(
        canal: _canalElegido!,
        codigo: codigo,
      );
      if (!mounted) return;
      Navigator.of(
        context,
      ).pop(AutorizacionResultado(canal: _canalElegido!, codigo: codigo));
    } on ApiException catch (e) {
      setState(() {
        _error = e.mensaje;
        _tieneError = true;
        _codigoController.clear();
      });
    } catch (_) {
      setState(() {
        _error = 'Ocurrió un error inesperado. Intenta nuevamente.';
        _tieneError = true;
        _codigoController.clear();
      });
    } finally {
      if (mounted) setState(() => _confirmando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      // SingleChildScrollView: con el teclado abierto (necesario para el
      // paso del código) la altura disponible del diálogo se reduce mucho
      // — probado en dispositivo real, sin esto el contenido se desborda
      // por debajo (overflow) en vez de simplemente poder desplazarse.
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!_codigoEnviado) ...[
              const Text(
                'Elige a dónde te enviamos el código de autorización:',
              ),
              const SizedBox(height: 12),
              if (widget.telefonoVerificado)
                _OpcionCanal(
                  icono: PhosphorIconsRegular.chatCircleDots,
                  texto: 'Por SMS a mi celular verificado',
                  seleccionado: _canalElegido == 'SMS',
                  onTap: () => setState(() => _canalElegido = 'SMS'),
                ),
              if (widget.telefonoVerificado && widget.emailVerificado)
                const SizedBox(height: 8),
              if (widget.emailVerificado)
                _OpcionCanal(
                  icono: PhosphorIconsRegular.envelopeSimple,
                  texto: 'Por correo a mi email verificado',
                  seleccionado: _canalElegido == 'EMAIL',
                  onTap: () => setState(() => _canalElegido = 'EMAIL'),
                ),
            ] else
              _PasoIngresarCodigo(
                canalTexto: _canalElegido == 'SMS' ? 'SMS' : 'correo',
                controller: _codigoController,
                cargando: _cargando || _confirmando,
                tieneError: _tieneError,
                segundosParaReenviar: _segundosParaReenviar,
                onReenviar: _enviarCodigo,
                onCompletado: (codigo) => _confirmar(codigo),
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: (_cargando || _confirmando)
              ? null
              : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        if (!_codigoEnviado)
          FilledButton(
            onPressed: (_cargando || _canalElegido == null)
                ? null
                : _enviarCodigo,
            child: _cargando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Enviar código'),
          )
        else
          FilledButton(
            onPressed: _confirmando ? null : () => _confirmar(),
            child: _confirmando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Continuar'),
          ),
      ],
    );
  }
}

/// Pide verificar un celular o correo NUEVO (primera vez o cambio) con un
/// código enviado a ese mismo valor. Si [autorizacion] viene informado, se
/// reenvía junto con la solicitud (necesario cuando el cliente ya tiene
/// algún canal verificado). Devuelve `true` si se verificó y guardó
/// correctamente.
Future<bool> mostrarVerificarCanal(
  BuildContext context, {
  required String canal, // 'SMS' | 'EMAIL'
  required ClientesService clientesService,
  AutorizacionResultado? autorizacion,
  String? valorInicial,
}) async {
  final resultado = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _VerificarCanalDialog(
      canal: canal,
      clientesService: clientesService,
      autorizacion: autorizacion,
      valorInicial: valorInicial,
    ),
  );
  return resultado ?? false;
}

class _VerificarCanalDialog extends StatefulWidget {
  const _VerificarCanalDialog({
    required this.canal,
    required this.clientesService,
    this.autorizacion,
    this.valorInicial,
  });

  final String canal;
  final ClientesService clientesService;
  final AutorizacionResultado? autorizacion;
  final String? valorInicial;

  @override
  State<_VerificarCanalDialog> createState() => _VerificarCanalDialogState();
}

class _VerificarCanalDialogState extends State<_VerificarCanalDialog> {
  final _valorController = TextEditingController();
  final _codigoController = TextEditingController();
  bool _codigoEnviado = false;
  bool _cargando = false;
  bool _confirmando = false;
  bool _tieneError = false;
  String? _error;
  Timer? _timerReenvio;
  int _segundosParaReenviar = 0;

  bool get _esSms => widget.canal == 'SMS';

  @override
  void initState() {
    super.initState();
    if (widget.valorInicial != null) {
      _valorController.text = widget.valorInicial!;
    }
  }

  @override
  void dispose() {
    _timerReenvio?.cancel();
    _valorController.dispose();
    _codigoController.dispose();
    super.dispose();
  }

  void _iniciarCooldownReenvio() {
    _timerReenvio?.cancel();
    setState(() => _segundosParaReenviar = _segundosCooldownReenvio);
    _timerReenvio = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _segundosParaReenviar--;
        if (_segundosParaReenviar <= 0) timer.cancel();
      });
    });
  }

  Future<void> _enviarCodigo() async {
    final valor = _valorController.text.trim();
    if (valor.isEmpty) {
      setState(
        () => _error = _esSms
            ? 'Ingresa tu número de celular.'
            : 'Ingresa tu correo.',
      );
      return;
    }
    setState(() {
      _cargando = true;
      _error = null;
      _tieneError = false;
    });
    try {
      if (_esSms) {
        await widget.clientesService.solicitarCodigoCelular(
          telefonoNuevo: valor,
          canalAutorizacion: widget.autorizacion?.canal,
          codigoAutorizacion: widget.autorizacion?.codigo,
        );
      } else {
        await widget.clientesService.solicitarCodigoCorreo(
          emailNuevo: valor,
          canalAutorizacion: widget.autorizacion?.canal,
          codigoAutorizacion: widget.autorizacion?.codigo,
        );
      }
      setState(() => _codigoEnviado = true);
      _iniciarCooldownReenvio();
    } on ApiException catch (e) {
      setState(() => _error = e.mensaje);
    } catch (_) {
      setState(
        () => _error = 'Ocurrió un error inesperado. Intenta nuevamente.',
      );
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _confirmarCodigo([String? codigoCompletado]) async {
    final codigo = (codigoCompletado ?? _codigoController.text).trim();
    if (codigo.length != 6) {
      setState(() {
        _error = 'Ingresa el código de 6 dígitos.';
        _tieneError = true;
      });
      return;
    }
    setState(() {
      _confirmando = true;
      _error = null;
      _tieneError = false;
    });
    try {
      final valor = _valorController.text.trim();
      if (_esSms) {
        await widget.clientesService.confirmarCodigoCelular(
          telefonoNuevo: valor,
          codigo: codigo,
        );
      } else {
        await widget.clientesService.confirmarCodigoCorreo(
          emailNuevo: valor,
          codigo: codigo,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() {
        _error = e.mensaje;
        _tieneError = true;
        // Se limpia para que el usuario reintente directo, sin tener que
        // borrar un código que ya sabe que está mal.
        _codigoController.clear();
      });
    } catch (_) {
      setState(() {
        _error = 'Ocurrió un error inesperado. Intenta nuevamente.';
        _tieneError = true;
        _codigoController.clear();
      });
    } finally {
      if (mounted) setState(() => _confirmando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_esSms ? 'Verificar celular' : 'Verificar correo'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!_codigoEnviado) ...[
              Text(
                _esSms
                    ? 'Te enviaremos un código por SMS para confirmar que este número es tuyo.'
                    : 'Te enviaremos un código por correo para confirmar que este email es tuyo.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _valorController,
                keyboardType: _esSms
                    ? TextInputType.phone
                    : TextInputType.emailAddress,
                inputFormatters: _esSms
                    ? [FilteringTextInputFormatter.digitsOnly]
                    : null,
                decoration: InputDecoration(
                  labelText: _esSms
                      ? 'Número de celular'
                      : 'Correo electrónico',
                  prefixIcon: PhosphorIcon(
                    _esSms
                        ? PhosphorIconsRegular.phone
                        : PhosphorIconsRegular.envelopeSimple,
                  ),
                ),
              ),
            ] else
              _PasoIngresarCodigo(
                canalTexto: _esSms ? 'SMS' : 'correo',
                controller: _codigoController,
                cargando: _confirmando,
                tieneError: _tieneError,
                segundosParaReenviar: _segundosParaReenviar,
                onReenviar: _enviarCodigo,
                onCompletado: (codigo) => _confirmarCodigo(codigo),
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: (_cargando || _confirmando)
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        if (!_codigoEnviado)
          FilledButton(
            onPressed: _cargando ? null : _enviarCodigo,
            child: _cargando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Enviar código'),
          )
        else
          FilledButton(
            onPressed: _confirmando ? null : () => _confirmarCodigo(),
            child: _confirmando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Confirmar'),
          ),
      ],
    );
  }
}
