// Lectura de convenios escaneados con Mistral (OCR + extracción estructurada).
// Se ejecuta SOLO en el servidor (función de Vercel): la clave MISTRAL_API_KEY no llega al navegador.
// Privacidad: no se guarda ni se registra el texto del documento; el IBAN se enmascara aquí mismo
// y solo se devuelven sus 4 últimos dígitos.

import { mascararIban } from '../src/contratos_logic.js';

export class ErrorApi extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

const MISTRAL = 'https://api.mistral.ai/v1';
const DOMINIO = /^[^@\s]+@grefa\.org$/i;

export const PROMPT_SISTEMA = `Eres un asistente que lee convenios de colaboración de GREFA con propietarios o titulares de parcelas
(programa de medidas compensatorias para aves esteparias). Recibes el texto obtenido por OCR de un documento escaneado, con partes
manuscritas, que puede contener errores. Devuelve SOLO un objeto JSON con esta forma exacta (null si el dato no consta o no es legible;
no inventes nada):

{
  "fecha_firma": "AAAA-MM-DD" | null,
  "lugar_firma": string | null,
  "titular": { "nombre": string | null, "nif": string | null, "regepa": string | null,
               "tipo": "particular" | "representante" | "entidad" | null, "entidad": string | null,
               "telefono": string | null, "email": string | null, "direccion": string | null },
  "firmante_grefa": string | null,
  "cargo_firmante": string | null,
  "programa": string | null,
  "zona_programa": string | null,
  "parcelas": [ { "sigpac_municipio": string | null, "sigpac_poligono": string | null, "sigpac_parcela": string | null,
                  "sigpac_agregado": string | null, "sigpac_zona": string | null, "sigpac_recinto": string | null,
                  "superficie_ha": number | null, "uso": string | null, "ayudas": [number] } ],
  "importe_total": number | null,
  "pct_firma": number | null,
  "iban": string | null,
  "consentimiento_rgpd_firmado": true | false | null,
  "dudas": [string]
}

Reglas:
- La tabla de parcelas tiene las columnas MUN, POL, PAR, AGR, ZONA, REC, SUP, USO y 9 casillas de «código de la ayuda» (1 a 9):
  "ayudas" lista los números de las casillas marcadas (con una X) en esa fila. Una fila vacía no es una parcela.
- "importe_total" es el precio del contrato en euros (número, sin símbolo). "pct_firma" es el porcentaje que se abona a la firma (p. ej. 60).
- "titular.tipo": "particular" si firma a título personal; "representante" si representa a una C.B., SAT u otra entidad (pon su nombre en "entidad").
- "iban": transcribe el IBAN completo si es legible (se enmascarará después); si no, null.
- "zona_programa": la zona indicada en la estipulación primera (p. ej. «Zona 4 - La Sagra Madrileña»).
- En "dudas" anota, en una frase corta cada una, los datos manuscritos o ilegibles de los que no estés seguro.
- No incluyas texto fuera del JSON.`;

const cadena = (v, max = 300) => {
  if (v == null) return null;
  const s = String(v).replace(/\s+/g, ' ').trim();
  return s ? s.slice(0, max) : null;
};
const numero = (v) => {
  if (v == null || v === '') return null;
  const n = Number(String(v).replace(/\s/g, '').replace(/€/g, '').replace(',', '.'));
  return Number.isFinite(n) ? n : null;
};
const fecha = (v) => {
  const s = cadena(v, 40);
  if (!s) return null;
  let m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
  if (!m) {
    const d = /^(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})$/.exec(s);
    if (d) m = [s, d[3], d[2].padStart(2, '0'), d[1].padStart(2, '0')];
  }
  if (!m) return null;
  const dt = new Date(`${m[1]}-${m[2]}-${m[3]}T00:00:00Z`);
  return Number.isNaN(dt.getTime()) ? null : `${m[1]}-${m[2]}-${m[3]}`;
};

