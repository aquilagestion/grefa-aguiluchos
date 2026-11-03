// Editores de propietarios, parcelas y convenios (y documentos, ayudas e importación del escaneo).
import { esc } from './informe.js';
import { guardarArchivo, pintarEditorHtml } from './informe_ui.js';
import { posicion } from './logic.js';
import {
  ETIQUETA_ESTADO, ESTADOS_CONTRATO, PROGRAMA_POR_DEFECTO, TIPOS_DOCUMENTO, TIPOS_PROPIETARIO, UNIDADES_AYUDA,
  aNumero, campanaDeNido, candidatosNidos, claveSigpac, indexarContratos, mismoNombre, parcelaDeNido, descripcionParcela, esIbanEnmascarado, formatoEuros, generarPagos, importeSugeridoLinea,
  importeTotalLineas, mascararIban, normNif, validarContrato, validarParcela, validarPropietario,
} from './contratos_logic.js';
import {
  T, asignarTitular, quitarTitular, borrarDocumento, borrarFila, documentoPorHash, extraerConMistral, guardarConvenio, sha256, guardarFila, listarDocumentos, mensajeError,
  registrarDocumento, subirArchivo, urlDocumento, vincularNido,
} from './contratos_api.js';
import { borradorConvenio, borradorRgpd, htmlBorrador } from './contrato_borrador.js';
import { ayudaBtn } from './ayuda.js';

// ── Utilidades de formulario ─────────────────────────────────────────────────
const val = (id) => document.getElementById(id)?.value ?? '';
const chk = (id) => Boolean(document.getElementById(id)?.checked);
const vacioNull = (s) => (String(s ?? '').trim() === '' ? null : String(s).trim());

export const campo = (id, etiqueta, valor, { tipo = 'text', ancho = false, extra = '' } = {}) =>
  `<div class="campo${ancho ? ' ancho' : ''}"><label for="${id}">${esc(etiqueta)}</label><input type="${tipo}" id="${id}" value="${esc(valor)}" ${extra} /></div>`;

export const selector = (id, etiqueta, opciones, sel, { ancho = false } = {}) =>
  `<div class="campo${ancho ? ' ancho' : ''}"><label for="${id}">${esc(etiqueta)}</label><select id="${id}">${
    opciones.map(([v, l]) => `<option value="${esc(v)}" ${String(v) === String(sel ?? '') ? 'selected' : ''}>${esc(l)}</option>`).join('')}</select></div>`;

const area = (id, etiqueta, valor) =>
  `<div class="campo ancho"><label for="${id}">${esc(etiqueta)}</label><textarea id="${id}">${esc(valor)}</textarea></div>`;

function aviso(id, texto, ok = false) {
  const el = document.getElementById(id);
  if (!el) return;
  el.textContent = texto;
  el.classList.toggle('ok', ok);
}

/** Abre un editor con cabecera, cuerpo y pie. */
function abrirEditor(ctl, { titulo, cuerpo, ancho = '', ayuda = '' }) {
  const sub = ctl.subDialogo(ancho);
  sub.dlg.innerHTML = `<form method="dialog" class="ed-form">
    <div class="dlg-cab"><h2>${esc(titulo)}</h2>${ayuda ? ayudaBtn(ayuda) : ''}<button type="button" class="btn" data-cerrar>Cerrar</button></div>
    <div class="dlg-cuerpo" id="ed-cuerpo">${cuerpo}</div>
    <div class="dlg-pie"><span class="msg" id="ed-msg"></span><span id="ed-acciones" style="display:contents"></span></div></form>`;
  sub.dlg.querySelector('[data-cerrar]').onclick = () => sub.cerrar();
  sub.dlg.showModal();
  return sub;
}

// ── Documentos ───────────────────────────────────────────────────────────────
/**
 * Lista y sube documentos de un convenio o un propietario.
 * `cola`: si el padre aún no está guardado, los archivos subidos se anotan ahí y se registran al guardar.
 */
export function seccionDocumentos(ctl, contenedor, { carpeta, contratoId = null, propietarioId = null, tipos, cola = null, tipoInicial }) {
  const guardado = () => (contratoId && contratoId !== '__nuevo__') || propietarioId;
  const pintar = async () => {
    let docs = [];
    let error = '';
    if (guardado()) {
      try { docs = await listarDocumentos({ contratoId, propietarioId }); } catch (e) { error = mensajeError(e); }
    }
    const pendientes = cola ?? [];
    contenedor.innerHTML = `<div class="docs">
      ${error ? `<p class="info" style="color:var(--rojo)">${esc(error)}</p>` : ''}
      <table class="mini"><tbody>
        ${docs.map((d) => `<tr><td>${esc(TIPOS_DOCUMENTO[d.tipo] ?? d.tipo)}</td><td>${esc(d.nombre)}</td>
          <td class="suave">${esc((d.created_at ?? '').slice(0, 10))} · ${esc(d.subido_por ?? '')}</td>
          <td><button type="button" class="btn" data-abrir="${esc(d.storage_path)}">Abrir</button>
          ${ctl.esAdmin ? `<button type="button" class="btn peligro" data-borrar="${esc(d.id)}">Borrar</button>` : ''}</td></tr>`).join('')}
        ${pendientes.map((d) => `<tr><td>${esc(TIPOS_DOCUMENTO[d.tipo] ?? d.tipo)}</td><td>${esc(d.meta.nombre)}</td>
          <td class="suave">subido; se registrará al guardar</td><td></td></tr>`).join('')}
        ${!docs.length && !pendientes.length ? '<tr><td class="suave">Sin documentos.</td></tr>' : ''}
      </tbody></table>
      <div class="doc-subir">
        <select class="doc-tipo">${tipos.map((t) => `<option value="${t}" ${t === tipoInicial ? 'selected' : ''}>${esc(TIPOS_DOCUMENTO[t])}</option>`).join('')}</select>
        <input type="file" class="doc-archivo" accept=".pdf,image/*,.doc,.docx" />
        <button type="button" class="btn doc-subir-btn">Subir</button>
        <span class="info doc-msg"></span>
      </div></div>`;
    contenedor.querySelectorAll('[data-abrir]').forEach((b) => {
      b.onclick = async () => {
        try { window.open(await urlDocumento(b.dataset.abrir), '_blank', 'noopener'); } catch (e) { alert(mensajeError(e)); }
      };
    });
    contenedor.querySelectorAll('[data-borrar]').forEach((b) => {
      b.onclick = async () => {
        const d = docs.find((x) => x.id === b.dataset.borrar);
        if (!d || !confirm(`¿Borrar definitivamente «${d.nombre}»?`)) return;
        try { await borrarDocumento(d); await pintar(); } catch (e) { alert(mensajeError(e)); }
      };
    });
    const msg = contenedor.querySelector('.doc-msg');
    contenedor.querySelector('.doc-subir-btn').onclick = async () => {
      const archivo = contenedor.querySelector('.doc-archivo').files[0];
      if (!archivo) { msg.textContent = 'Elige un archivo.'; return; }
      msg.textContent = 'Subiendo…';
      try {
        const meta = await subirArchivo(archivo, carpeta);
        const tipo = contenedor.querySelector('.doc-tipo').value;
        if (guardado()) await registrarDocumento({ meta, tipo, contratoId: contratoId && contratoId !== '__nuevo__' ? contratoId : null, propietarioId });
        else cola?.push({ meta, tipo });
        await pintar();
      } catch (e) {
        msg.textContent = mensajeError(e);
      }
    };
  };
  pintar();
  return { recargar: pintar };
}

// ── Propietarios ─────────────────────────────────────────────────────────────
const opcionesTipoProp = Object.entries(TIPOS_PROPIETARIO);

