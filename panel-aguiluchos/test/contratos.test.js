import test from 'node:test';
import assert from 'node:assert/strict';
import {
  avisosCaducidad, campanaDeNido, claveSigpac, compensacionACsv, descripcionParcela, estadoContratoNido, estadosPorNido,
  esIbanEnmascarado, generarPagos, grupoSemaforo, importeSugeridoLinea, importeTotalLineas, indexarContratos, mascararIban,
  normRefCat, resumenCompensacion, candidatosNidos, mismoNombre, normTelefono, validarContrato, validarParcela, validarPropietario,
} from '../src/contratos_logic.js';

const HOY = new Date(2026, 10, 3); // 3-nov-2026

test('IBAN: solo quedan los 4 últimos dígitos', () => {
  const m = mascararIban('ES69 2100 4747 0401 0027 2447');
  assert.equal(m, '•••• •••• •••• •••• •••• 2447');
  assert.ok(!m.includes('2100'));
  assert.ok(esIbanEnmascarado(m));
  assert.ok(!esIbanEnmascarado('ES6921004747040100272447'));
  assert.equal(mascararIban(''), '');
  assert.equal(mascararIban('123'), '');
});

test('claves de parcela y descripción', () => {
  const p = { sigpac_provincia: '28', sigpac_municipio: '150', sigpac_agregado: '0', sigpac_zona: '0', sigpac_poligono: '10', sigpac_parcela: '21', sigpac_recinto: '1', referencia_catastral: '28150A010000210000XX', municipio: 'Pinto', provincia: 'Madrid' };
  assert.equal(claveSigpac(p), 'españa|28|150|0|0|10|21|1');
  assert.equal(claveSigpac({ ...p, sigpac_municipio: '0150' }), claveSigpac({ ...p, sigpac_municipio: '150' }));
  assert.equal(claveSigpac({ referencia_catastral: 'x' }), '');
  assert.match(descripcionParcela(p), /Pol\. 10 · Parc\. 21 · Rec\. 1 · Ref\. 28150A/);
  assert.equal(normRefCat(' 28150a-010000 '), '28150A010000');
});

test('campaña del nido', () => {
  assert.equal(campanaDeNido({ fecha_incubacion: '2025-05-01' }, HOY), 2025);
  assert.equal(campanaDeNido({ fecha_entrada_nido: '2024-06-10' }, HOY), 2024);
  assert.equal(campanaDeNido({}, HOY), 2026);
});

const datos = (extra = {}) => ({
  parcelas: [
    { id: 'p1', referencia_catastral: '28150A010000210000XX' },
    { id: 'p2', referencia_catastral: null },
    { id: 'p3', referencia_catastral: 'ZZZ' },
  ],
  vinculos: [{ nido_id: 'n2', parcela_id: 'p2' }],
  contratos: [
    { id: 'c1', estado: 'firmado', campana: 2025, vigencia_hasta: '2027-06-30' },
    { id: 'c2', estado: 'enviado', campana: 2025 },
    { id: 'c3', estado: 'firmado', campana: 2025, vigencia_hasta: '2026-12-01' },
    { id: 'c4', estado: 'firmado', campana: 2025, vigencia_hasta: '2026-01-31' },
    { id: 'c5', estado: 'rechazado', campana: 2025 },
  ],
  lineas: [
    { contrato_id: 'c1', parcela_id: 'p1', campana: 2025 },
    { contrato_id: 'c2', parcela_id: 'p2', campana: 2025 },
    { contrato_id: 'c3', parcela_id: 'p3', campana: 2025 },
    { contrato_id: 'c5', parcela_id: 'p3', campana: 2024 },
  ],
  ...extra,
});

