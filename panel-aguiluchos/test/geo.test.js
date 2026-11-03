import test from 'node:test';
import assert from 'node:assert/strict';
import { agruparPorNivel, norm, opcionesCascada, ubicacion } from '../src/geo.js';
import { filtrar } from '../src/logic.js';
import { encuadre, proyectar, puntosDe } from '../src/mapa_img.js';
import { agruparGeo, construirInforme, seccionMapas } from '../src/informe.js';

const n = (municipio, provincia, extra = {}) => ({ id: `${municipio}-${provincia}`, etiqueta: municipio, municipio, provincia, ...extra });

const datos = [
  n('Portillo de Toledo', 'Toledo', { resultado_reproductivo: 'Éxito' }),
  n('Pinto', 'Madrid'),
  n('Guadalajara', 'Guadalajara', { resultado_reproductivo: 'Fracaso' }),
  n('Sanabria', 'Zamora'),
  n('LIMIA', 'Galicia'),
  n('Fermoselle', 'orense'),
  n('Rara', 'Atlantida'),
  n('', ''),
];

test('ubicación: provincia → comunidad, alias y comunidades en el campo provincia', () => {
  assert.deepEqual(ubicacion(datos[0]), { pais: 'España', comunidad: 'Castilla-La Mancha', provincia: 'Toledo', localidad: 'Portillo de Toledo' });
  assert.equal(ubicacion(datos[1]).comunidad, 'Comunidad de Madrid');
  assert.equal(ubicacion(datos[3]).comunidad, 'Castilla y León');
  // «Galicia» en el campo provincia es una comunidad; LIMIA se sitúa en Ourense.
  assert.deepEqual(ubicacion(datos[4]), { pais: 'España', comunidad: 'Galicia', provincia: 'Ourense', localidad: 'LIMIA' });
  assert.equal(ubicacion(datos[5]).provincia, 'Ourense');
  assert.equal(ubicacion(datos[5]).comunidad, 'Galicia');
  // desconocida: se conserva la provincia y la comunidad queda sin indicar
  assert.equal(ubicacion(datos[6]).provincia, 'Atlantida');
  assert.equal(ubicacion(datos[6]).comunidad, 'Sin indicar');
  assert.deepEqual(ubicacion(datos[7]), { pais: 'España', comunidad: 'Sin indicar', provincia: 'Sin indicar', localidad: 'Sin indicar' });
});

test('norm quita tildes y signos', () => {
  assert.equal(norm('  Castilla-La  Mancha '), 'castilla la mancha');
  assert.equal(norm('Málaga'), 'malaga');
});

test('opciones en cascada dependen de la selección superior', () => {
  const todo = opcionesCascada(datos);
  assert.deepEqual(todo.paises, ['España']);
  assert.ok(todo.comunidades.includes('Galicia'));
  assert.ok(todo.localidades.includes('Pinto'));

  const clm = opcionesCascada(datos, { pais: 'España', comunidad: 'Castilla-La Mancha' });
  assert.deepEqual(clm.provincias, ['Guadalajara', 'Toledo']);
  assert.deepEqual(clm.localidades, ['Guadalajara', 'Portillo de Toledo']);

  const tol = opcionesCascada(datos, { comunidad: 'Castilla-La Mancha', provincia: 'Toledo' });
  assert.deepEqual(tol.localidades, ['Portillo de Toledo']);
});

test('filtrar por país, comunidad, provincia y localidad', () => {
  const f = (o) => filtrar(datos, { texto: '', ...o }).map((x) => x.municipio);
  assert.equal(f({ pais: 'España' }).length, datos.length);
  assert.deepEqual(f({ comunidad: 'Castilla-La Mancha' }).sort(), ['Guadalajara', 'Portillo de Toledo']);
  assert.deepEqual(f({ comunidad: 'Castilla-La Mancha', provincia: 'Toledo' }), ['Portillo de Toledo']);
  assert.deepEqual(f({ comunidad: 'Galicia' }).sort(), ['Fermoselle', 'LIMIA']);
  assert.deepEqual(f({ localidad: 'Pinto' }), ['Pinto']);
  assert.deepEqual(f({ provincia: 'Madrid', localidad: 'Guadalajara' }), []);
});

test('agrupar por nivel y estadísticas por comunidad', () => {
  const g = agruparPorNivel(datos, 'comunidad');
  assert.equal(g.find(([k]) => k === 'Galicia')[1].length, 2);
  const filas = agruparGeo(datos, 'comunidad');
  const clm = filas.find((x) => x.nombre === 'Castilla-La Mancha');
  assert.equal(clm.total, 2);
  assert.equal(clm.exito, 1);
  assert.equal(clm.fracaso, 1);
});

test('proyección y encuadre de mapas', () => {
  const p0 = proyectar(0, 0, 0);
  assert.ok(Math.abs(p0.x - 128) < 1e-6 && Math.abs(p0.y - 128) < 1e-6);
  const pts = [{ lat: 40.4, lon: -3.7 }, { lat: 39.9, lon: -4.3 }];
  const e = encuadre(pts, { ancho: 760, alto: 380 });
  const a = proyectar(pts[0].lat, pts[0].lon, e.z);
  const b = proyectar(pts[1].lat, pts[1].lon, e.z);
  assert.ok(Math.abs(a.x - b.x) <= 760 - 92 && Math.abs(a.y - b.y) <= 380 - 92);
  // un punto solo: zoom máximo permitido
  assert.equal(encuadre([pts[0]], { ancho: 760, alto: 380, zMax: 14 }).z, 14);
});

test('puntosDe ignora nidos sin coordenadas y colorea por estado', () => {
  const lista = [
    { etiqueta: 'A', coordenada_x: 440000, coordenada_y: 4400000, resultado_reproductivo: 'Éxito' },
    { etiqueta: 'B' },
  ];
  const p = puntosDe(lista);
  assert.equal(p.length, 1);
  assert.equal(p[0].color, '#2e6b3a');
});

test('informe: sección de mapas agrupada e imágenes incrustadas', () => {
  const mapas = [
    { nivel: 'general', titulo: 'Todos los nidos', n: 5, dataUrl: 'data:image/png;base64,AAA' },
    { nivel: 'comunidad', titulo: 'Galicia', n: 2, dataUrl: 'data:image/png;base64,BBB' },
    { nivel: 'comunidad', titulo: 'Comunidad de Madrid', n: 1, dataUrl: 'data:image/png;base64,CCC' },
  ];
  const html = seccionMapas(mapas, 2);
  assert.match(html, /Por comunidad autónoma/);
  assert.match(html, /<table class="mapas">/);
  assert.match(html, /Galicia · 2 nido\(s\)/);
  assert.match(html, /2 nido\(s\) sin coordenadas/);

  const doc = construirInforme(datos, {
    titulo: 'T', referencia: 'R', fecha: new Date(2026, 10, 2), secciones: ['comunidades', 'provincias'], mapas,
  });
  assert.match(doc, /1\. Mapas de localización/);
  assert.match(doc, /2\. Resultados por comunidad autónoma/);
  assert.match(doc, /3\. Resultados por provincia/);
  assert.match(doc, /Castilla-La Mancha/);
});
