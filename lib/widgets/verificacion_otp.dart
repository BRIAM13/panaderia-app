import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_client.dart';
import '../services/clientes_service.dart';
import '../theme/app_theme.dart';

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
    final color = seleccionado
        ? AppColors.primary
        : AppColors.textSecondary;

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
              Icon(
                seleccionado
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: color,
                size: 20,
              ),
              const SizedBox(width: 10),
              Icon(icono, color: color, size: 20),
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

/// Campo de 6 dígitos con espaciado grande, reutilizado por ambos flujos de
/// código (verificar canal / autorizar cambio).
class _CampoCodigoOtp extends StatelessWidget {
  const _CampoCodigoOtp({required this.controller, this.autofocus = false});

  final TextEditingController controller;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(6),
      ],
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 28,
        letterSpacing: 12,
        fontWeight: FontWeight.w700,
      ),
      decoration: const InputDecoration(
        counterText: '',
        hintText: '000000',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      maxLength: 6,
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
  String? _error;

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
    _codigoController.dispose();
    super.dispose();
  }

  Future<void> _enviarCodigo() async {
    if (_canalElegido == null) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      await widget.clientesService.solicitarAutorizacion(canal: _canalElegido!);
      setState(() => _codigoEnviado = true);
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

  Future<void> _confirmar() async {
    final codigo = _codigoController.text.trim();
    if (codigo.length != 6) {
      setState(() => _error = 'Ingresa el código de 6 dígitos.');
      return;
    }
    // La verificación real ocurre en el endpoint que consume este
    // resultado (ej. cambiar celular) — aquí solo se recolecta el código.
    Navigator.of(
      context,
    ).pop(AutorizacionResultado(canal: _canalElegido!, codigo: codigo));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_codigoEnviado) ...[
            const Text('Elige a dónde te enviamos el código de autorización:'),
            const SizedBox(height: 12),
            if (widget.telefonoVerificado)
              _OpcionCanal(
                icono: Icons.sms_rounded,
                texto: 'Por SMS a mi celular verificado',
                seleccionado: _canalElegido == 'SMS',
                onTap: () => setState(() => _canalElegido = 'SMS'),
              ),
            if (widget.telefonoVerificado && widget.emailVerificado)
              const SizedBox(height: 8),
            if (widget.emailVerificado)
              _OpcionCanal(
                icono: Icons.email_rounded,
                texto: 'Por correo a mi email verificado',
                seleccionado: _canalElegido == 'EMAIL',
                onTap: () => setState(() => _canalElegido = 'EMAIL'),
              ),
          ] else ...[
            Text(
              'Ingresa el código de 6 dígitos enviado por ${_canalElegido == 'SMS' ? 'SMS' : 'correo'}.',
            ),
            const SizedBox(height: 12),
            _CampoCodigoOtp(controller: _codigoController, autofocus: true),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _cargando ? null : () => Navigator.of(context).pop(),
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
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Enviar código'),
          )
        else
          FilledButton(onPressed: _confirmar, child: const Text('Continuar')),
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
  String? _error;

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
    _valorController.dispose();
    _codigoController.dispose();
    super.dispose();
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

  Future<void> _confirmarCodigo() async {
    final codigo = _codigoController.text.trim();
    if (codigo.length != 6) {
      setState(() => _error = 'Ingresa el código de 6 dígitos.');
      return;
    }
    setState(() {
      _cargando = true;
      _error = null;
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
      setState(() => _error = e.mensaje);
    } catch (_) {
      setState(
        () => _error = 'Ocurrió un error inesperado. Intenta nuevamente.',
      );
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_esSms ? 'Verificar celular' : 'Verificar correo'),
      content: Column(
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
                labelText: _esSms ? 'Número de celular' : 'Correo electrónico',
                prefixIcon: Icon(
                  _esSms ? Icons.phone_outlined : Icons.email_outlined,
                ),
              ),
            ),
          ] else ...[
            Text(
              'Ingresa el código de 6 dígitos enviado ${_esSms ? 'por SMS' : 'a tu correo'}.',
            ),
            const SizedBox(height: 12),
            _CampoCodigoOtp(controller: _codigoController, autofocus: true),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _cargando ? null : _enviarCodigo,
              child: const Text('Reenviar código'),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _cargando ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        if (!_codigoEnviado)
          FilledButton(
            onPressed: _cargando ? null : _enviarCodigo,
            child: _cargando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Enviar código'),
          )
        else
          FilledButton(
            onPressed: _cargando ? null : _confirmarCodigo,
            child: _cargando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Confirmar'),
          ),
      ],
    );
  }
}
