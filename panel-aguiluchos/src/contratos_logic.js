// Lógica pura de parcelas, propietarios y convenios (sin red ni DOM): se prueba con node --test.

export const ESTADOS_CONTRATO = ['borrador', 'enviado', 'firmado', 'caducado', 'rechazado'];
export const ETIQUETA_ESTADO = {
  borrador: 'Borrador', enviado: 'Enviado a firma', firmado: 'Firmado', caducado: 'Caducado', rechazado: 'Rechazado',
};
export const TIPOS_DOCUMENTO = {
  convenio_firmado: 'Convenio firmado',
  consentimiento_rgpd: 'Consentimiento RGPD',
  dni: 'Copia del DNI',
  titularidad_cuenta: 'Certificado de titularidad de la cuenta',
  hoja_catastral: 'Hoja catastral',
  croquis_sigpac: 'Croquis / salida gráfica SIGPAC',
  otro: 'Otro documento',
};
export const TIPOS_PROPIETARIO = { particular: 'Particular', representante: 'Representante de C.B. / SAT…', entidad: 'Entidad' };
export const UNIDADES_AYUDA = { ha: '€/ha', anual: '€/año', fijo: '€ fijo', variable: 'Variable (lonja…)' };
export const AVISO_CADUCIDAD_DIAS = 60;

export const PROGRAMA_POR_DEFECTO = 'Compensatorias esteparias · Comunidad de Madrid';

// ── Normalización ───────────────────────────────────────────────────────────
export const normRefCat = (s) => String(s ?? '').toUpperCase().replace(/[^A-Z0-9]/g, '');
export const normNif = (s) => String(s ?? '').toUpperCase().replace(/[^A-Z0-9]/g, '');

const txt = (v) => (v == null ? '' : String(v).trim());

/** Clave SIGPAC de una parcela (provincia, municipio, agregado, zona, polígono, parcela y recinto). */
export function claveSigpac(p) {
  const partes = [p.sigpac_provincia, p.sigpac_municipio, p.sigpac_agregado, p.sigpac_zona, p.sigpac_poligono, p.sigpac_parcela, p.sigpac_recinto];
  if (!txt(p.sigpac_poligono) || !txt(p.sigpac_parcela)) return '';
  return [p.pais || 'España', ...partes.map((x) => txt(x).replace(/^0+(?=\d)/, ''))].join('|').toLowerCase();
}

export function descripcionParcela(p) {
  if (!p) return '';
  const sig = txt(p.sigpac_poligono) || txt(p.sigpac_parcela)
    ? `Pol. ${txt(p.sigpac_poligono) || '—'} · Parc. ${txt(p.sigpac_parcela) || '—'}${txt(p.sigpac_recinto) ? ` · Rec. ${txt(p.sigpac_recinto)}` : ''}`
    : '';
  const ref = txt(p.referencia_catastral);
  const lugar = [txt(p.municipio), txt(p.provincia)].filter(Boolean).join(', ');
  return [sig, ref && `Ref. ${ref}`, lugar].filter(Boolean).join(' · ') || 'Parcela sin identificar';
}

// ── IBAN: nunca se guarda completo ───────────────────────────────────────────
/** «ES69 2100 4747 0401 0027 2447» -> «•••• •••• •••• •••• •••• 2447» (solo quedan los 4 últimos dígitos). */
export function mascararIban(iban) {
  const limpio = String(iban ?? '').replace(/[^A-Za-z0-9]/g, '');
  if (limpio.length < 8) return '';
  const oculto = '•'.repeat(limpio.length - 4) + limpio.slice(-4);
  return oculto.match(/.{1,4}/g).join(' ');
}
export const esIbanEnmascarado = (s) => /^[•\s]+[A-Za-z0-9]{4}$/.test(String(s ?? '').trim());

// ── Fechas y campañas ────────────────────────────────────────────────────────
const aFecha = (s) => {
  if (!s) return null;
  const d = new Date(`${String(s).slice(0, 10)}T00:00:00`);
  return Number.isNaN(d.getTime()) ? null : d;
};

/** Campaña (año) de un nido: la de su incubación o, si falta, la de la primera fecha disponible. */
export function campanaDeNido(n, hoy = new Date()) {
  for (const k of ['fecha_incubacion', 'fecha_entrada_nido', 'fecha_eclosion', 'fecha_vuelo']) {
    const d = aFecha(n?.[k]);
    if (d) return d.getFullYear();
  }
  return hoy.getFullYear();
}