const camposPropietario = (p, pre) => `
  <div class="campos">
    ${campo(`${pre}nombre`, 'Nombre y apellidos / razón social', p.nombre, { ancho: true })}
    ${selector(`${pre}tipo`, 'Actúa como', opcionesTipoProp, p.tipo ?? 'particular')}
    ${campo(`${pre}entidad`, 'C.B. / SAT / entidad que representa', p.entidad)}
    ${campo(`${pre}nif`, 'DNI / NIF / CIF', p.nif)}
    ${campo(`${pre}regepa`, 'Nº de REGEPA', p.regepa)}
    ${campo(`${pre}telefono`, 'Teléfono', p.telefono)}
    ${campo(`${pre}email`, 'Correo electrónico', p.email)}
    ${campo(`${pre}direccion`, 'Dirección', p.direccion, { ancho: true })}
    ${campo(`${pre}iban`, 'IBAN (solo se guardan los 4 últimos dígitos)', p.iban_enmascarado, { ancho: true, extra: 'autocomplete="off" spellcheck="false"' })}
    <div class="campo"><label><input type="checkbox" id="${pre}rgpd" ${p.rgpd_firmado ? 'checked' : ''} /> Consentimiento RGPD firmado</label></div>
    ${campo(`${pre}rgpd_fecha`, 'Fecha del consentimiento', p.rgpd_fecha, { tipo: 'date' })}
    ${area(`${pre}notas`, 'Notas', p.notas)}
  </div>`;

function leerPropietario(pre, base = {}) {
  const ibanEntrada = val(`${pre}iban`).trim();
  return {
    ...base,
    nombre: val(`${pre}nombre`).trim(),
    tipo: val(`${pre}tipo`) || 'particular',
    entidad: vacioNull(val(`${pre}entidad`)),
    nif: vacioNull(normNif(val(`${pre}nif`))),
    regepa: vacioNull(val(`${pre}regepa`)),
    telefono: vacioNull(val(`${pre}telefono`)),
    email: vacioNull(val(`${pre}email`)),
    direccion: vacioNull(val(`${pre}direccion`)),
    // Nunca se envía el IBAN completo: se enmascara aquí, en el navegador.
    iban_enmascarado: ibanEntrada ? (esIbanEnmascarado(ibanEntrada) ? ibanEntrada : mascararIban(ibanEntrada) || null) : null,
    rgpd_firmado: chk(`${pre}rgpd`),
    rgpd_fecha: vacioNull(val(`${pre}rgpd_fecha`)),
    notas: vacioNull(val(`${pre}notas`)),
  };
}

export function editarPropietario(ctl, { propietario = null, alGuardar = null } = {}) {
  const esNuevo = !propietario;
  const p = propietario ?? { id: crypto.randomUUID(), tipo: 'particular' };
  const convenios = ctl.datos.contratos.filter((c) => c.propietario_id === p.id);
  const sub = abrirEditor(ctl, {
    ayuda: 'propietario-editor',
    titulo: esNuevo ? 'Nuevo propietario' : `Propietario: ${p.nombre}`,
    cuerpo: `${camposPropietario(p, 'pr-')}
      <fieldset><legend>Documentos del propietario ${ayudaBtn('cv-documentos')}</legend><div id="pr-docs"></div></fieldset>
      ${esNuevo ? '' : `<fieldset><legend>Convenios</legend>${convenios.length
        ? convenios.map((c) => `<div>${esc(c.campana)} · ${esc(ETIQUETA_ESTADO[c.estado])} · ${esc(formatoEuros(c.importe_total))}</div>`).join('')
        : '<span class="info">Sin convenios.</span>'}</fieldset>`}`,
  });
  seccionDocumentos(ctl, document.getElementById('pr-docs'), {
    carpeta: `propietarios/${p.id}`, propietarioId: esNuevo ? null : p.id, tipos: ['consentimiento_rgpd', 'dni', 'titularidad_cuenta', 'otro'], tipoInicial: 'consentimiento_rgpd',
  });
  const acciones = document.getElementById('ed-acciones');
  acciones.innerHTML = `${esNuevo || !ctl.esAdmin ? '' : '<button type="button" class="btn peligro" id="pr-borrar">Eliminar</button>'}
    <button type="button" class="btn" id="pr-rgpd" title="Borrador editable del consentimiento informado">Borrador RGPD</button>
    <button type="submit" class="btn primario" id="pr-guardar">Guardar propietario</button>`;
  document.getElementById('pr-rgpd').onclick = () => ctl.abrirBorrador(
    `Consentimiento RGPD - ${leerPropietario('pr-', p).nombre || 'titular'}`,
    borradorRgpd({ contrato: null, propietario: leerPropietario('pr-', p) }),
  );
  const borrar = document.getElementById('pr-borrar');
  if (borrar) {
    borrar.onclick = async () => {
      if (!confirm('¿Eliminar este propietario? Solo es posible si no tiene convenios.')) return;
      try { await borrarFila(T.propietarios, p.id); await ctl.recargar(); sub.cerrar(); } catch (e) { aviso('ed-msg', mensajeError(e)); }
    };
  }
  sub.dlg.querySelector('form').onsubmit = async (ev) => {
    ev.preventDefault();
    const fila = leerPropietario('pr-', p);
    const errores = validarPropietario(fila);
    if (errores.length) return aviso('ed-msg', errores.join(' '));
    document.getElementById('pr-guardar').disabled = true;
    try {
      const guardado = await guardarFila(T.propietarios, fila, esNuevo);
      await ctl.recargar();
      sub.cerrar();
      alGuardar?.(guardado);
    } catch (e) {
      aviso('ed-msg', mensajeError(e));
      document.getElementById('pr-guardar').disabled = false;
    }
  };
}

// ── Parcelas ─────────────────────────────────────────────────────────────────
const camposParcela = (p, pre) => `
  <div class="campos">
    ${campo(`${pre}pais`, 'País', p.pais ?? 'España')}
    ${campo(`${pre}provincia`, 'Provincia', p.provincia)}
    ${campo(`${pre}municipio`, 'Municipio (nombre)', p.municipio)}
    ${campo(`${pre}sigpac_provincia`, 'SIGPAC · provincia', p.sigpac_provincia)}
    ${campo(`${pre}sigpac_municipio`, 'SIGPAC · MUN (código)', p.sigpac_municipio)}
    ${campo(`${pre}sigpac_agregado`, 'SIGPAC · AGR', p.sigpac_agregado)}
    ${campo(`${pre}sigpac_zona`, 'SIGPAC · ZONA', p.sigpac_zona)}
    ${campo(`${pre}sigpac_poligono`, 'SIGPAC · POL (polígono)', p.sigpac_poligono)}
    ${campo(`${pre}sigpac_parcela`, 'SIGPAC · PAR (parcela)', p.sigpac_parcela)}
    ${campo(`${pre}sigpac_recinto`, 'SIGPAC · REC (recinto)', p.sigpac_recinto)}
    ${campo(`${pre}referencia_catastral`, 'Referencia catastral', p.referencia_catastral, { ancho: true })}
    ${campo(`${pre}superficie_ha`, 'Superficie (ha)', p.superficie_ha, { tipo: 'number', extra: 'step="any" min="0"' })}
    ${campo(`${pre}uso`, 'Uso (TA, PS…)', p.uso)}
    ${campo(`${pre}lat`, 'Latitud (opcional)', p.lat, { tipo: 'number', extra: 'step="any"' })}
    ${campo(`${pre}lon`, 'Longitud (opcional)', p.lon, { tipo: 'number', extra: 'step="any"' })}
    ${campo(`${pre}zona_programa`, 'Zona del programa', p.zona_programa, { ancho: true })}
    ${area(`${pre}notas`, 'Notas', p.notas)}
  </div>`;

