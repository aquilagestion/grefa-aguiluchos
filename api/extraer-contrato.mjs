import { ErrorApi, extraerContrato } from '../panel-aguiluchos/api/_extraccion.js';

// POST /api/extraer-contrato   { "path": "<ruta en el bucket contratos>" }
// Cabecera: Authorization: Bearer <JWT de Supabase del usuario>
// Vercel Function en la raíz del repo (el proyecto de Vercel usa la raíz como Root Directory).
export const config = { maxDuration: 60 };

export default async function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store');
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Método no permitido.' });
  }
  try {
    const cuerpo = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : req.body ?? {};
    const token = String(req.headers.authorization ?? '').replace(/^Bearer\s+/i, '');
    const env = {
      SUPABASE_URL: process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL,
      SUPABASE_ANON_KEY: process.env.SUPABASE_ANON_KEY || process.env.VITE_SUPABASE_ANON_KEY,
      MISTRAL_API_KEY: process.env.MISTRAL_API_KEY,
      MISTRAL_OCR_MODEL: process.env.MISTRAL_OCR_MODEL,
      MISTRAL_MODEL: process.env.MISTRAL_MODEL,
    };
    const { datos, paginas, modelo } = await extraerContrato({ path: cuerpo.path, token }, env);
    return res.status(200).json({ datos, paginas, modelo });
  } catch (e) {
    const status = e instanceof ErrorApi ? e.status : 500;
    // Sin detalles internos ni contenido del documento en el mensaje.
    return res.status(status).json({ error: e instanceof ErrorApi ? e.message : 'Error interno al leer el contrato.' });
  }
}
