import { createClient } from '@supabase/supabase-js';
import { COLUMNAS } from './columns.js';

const url = import.meta.env.VITE_SUPABASE_URL;
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

export const configurado = Boolean(url && anonKey && !url.includes('xxxx'));
export const exigeLogin = String(import.meta.env.VITE_REQUIRE_LOGIN ?? 'true') !== 'false';

export const supabase = configurado ? createClient(url, anonKey) : null;

// Los enlaces de confirmación y recuperación abren grefa-proyectos, que ya sabe
// fijar la contraseña nueva (mismo proyecto de Supabase, misma cuenta).
const URL_CONFIRMACION = 'https://grefa-proyectos.vercel.app/auth/callback?next=/';
const URL_RECUPERACION = 'https://grefa-proyectos.vercel.app/auth/callback?next=/actualizar-contrasena';

const mensajeAuth = (error) => {
  const m = String(error?.message ?? error).toLowerCase();
  if (m.includes('invalid login')) return 'Correo o contraseña incorrectos.';
  if (m.includes('not confirmed')) return 'El correo todavía no está confirmado. Abre el enlace que te enviamos.';
  if (m.includes('already registered')) return 'Ese correo ya tiene cuenta. Inicia sesión o recupera la contraseña.';
  if (m.includes('same password') || m.includes('different from the old')) return 'La contraseña nueva debe ser distinta de la actual.';
  if (m.includes('rate limit')) return 'Demasiados intentos. Espera unos minutos.';
  return error?.message ?? String(error);
};

/** Crea la cuenta; devuelve true si queda con sesión y false si hay que confirmar el correo. */
export async function registrar({ nombre, email, clave }) {
  const { data, error } = await supabase.auth.signUp({
    email: email.trim().toLowerCase(),
    password: clave,
    options: { data: { full_name: nombre.trim() }, emailRedirectTo: URL_CONFIRMACION },
  });
  if (error) throw new Error(mensajeAuth(error));
  return Boolean(data.session);
}

export async function recuperarClave(email) {
  const { error } = await supabase.auth.resetPasswordForEmail(email.trim().toLowerCase(), { redirectTo: URL_RECUPERACION });
  if (error) throw new Error(mensajeAuth(error));
}

export async function cambiarClave(clave) {
  const { error } = await supabase.auth.updateUser({ password: clave });
  if (error) throw new Error(mensajeAuth(error));
}

const TABLA = 'nidos_grefa';
const PAGINA = 1000;

export async function cargarNidos() {
  const todos = [];
  for (let desde = 0; ; desde += PAGINA) {
    const { data, error } = await supabase
      .from(TABLA)
      .select('*')
      .eq('is_deleted', false)
      .order('numeracion', { ascending: true })
      .order('id', { ascending: true })
      .range(desde, desde + PAGINA - 1);
    if (error) throw error;
    todos.push(...data);
    if (data.length < PAGINA) break;
  }
  return todos;
}

const soloColumnas = (n) => Object.fromEntries(COLUMNAS.map((c) => [c.key, n[c.key] ?? (c.tipo === 'list' ? [] : null)]));

/**
 * Crea o actualiza un nido. `updated_at` es la hora de edición del cliente: el
 * trigger de Supabase aplica Last-Write-Wins (gana el mayor). Devuelve la fila
 * resultante y si el servidor conservó una versión más reciente que la nuestra.
 */
export async function guardarNido(nido, esNuevo) {
  const ahora = new Date().toISOString();
  const fila = { ...soloColumnas(nido), updated_at: ahora, is_deleted: false };
  const q = esNuevo
    ? supabase.from(TABLA).insert({ id: nido.id, ...fila })
    : supabase.from(TABLA).update(fila).eq('id', nido.id);
  const { data, error } = await q.select().single();
  if (error) throw error;
  return { fila: data, descartado: new Date(data.updated_at) > new Date(ahora) };
}

/**
 * Tiempo real: avisa de cada cambio en `nidos_grefa` (app de campo, otro panel…).
 * `onEvento` recibe el payload de postgres_changes; `onEstado` el estado del canal
 * (SUBSCRIBED, CHANNEL_ERROR, TIMED_OUT, CLOSED). Devuelve la función para cancelar.
 * Requiere la tabla en la publicación `supabase_realtime`
 * (ver `aguiluchos/supabase/habilitar_realtime.sql`).
 */
export function suscribirCambios({ onEvento, onEstado }) {
  const canal = supabase
    .channel('nidos-grefa-en-vivo')
    .on('postgres_changes', { event: '*', schema: 'public', table: TABLA }, onEvento)
    .subscribe((estado) => onEstado(estado));
  return () => supabase.removeChannel(canal);
}

export async function borrarNido(id) {
  const { error } = await supabase
    .from(TABLA)
    .update({ is_deleted: true, updated_at: new Date().toISOString() })
    .eq('id', id);
  if (error) throw error;
}