const CAMPOS_PARCELA_TXT = ['pais', 'provincia', 'municipio', 'sigpac_provincia', 'sigpac_municipio', 'sigpac_agregado', 'sigpac_zona',
  'sigpac_poligono', 'sigpac_parcela', 'sigpac_recinto', 'referencia_catastral', 'uso', 'zona_programa', 'notas'];

function leerParcela(pre, base = {}) {
  const f = { ...base };
  for (const k of CAMPOS_PARCELA_TXT) f[k] = vacioNull(val(`${pre}${k}`));
  f.pais = f.pais ?? 'España';
  f.superficie_ha = aNumero(val(`${pre}superficie_ha`));
  f.lat = aNumero(val(`${pre}lat`));
  f.lon = aNumero(val(`${pre}lon`));
  return f;
}

/** Parcela nueva con los datos de un nido (para crearla y vincularla desde su ficha). */
export function parcelaDesdeNido(n) {
  const pos = posicion(n);
  return {
    id: crypto.randomUUID(),
    pais: 'España',
    provincia: n.provincia ?? null,
    municipio: n.municipio ?? null,
    referencia_catastral: n.referencia_catastral ?? null,
    lat: pos ? Number(pos.lat.toFixed(6)) : null,
    lon: pos ? Number(pos.lon.toFixed(6)) : null,
  };
}

export function editarParcela(ctl, { parcela = null, nidoParaVincular = null, alGuardar = null } = {}) {
  const esNuevo = !parcela || !ctl.datos.parcelas.some((x) => x.id === parcela.id);
  const p = parcela ?? { id: crypto.randomUUID(), pais: 'España' };
  const d = ctl.datos;
  const titulares = d.titularidad.filter((t) => t.parcela_id === p.id);
  const nidos = esNuevo ? [] : ctl.nidosDeParcela(p);
  const lineas = d.lineas.filter((l) => l.parcela_id === p.id);
  const sub = abrirEditor(ctl, {
    ayuda: 'parcela-editor',
    titulo: esNuevo ? 'Nueva parcela' : `Parcela: ${descripcionParcela(p)}`,
    cuerpo: `${nidoParaVincular ? `<p class="info">Se creará con los datos del nido ${esc(nidoParaVincular.etiqueta || nidoParaVincular.numeracion || '')} y quedará vinculada a él.</p>` : ''}
      ${camposParcela(p, 'pa-')}
      ${esNuevo ? '<p class="info">Guarda la parcela para añadir propietarios.</p>' : `
      <fieldset><legend>Propietarios de la parcela</legend><div id="pa-tit"></div></fieldset>
      <fieldset><legend>Nidos en esta parcela</legend>${nidos.length
        ? nidos.map((n) => `<span class="chip curso" style="margin:0 4px 4px 0">${esc(n.etiqueta || n.numeracion)}</span>`).join('')
        : '<span class="info">Ningún nido vinculado (se vinculan desde la ficha del nido o por la referencia catastral).</span>'}</fieldset>
      <fieldset><legend>Convenios que la incluyen</legend>${lineas.length
        ? lineas.map((l) => { const c = d.contratos.find((x) => x.id === l.contrato_id); return `<div>${esc(l.campana)} · ${esc(ETIQUETA_ESTADO[c?.estado] ?? '')} · ${esc(d.propietarios.find((o) => o.id === c?.propietario_id)?.nombre ?? '')}</div>`; }).join('')
        : '<span class="info">Sin convenios.</span>'}</fieldset>`}`,
  });

  const pintarTitulares = () => {
    const cont = document.getElementById('pa-tit');
    if (!cont) return;
    const lista = ctl.datos.titularidad.filter((t) => t.parcela_id === p.id);
    const libres = ctl.datos.propietarios.filter((o) => !lista.some((t) => t.propietario_id === o.id));
    cont.innerHTML = `${lista.map((t) => {
      const o = ctl.datos.propietarios.find((x) => x.id === t.propietario_id);
      return `<div class="fila-tit"><span>${esc(o?.nombre ?? '—')}${t.porcentaje != null ? ` · ${esc(t.porcentaje)} %` : ''}</span>
        <button type="button" class="btn" data-quitar="${esc(t.propietario_id)}">Quitar</button></div>`;
    }).join('') || '<span class="info">Sin propietarios asignados.</span>'}
      <div class="doc-subir"><select id="pa-nuevo-prop"><option value="">Añadir propietario…</option>${libres.map((o) => `<option value="${esc(o.id)}">${esc(o.nombre)}</option>`).join('')}</select>
      <input type="number" id="pa-pct" min="0.01" max="100" step="any" placeholder="% titularidad" style="width:120px" />
      <button type="button" class="btn" id="pa-add-prop">Añadir</button>
      <button type="button" class="btn" id="pa-crear-prop">Nuevo propietario…</button></div>`;
    cont.querySelectorAll('[data-quitar]').forEach((b) => {
      b.onclick = async () => {
        try {
          await quitarTitular(p.id, b.dataset.quitar);
          await ctl.recargar();
          pintarTitulares();
        } catch (e) { aviso('ed-msg', mensajeError(e)); }
      };
    });
    document.getElementById('pa-add-prop').onclick = async () => {
      const id = val('pa-nuevo-prop');
      if (!id) return;
      try {
        await asignarTitular(p.id, id, aNumero(val('pa-pct')));
        await ctl.recargar();
        pintarTitulares();
      } catch (e) { aviso('ed-msg', mensajeError(e)); }
    };
    document.getElementById('pa-crear-prop').onclick = () => editarPropietario(ctl, { alGuardar: () => pintarTitulares() });
  };
  if (!esNuevo) pintarTitulares();

  document.getElementById('ed-acciones').innerHTML = `${esNuevo || !ctl.esAdmin ? '' : '<button type="button" class="btn peligro" id="pa-borrar">Eliminar</button>'}
    <button type="submit" class="btn primario" id="pa-guardar">Guardar parcela</button>`;
  const borrar = document.getElementById('pa-borrar');
  if (borrar) {
    borrar.onclick = async () => {
      if (!confirm('¿Eliminar esta parcela? Solo es posible si no está en ningún convenio.')) return;
      try { await borrarFila(T.parcelas, p.id); await ctl.recargar(); sub.cerrar(); } catch (e) { aviso('ed-msg', mensajeError(e)); }
    };
  }
  sub.dlg.querySelector('form').onsubmit = async (ev) => {
    ev.preventDefault();
    const fila = leerParcela('pa-', p);
    const errores = validarParcela(fila);
    if (errores.length) return aviso('ed-msg', errores.join(' '));
    document.getElementById('pa-guardar').disabled = true;
    try {
      const guardada = await guardarFila(T.parcelas, fila, esNuevo);
      if (nidoParaVincular) await vincularNido(nidoParaVincular.id, guardada.id);
      await ctl.recargar();
      sub.cerrar();
      alGuardar?.(guardada);
    } catch (e) {
      aviso('ed-msg', mensajeError(e));
      document.getElementById('pa-guardar').disabled = false;
    }
  };
}

// ── Convenios ────────────────────────────────────────────────────────────────
const NUEVA = '__nueva__';
const PROP_NUEVO = '__nuevo__';

/** Ayudas del catálogo para un programa y campaña (si no hay, las de la campaña más reciente del programa). */
export function ayudasDe(datos, programa, campana) {
  const todas = datos.ayudas ?? [];
  const delPrograma = todas.filter((a) => !programa || a.programa === programa);
  const exactas = delPrograma.filter((a) => a.campana === Number(campana));
  if (exactas.length) return exactas;
  const ultima = Math.max(0, ...delPrograma.map((a) => a.campana));
  return delPrograma.filter((a) => a.campana === ultima);
}