// ── Semáforo de contrato por nido ────────────────────────────────────────────
export const SEMAFORO = {
  firmado: { color: '#2e6b3a', etiqueta: 'Contrato firmado' },
  caduca: { color: '#e08a1e', etiqueta: 'Contrato firmado: caduca pronto' },
  pendiente: { color: '#e08a1e', etiqueta: 'Contrato pendiente de firma' },
  sin: { color: '#c0392b', etiqueta: 'Sin contrato' },
  caducado: { color: '#c0392b', etiqueta: 'Contrato caducado' },
  sinparcela: { color: '#8a8f8c', etiqueta: 'Sin parcela vinculada' },
};
/** Valores del filtro «Contrato» del panel. */
export const FILTROS_CONTRATO = {
  firmado: 'Firmado vigente',
  pendiente: 'Pendiente de firma / caduca pronto',
  sin: 'Sin contrato / caducado',
  sinparcela: 'Sin parcela vinculada',
};
export const grupoSemaforo = (codigo) => (codigo === 'caduca' ? 'pendiente' : codigo === 'caducado' ? 'sin' : codigo);

const ORDEN_ESTADO = { firmado: 0, enviado: 1, borrador: 2, caducado: 3, rechazado: 4 };

/** Índices para consultar rápido el estado de contrato de cada nido. */
export function indexarContratos(datos) {
  const parcelas = datos?.parcelas ?? [];
  const contratos = new Map((datos?.contratos ?? []).map((c) => [c.id, c]));
  const porRefCat = new Map();
  for (const p of parcelas) {
    const k = normRefCat(p.referencia_catastral);
    if (k && !porRefCat.has(k)) porRefCat.set(k, p);
  }
  const parcelaPorId = new Map(parcelas.map((p) => [p.id, p]));
  const vinculo = new Map((datos?.vinculos ?? []).map((v) => [v.nido_id, v.parcela_id]));
  const lineasPorParcela = new Map();
  for (const l of datos?.lineas ?? []) {
    if (!lineasPorParcela.has(l.parcela_id)) lineasPorParcela.set(l.parcela_id, []);
    lineasPorParcela.get(l.parcela_id).push(l);
  }
  return { contratos, porRefCat, parcelaPorId, vinculo, lineasPorParcela };
}

/** Parcela de un nido: el vínculo explícito o, si no, la referencia catastral coincidente. */
export function parcelaDeNido(nido, ix) {
  const id = ix.vinculo.get(nido.id);
  if (id && ix.parcelaPorId.has(id)) return ix.parcelaPorId.get(id);
  const k = normRefCat(nido.referencia_catastral);
  return k ? ix.porRefCat.get(k) ?? null : null;
}

/**
 * Estado del contrato de un nido para su campaña.
 * @returns {{codigo:string, parcela:object|null, contrato:object|null, campana:number}}
 */
export function estadoContratoNido(nido, ix, hoy = new Date()) {
  const campana = campanaDeNido(nido, hoy);
  const parcela = parcelaDeNido(nido, ix);
  if (!parcela) return { codigo: 'sinparcela', parcela: null, contrato: null, campana };
  const candidatos = (ix.lineasPorParcela.get(parcela.id) ?? [])
    .filter((l) => l.campana === campana)
    .map((l) => ix.contratos.get(l.contrato_id))
    .filter(Boolean)
    .sort((a, b) => (ORDEN_ESTADO[a.estado] ?? 9) - (ORDEN_ESTADO[b.estado] ?? 9));
  const c = candidatos[0];
  if (!c || c.estado === 'rechazado') return { codigo: 'sin', parcela, contrato: c ?? null, campana };
  if (c.estado === 'caducado') return { codigo: 'caducado', parcela, contrato: c, campana };
  if (c.estado === 'firmado') {
    const fin = aFecha(c.vigencia_hasta);
    const hoy0 = new Date(hoy.getFullYear(), hoy.getMonth(), hoy.getDate());
    if (fin && fin < hoy0) return { codigo: 'caducado', parcela, contrato: c, campana };
    if (fin && (fin - hoy0) / 86_400_000 <= AVISO_CADUCIDAD_DIAS) return { codigo: 'caduca', parcela, contrato: c, campana };
    return { codigo: 'firmado', parcela, contrato: c, campana };
  }
  return { codigo: 'pendiente', parcela, contrato: c, campana };
}

/** Mapa nido.id -> estado de contrato (para tabla, filtro y mapa). */
export function estadosPorNido(nidos, datos, hoy = new Date()) {
  const ix = indexarContratos(datos);
  const m = new Map();
  for (const n of nidos) m.set(n.id, estadoContratoNido(n, ix, hoy));
  return m;
}

