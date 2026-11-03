import test from 'node:test';
import assert from 'node:assert/strict';
import { ErrorApi, extraerContrato, normalizarExtraccion, parsearJson, rutaValida } from '../api/_extraccion.js';

const ENV = { SUPABASE_URL: 'https://x.supabase.co', SUPABASE_ANON_KEY: 'anon', MISTRAL_API_KEY: 'mk' };
const respuesta = (cuerpo, ok = true, status = 200) => ({ ok, status, json: async () => cuerpo });

const MODELO = {
  fecha_firma: '16/06/2025', lugar_firma: 'Madrid',
  titular: { nombre: 'Titular Ejemplo', nif: '12.345.678-z', tipo: 'particular' },
  parcelas: [
    { sigpac_municipio: '150', sigpac_poligono: '10', sigpac_parcela: '21', sigpac_recinto: '1', superficie_ha: '2,4', uso: 'TA', ayudas: ['4', 4, 9, 'x', 0] },
    { sigpac_poligono: null, sigpac_parcela: null },
  ],
  importe_total: '500 €', pct_firma: 60, iban: 'ES69 2100 4747 0401 0027 2447', consentimiento_rgpd_firmado: true,
  dudas: ['REGEPA ilegible'], campo_inesperado: 'no debe salir',
};

test('normaliza la salida del modelo y enmascara el IBAN', () => {
  const d = normalizarExtraccion(MODELO);
  assert.equal(d.fecha_firma, '2025-06-16');
  assert.equal(d.titular.nif, '12345678Z');
  assert.equal(d.parcelas.length, 1);
  assert.deepEqual(d.parcelas[0].ayudas, [4, 9]);
  assert.equal(d.parcelas[0].superficie_ha, 2.4);
  assert.equal(d.importe_total, 500);
  assert.equal(d.iban_enmascarado, '•••• •••• •••• •••• •••• 2447');
  assert.ok(!JSON.stringify(d).includes('2100'));
  assert.ok(!('iban' in d) && !('campo_inesperado' in d));
});

test('parsearJson admite bloques de código y rechaza basura', () => {
  assert.deepEqual(parsearJson('```json\n{"a":1}\n```'), { a: 1 });
  assert.throws(() => parsearJson('sin json'), ErrorApi);
});

test('rutaValida solo admite rutas internas del bucket', () => {
  assert.equal(rutaValida('convenios/abc/x.pdf'), true);
  assert.equal(rutaValida('../etc/passwd'), false);
  assert.equal(rutaValida('/abs'), false);
  assert.equal(rutaValida('a b.pdf'), false);
});

test('exige clave, sesión @grefa.org y ruta válida', async () => {
  await assert.rejects(() => extraerContrato({ path: 'a/b.pdf', token: 't' }, { ...ENV, MISTRAL_API_KEY: '' }), { status: 503 });
  await assert.rejects(() => extraerContrato({ path: 'a/b.pdf', token: '' }, ENV), { status: 401 });
  await assert.rejects(() => extraerContrato({ path: '../x', token: 't' }, ENV), { status: 400 });
  const ajeno = async (url) => (String(url).includes('/auth/v1/user') ? respuesta({ email: 'x@gmail.com' }) : respuesta({}, false, 500));
  await assert.rejects(() => extraerContrato({ path: 'a/b.pdf', token: 't' }, ENV, ajeno), { status: 401 });
});

test('flujo completo: URL firmada -> OCR -> extracción; el IBAN completo no sale', async () => {
  const llamadas = [];
  const f = async (url, init) => {
    url = String(url); llamadas.push(url);
    if (url.includes('/auth/v1/user')) return respuesta({ email: 'ana@grefa.org' });
    if (url.includes('/object/sign/contratos/')) return respuesta({ signedURL: '/object/sign/contratos/a/b.pdf?token=abc' });
    if (url.endsWith('/v1/ocr')) {
      assert.equal(JSON.parse(init.body).document.type, 'document_url');
      return respuesta({ pages: [{ markdown: 'texto página 1' }, { markdown: 'texto página 2' }] });
    }
    if (url.endsWith('/chat/completions')) return respuesta({ choices: [{ message: { content: JSON.stringify(MODELO) } }] });
    throw new Error(`url inesperada ${url}`);
  };
  const r = await extraerContrato({ path: 'a/b.pdf', token: 't' }, ENV, f);
  assert.equal(r.paginas, 2);
  assert.equal(r.datos.titular.nif, '12345678Z');
  assert.ok(!JSON.stringify(r).includes('2100 4747'));
  assert.equal(llamadas.length, 4);
});
