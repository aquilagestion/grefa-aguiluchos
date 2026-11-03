import test from 'node:test';
import assert from 'node:assert/strict';
import { borradorConvenio, borradorRgpd, totalesPorAyuda } from '../src/contrato_borrador.js';

const ayudas = [
  { codigo: 1, descripcion: 'Barbecho', unidad: 'ha', importe: 100 },
  { codigo: 2, descripcion: 'Siega tardía', unidad: 'ha', importe: 50 },
  { codigo: 3, descripcion: 'Variable', unidad: 'variable', importe: null },
];
const datos = {
  contrato: { campana: 2026, fecha_firma: '2026-06-16', pct_firma: 60, importe_total: 1500, programa: null },
  propietario: { nombre: 'Titular <Prueba> & Co', nif: '00000000T', tipo: 'particular' },
  lineas: [
    { parcela: { sigpac_poligono: '10', sigpac_parcela: '21', sigpac_recinto: '1', municipio: 'Madrid' }, linea: { superficie_ha: 5, ayudas: [1, 2] } },
    { parcela: { sigpac_poligono: '11', sigpac_parcela: '3' }, linea: { superficie_ha: 3, ayudas: [1] } },
  ],
  ayudas,
};

test('totales por ayuda: suma superficie e importe, y deja vacío lo variable', () => {
  const t = totalesPorAyuda(datos.lineas.map((x) => x.linea), ayudas);
  assert.equal(t[0].sup, 8);
  assert.equal(t[0].total, 800);
  assert.equal(t[1].total, 250);
  assert.equal(t[2].total, null);
});

test('borrador del convenio: escapa HTML y recoge titular y parcelas', () => {
  const html = borradorConvenio(datos);
  assert.ok(html.includes('Titular &lt;Prueba&gt; &amp; Co'));
  assert.ok(!html.includes('<Prueba>'));
  assert.ok(html.includes('00000000T'));
  assert.ok(html.includes('CONVENIO') || html.includes('Convenio'));
});

test('borrador RGPD funciona sin convenio y no trae IBAN', () => {
  const html = borradorRgpd({ contrato: null, propietario: { nombre: 'Ana', nif: '1' , iban_enmascarado: '•••• 2447' } });
  assert.ok(html.includes('CONSENTIMIENTO'));
  assert.ok(!html.includes('2447'));
});