// ── Importes y pagos ─────────────────────────────────────────────────────────
const redondear = (v) => Math.round((Number(v) + Number.EPSILON) * 100) / 100;
export const aNumero = (v) => {
  if (v == null || v === '') return null;
  const n = Number(String(v).replace(/\s/g, '').replace(',', '.'));
  return Number.isFinite(n) ? n : null;
};

/** Importe sugerido de una línea: suma de las ayudas marcadas (por ha, por año o fijas). */
export function importeSugeridoLinea(linea, ayudas) {
  const sup = aNumero(linea.superficie_ha) ?? 0;
  let total = 0;
  for (const cod of linea.ayudas ?? []) {
    const a = ayudas.find((x) => x.codigo === cod);
    if (!a || a.importe == null) continue;
    total += a.unidad === 'ha' ? a.importe * sup : a.importe;
  }
  return redondear(total);
}

export const importeTotalLineas = (lineas) => redondear(lineas.reduce((s, l) => s + (aNumero(l.importe) ?? 0), 0));

/** Pagos del convenio: pct % a la firma y el resto a la finalización. */
export function generarPagos(total, pctFirma = 60) {
  const t = aNumero(total);
  if (t == null || t <= 0) return [];
  const pct = Math.min(100, Math.max(0, Math.round(pctFirma)));
  const firma = redondear((t * pct) / 100);
  const resto = redondear(t - firma);
  const pagos = [];
  if (firma > 0) pagos.push({ concepto: `Pago a la firma (${pct} %)`, importe: firma, estado: 'pendiente' });
  if (resto > 0) pagos.push({ concepto: `Pago a la finalización (${100 - pct} %)`, importe: resto, estado: 'pendiente' });
  return pagos;
}

export const formatoEuros = (v) =>
  v == null || v === '' || Number.isNaN(Number(v)) ? '—'
    : `${Number(v).toLocaleString('es-ES', { minimumFractionDigits: 2, maximumFractionDigits: 2 })} €`;

/** Compensación por campaña y por propietario (comprometido, pagado, pendiente). */
export function resumenCompensacion(contratos, pagos, propietarios) {
  const nombre = new Map(propietarios.map((p) => [p.id, p.nombre]));
  const pagosDe = new Map();
  for (const p of pagos) {
    if (!pagosDe.has(p.contrato_id)) pagosDe.set(p.contrato_id, []);
    pagosDe.get(p.contrato_id).push(p);
  }
  // Solo cuenta lo comprometido: convenios firmados (o ya caducados tras firmarse).
  const firmados = contratos.filter((c) => c.estado === 'firmado' || c.estado === 'caducado');
  const filas = firmados.map((c) => {
    const ps = pagosDe.get(c.id) ?? [];
    const pagado = redondear(ps.filter((p) => p.estado === 'pagado').reduce((s, p) => s + Number(p.importe), 0));
    const comprometido = aNumero(c.importe_total) ?? redondear(ps.reduce((s, p) => s + Number(p.importe), 0));
    return {
      contrato_id: c.id,
      campana: c.campana,
      propietario: nombre.get(c.propietario_id) ?? '—',
      estado: c.estado,
      comprometido,
      pagado,
      pendiente: redondear(Math.max(0, comprometido - pagado)),
    };
  });
  const porCampana = new Map();
  for (const f of filas) {
    const t = porCampana.get(f.campana) ?? { campana: f.campana, contratos: 0, comprometido: 0, pagado: 0, pendiente: 0 };
    t.contratos += 1;
    t.comprometido = redondear(t.comprometido + f.comprometido);
    t.pagado = redondear(t.pagado + f.pagado);
    t.pendiente = redondear(t.pendiente + f.pendiente);
    porCampana.set(f.campana, t);
  }
  return {
    filas: filas.sort((a, b) => b.campana - a.campana || a.propietario.localeCompare(b.propietario, 'es')),
    campanas: [...porCampana.values()].sort((a, b) => b.campana - a.campana),
  };
}