const hoyISO = () => new Date().toISOString().slice(0, 10);

const mismaParcelaSigpac = (a, b) => {
  const n = (x) => String(x ?? '').trim().replace(/^0+(?=\d)/, '').toLowerCase();
  return n(a.sigpac_poligono) === n(b.sigpac_poligono) && n(a.sigpac_parcela) === n(b.sigpac_parcela)
    && n(a.sigpac_recinto) === n(b.sigpac_recinto) && n(a.sigpac_municipio) === n(b.sigpac_municipio);
};

/** Estado inicial del editor a partir de los datos leídos del documento (se asocia a lo ya registrado). */
export function convenioDesdeExtraccion(x, datos, doc) {
  const anio = x.fecha_firma ? Number(x.fecha_firma.slice(0, 4)) : new Date().getFullYear();
  const programa = x.programa ?? PROGRAMA_POR_DEFECTO;
  const t = x.titular ?? {};
  const nif = normNif(t.nif);
  // Propietario ya registrado: por NIF y, si no, por nombre (o entidad).
  const existente = (nif ? datos.propietarios.find((o) => normNif(o.nif) === nif) : null)
    ?? datos.propietarios.find((o) => mismoNombre(o.nombre, t.nombre) || (t.entidad && mismoNombre(o.nombre, t.entidad))) ?? null;
  const catalogo = ayudasDe(datos, PROGRAMA_POR_DEFECTO, anio);
  const lineas = (x.parcelas ?? []).map((pl) => {
    // Parcela ya registrada: por identificación SIGPAC o por referencia catastral.
    const par = datos.parcelas.find((p) => mismaParcelaSigpac(p, pl));
    const linea = { parcela_id: par?.id ?? NUEVA, nueva: par ? null : { ...pl, pais: 'España', zona_programa: x.zona_programa ?? null }, superficie_ha: pl.superficie_ha, uso: pl.uso, ayudas: pl.ayudas ?? [] };
    linea.importe = importeSugeridoLinea(linea, catalogo) || null;
    return linea;
  });
  const total = x.importe_total ?? (importeTotalLineas(lineas) || null);
  const avisos = [...(x.dudas ?? [])];
  if (existente) avisos.unshift(`Titular reconocido: ya está registrado como «${existente.nombre}».`);
  const ya = lineas.filter((l) => l.parcela_id !== NUEVA).length;
  if (ya) avisos.unshift(`${ya} parcela(s) ya estaban registradas y se han asociado automáticamente.`);
  return {
    contrato: {
      id: crypto.randomUUID(),
      campana: anio,
      programa: PROGRAMA_POR_DEFECTO,
      zona_programa: x.zona_programa ?? null,
      estado: x.fecha_firma ? 'firmado' : 'borrador',
      fecha_firma: x.fecha_firma ?? null,
      vigencia_desde: x.fecha_firma ?? null,
      vigencia_hasta: null,
      importe_total: total,
      pct_firma: x.pct_firma ?? 60,
      lugar_firma: x.lugar_firma ?? null,
      firmante_grefa: x.firmante_grefa ?? null,
      cargo_firmante: x.cargo_firmante ?? null,
      observaciones: programa !== PROGRAMA_POR_DEFECTO ? `Programa indicado en el documento: ${programa}` : null,
    },
    propietarioId: existente?.id ?? PROP_NUEVO,
    propietarioNuevo: existente ? null : {
      nombre: t.nombre ?? '', tipo: t.tipo ?? 'particular', entidad: t.entidad, nif: nif || null, regepa: t.regepa, telefono: t.telefono,
      email: t.email, direccion: t.direccion, iban_enmascarado: x.iban_enmascarado, rgpd_firmado: x.consentimiento_rgpd_firmado === true,
      rgpd_fecha: x.consentimiento_rgpd_firmado ? x.fecha_firma : null,
    },
    lineas,
    pagos: x.fecha_firma ? generarPagos(total, x.pct_firma ?? 60) : [],
    docsNuevos: doc ? [{ meta: doc.meta, tipo: 'convenio_firmado', extraccion: { ...x, leido_con: doc.modelo, leido_el: hoyISO() } }] : [],
    dudas: avisos,
    aviso: 'Datos leídos automáticamente del documento. Compruébalos con el original antes de guardar: la lectura de textos manuscritos puede fallar.',
  };
}

function lineaHtml(l, i, datos, ayudasCat) {
  const nueva = l.parcela_id === NUEVA;
  const sel = [`<option value="${NUEVA}" ${nueva ? 'selected' : ''}>➕ Parcela nueva…</option>`,
    ...datos.parcelas.map((p) => `<option value="${esc(p.id)}" ${p.id === l.parcela_id ? 'selected' : ''}>${esc(descripcionParcela(p))}</option>`)].join('');
  const n = l.nueva ?? {};
  return `<div class="linea-cv" data-linea="${i}">
    <div class="linea-cab">
      <select class="l-parcela">${sel}</select>
      <input type="number" class="l-sup" step="any" min="0" placeholder="Sup. (ha)" value="${esc(l.superficie_ha ?? '')}" title="Superficie (ha)" />
      <input type="text" class="l-uso" placeholder="Uso" value="${esc(l.uso ?? '')}" title="Uso" style="width:70px" />
      <input type="number" class="l-importe" step="any" min="0" placeholder="Importe €" value="${esc(l.importe ?? '')}" title="Importe de la línea (€)" />
      <button type="button" class="btn" data-sugerir="${i}" title="Suma de las ayudas marcadas">Calcular €</button>
      <button type="button" class="btn peligro" data-quitar-linea="${i}">Quitar</button>
    </div>
    <div class="ayudas-chk">${ayudasCat.map((a) => `<label title="${esc(a.descripcion ?? '')}"><input type="checkbox" class="l-ayuda" value="${a.codigo}" ${(l.ayudas ?? []).includes(a.codigo) ? 'checked' : ''}/> ${a.codigo}</label>`).join('')}
      <span class="info">Ayudas aplicadas (códigos)</span></div>
    ${nueva ? `<div class="linea-nueva campos">
      ${campo(`ln${i}-sigpac_municipio`, 'MUN', n.sigpac_municipio)}${campo(`ln${i}-sigpac_poligono`, 'POL', n.sigpac_poligono)}
      ${campo(`ln${i}-sigpac_parcela`, 'PAR', n.sigpac_parcela)}${campo(`ln${i}-sigpac_recinto`, 'REC', n.sigpac_recinto)}
      ${campo(`ln${i}-sigpac_agregado`, 'AGR', n.sigpac_agregado)}${campo(`ln${i}-sigpac_zona`, 'ZONA', n.sigpac_zona)}
      ${campo(`ln${i}-provincia`, 'Provincia', n.provincia)}${campo(`ln${i}-municipio`, 'Municipio (nombre)', n.municipio)}
      ${campo(`ln${i}-referencia_catastral`, 'Ref. catastral', n.referencia_catastral)}
      <p class="info ancho">Esta parcela se creará al guardar el convenio.</p></div>` : ''}
  </div>`;
}

function pagoHtml(p, i) {
  return `<tr data-pago="${i}">
    <td><input type="text" class="p-concepto" value="${esc(p.concepto ?? '')}" /></td>
    <td><input type="number" class="p-importe" step="any" min="0" value="${esc(p.importe ?? '')}" style="width:100px" /></td>
    <td><input type="date" class="p-prevista" value="${esc(p.fecha_prevista ?? '')}" /></td>
    <td><input type="date" class="p-pagada" value="${esc(p.fecha_pago ?? '')}" /></td>
    <td><select class="p-estado"><option value="pendiente" ${p.estado !== 'pagado' ? 'selected' : ''}>Pendiente</option><option value="pagado" ${p.estado === 'pagado' ? 'selected' : ''}>Pagado</option></select></td>
    <td><button type="button" class="btn peligro" data-quitar-pago="${i}">×</button></td></tr>`;
}