/** Normaliza lo que devuelve el modelo: tipos correctos, IBAN enmascarado y nada inesperado. */
export function normalizarExtraccion(bruto) {
  const b = bruto && typeof bruto === 'object' ? bruto : {};
  const t = b.titular && typeof b.titular === 'object' ? b.titular : {};
  const tipo = ['particular', 'representante', 'entidad'].includes(t.tipo) ? t.tipo : null;
  const ayudas = (a) => [...new Set((Array.isArray(a) ? a : []).map((x) => Math.trunc(Number(x))).filter((x) => x >= 1 && x <= 99))].sort((x, y) => x - y);
  const parcelas = (Array.isArray(b.parcelas) ? b.parcelas : [])
    .map((p) => ({
      sigpac_municipio: cadena(p?.sigpac_municipio, 10),
      sigpac_poligono: cadena(p?.sigpac_poligono, 10),
      sigpac_parcela: cadena(p?.sigpac_parcela, 10),
      sigpac_agregado: cadena(p?.sigpac_agregado, 10),
      sigpac_zona: cadena(p?.sigpac_zona, 10),
      sigpac_recinto: cadena(p?.sigpac_recinto, 10),
      superficie_ha: numero(p?.superficie_ha),
      uso: cadena(p?.uso, 20),
      ayudas: ayudas(p?.ayudas),
    }))
    .filter((p) => p.sigpac_poligono || p.sigpac_parcela);
  const pct = numero(b.pct_firma);
  return {
    fecha_firma: fecha(b.fecha_firma),
    lugar_firma: cadena(b.lugar_firma, 80),
    titular: {
      nombre: cadena(t.nombre, 160),
      nif: cadena(t.nif, 20)?.toUpperCase().replace(/[^A-Z0-9]/g, '') ?? null,
      regepa: cadena(t.regepa, 40),
      tipo,
      entidad: cadena(t.entidad, 160),
      telefono: cadena(t.telefono, 30),
      email: cadena(t.email, 120),
      direccion: cadena(t.direccion, 200),
    },
    firmante_grefa: cadena(b.firmante_grefa, 120),
    cargo_firmante: cadena(b.cargo_firmante, 120),
    programa: cadena(b.programa, 200),
    zona_programa: cadena(b.zona_programa, 120),
    parcelas,
    importe_total: numero(b.importe_total),
    pct_firma: pct != null && pct >= 0 && pct <= 100 ? Math.round(pct) : null,
    // El IBAN completo no sale de esta función.
    iban_enmascarado: mascararIban(b.iban) || null,
    consentimiento_rgpd_firmado: typeof b.consentimiento_rgpd_firmado === 'boolean' ? b.consentimiento_rgpd_firmado : null,
    dudas: (Array.isArray(b.dudas) ? b.dudas : []).map((d) => cadena(d, 200)).filter(Boolean).slice(0, 12),
  };
}

/** Extrae el objeto JSON de una respuesta del modelo (admite ```json … ```). */
export function parsearJson(texto) {
  let s = String(texto ?? '').trim();
  const bloque = /```(?:json)?\s*([\s\S]*?)```/i.exec(s);
  if (bloque) s = bloque[1].trim();
  const ini = s.indexOf('{');
  const fin = s.lastIndexOf('}');
  if (ini < 0 || fin <= ini) throw new ErrorApi(502, 'El modelo no devolvió datos legibles.');
  try {
    return JSON.parse(s.slice(ini, fin + 1));
  } catch {
    throw new ErrorApi(502, 'El modelo devolvió un JSON no válido.');
  }
}

/** Ruta permitida dentro del bucket `contratos`. */
export function rutaValida(path) {
  return typeof path === 'string' && path.length <= 300 && /^[A-Za-z0-9_\-./]+$/.test(path) && !path.includes('..') && !path.startsWith('/');
}

async function json(resp) {
  try {
    return await resp.json();
  } catch {
    return null;
  }
}

