import { supabase } from './api.js';

const BUCKET = 'contratos';
const PAGINA = 1000;

export const T = {
  propietarios: 'propietarios_grefa',
  parcelas: 'parcelas_grefa',
  titularidad: 'parcela_propietarios_grefa',
  vinculos: 'nido_parcela_grefa',
  ayudas: 'ayudas_grefa',
  contratos: 'contratos_grefa',
  lineas: 'contrato_parcelas_grefa',
  pagos: 'contrato_pagos_grefa',
  documentos: 'contrato_documentos_grefa',
};

/** Las tablas aún no existen: falta ejecutar `contratos_parcelas.sql` en Supabase. */
export class FaltanTablas extends Error {
  constructor() {
    super('Faltan las tablas de contratos en Supabase. Ejecuta aguiluchos/supabase/contratos_parcelas.sql en el SQL Editor.');
    this.name = 'FaltanTablas';
  }
}

const sinTabla = (e) => e && (e.code === '42P01' || e.code === 'PGRST205' || /schema cache|does not exist/i.test(e.message ?? ''));

/** Traduce errores habituales de Postgres a mensajes entendibles. */
export function mensajeError(e) {
  if (e instanceof FaltanTablas) return e.message;
  const m = String(e?.message ?? e);
  if (e?.code === '23505') {
    if (/contrato_parcelas_grefa_uq/.test(m)) return 'Una de las parcelas ya figura en otro convenio de esa campaña.';
    if (/propietarios_grefa_nif_uq/.test(m)) return 'Ya existe un propietario con ese NIF.';
    if (/parcelas_grefa_sigpac_uq/.test(m)) return 'Ya existe una parcela con esa identificación SIGPAC.';
    return 'Ya existe un registro igual.';
  }
  if (e?.code === '42501' || /row-level security|permission denied/i.test(m)) return 'No tienes permiso para esta operación.';
  if (e?.code === '23503') return 'No se puede completar: hay datos relacionados (por ejemplo, un convenio que usa este registro).';
  return m;
}

async function leerTodo(tabla, orden) {
  const filas = [];
  for (let desde = 0; ; desde += PAGINA) {
    let q = supabase.from(tabla).select('*').range(desde, desde + PAGINA - 1);
    if (orden) q = q.order(orden, { ascending: true });
    const { data, error } = await q;
    if (error) throw sinTabla(error) ? new FaltanTablas() : error;
    filas.push(...data);
    if (data.length < PAGINA) break;
  }
  return filas;
}

/** Todos los datos de parcelas, propietarios y convenios (volumen pequeño). */
export async function cargarDatosContratos() {
  const [propietarios, parcelas, titularidad, vinculos, ayudas, contratos, lineas, pagos] = await Promise.all([
    leerTodo(T.propietarios, 'nombre'),
    leerTodo(T.parcelas, 'created_at'),
    leerTodo(T.titularidad),
    leerTodo(T.vinculos),
    leerTodo(T.ayudas, 'codigo'),
    leerTodo(T.contratos, 'campana'),
    leerTodo(T.lineas),
    leerTodo(T.pagos, 'created_at'),
  ]);
  return { propietarios, parcelas, titularidad, vinculos, ayudas, contratos, lineas, pagos };
}

const limpiar = (fila) => Object.fromEntries(Object.entries(fila).map(([k, v]) => [k, v === '' ? null : v]));

/** Inserta o actualiza una fila y devuelve la fila guardada. */
export async function guardarFila(tabla, fila, esNuevo) {
  const f = limpiar(fila);
  const { id, ...resto } = f;
  const q = esNuevo
    ? supabase.from(tabla).insert(id ? { id, ...resto } : resto)
    : supabase.from(tabla).update(resto).eq('id', id);
  const { data, error } = await q.select().single();
  if (error) throw error;
  return data;
}

export async function borrarFila(tabla, id) {
  const { error } = await supabase.from(tabla).delete().eq('id', id);
  if (error) throw error;
}

/** Sincroniza una lista hija (líneas, pagos…) con la lista deseada: borra, actualiza e inserta por id. */
async function sincronizarHijos(tabla, padreClave, padreId, existentes, deseadas) {
  const ids = new Set(deseadas.filter((x) => x.id).map((x) => x.id));
  const quitar = existentes.filter((x) => !ids.has(x.id)).map((x) => x.id);
  if (quitar.length) {
    const { error } = await supabase.from(tabla).delete().in('id', quitar);
    if (error) throw error;
  }
  for (const h of deseadas) {
    const fila = { ...limpiar(h), [padreClave]: padreId };
    if (h.id && existentes.some((x) => x.id === h.id)) {
      const { id, ...resto } = fila;
      const { error } = await supabase.from(tabla).update(resto).eq('id', id);
      if (error) throw error;
    } else {
      const { id: _omitir, ...resto } = fila;
      const { error } = await supabase.from(tabla).insert(resto);
      if (error) throw error;
    }
  }
}

