import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { AYUDA_TAB, GRUPOS, MANUAL, ayudaBtn, idsEnlazadosEnManual, manualHtmlCompleto } from '../src/ayuda.js';

const ids = new Set(MANUAL.map((s) => s.id));

test('manual: ids únicos, con título, grupo válido y contenido', () => {
  assert.equal(ids.size, MANUAL.length);
  const grupos = new Set(GRUPOS.map(([g]) => g));
  for (const s of MANUAL) {
    assert.ok(s.titulo.length > 3, s.id);
    assert.ok(grupos.has(s.grupo), `grupo inválido en ${s.id}`);
    assert.ok(s.html.length > 80, `contenido vacío en ${s.id}`);
    assert.ok(!s.html.includes('${'), `plantilla sin resolver en ${s.id}`);
    assert.ok(!s.html.includes('undefined'), `undefined en ${s.id}`);
  }
});

test('manual: todos los enlaces internos apuntan a secciones existentes', () => {
  for (const id of idsEnlazadosEnManual()) assert.ok(ids.has(id), `enlace roto: ${id}`);
});

test('ayuda contextual: cada id usado en el código existe en el manual', () => {
  const dir = new URL('../src/', import.meta.url);
  const usados = new Set();
  for (const f of readdirSync(dir).filter((n) => n.endsWith('.js') && n !== 'ayuda.js')) {
    const src = readFileSync(new URL(f, dir), 'utf8');
    for (const m of src.matchAll(/ayudaBtn\(\s*'([a-z0-9-]+)'/g)) usados.add(m[1]);
    for (const m of src.matchAll(/ayuda:\s*'([a-z0-9-]+)'/g)) usados.add(m[1]);
    for (const m of src.matchAll(/data-ayuda="([a-z0-9-]+)"/g)) usados.add(m[1]);
  }
  assert.ok(usados.size >= 15, `pocos ids de ayuda contextual (${usados.size})`);
  for (const id of usados) assert.ok(ids.has(id), `falta la sección «${id}» del manual`);
  for (const id of Object.values(AYUDA_TAB)) assert.ok(ids.has(id), `falta la sección de pestaña «${id}»`);
  for (const id of ['ficha', 'nuevo-nido', 'informe-editor', 'borradores', 'mapa', 'tabla', 'causas', 'filtros', 'indicadores']) {
    assert.ok(ids.has(id), id);
  }
});

test('ayudaBtn escapa el id y es un botón sin envío', () => {
  const h = ayudaBtn('a"b');
  assert.ok(h.includes('type="button"'));
  assert.ok(h.includes('data-ayuda="a&quot;b"'));
});

test('manual descargable: documento completo con índice y enlaces internos', () => {
  const h = manualHtmlCompleto();
  assert.ok(h.startsWith('<!DOCTYPE html>'));
  assert.ok(h.includes('href="#semaforo"'));
  assert.ok(!h.includes('data-ayuda'));
  for (const s of MANUAL) assert.ok(h.includes(`id="${s.id}"`), s.id);
});