test('semáforo de contrato por nido (vínculo explícito o referencia catastral)', () => {
  const ix = indexarContratos(datos());
  const n = (id, extra = {}) => ({ id, fecha_incubacion: '2025-05-01', ...extra });

  // por referencia catastral -> firmado vigente
  assert.equal(estadoContratoNido(n('n1', { referencia_catastral: '28150a010000210000xx' }), ix, HOY).codigo, 'firmado');
  // por vínculo explícito -> enviado = pendiente
  assert.equal(estadoContratoNido(n('n2'), ix, HOY).codigo, 'pendiente');
  // firmado que caduca en menos de 60 días
  assert.equal(estadoContratoNido(n('n3', { referencia_catastral: 'ZZZ' }), ix, HOY).codigo, 'caduca');
  // otra campaña sin convenio -> sin contrato
  assert.equal(estadoContratoNido(n('n4', { referencia_catastral: 'ZZZ', fecha_incubacion: '2024-05-01' }), ix, HOY).codigo, 'sin');
  // sin parcela
  assert.equal(estadoContratoNido(n('n5'), ix, HOY).codigo, 'sinparcela');
  assert.equal(grupoSemaforo('caduca'), 'pendiente');
  assert.equal(grupoSemaforo('caducado'), 'sin');
});

test('convenio firmado con vigencia pasada figura como caducado; el rechazado como sin contrato', () => {
  const d = datos({
    contratos: [{ id: 'c4', estado: 'firmado', campana: 2025, vigencia_hasta: '2026-01-31' }, { id: 'c5', estado: 'rechazado', campana: 2024 }],
    lineas: [{ contrato_id: 'c4', parcela_id: 'p1', campana: 2025 }, { contrato_id: 'c5', parcela_id: 'p3', campana: 2024 }],
  });
  const m = estadosPorNido([
    { id: 'a', referencia_catastral: '28150A010000210000XX', fecha_incubacion: '2025-05-01' },
    { id: 'b', referencia_catastral: 'ZZZ', fecha_incubacion: '2024-05-01' },
  ], d, HOY);
  assert.equal(m.get('a').codigo, 'caducado');
  assert.equal(m.get('b').codigo, 'sin');
});

test('importe sugerido por línea y total', () => {
  const ayudas = [
    { codigo: 1, unidad: 'ha', importe: 300 },
    { codigo: 4, unidad: 'fijo', importe: 400 },
    { codigo: 7, unidad: 'variable', importe: null },
  ];
  assert.equal(importeSugeridoLinea({ superficie_ha: '2,5', ayudas: [1, 4, 7] }, ayudas), 1150);
  assert.equal(importeSugeridoLinea({ superficie_ha: 1, ayudas: [] }, ayudas), 0);
  assert.equal(importeTotalLineas([{ importe: 400 }, { importe: '100,50' }, { importe: null }]), 500.5);
});

test('pagos 60/40 sin perder céntimos', () => {
  const p = generarPagos(500, 60);
  assert.deepEqual(p.map((x) => x.importe), [300, 200]);
  assert.match(p[0].concepto, /60 %/);
  assert.match(p[1].concepto, /40 %/);
  const q = generarPagos(100.01, 60);
  assert.equal(Math.round((q[0].importe + q[1].importe) * 100), 10001);
  assert.deepEqual(generarPagos(0), []);
  assert.deepEqual(generarPagos(100, 100).map((x) => x.importe), [100]);
});

test('resumen de compensación por campaña y propietario', () => {
  const r = resumenCompensacion(
    [
      { id: 'c1', propietario_id: 'o1', campana: 2025, estado: 'firmado', importe_total: 500 },
      { id: 'c2', propietario_id: 'o2', campana: 2025, estado: 'firmado', importe_total: 300 },
      { id: 'c3', propietario_id: 'o2', campana: 2025, estado: 'borrador', importe_total: 999 },
    ],
    [
      { contrato_id: 'c1', importe: 300, estado: 'pagado' },
      { contrato_id: 'c1', importe: 200, estado: 'pendiente' },
    ],
    [{ id: 'o1', nombre: 'Ana' }, { id: 'o2', nombre: 'Luis' }],
  );
  assert.equal(r.campanas.length, 1);
  assert.deepEqual(r.campanas[0], { campana: 2025, contratos: 2, comprometido: 800, pagado: 300, pendiente: 500 });
  assert.equal(r.filas.find((f) => f.propietario === 'Ana').pendiente, 200);
  const csv = compensacionACsv(r);
  assert.match(csv, /Campaña;Propietario/);
  assert.match(csv, /2025;Ana;Firmado;500;300;200/);
});

