import 'package:flutter_test/flutter_test.dart';
import 'package:panaderia_app/models/perfil_cliente_model.dart';

void main() {
  group('segmentoClienteFromString', () {
    test('mapea cada valor del backend a su segmento correspondiente', () {
      expect(segmentoClienteFromString('NUEVO'), SegmentoCliente.nuevo);
      expect(segmentoClienteFromString('EN_RIESGO'), SegmentoCliente.enRiesgo);
      expect(segmentoClienteFromString('VIP'), SegmentoCliente.vip);
      expect(segmentoClienteFromString('FRECUENTE'), SegmentoCliente.frecuente);
    });

    test('un valor desconocido o vacío cae a REGULAR en vez de romper', () {
      expect(segmentoClienteFromString(''), SegmentoCliente.regular);
      expect(segmentoClienteFromString('ALGO_INESPERADO'), SegmentoCliente.regular);
    });
  });

  group('HistorialCliente.fromJson', () {
    test('parsea un historial completo con tiendas', () {
      final json = {
        'totalPedidos': 13,
        'pedidosEntregados': 13,
        'totalGastado': 164.5,
        'deudaPendiente': 0,
        'ultimaCompra': '2026-08-25T00:56:23.423Z',
        'diasDesdeUltimaCompra': 3,
        'tiendas': [
          {'idTienda': 1, 'nombre': 'Hamburguesas'},
        ],
      };

      final historial = HistorialCliente.fromJson(json);

      expect(historial.totalPedidos, 13);
      expect(historial.pedidosEntregados, 13);
      expect(historial.totalGastado, 164.5);
      expect(historial.deudaPendiente, 0);
      expect(historial.diasDesdeUltimaCompra, 3);
      expect(historial.ultimaCompra, isNotNull);
      expect(historial.tiendas, hasLength(1));
      expect(historial.tiendas.first.nombre, 'Hamburguesas');
    });

    test('un cliente NUEVO sin compras parsea con valores en cero/null, sin lanzar', () {
      final json = {
        'totalPedidos': 0,
        'pedidosEntregados': 0,
        'totalGastado': 0,
        'deudaPendiente': 0,
        'ultimaCompra': null,
        'diasDesdeUltimaCompra': null,
        'tiendas': [],
      };

      final historial = HistorialCliente.fromJson(json);

      expect(historial.ultimaCompra, isNull);
      expect(historial.diasDesdeUltimaCompra, isNull);
      expect(historial.tiendas, isEmpty);
    });
  });

  group('PerfilCliente.fromJson', () {
    test('combina cliente, historial y segmento en un solo objeto', () {
      final json = {
        'cliente': {
          'idCliente': 7,
          'idPersona': 7,
          'dni': '12345678',
          'nombres': 'JUAN',
          'apellidoPaterno': 'PEREZ',
          'apellidoMaterno': null,
          'telefono': '999999999',
          'email': null,
          'direccion': null,
          'descripcionNegocio': null,
          'nombreComercialOficial': false,
          'origenValidacion': 'RENIEC',
          'calidadDato': 'RENIEC',
          'puntosFidelidad': 16,
          'activo': true,
          'telefonoVerificado': false,
          'emailVerificado': false,
        },
        'historial': {
          'totalPedidos': 13,
          'pedidosEntregados': 13,
          'totalGastado': 164.5,
          'deudaPendiente': 0,
          'ultimaCompra': '2026-08-25T00:56:23.423Z',
          'diasDesdeUltimaCompra': 3,
          'tiendas': [],
        },
        'segmento': 'FRECUENTE',
      };

      final perfil = PerfilCliente.fromJson(json);

      expect(perfil.cliente.idCliente, 7);
      expect(perfil.cliente.puntosFidelidad, 16);
      expect(perfil.historial.totalGastado, 164.5);
      expect(perfil.segmento, SegmentoCliente.frecuente);
    });
  });

  group('NotaCliente.fromJson', () {
    test('parsea una nota con su autor', () {
      final nota = NotaCliente.fromJson({
        'idNota': 1,
        'idCliente': 7,
        'texto': 'Cliente frecuente, siempre paga puntual.',
        'fechaCreacion': '2026-08-29T23:53:00.407Z',
        'autor': 'WALTER SANTO RONCEROS',
      });

      expect(nota.idNota, 1);
      expect(nota.texto, 'Cliente frecuente, siempre paga puntual.');
      expect(nota.autor, 'WALTER SANTO RONCEROS');
    });
  });
}