/**
 * Editor de convenio.
 * @param {object} ctl controlador
 * @param {{contrato?:object, parcelaInicial?:object, campana?:number}} op
 */
export function editarConvenio(ctl, op = {}) {
  const d = ctl.datos;
  const existente = op.contrato ?? null;
  const esNuevo = !existente;

  /** Estado del formulario (se vuelca desde el DOM antes de cada repintado). */
  let E;
  if (existente) {
    E = {
      contrato: { ...existente },
      propietarioId: existente.propietario_id,
      propietarioNuevo: null,
      lineas: d.lineas.filter((l) => l.contrato_id === existente.id).map((l) => ({ ...l, nueva: null })),
      pagos: d.pagos.filter((p) => p.contrato_id === existente.id).map((p) => ({ ...p })),
      docsNuevos: [], dudas: [], aviso: '',
    };
  } else if (op.inicial) {
    E = op.inicial;
  } else {
    E = {
      contrato: {
        id: crypto.randomUUID(), campana: op.campana ?? new Date().getFullYear(), programa: PROGRAMA_POR_DEFECTO,
        estado: 'borrador', pct_firma: 60, lugar_firma: null,
      },
      propietarioId: op.propietarioId ?? '',
      propietarioNuevo: null,
      lineas: op.parcelaInicial ? [{ parcela_id: op.parcelaInicial.id, superficie_ha: op.parcelaInicial.superficie_ha, uso: op.parcelaInicial.uso, ayudas: [], importe: null }] : [],
      pagos: [], docsNuevos: [], dudas: [], aviso: '',
    };
    if (op.parcelaInicial) {
      const titular = d.titularidad.find((t) => t.parcela_id === op.parcelaInicial.id);
      if (titular) E.propietarioId = titular.propietario_id;
    }
  }
  E.nidoSel ??= {};
  const existentes = existente
    ? { contrato: existente, lineas: d.lineas.filter((l) => l.contrato_id === existente.id), pagos: d.pagos.filter((p) => p.contrato_id === existente.id) }
    : null;

  const catalogo = () => ayudasDe(ctl.datos, E.contrato.programa, E.contrato.campana);

  const capturar = () => {
    const c = E.contrato;
    c.campana = Number(val('cv-campana')) || c.campana;
    c.programa = vacioNull(val('cv-programa'));
    c.zona_programa = vacioNull(val('cv-zona'));
    c.estado = val('cv-estado') || c.estado;
    c.fecha_firma = vacioNull(val('cv-firma'));
    c.vigencia_desde = vacioNull(val('cv-desde'));
    c.vigencia_hasta = vacioNull(val('cv-hasta'));
    c.lugar_firma = vacioNull(val('cv-lugar'));
    c.firmante_grefa = vacioNull(val('cv-firmante'));
    c.cargo_firmante = vacioNull(val('cv-cargo'));
    c.pct_firma = Math.min(100, Math.max(0, Number(val('cv-pct')) || 0));
    c.importe_total = aNumero(val('cv-total'));
    c.observaciones = vacioNull(val('cv-obs'));
    E.propietarioId = val('cv-prop');
    if (E.propietarioId === PROP_NUEVO && document.getElementById('cvp-nombre')) E.propietarioNuevo = leerPropietario('cvp-', E.propietarioNuevo ?? {});
    E.lineas = [...document.querySelectorAll('[data-linea]')].map((el, i) => {
      const parcelaId = el.querySelector('.l-parcela').value;
      const nueva = parcelaId === NUEVA
        ? Object.fromEntries(['sigpac_municipio', 'sigpac_poligono', 'sigpac_parcela', 'sigpac_recinto', 'sigpac_agregado', 'sigpac_zona', 'provincia', 'municipio', 'referencia_catastral']
          .map((k) => [k, vacioNull(val(`ln${i}-${k}`))]))
        : null;
      const previa = E.lineas[i] ?? {};
      return {
        id: previa.id, parcela_id: parcelaId, nueva: nueva && { ...(previa.nueva ?? {}), ...nueva, pais: 'España' },
        superficie_ha: aNumero(el.querySelector('.l-sup').value), uso: vacioNull(el.querySelector('.l-uso').value),
        ayudas: [...el.querySelectorAll('.l-ayuda:checked')].map((x) => Number(x.value)),
        importe: aNumero(el.querySelector('.l-importe').value),
      };
    });
    document.querySelectorAll('[data-nido]').forEach((tr) => {
      E.nidoSel[tr.dataset.nido] = { marcado: tr.querySelector('.nv-check').checked, linea: Number(tr.querySelector('.nv-linea').value) || 0 };
    });
    E.pagos = [...document.querySelectorAll('[data-pago]')].map((tr, i) => ({
      id: E.pagos[i]?.id, concepto: tr.querySelector('.p-concepto').value.trim(), importe: aNumero(tr.querySelector('.p-importe').value) ?? 0,
      fecha_prevista: vacioNull(tr.querySelector('.p-prevista').value), fecha_pago: vacioNull(tr.querySelector('.p-pagada').value),
      estado: tr.querySelector('.p-estado').value,
    }));
  };

  const sub = abrirEditor(ctl, { titulo: '', cuerpo: '', ancho: 'ancho', ayuda: 'convenio-editor' });
  const cab = sub.dlg.querySelector('.dlg-cab h2');
  let guardadoOk = false;
  sub.dlg.addEventListener('close', () => op.alCerrar?.(guardadoOk));

  /** Nidos sin parcela cuyo propietario (nombre o teléfono) coincide con el titular del convenio. */
  const candidatos = () => {
    const ix = indexarContratos(ctl.datos);
    const nidos = ctl.nidos?.() ?? [];
    const ocupados = new Set(nidos.filter((n) => parcelaDeNido(n, ix)).map((n) => n.id));
    const tit = E.propietarioId === PROP_NUEVO ? E.propietarioNuevo : ctl.datos.propietarios.find((o) => o.id === E.propietarioId);
    return tit ? candidatosNidos(nidos, tit, ocupados) : [];
  };
  const etiquetaLinea = (l, i) => `${i + 1}. ${descripcionParcela(l.parcela_id === NUEVA ? (l.nueva ?? {}) : (ctl.datos.parcelas.find((p) => p.id === l.parcela_id) ?? {}))}`;
  const nidosHtml = () => {
    const cands = candidatos();
    if (!cands.length) return '<span class="info">No hay nidos sin parcela que coincidan con este titular. También puedes vincularlos desde la ficha de cada nido.</span>';
    if (!E.lineas.length) return '<span class="info">Añade primero las parcelas del convenio.</span>';
    return `<p class="info">Encontrados por el nombre del propietario o el teléfono. Desmarca los que no correspondan.</p>
      <table class="mini"><tbody>${cands.map(({ nido: n, motivos }) => {
    const s = (E.nidoSel[n.id] ??= { marcado: motivos.some((m) => m.includes('nombre')), linea: 0 });
    return `<tr data-nido="${esc(n.id)}"><td><input type="checkbox" class="nv-check" ${s.marcado ? 'checked' : ''} /></td>
          <td><b>${esc(n.etiqueta || n.numeracion)}</b> · ${esc(n.municipio ?? '')} · campaña ${esc(campanaDeNido(n))}</td>
          <td class="suave">${esc(motivos.join(' + '))}${n.propietario ? ` («${esc(n.propietario)}»)` : ''}</td>
          <td><select class="nv-linea">${E.lineas.map((l, i) => `<option value="${i}" ${s.linea === i ? 'selected' : ''}>${esc(etiquetaLinea(l, i))}</option>`).join('')}</select></td></tr>`;
  }).join('')}</tbody></table>`;
  };

  const pintar = () => {
    const c = E.contrato;
    const dlgCuerpo = document.getElementById('ed-cuerpo');
    cab.textContent = esNuevo ? 'Nuevo convenio' : `Convenio ${c.campana} · ${d.propietarios.find((o) => o.id === c.propietario_id)?.nombre ?? ''}`;
    const cat = catalogo();
    dlgCuerpo.innerHTML = `
      <fieldset><legend>Titular y campaña ${ayudaBtn('cv-titular')}</legend><div class="campos">
        <div class="campo ancho"><label for="cv-prop">Propietario (titular)</label>
          <select id="cv-prop"><option value="">— Elige —</option><option value="${PROP_NUEVO}" ${E.propietarioId === PROP_NUEVO ? 'selected' : ''}>➕ Propietario nuevo…</option>
          ${d.propietarios.map((o) => `<option value="${esc(o.id)}" ${o.id === E.propietarioId ? 'selected' : ''}>${esc(o.nombre)}${o.nif ? ` · ${esc(o.nif)}` : ''}</option>`).join('')}</select></div>
        ${campo('cv-campana', 'Campaña (año)', c.campana, { tipo: 'number', extra: 'min="2000" max="2100" step="1"' })}
        ${selector('cv-estado', 'Estado', ESTADOS_CONTRATO.map((e) => [e, ETIQUETA_ESTADO[e]]), c.estado)}
        ${campo('cv-programa', 'Programa', c.programa, { ancho: true })}
        ${campo('cv-zona', 'Zona del programa', c.zona_programa, { ancho: true })}
      </div>
      ${E.propietarioId === PROP_NUEVO ? `<div class="sub-prop"><h4>Datos del propietario nuevo</h4>${camposPropietario(E.propietarioNuevo ?? { tipo: 'particular' }, 'cvp-')}</div>` : ''}
      </fieldset>
      <fieldset><legend>Firma y vigencia ${ayudaBtn('cv-firma')}</legend><div class="campos">
        ${campo('cv-firma', 'Fecha de firma', c.fecha_firma, { tipo: 'date' })}
        ${campo('cv-desde', 'Vigencia desde', c.vigencia_desde, { tipo: 'date' })}
        ${campo('cv-hasta', 'Vigencia hasta', c.vigencia_hasta, { tipo: 'date' })}
        ${campo('cv-lugar', 'Lugar de firma', c.lugar_firma)}
        ${campo('cv-firmante', 'Firma por GREFA', c.firmante_grefa)}
        ${campo('cv-cargo', 'Cargo', c.cargo_firmante)}
      </div></fieldset>
      <fieldset><legend>Parcelas del convenio (una parcela solo puede estar en un convenio por campaña) ${ayudaBtn('cv-parcelas')}</legend>
        <div id="cv-lineas">${E.lineas.map((l, i) => lineaHtml(l, i, ctl.datos, cat)).join('') || '<span class="info">Sin parcelas.</span>'}</div>
        <button type="button" class="btn" id="cv-add-linea">+ Añadir parcela</button>
      </fieldset>
      <fieldset><legend>Nidos de este titular ${ayudaBtn('cv-nidos')}</legend>${nidosHtml()}</fieldset>
      <fieldset><legend>Compensación económica ${ayudaBtn('cv-compensacion')}</legend><div class="campos">
        ${campo('cv-total', 'Importe total del convenio (€)', c.importe_total, { tipo: 'number', extra: 'step="any" min="0"' })}
        ${campo('cv-pct', '% que se abona a la firma', c.pct_firma ?? 60, { tipo: 'number', extra: 'min="0" max="100" step="1"' })}
      </div>
      <div style="margin:6px 0"><button type="button" class="btn" id="cv-suma">Total = suma de las líneas</button>
        <button type="button" class="btn" id="cv-gen-pagos">Generar pagos (firma / finalización)</button></div>
      <table class="mini"><thead><tr><th>Concepto</th><th>Importe €</th><th>Prevista</th><th>Pagado el</th><th>Estado</th><th></th></tr></thead>
        <tbody id="cv-pagos">${E.pagos.map((p, i) => pagoHtml(p, i)).join('')}</tbody></table>
      <button type="button" class="btn" id="cv-add-pago">+ Añadir pago</button></fieldset>
      <fieldset><legend>Documentos ${ayudaBtn('cv-documentos')}</legend>
        <p class="info">Convenio ya firmado: rellena los datos, pon el estado «Firmado» y sube aquí el PDF escaneado. También: consentimiento RGPD, DNI, titularidad de la cuenta, hoja catastral y croquis SIGPAC.</p>
        <div id="cv-docs"></div></fieldset>
      <div class="campos">${area('cv-obs', 'Observaciones', c.observaciones)}</div>`;
    enlazar();
  };

  const enlazar = () => {
    const repintar = () => { capturar(); pintar(); };
    document.getElementById('cv-prop').onchange = repintar;
    document.getElementById('cv-campana').onchange = repintar;
    document.getElementById('cv-add-linea').onclick = () => { capturar(); E.lineas.push({ parcela_id: '', superficie_ha: null, uso: null, ayudas: [], importe: null }); pintar(); };
    document.querySelectorAll('.l-parcela').forEach((s, i) => {
      s.onchange = () => {
        capturar();
        const p = ctl.datos.parcelas.find((x) => x.id === E.lineas[i].parcela_id);
        if (p) { E.lineas[i].superficie_ha ??= p.superficie_ha; E.lineas[i].uso ??= p.uso; }
        pintar();
      };
    });
    document.querySelectorAll('[data-quitar-linea]').forEach((b) => { b.onclick = () => { capturar(); E.lineas.splice(Number(b.dataset.quitarLinea), 1); pintar(); }; });
    document.querySelectorAll('[data-sugerir]').forEach((b) => {
      b.onclick = () => { capturar(); const i = Number(b.dataset.sugerir); E.lineas[i].importe = importeSugeridoLinea(E.lineas[i], catalogo()) || null; pintar(); };
    });
    document.getElementById('cv-suma').onclick = () => { capturar(); E.contrato.importe_total = importeTotalLineas(E.lineas) || null; pintar(); };
    document.getElementById('cv-gen-pagos').onclick = () => {
      capturar();
      if (E.pagos.length && !confirm('Se sustituirán los pagos actuales. ¿Continuar?')) return;
      E.pagos = generarPagos(E.contrato.importe_total, E.contrato.pct_firma ?? 60);
      pintar();
    };
    document.getElementById('cv-add-pago').onclick = () => { capturar(); E.pagos.push({ concepto: 'Pago', importe: 0, estado: 'pendiente' }); pintar(); };
    document.querySelectorAll('[data-quitar-pago]').forEach((b) => { b.onclick = () => { capturar(); E.pagos.splice(Number(b.dataset.quitarPago), 1); pintar(); }; });
    seccionDocumentos(ctl, document.getElementById('cv-docs'), {
      carpeta: `convenios/${E.contrato.id}`, contratoId: esNuevo ? '__nuevo__' : E.contrato.id, tipos: Object.keys(TIPOS_DOCUMENTO),
      cola: esNuevo ? E.docsNuevos : null, tipoInicial: 'convenio_firmado',
    });
  };

  pintar();

  document.getElementById('ed-acciones').innerHTML = `${esNuevo || !ctl.esAdmin ? '' : '<button type="button" class="btn peligro" id="cv-borrar">Eliminar</button>'}
    <button type="button" class="btn" id="cv-borrador" title="Documento editable con los datos del convenio (PDF / Word)">Borrador del convenio</button>
    <button type="submit" class="btn primario" id="cv-guardar">Guardar convenio</button>`;

  const datosBorrador = () => {
    const c = E.contrato;
    const prop = E.propietarioId === PROP_NUEVO ? (E.propietarioNuevo ?? {}) : ctl.datos.propietarios.find((o) => o.id === E.propietarioId);
    const lineas = E.lineas.map((l) => ({
      parcela: l.parcela_id === NUEVA ? (l.nueva ?? {}) : (ctl.datos.parcelas.find((p) => p.id === l.parcela_id) ?? {}), linea: l,
    }));
    return { contrato: c, propietario: prop ?? { nombre: '' }, lineas, ayudas: catalogo() };
  };
  document.getElementById('cv-borrador').onclick = () => {
    capturar();
    const x = datosBorrador();
    ctl.abrirBorrador(`Convenio ${x.contrato.campana} - ${x.propietario.nombre || 'titular'}`, borradorConvenio(x));
  };
  const borrar = document.getElementById('cv-borrar');
  if (borrar) {
    borrar.onclick = async () => {
      if (!confirm('¿Eliminar este convenio con sus parcelas, pagos y documentos? No se puede deshacer.')) return;
      try {
        const docs = await listarDocumentos({ contratoId: E.contrato.id });
        for (const doc of docs) await borrarDocumento(doc);
        await borrarFila(T.contratos, E.contrato.id);
        await ctl.recargar();
        sub.cerrar();
      } catch (e) { aviso('ed-msg', mensajeError(e)); }
    };
  }

  sub.dlg.querySelector('form').onsubmit = async (ev) => {
    ev.preventDefault();
    capturar();
    const boton = document.getElementById('cv-guardar');
    const c = E.contrato;
    // Validación previa (antes de crear nada).
    const errores = [];
    if (E.propietarioId === PROP_NUEVO) errores.push(...validarPropietario(E.propietarioNuevo ?? { nombre: '' }));
    for (const l of E.lineas) {
      if (!l.parcela_id) errores.push('Elige la parcela de cada línea.');
      if (l.parcela_id === NUEVA) errores.push(...validarParcela(l.nueva ?? {}));
    }
    errores.push(...validarContrato(
      { ...c, propietario_id: E.propietarioId === PROP_NUEVO ? 'nuevo' : E.propietarioId },
      E.lineas.map((l, i) => ({ ...l, parcela_id: l.parcela_id === NUEVA ? `nueva-${i}` : l.parcela_id })),
    ));
    if (errores.length) return aviso('ed-msg', [...new Set(errores)].join(' '));
    boton.disabled = true;
    try {
      // 1) Propietario nuevo (o el ya existente con el mismo NIF).
      let propietarioId = E.propietarioId;
      if (propietarioId === PROP_NUEVO) {
        const nuevo = E.propietarioNuevo;
        const igual = nuevo.nif ? ctl.datos.propietarios.find((o) => normNif(o.nif) === normNif(nuevo.nif)) : null;
        propietarioId = igual?.id ?? (await guardarFila(T.propietarios, { ...nuevo, id: crypto.randomUUID() }, true)).id;
      }
      // 2) Parcelas nuevas (si ya existe una con el mismo SIGPAC se reutiliza).
      const lineas = [];
      const parcelaIds = [];
      for (const l of E.lineas) {
        let parcelaId = l.parcela_id;
        if (parcelaId === NUEVA) {
          const n = l.nueva;
          const igual = ctl.datos.parcelas.find((p) => claveSigpac(p) && claveSigpac(p) === claveSigpac({ ...n, pais: 'España' }));
          parcelaId = igual?.id ?? (await guardarFila(T.parcelas, {
            ...n, id: crypto.randomUUID(), superficie_ha: l.superficie_ha, uso: l.uso, zona_programa: c.zona_programa,
          }, true)).id;
          if (!igual && propietarioId) {
            await asignarTitular(parcelaId, propietarioId, null);
          }
        } else if (propietarioId && !ctl.datos.titularidad.some((x) => x.parcela_id === parcelaId)) {
          // Parcela registrada sin propietario: queda asociada al titular de este convenio.
          await asignarTitular(parcelaId, propietarioId, null);
        }
        parcelaIds.push(parcelaId);
        lineas.push({ id: l.id, parcela_id: parcelaId, superficie_ha: l.superficie_ha, uso: l.uso, ayudas: l.ayudas, importe: l.importe });
      }
      // 3) Convenio, líneas y pagos.
      const total = c.importe_total ?? (importeTotalLineas(lineas) || null);
      const guardado = await guardarConvenio({
        contrato: { ...c, propietario_id: propietarioId, importe_total: total },
        lineas,
        pagos: E.pagos.filter((p) => p.concepto),
        existentes,
      });
      // 4) Documentos subidos antes de guardar.
      for (const dc of E.docsNuevos) {
        await registrarDocumento({ meta: dc.meta, tipo: dc.tipo, contratoId: guardado.id, extraccion: dc.extraccion ?? null });
      }
      // 5) Nidos marcados: se vinculan a la parcela elegida.
      const vigentes = new Set(candidatos().map((x) => x.nido.id));
      for (const [nidoId, s] of Object.entries(E.nidoSel)) {
        if (s.marcado && vigentes.has(nidoId) && parcelaIds[s.linea]) await vincularNido(nidoId, parcelaIds[s.linea]);
      }
      // 6) El consentimiento RGPD leído del documento actualiza al propietario.
      if (E.docsNuevos.some((dc) => dc.extraccion?.consentimiento_rgpd_firmado)) {
        await guardarFila(T.propietarios, { id: propietarioId, rgpd_firmado: true, rgpd_fecha: c.fecha_firma ?? hoyISO() }, false);
      }
      guardadoOk = true;
      await ctl.recargar();
      sub.cerrar();
    } catch (e) {
      aviso('ed-msg', mensajeError(e));
      boton.disabled = false;
    }
  };
}