/**
 * @param {{path:string, token:string}} entrada  ruta en el bucket y JWT del usuario
 * @param {{SUPABASE_URL:string, SUPABASE_ANON_KEY:string, MISTRAL_API_KEY:string, MISTRAL_OCR_MODEL?:string, MISTRAL_MODEL?:string}} env
 * @param {typeof fetch} fetchImpl
 */
export async function extraerContrato({ path, token }, env, fetchImpl = fetch) {
  if (!env.MISTRAL_API_KEY) throw new ErrorApi(503, 'Falta configurar MISTRAL_API_KEY en el servidor.');
  if (!env.SUPABASE_URL || !env.SUPABASE_ANON_KEY) throw new ErrorApi(503, 'Falta configurar Supabase en el servidor.');
  if (!token) throw new ErrorApi(401, 'Inicia sesión para leer contratos.');
  if (!rutaValida(path)) throw new ErrorApi(400, 'Ruta de documento no válida.');
  const base = env.SUPABASE_URL.replace(/\/$/, '');

  // 1) Solo usuarios @grefa.org con sesión válida.
  const u = await fetchImpl(`${base}/auth/v1/user`, { headers: { apikey: env.SUPABASE_ANON_KEY, Authorization: `Bearer ${token}` } });
  const usuario = u.ok ? await json(u) : null;
  if (!usuario?.email || !DOMINIO.test(usuario.email)) throw new ErrorApi(401, 'Sesión no válida.');

  // 2) URL firmada de corta vida (con el permiso del propio usuario: RLS de Storage).
  const s = await fetchImpl(`${base}/storage/v1/object/sign/contratos/${path.split('/').map(encodeURIComponent).join('/')}`, {
    method: 'POST',
    headers: { apikey: env.SUPABASE_ANON_KEY, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ expiresIn: 300 }),
  });
  const firma = s.ok ? await json(s) : null;
  if (!firma?.signedURL) throw new ErrorApi(404, 'No se encontró el documento o no tienes acceso.');
  const urlDocumento = firma.signedURL.startsWith('http') ? firma.signedURL : `${base}/storage/v1${firma.signedURL}`;

  // 3) OCR (PDF o imagen).
  const esImagen = /\.(jpe?g|png|webp)$/i.test(path);
  const ocr = await fetchImpl(`${MISTRAL}/ocr`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${env.MISTRAL_API_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: env.MISTRAL_OCR_MODEL || 'mistral-ocr-latest',
      document: esImagen ? { type: 'image_url', image_url: urlDocumento } : { type: 'document_url', document_url: urlDocumento },
    }),
  });
  if (!ocr.ok) throw new ErrorApi(502, `Mistral OCR respondió ${ocr.status}.`);
  const ocrJson = await json(ocr);
  const texto = (ocrJson?.pages ?? []).map((p) => p.markdown ?? '').join('\n\n---\n\n').trim();
  if (!texto) throw new ErrorApi(422, 'No se pudo leer texto del documento.');

  // 4) Extracción estructurada.
  const chat = await fetchImpl(`${MISTRAL}/chat/completions`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${env.MISTRAL_API_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: env.MISTRAL_MODEL || 'mistral-large-latest',
      temperature: 0,
      response_format: { type: 'json_object' },
      messages: [
        { role: 'system', content: PROMPT_SISTEMA },
        { role: 'user', content: `Texto del documento (OCR):\n\n${texto.slice(0, 60_000)}` },
      ],
    }),
  });
  if (!chat.ok) throw new ErrorApi(502, `Mistral respondió ${chat.status} al extraer los datos.`);
  const chatJson = await json(chat);
  const contenido = chatJson?.choices?.[0]?.message?.content;
  const datos = normalizarExtraccion(parsearJson(contenido));
  return { datos, paginas: ocrJson.pages.length, modelo: env.MISTRAL_MODEL || 'mistral-large-latest' };
}
