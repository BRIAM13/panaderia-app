// El servidor nunca debe aceptar "este documento está verificado" solo
// porque lo diga el cliente HTTP. Estas pruebas fijan ese contrato: la
// única entrada que puede producir un OrigenValidacion 'RENIEC' es una
// respuesta 'API_REAL' de la fuente oficial, y todo lo demás cae a 'MANUAL'
// o se rechaza.
jest.mock('../controllers/externalController', () => ({
  verificarDocumentoOficial: jest.fn(),
}));

const { verificarDocumentoOficial } = require('../controllers/externalController');
const {
  resolverOrigenValidacion,
  origenSegunFuente,
  datosOficiales,
  esRucPeru,
  normalizar,
  ORIGEN_VERIFICADO,
  ORIGEN_MANUAL,
} = require('../utils/verificacionDocumento');

beforeEach(() => {
  verificarDocumentoOficial.mockReset();
});

describe('origenSegunFuente', () => {
  test('solo la API real justifica marcar RENIEC', () => {
    expect(origenSegunFuente('API_REAL')).toBe(ORIGEN_VERIFICADO);
  });

  test('el simulador local nunca cuenta como verificado', () => {
    expect(origenSegunFuente('SIMULADO')).toBe(ORIGEN_MANUAL);
    expect(origenSegunFuente('NO_ENCONTRADO')).toBe(ORIGEN_MANUAL);
    expect(origenSegunFuente(undefined)).toBe(ORIGEN_MANUAL);
  });
});

describe('esRucPeru', () => {
  test('11 dígitos es RUC; 8 dígitos (DNI) y basura no lo son', () => {
    expect(esRucPeru('20123456789')).toBe(true);
    expect(esRucPeru('12345678')).toBe(false);
    expect(esRucPeru(null)).toBe(false);
    expect(esRucPeru('20123456789abc')).toBe(false);
  });
});

describe('normalizar', () => {
  test('deja los datos oficiales en mayúsculas y sin espacios sobrantes', () => {
    expect(normalizar('  briam luis ')).toBe('BRIAM LUIS');
    expect(normalizar(null)).toBe('');
    expect(normalizar(undefined)).toBe('');
  });
});

describe('datosOficiales', () => {
  test('un DNI verificado trae nombres y ambos apellidos en mayúsculas', () => {
    const oficial = datosOficiales(
      { fuente: 'API_REAL', nombres: 'Briam Luis', apellidoPaterno: 'Ronceros', apellidoMaterno: 'Achuli' },
      '72701801',
    );
    expect(oficial).toEqual({
      nombres: 'BRIAM LUIS',
      apellidoPaterno: 'RONCEROS',
      apellidoMaterno: 'ACHULI',
      nombreComercial: '',
    });
  });

  test('un apellido materno vacío queda en null, no en cadena vacía', () => {
    const oficial = datosOficiales(
      { fuente: 'API_REAL', nombres: 'Ana', apellidoPaterno: 'Perez', apellidoMaterno: '' },
      '12345678',
    );
    expect(oficial.apellidoMaterno).toBeNull();
  });

  test('un RUC verificado guarda la razón social en nombres y no inventa apellidos', () => {
    const oficial = datosOficiales(
      { fuente: 'API_REAL', razonSocial: 'Panificadora Ronceros S.A.C.', nombreComercial: 'Pan Ronceros' },
      '20123456789',
    );
    expect(oficial).toEqual({
      nombres: 'PANIFICADORA RONCEROS S.A.C.',
      apellidoPaterno: '',
      apellidoMaterno: null,
      nombreComercial: 'PAN RONCEROS',
    });
  });

  test('sin respuesta de la API real no hay datos oficiales que guardar', () => {
    expect(datosOficiales({ fuente: 'SIMULADO', nombres: 'Carlos' }, '12345678')).toBeNull();
    expect(datosOficiales({ fuente: 'NO_ENCONTRADO' }, '12345678')).toBeNull();
    expect(datosOficiales(null, '12345678')).toBeNull();
  });
});

describe('resolverOrigenValidacion', () => {
  test('el bug reportado: un DNI que RENIEC no reconoce se rechaza, nunca queda como verificado', async () => {
    verificarDocumentoOficial.mockResolvedValue({ fuente: 'NO_ENCONTRADO' });

    const resultado = await resolverOrigenValidacion({ documento: '99999999', origenSolicitado: 'RENIEC' });

    expect(resultado.aceptado).toBe(false);
    expect(resultado.oficial).toBeNull();
    expect(resultado.mensaje).toMatch(/RENIEC no reconoce/);
  });

  test('un RUC inexistente se rechaza con el mensaje de SUNAT, no el de RENIEC', async () => {
    verificarDocumentoOficial.mockResolvedValue({ fuente: 'NO_ENCONTRADO' });

    const resultado = await resolverOrigenValidacion({ documento: '20999999999', origenSolicitado: 'RENIEC' });

    expect(resultado.aceptado).toBe(false);
    expect(resultado.mensaje).toMatch(/SUNAT no reconoce/);
  });

  test('con confirmación de la API real, el origen es RENIEC y los nombres son los oficiales', async () => {
    verificarDocumentoOficial.mockResolvedValue({
      fuente: 'API_REAL',
      nombres: 'Briam Luis',
      apellidoPaterno: 'Ronceros',
      apellidoMaterno: 'Achuli',
    });

    const resultado = await resolverOrigenValidacion({ documento: '72701801', origenSolicitado: 'RENIEC' });

    expect(resultado).toMatchObject({ aceptado: true, origen: 'RENIEC' });
    expect(resultado.oficial.nombres).toBe('BRIAM LUIS');
  });

  test('si apiperu.dev no responde (simulador), el dato se guarda pero NO como verificado', async () => {
    verificarDocumentoOficial.mockResolvedValue({
      fuente: 'SIMULADO',
      nombres: 'Carlos',
      apellidoPaterno: 'Garcia',
      apellidoMaterno: 'Lopez',
    });

    const resultado = await resolverOrigenValidacion({ documento: '12345678', origenSolicitado: 'RENIEC' });

    expect(resultado).toMatchObject({ aceptado: true, origen: 'MANUAL', oficial: null });
  });

  test('sin documento no hay nada que verificar: siempre MANUAL, sin gastar la API paga', async () => {
    const resultado = await resolverOrigenValidacion({ documento: null, origenSolicitado: 'RENIEC' });

    expect(resultado).toMatchObject({ aceptado: true, origen: 'MANUAL', oficial: null });
    expect(verificarDocumentoOficial).not.toHaveBeenCalled();
  });

  test('un registro manual no consulta la fuente oficial (no cuesta un consumo)', async () => {
    const resultado = await resolverOrigenValidacion({ documento: '12345678', origenSolicitado: 'MANUAL' });

    expect(resultado).toMatchObject({ aceptado: true, origen: 'MANUAL', oficial: null });
    expect(verificarDocumentoOficial).not.toHaveBeenCalled();
  });

  test('mandar un origen inventado en el body no abre ninguna puerta', async () => {
    for (const origenInventado of ['SUNAT', 'reniec', true, 1, undefined]) {
      // eslint-disable-next-line no-await-in-loop
      const resultado = await resolverOrigenValidacion({ documento: '12345678', origenSolicitado: origenInventado });
      expect(resultado.origen).toBe('MANUAL');
    }
    expect(verificarDocumentoOficial).not.toHaveBeenCalled();
  });
});