// ── Importar convenios ya firmados (Mistral) ─────────────────────────────────
export function importarEscaneado(ctl) {
  const sub = abrirEditor(ctl, {
    ayuda: 'leer-firmados',
    titulo: 'Leer convenios firmados',
    cuerpo: `<p>Sube uno o varios convenios firmados (PDF o foto). Se leen con <b>Mistral</b> y se proponen titular, parcelas, ayudas e importe,
      <b>asociándolos a los propietarios, parcelas y nidos ya registrados</b>. Tú revisas cada uno antes de guardar; el archivo se conserva como «Convenio firmado».</p>
      <div class="campo ancho"><input type="file" id="im-archivo" accept=".pdf,image/*" multiple /></div>
      <p class="info">Privacidad: el documento se envía a Mistral solo para leerlo; el IBAN se enmascara en el servidor y solo se guardan sus 4 últimos dígitos.</p>
      <div id="im-estado" class="info"></div>`,
  });
  // Los editores de cada convenio reutilizan estos ids: se renombran para que no choquen con los del importador.
  const acciones = sub.dlg.querySelector('#ed-acciones');
  for (const id of ['ed-cuerpo', 'ed-msg', 'ed-acciones']) sub.dlg.querySelector('#' + id).id = id.replace('ed-', 'im-');
  acciones.innerHTML = '<button type="button" class="btn primario" id="im-leer">Subir y leer</button>';
  const estado = document.getElementById('im-estado');
  const resumen = { guardados: 0, saltados: [], errores: [] };

  /** Sube y lee un archivo; no abre el editor (así se puede ir leyendo el siguiente mientras se revisa uno). */
  const procesar = async (archivo) => {
    const hash = await sha256(archivo);
    const dup = await documentoPorHash(hash);
    if (dup) return { omitido: `«${archivo.name}»: ya estaba subido (${dup.nombre}).` };
    const meta = await subirArchivo(archivo, `convenios/${crypto.randomUUID()}`);
    try {
      const r = await extraerConMistral(meta.storage_path);
      return { inicial: convenioDesdeExtraccion(r.datos, ctl.datos, { meta, modelo: r.modelo }) };
    } catch (e) {
      const inicial = convenioDesdeExtraccion({ parcelas: [], titular: {} }, ctl.datos, null);
      inicial.contrato.estado = 'borrador';
      inicial.docsNuevos = [{ meta, tipo: 'convenio_firmado' }];
      inicial.propietarioId = '';
      inicial.propietarioNuevo = null;
      inicial.aviso = `No se pudo leer automáticamente «${archivo.name}» (${e.message}). Rellena los datos a mano; el archivo queda adjunto.`;
      inicial.dudas = [];
      return { inicial };
    }
  };

  document.getElementById('im-leer').onclick = async () => {
    const archivos = [...document.getElementById('im-archivo').files];
    if (!archivos.length) { estado.textContent = 'Elige al menos un archivo.'; return; }
    document.getElementById('im-leer').disabled = true;
    const tareas = new Map();
    const preparar = (i) => {
      if (i < archivos.length && !tareas.has(i)) {
        tareas.set(i, procesar(archivos[i]).catch((e) => ({ error: `«${archivos[i].name}»: ${mensajeError(e)}` })));
      }
      return tareas.get(i);
    };
    const siguiente = async (i) => {
      if (i >= archivos.length) {
        estado.innerHTML = `<b>Terminado.</b> Convenios guardados: ${resumen.guardados} de ${archivos.length}.${
          [...resumen.saltados, ...resumen.errores].map((m) => `<br>${esc(m)}`).join('')}`;
        acciones.innerHTML = '<button type="button" class="btn primario" id="im-fin">Cerrar</button>';
        document.getElementById('im-fin').onclick = () => sub.cerrar();
        return;
      }
      estado.textContent = `Leyendo «${archivos[i].name}» con Mistral (${i + 1} de ${archivos.length}; unos 10-40 s)…`;
      preparar(i);
      preparar(i + 1);
      const r = await tareas.get(i);
      if (r.omitido) { resumen.saltados.push(r.omitido); return siguiente(i + 1); }
      if (r.error) { resumen.errores.push(r.error); return siguiente(i + 1); }
      estado.textContent = `Revisando ${i + 1} de ${archivos.length}…`;
      editarConvenio(ctl, { inicial: r.inicial, alCerrar: (ok) => { if (ok) resumen.guardados += 1; else resumen.saltados.push(`«${archivos[i].name}»: no se guardó.`); siguiente(i + 1); } });
    };
    siguiente(0);
  };
}

