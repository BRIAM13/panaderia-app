import 'dart:async';

import 'package:flutter/material.dart';

import '../utils/text_formatters.dart';

/// Campo de texto libre que "aprende": a medida que se escribe, propone
/// valores ya usados antes que empiezan con lo tecleado (ej. tipos de carne
/// guardados en pedidos anteriores), pero SIEMPRE permite terminar de
/// escribir un valor nuevo — no es un selector cerrado, es solo una ayuda.
///
/// La lista de sugerencias se muestra EN LÍNEA (no como un overlay
/// flotante) a propósito: un `Opacity`/`Stack` con overlay causó antes un
/// bug de renderizado en blanco en dispositivos reales con Impeller/Vulkan
/// (ver el rediseño del ingreso de código OTP) — un widget normal dentro
/// del árbol es la opción robusta.
class CampoConSugerencias extends StatefulWidget {
  const CampoConSugerencias({
    super.key,
    required this.controller,
    required this.label,
    required this.icono,
    required this.buscarSugerencias,
  });

  final TextEditingController controller;
  final String label;
  final IconData icono;
  final Future<List<String>> Function(String prefijo) buscarSugerencias;

  @override
  State<CampoConSugerencias> createState() => _CampoConSugerenciasState();
}

class _CampoConSugerenciasState extends State<CampoConSugerencias> {
  final _focusNode = FocusNode();
  Timer? _debounce;
  List<String> _sugerencias = [];
  bool _mostrarLista = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_alCambiarTexto);
    _focusNode.addListener(_alCambiarFoco);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_alCambiarTexto);
    _focusNode.removeListener(_alCambiarFoco);
    _focusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _alCambiarFoco() {
    if (_focusNode.hasFocus) {
      setState(() => _mostrarLista = true);
      _buscar(widget.controller.text);
    } else {
      // Retraso a propósito: si el usuario tocó una sugerencia de la lista,
      // ese toque necesita alcanzar a procesarse antes de que la lista
      // desaparezca — si se ocultara de inmediato al perder foco, el tap
      // nunca llegaría a registrarse.
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) setState(() => _mostrarLista = false);
      });
    }
  }

  void _alCambiarTexto() {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 250),
      () => _buscar(widget.controller.text),
    );
  }

  Future<void> _buscar(String texto) async {
    try {
      final resultado = await widget.buscarSugerencias(texto);
      if (mounted) setState(() => _sugerencias = resultado);
    } catch (_) {
      // Silencioso: las sugerencias son solo una ayuda, nunca deben
      // bloquear ni ensuciar el formulario si la consulta falla.
    }
  }

  void _seleccionar(String valor) {
    widget.controller.text = valor;
    widget.controller.selection = TextSelection.collapsed(
      offset: valor.length,
    );
    setState(() => _mostrarLista = false);
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visibles = _sugerencias
        .where((s) => s != widget.controller.text)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: widget.controller,
          focusNode: _focusNode,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: const [UpperCaseTextFormatter()],
          decoration: InputDecoration(
            labelText: widget.label,
            prefixIcon: Icon(widget.icono),
          ),
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Campo requerido' : null,
        ),
        if (_mostrarLista && visibles.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            constraints: const BoxConstraints(maxHeight: 176),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: scheme.outline.withValues(alpha: 0.2)),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: visibles.length,
              itemBuilder: (context, i) => ListTile(
                dense: true,
                leading: Icon(
                  Icons.history_rounded,
                  size: 18,
                  color: scheme.primary,
                ),
                title: Text(visibles[i]),
                onTap: () => _seleccionar(visibles[i]),
              ),
            ),
          ),
      ],
    );
  }
}