/** Guarda un convenio con sus líneas de parcela y sus pagos. */
export async function guardarConvenio({ contrato, lineas, pagos, existentes }) {
  const esNuevo = !existentes?.contrato;
  const { id: _i, ...campos } = contrato;
  const guardado = await guardarFila(T.contratos, { id: contrato.id, ...campos }, esNuevo);
  // Primero se retiran las líneas quitadas y luego se insertan las nuevas (evita choques del índice único).
  await sincronizarHijos(T.lineas, 'contrato_id', guardado.id, existentes?.lineas ?? [], lineas.map(({ campana: _c, ...l }) => l));
  await sincronizarHijos(T.pagos, 'contrato_id', guardado.id, existentes?.pagos ?? [], pagos);
  return guardado;
}

export async function asignarTitular(parcelaId, propietarioId, porcentaje = null) {
  const { error } = await supabase.from(T.titularidad)
    .upsert({ parcela_id: parcelaId, propietario_id: propietarioId, porcentaje }, { onConflict: 'parcela_id,propietario_id' });
  if (error) throw error;
}

export async function quitarTitular(parcelaId, propietarioId) {
  const { error } = await supabase.from(T.titularidad).delete().eq('parcela_id', parcelaId).eq('propietario_id', propietarioId);
  if (error) throw error;
}

export async function vincularNido(nidoId, parcelaId) {
  const { error } = await supabase.from(T.vinculos).upsert({ nido_id: nidoId, parcela_id: parcelaId }, { onConflict: 'nido_id' });
  if (error) throw error;
}

export async function desvincularNido(nidoId) {
  const { error } = await supabase.from(T.vinculos).delete().eq('nido_id', nidoId);
  if (error) throw error;
}

// ── Documentos (bucket privado) ──────────────────────────────────────────────
export const nombreSeguro = (nombre) =>
  String(nombre ?? 'documento').normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[^A-Za-z0-9._-]+/g, '_').replace(/^_+|_+$/g, '').slice(-80) || 'documento';

export async function sha256(archivo) {
  const buf = await archivo.arrayBuffer();
  const h = await crypto.subtle.digest('SHA-256', buf);
  return [...new Uint8Array(h)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/** Sube un archivo al bucket y devuelve sus metadatos (todavía sin fila en la base de datos). */
export async function subirArchivo(archivo, carpeta) {
  const path = `${carpeta}/${crypto.randomUUID()}-${nombreSeguro(archivo.name)}`;
  const { error } = await supabase.storage.from(BUCKET).upload(path, archivo, {
    contentType: archivo.type || 'application/octet-stream',
    upsert: false,
  });
  if (error) throw error;
  return { storage_path: path, nombre: archivo.name, mime: archivo.type || null, tamano: archivo.size, sha256: await sha256(archivo) };
}

export async function registrarDocumento({ meta, tipo, contratoId = null, propietarioId = null, extraccion = null }) {
  return guardarFila(T.documentos, {
    ...meta, tipo, contrato_id: contratoId, propietario_id: propietarioId, extraccion,
  }, true);
}

export async function listarDocumentos({ contratoId, propietarioId }) {
  let q = supabase.from(T.documentos).select('*').order('created_at', { ascending: false });
  if (contratoId) q = q.eq('contrato_id', contratoId);
  if (propietarioId) q = q.eq('propietario_id', propietarioId);
  const { data, error } = await q;
  if (error) throw sinTabla(error) ? new FaltanTablas() : error;
  return data;
}

export async function urlDocumento(path, segundos = 300) {
  const { data, error } = await supabase.storage.from(BUCKET).createSignedUrl(path, segundos);
  if (error) throw error;
  return data.signedUrl;
}

/** Borra la fila y el archivo (solo el administrador; la base de datos lo exige). */
export async function borrarDocumento(doc) {
  const { error } = await supabase.from(T.documentos).delete().eq('id', doc.id);
  if (error) throw error;
  await supabase.storage.from(BUCKET).remove([doc.storage_path]);
}

/** Documento ya subido con el mismo contenido (evita importar dos veces el mismo PDF). */
export async function documentoPorHash(hash) {
  const { data, error } = await supabase.from(T.documentos).select('id, nombre, contrato_id, propietario_id').eq('sha256', hash).limit(1);
  if (error) throw sinTabla(error) ? new FaltanTablas() : error;
  return data?.[0] ?? null;
}

/** Lee el convenio con Mistral (función de servidor). Devuelve { datos, paginas, modelo }. */
export async function extraerConMistral(path) {
  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token;
  const r = await fetch('/api/extraer-contrato', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token ?? ''}` },
    body: JSON.stringify({ path }),
  });
  let cuerpo = null;
  try { cuerpo = await r.json(); } catch { /* respuesta no JSON */ }
  if (!r.ok) throw new Error(cuerpo?.error ?? `La lectura del contrato falló (${r.status}).`);
  return cuerpo;
}