// ── Catálogo de ayudas ───────────────────────────────────────────────────────
export function editarAyudas(ctl) {
  const programas = [...new Set([PROGRAMA_POR_DEFECTO, ...ctl.datos.ayudas.map((a) => a.programa)])];
  let programa = programas[0];
  let campana = Math.max(new Date().getFullYear(), ...ctl.datos.ayudas.filter((a) => a.programa === programa).map((a) => a.campana));
  const sub = abrirEditor(ctl, { titulo: 'Catálogo de ayudas', cuerpo: '', ancho: 'ancho', ayuda: 'ayudas' });
  let filas = [];

  const cargarFilas = () => {
    filas = ctl.datos.ayudas.filter((a) => a.programa === programa && a.campana === campana).map((a) => ({ ...a })).sort((a, b) => a.codigo - b.codigo);
  };
  const capturar = () => {
    filas = [...document.querySelectorAll('[data-ayuda]')].map((tr, i) => ({
      ...filas[i], descripcion: vacioNull(tr.querySelector('.a-desc').value), unidad: tr.querySelector('.a-unidad').value,
      importe: aNumero(tr.querySelector('.a-importe').value), nota: vacioNull(tr.querySelector('.a-nota').value),
    }));
  };
  const pintar = () => {
    document.getElementById('ed-cuerpo').innerHTML = `
      <div class="campos">
        ${selector('ay-prog', 'Programa', programas.map((p) => [p, p]), programa, { ancho: true })}
        ${campo('ay-camp', 'Campaña', campana, { tipo: 'number', extra: 'min="2000" max="2100"' })}
      </div>
      <p class="info">Códigos de ayuda del convenio (Anexo I) con su importe. Las «Variable» (p. ej. lonja) no se calculan solas.</p>
      <table class="mini"><thead><tr><th>Cód.</th><th>Descripción</th><th>Unidad</th><th>Importe</th><th>Nota</th></tr></thead><tbody>
      ${filas.map((a) => `<tr data-ayuda="${a.codigo}"><td><b>${a.codigo}</b></td>
        <td><input type="text" class="a-desc" value="${esc(a.descripcion ?? '')}" style="width:100%" /></td>
        <td><select class="a-unidad">${Object.entries(UNIDADES_AYUDA).map(([k, l]) => `<option value="${k}" ${a.unidad === k ? 'selected' : ''}>${esc(l)}</option>`).join('')}</select></td>
        <td><input type="number" class="a-importe" step="any" min="0" value="${esc(a.importe ?? '')}" style="width:100px" /></td>
        <td><input type="text" class="a-nota" value="${esc(a.nota ?? '')}" /></td></tr>`).join('')}
      </tbody></table>
      <button type="button" class="btn" id="ay-add">+ Añadir código</button>
      <button type="button" class="btn" id="ay-copiar" title="Copia este catálogo a otra campaña">Copiar a otra campaña…</button>`;
    document.getElementById('ay-prog').onchange = () => { programa = val('ay-prog'); cargarFilas(); pintar(); };
    document.getElementById('ay-camp').onchange = () => { campana = Number(val('ay-camp')) || campana; cargarFilas(); pintar(); };
    document.getElementById('ay-add').onclick = () => {
      capturar();
      filas.push({ programa, campana, codigo: Math.max(0, ...filas.map((f) => f.codigo)) + 1, descripcion: '', unidad: 'fijo', importe: null, nota: null });
      pintar();
    };
    document.getElementById('ay-copiar').onclick = async () => {
      capturar();
      const destino = Number(prompt('¿A qué campaña (año) quieres copiar este catálogo?', String(campana + 1)));
      if (!destino || destino === campana) return;
      try {
        for (const a of filas) {
          const { id: _i, ...resto } = a;
          await guardarFila(T.ayudas, { ...resto, campana: destino }, true);
        }
        await ctl.recargar();
        campana = destino;
        cargarFilas();
        pintar();
        aviso('ed-msg', `Catálogo copiado a ${destino}.`, true);
      } catch (e) { aviso('ed-msg', mensajeError(e)); }
    };
  };
  cargarFilas();
  pintar();
  document.getElementById('ed-acciones').innerHTML = '<button type="button" class="btn primario" id="ay-guardar">Guardar catálogo</button>';
  document.getElementById('ay-guardar').onclick = async () => {
    capturar();
    try {
      for (const a of filas) await guardarFila(T.ayudas, a, !a.id);
      await ctl.recargar();
      cargarFilas();
      pintar();
      aviso('ed-msg', 'Catálogo guardado.', true);
    } catch (e) { aviso('ed-msg', mensajeError(e)); }
  };
}

export { guardarArchivo, htmlBorrador, pintarEditorHtml };
