// La memoria de corta duración de externalController es lo que evita pagar
// DOS consultas a apiperu.dev por cada cliente registrado (una del "Buscar"
// del formulario, otra de la comprobación que ahora hace el servidor al
// guardar). Estas pruebas fijan sus dos reglas críticas: se recuerdan solo
// las respuestas autoritativas, y una entrada vencida no se reusa.
const {
  recordarConsulta,
  leerConsultaRecordada,
  olvidarConsultasRecordadas,
} = require('../controllers/externalController');

beforeEach(() => {
  olvidarConsultasRecordadas();
});

afterAll(() => {
  olvidarConsultasRecordadas();
  jest.useRealTimers();
});

describe('memoria de consultas de documento', () => {
  test('una respuesta de la API real se recuerda y se devuelve igual', () => {
    const respuesta = { fuente: 'API_REAL', dni: '72701801', nombres: 'BRIAM LUIS' };
    recordarConsulta('72701801', respuesta);
    expect(leerConsultaRecordada('72701801')).toEqual(respuesta);
  });

  test('un "no encontrado" también se recuerda: repetir un DNI mal tecleado no cuesta otro consumo', () => {
    recordarConsulta('99999999', { fuente: 'NO_ENCONTRADO' });
    expect(leerConsultaRecordada('99999999')).toEqual({ fuente: 'NO_ENCONTRADO' });
  });

  test('una respuesta SIMULADA nunca se recuerda: no debe sobrevivir a que la API vuelva', () => {
    recordarConsulta('12345678', { fuente: 'SIMULADO', nombres: 'CARLOS' });
    expect(leerConsultaRecordada('12345678')).toBeNull();
  });

  test('un documento que nunca se consultó no está en memoria', () => {
    expect(leerConsultaRecordada('11111111')).toBeNull();
  });

  test('una entrada vencida se descarta en vez de devolverse', () => {
    jest.useFakeTimers();
    try {
      recordarConsulta('72701801', { fuente: 'API_REAL', nombres: 'BRIAM LUIS' });
      expect(leerConsultaRecordada('72701801')).not.toBeNull();

      // Media hora y un minuto después (el TTL por defecto es 30 min).
      jest.advanceTimersByTime(31 * 60 * 1000);
      expect(leerConsultaRecordada('72701801')).toBeNull();
    } finally {
      jest.useRealTimers();
    }
  });
});