test('validaciones', () => {
  assert.deepEqual(validarPropietario({ nombre: 'Ana', iban_enmascarado: '•••• 2447' }), []);
  assert.ok(validarPropietario({ nombre: 'Ana', iban_enmascarado: 'ES6921004747040100272447' }).length);
  assert.ok(validarPropietario({ nombre: '' }).length);
  assert.ok(validarParcela({}).length);
  assert.deepEqual(validarParcela({ sigpac_poligono: '1', sigpac_parcela: '2' }), []);
  assert.deepEqual(validarParcela({ referencia_catastral: 'X' }), []);
  const base = { propietario_id: 'o', campana: 2026, estado: 'borrador' };
  assert.ok(validarContrato(base, []).length);
  assert.deepEqual(validarContrato(base, [{ parcela_id: 'p1' }]), []);
  assert.ok(validarContrato({ ...base, estado: 'firmado' }, [{ parcela_id: 'p1' }]).some((m) => /fecha de firma/.test(m)));
  assert.ok(validarContrato(base, [{ parcela_id: 'p1' }, { parcela_id: 'p1' }]).some((m) => /repetida/.test(m)));
});

test('avisos de caducidad', () => {
  const a = avisosCaducidad([
    { id: 'a', estado: 'firmado', vigencia_hasta: '2026-12-01' },
    { id: 'b', estado: 'firmado', vigencia_hasta: '2027-12-01' },
    { id: 'c', estado: 'borrador', vigencia_hasta: '2026-11-10' },
    { id: 'd', estado: 'firmado', vigencia_hasta: '2026-10-01' },
  ], HOY);
  assert.deepEqual(a.map((x) => x.contrato.id), ['d', 'a']);
  assert.ok(a[0].dias < 0);
});

test('nombres: coincidencia robusta a acentos, orden y formas jurídicas', () => {
  assert.equal(mismoNombre('Pablo Robles del Río', 'ROBLES DEL RIO, Pablo'), true);
  assert.equal(mismoNombre('Pablo Robles', 'Pablo Robles Del Rio'), true);
  assert.equal(mismoNombre('Pablo Robles', 'Pablo Gómez'), false);
  assert.equal(mismoNombre('García', 'García López'), false); // una sola palabra: no basta
  assert.equal(normTelefono('+34 600 123 456'), '600123456');
});

test('candidatos: por nombre y/o teléfono, sin los ya vinculados, los más seguros primero', () => {
  const nidos = [
    { id: 'a', numeracion: '1', propietario: 'Pablo Robles del Rio', tlfn: '600 123 456' },
    { id: 'b', numeracion: '2', propietario: 'Robles Pablo', tlfn: null },
    { id: 'c', numeracion: '3', propietario: 'Otra Persona', tlfn: '600123456' },
    { id: 'd', numeracion: '4', propietario: 'Ana López', tlfn: '611111111' },
    { id: 'e', numeracion: '5', propietario: 'Pablo Robles', tlfn: null },
  ];
  const r = candidatosNidos(nidos, { nombre: 'Pablo Robles del Río', telefono: '600123456' }, new Set(['e']));
  assert.deepEqual(r.map((x) => x.nido.id), ['a', 'b', 'c']);
  assert.deepEqual(r[0].motivos, ['mismo nombre de propietario', 'mismo teléfono']);
  assert.equal(candidatosNidos(nidos, { nombre: null, telefono: null }).length, 0);
});
