import test from 'node:test';
import assert from 'node:assert/strict';
import {
  agrupar, anioCampana, construirInforme, construirInformeNido, documentoHtml, incidencias, justificacion,
  nombreArchivo, pollosSinDeterminar, referenciaPorDefecto, textoConclusiones,
} from '../src/informe.js';

const nido = (o = {}) => ({
  id: crypto.randomUUID(), etiqueta: 'A1', numeracion: '1', municipio: 'Toledo', provincia: 'Toledo',
  especie: 'Aguilucho cenizo', fecha_incubacion: '2026-05-01', intervencion: false, tipo_acciones_manejo: [], ...o,
});

const datos = [
  nido({ etiqueta: 'E1', resultado_reproductivo: 'Éxito', num_pollos_nacidos: 3, num_pollos_volados: 2, num_pollos_muertos: 1, intervencion: true, tipo_acciones_manejo: ['Dron'], coordenada_x: 440000, coordenada_y: 4400000 }),
  nido({ etiqueta: 'F1', municipio: 'Madrid', resultado_reproductivo: 'Fracaso', causas_fracaso: 'Depredación', estado_fracaso: 'Huevos', num_pollos_nacidos: 0 }),
  nido({ etiqueta: 'C1', num_pollos_nacidos: 2, num_pollos_volados: 2, num_pollos_muertos: 1 }),
];
const opts = { titulo: 'Informe <test>', referencia: 'REF-1', fecha: new Date(2026, 10, 2), autor: 'Ana', filtros: '' };

test('justificación replica el texto de la app', () => {
  assert.equal(justificacion(datos[0]), 'Intervención de conservación (Dron)');
  assert.equal(justificacion(datos[1]), 'Fracaso (Huevos): Depredación');
  assert.equal(justificacion(nido()), '—');
});

test('agrupación y pollos sin determinar', () => {
  const g = agrupar(datos, 'municipio');
  assert.equal(g[0].nombre, 'Toledo');
  assert.equal(g[0].total, 2);
  assert.equal(pollosSinDeterminar(datos), 0 + 0 + 0); // 3-2-1=0, 0, max(0,2-2-1)=0
});

test('incidencias detecta datos incoherentes y sin coordenadas', () => {
  const inc = incidencias(datos).join(' ');
  assert.match(inc, /sin coordenadas/);
  assert.match(inc, /volados \+ muertos superiores/);
  assert.match(inc, /sin resultado reproductivo cerrado/);
});

test('conclusiones citan cifras exactas', () => {
  const t = textoConclusiones(datos);
  assert.match(t, /3 nido\(s\) analizados, 1 finalizaron con éxito, 1 fracasaron y 1 no tienen/);
  assert.match(t, /50 %/);
  assert.match(t, /Depredación/);
});

test('informe de campaña: secciones, escape y firma', () => {
  const html = construirInforme(datos, { ...opts, secciones: ['resumen', 'relacion'] });
  assert.match(html, /Informe &lt;test&gt;/);
  assert.match(html, /REF-1/);
  assert.match(html, /1\. Resumen ejecutivo/);
  assert.match(html, /2\. Relación de nidos/);
  assert.doesNotMatch(html, /Causas de fracaso<\/h2>/);
  assert.match(html, /Firma y sello/);
  assert.equal((html.match(/<tr>/g) ?? []).length > 10, true);
});

test('anexo de fichas incluye una ficha por nido', () => {
  const html = construirInforme(datos, { ...opts, secciones: ['fichas'] });
  assert.equal((html.match(/class="ficha"/g) ?? []).length, 3);
  assert.match(html, /Fase 4 · Cosecha y balance/);
});

test('informe individual de nido', () => {
  const html = construirInformeNido(datos[0], opts);
  assert.match(html, /Ficha técnica · E1/);
  assert.match(html, /Posición WGS84/);
  assert.match(html, /Fecha estimada de eclosión.*31\/05\/2026/);
  assert.match(html, /Balance: 3 nacidos = 2 volados \+ 1 muertos \+ 0 sin determinar/);
});

test('utilidades: año de campaña, referencia, documento y nombre', () => {
  assert.equal(anioCampana(datos), '2026');
  assert.match(referenciaPorDefecto(new Date(2026, 10, 2, 9, 5)), /^GREFA-AGU-2026-1102-0905$/);
  assert.match(documentoHtml('<p>x</p>', 'T'), /<style>[\s\S]*<\/style>[\s\S]*<p>x<\/p>/);
  assert.equal(nombreArchivo('GREFA/AGU 1', 'doc'), 'GREFA_AGU_1.doc');
});