const csvCelda = (v) => {
  const s = String(v ?? '');
  return /[;"\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
};
export function compensacionACsv(resumen) {
  const cab = ['Campaña', 'Propietario', 'Estado', 'Comprometido (€)', 'Pagado (€)', 'Pendiente (€)'];
  const eur = (v) => String(v).replace('.', ',');
  const filas = resumen.filas.map((f) => [f.campana, f.propietario, ETIQUETA_ESTADO[f.estado] ?? f.estado, eur(f.comprometido), eur(f.pagado), eur(f.pendiente)]);
  return `\uFEFF${[cab, ...filas].map((r) => r.map(csvCelda).join(';')).join('\r\n')}`;
}

// ── Validación de formularios ────────────────────────────────────────────────
export function validarPropietario(p) {
  const e = [];
  if (!txt(p.nombre)) e.push('El nombre es obligatorio.');
  if (txt(p.email) && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(txt(p.email))) e.push('El correo no es válido.');
  if (p.iban_enmascarado && !esIbanEnmascarado(p.iban_enmascarado)) e.push('El IBAN debe estar enmascarado (solo los últimos 4 dígitos).');
  return e;
}

export function validarParcela(p) {
  const e = [];
  const tieneSigpac = txt(p.sigpac_poligono) && txt(p.sigpac_parcela);
  if (!tieneSigpac && !txt(p.referencia_catastral)) e.push('Indica polígono y parcela (SIGPAC) o la referencia catastral.');
  const sup = aNumero(p.superficie_ha);
  if (txt(p.superficie_ha) && (sup == null || sup < 0)) e.push('La superficie no es válida.');
  return e;
}

export function validarContrato(c, lineas) {
  const e = [];
  if (!c.propietario_id) e.push('Elige el propietario (titular).');
  if (!Number.isInteger(Number(c.campana)) || c.campana < 2000) e.push('La campaña no es válida.');
  if (!lineas.length) e.push('Añade al menos una parcela al convenio.');
  if (c.estado === 'firmado' && !c.fecha_firma) e.push('Un convenio firmado necesita la fecha de firma.');
  if (c.vigencia_desde && c.vigencia_hasta && c.vigencia_hasta < c.vigencia_desde) e.push('La vigencia termina antes de empezar.');
  const repetidas = new Set();
  for (const l of lineas) {
    if (repetidas.has(l.parcela_id)) e.push('Una parcela está repetida en el convenio.');
    repetidas.add(l.parcela_id);
  }
  return [...new Set(e)];
}

/** Avisos de convenios firmados que caducan pronto o ya caducaron. */
export function avisosCaducidad(contratos, hoy = new Date()) {
  const hoy0 = new Date(hoy.getFullYear(), hoy.getMonth(), hoy.getDate());
  const out = [];
  for (const c of contratos) {
    if (c.estado !== 'firmado') continue;
    const fin = aFecha(c.vigencia_hasta);
    if (!fin) continue;
    const dias = Math.round((fin - hoy0) / 86_400_000);
    if (dias <= AVISO_CADUCIDAD_DIAS) out.push({ contrato: c, dias });
  }
  return out.sort((a, b) => a.dias - b.dias);
}

// ── Asociación automática de un convenio con nidos ya registrados ────────────
const PALABRAS_VACIAS = new Set(['de', 'del', 'la', 'el', 'los', 'las', 'y', 'e', 'sl', 'sa', 'sat', 'cb', 'scp']);
const tokensNombre = (s) => String(s ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase()
  .replace(/[^a-z0-9 ]/g, ' ').split(/\s+/).filter((t) => t.length > 1 && !PALABRAS_VACIAS.has(t));
export const normTelefono = (s) => {
  const d = String(s ?? '').replace(/\D/g, '');
  return d.length >= 9 ? d.slice(-9) : '';
};

/** ¿Es el mismo nombre? Exige al menos 2 palabras en común y que todas las de la lista más corta estén en la otra. */
export function mismoNombre(a, b) {
  const A = new Set(tokensNombre(a));
  const B = new Set(tokensNombre(b));
  if (A.size < 2 || B.size < 2) return false;
  const comunes = [...A].filter((t) => B.has(t)).length;
  return comunes >= 2 && comunes >= Math.min(A.size, B.size);
}

/**
 * Nidos que probablemente pertenecen al titular de un convenio (por nombre del propietario y/o teléfono).
 * @param {object[]} nidos
 * @param {{nombre?:string, entidad?:string, telefono?:string}} titular
 * @param {Set<string>} [excluir] ids de nidos que ya tienen parcela
 * @returns {{nido:object, motivos:string[], fuerza:number}[]} de más a menos probable
 */
export function candidatosNidos(nidos, titular, excluir = new Set()) {
  const tel = normTelefono(titular?.telefono);
  const out = [];
  for (const n of nidos) {
    if (excluir.has(n.id)) continue;
    const motivos = [];
    if (n.propietario && (mismoNombre(n.propietario, titular?.nombre) || mismoNombre(n.propietario, titular?.entidad))) motivos.push('mismo nombre de propietario');
    if (tel && normTelefono(n.tlfn) === tel) motivos.push('mismo teléfono');
    if (motivos.length) out.push({ nido: n, motivos, fuerza: motivos.length });
  }
  return out.sort((a, b) => b.fuerza - a.fuerza || String(a.nido.numeracion).localeCompare(String(b.nido.numeracion), 'es', { numeric: true }));
}
