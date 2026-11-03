// Panel «Contratos»: convenios, parcelas, propietarios, compensación y catálogo de ayudas.
import { esc } from './informe.js';
import { guardarArchivo, pintarEditorHtml } from './informe_ui.js';
import {
  ETIQUETA_ESTADO, SEMAFORO, avisosCaducidad, compensacionACsv, descripcionParcela, estadosPorNido, formatoEuros,
  resumenCompensacion, ESTADOS_CONTRATO, indexarContratos, parcelaDeNido, TIPOS_PROPIETARIO,
} from './contratos_logic.js';
import { FaltanTablas, cargarDatosContratos, desvincularNido, mensajeError, vincularNido } from './contratos_api.js';
import { htmlBorrador } from './contrato_borrador.js';
import {
  editarAyudas, editarConvenio, editarParcela, editarPropietario, importarEscaneado, parcelaDesdeNido,
} from './contratos_editores.js';

const vacio = () => ({ propietarios: [], parcelas: [], titularidad: [], vinculos: [], ayudas: [], contratos: [], lineas: [], pagos: [] });
const CLASE_ESTADO = { firmado: 'exito', caducado: 'fracaso', rechazado: 'fracaso', enviado: 'curso', borrador: 'interv' };
const norm = (s) => String(s ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();

export const puntoSemaforo = (codigo) => {
  const s = SEMAFORO[codigo] ?? SEMAFORO.sinparcela;
  return `<span class="semaforo" style="background:${s.color}" title="${esc(s.etiqueta)}"></span>`;
};

/**
 * @param {{obtenerNidos:()=>object[], email:string, esAdmin:boolean, alCambiar:()=>void}} opciones
 */
export function crearControlador({ obtenerNidos, email, esAdmin, alCambiar }) {
  const ctl = {
    datos: vacio(),
    disponible: false,
    error: '',
    cargado: false,
    email,
    esAdmin,
  };
  let panel = null; // { dlg, tab, filtros }

  ctl.nidos = () => obtenerNidos();
  ctl.estados = () => estadosPorNido(obtenerNidos(), ctl.datos);

  ctl.nidosDeParcela = (parcela) => {
    const ix = indexarContratos(ctl.datos);
    return obtenerNidos().filter((n) => parcelaDeNido(n, ix)?.id === parcela.id);
  };

  ctl.cargar = async () => {
    try {
      ctl.datos = await cargarDatosContratos();
      ctl.disponible = true;
      ctl.error = '';
    } catch (e) {
      ctl.datos = vacio();
      ctl.disponible = false;
      ctl.error = e instanceof FaltanTablas ? e.message : mensajeError(e);
    }
    ctl.cargado = true;
  };

  ctl.recargar = async () => {
    await ctl.cargar();
    alCambiar?.();
    if (panel?.dlg.open) pintarPanel();
  };

  /** Diálogo secundario apilado sobre otro (se elimina al cerrarse). */
  ctl.subDialogo = (clase = '') => {
    const dlg = document.createElement('dialog');
    dlg.className = `sub-dlg ${clase}`.trim();
    document.body.appendChild(dlg);
    const cerrar = () => { if (dlg.open) dlg.close(); };
    dlg.addEventListener('close', () => dlg.remove());
    return { dlg, cerrar };
  };

  ctl.abrirBorrador = (titulo, cuerpo) => {
    const sub = ctl.subDialogo('informe-dlg');
    sub.dlg.showModal();
    pintarEditorHtml(sub.dlg, htmlBorrador(cuerpo, titulo), { titulo, referencia: titulo }, null);
  };

  // ── Panel ──
  ctl.abrir = async (tab = 'convenios') => {
    if (!panel) {
      const dlg = document.createElement('dialog');
      dlg.className = 'panel-contratos';
      document.body.appendChild(dlg);
      panel = { dlg, tab, filtros: { q: '', campana: '', estado: '' } };
    }
    panel.tab = tab;
    panel.dlg.innerHTML = '<div class="dlg-cab"><h2>Contratos y parcelas</h2></div><div class="dlg-cuerpo"><p class="info">Cargando…</p></div>';
    if (!panel.dlg.open) panel.dlg.showModal();
    await ctl.cargar();
    pintarPanel();
  };

  const TABS = [['convenios', 'Convenios'], ['parcelas', 'Parcelas'], ['propietarios', 'Propietarios'], ['compensacion', 'Compensación'], ['ayudas', 'Ayudas']];

  function pintarPanel() {
    const { dlg } = panel;
    const f = panel.filtros;
    dlg.innerHTML = `<div class="dlg-cab"><h2>Contratos y parcelas</h2><button type="button" class="btn" id="pc-cerrar">Cerrar</button></div>
      <div class="dlg-cuerpo">
        ${ctl.disponible ? '' : `<div class="aviso error">${esc(ctl.error || 'Contratos no disponibles.')}</div>`}
        ${ctl.disponible ? avisosHtml() : ''}
        <div class="tabs">${TABS.map(([k, l]) => `<button type="button" data-tab="${k}" class="${k === panel.tab ? 'activa' : ''}">${esc(l)}</button>`).join('')}</div>
        <div id="pc-contenido">${ctl.disponible ? contenidoTab() : ''}</div>
      </div>`;
    dlg.querySelector('#pc-cerrar').onclick = () => dlg.close();
    dlg.querySelectorAll('[data-tab]').forEach((b) => { b.onclick = () => { panel.tab = b.dataset.tab; pintarPanel(); }; });
    if (ctl.disponible) enlazarTab(f);
  }

  function avisosHtml() {
    const av = avisosCaducidad(ctl.datos.contratos);
    if (!av.length) return '';
    const frase = (a) => `Convenio ${a.contrato.campana} de ${nombreProp(a.contrato.propietario_id)}: ${a.dias < 0 ? `caducó hace ${-a.dias} días` : a.dias === 0 ? 'caduca hoy' : `caduca en ${a.dias} días`}.`;
    return `<div class="aviso">${av.map((a) => esc(frase(a))).join('<br>')}</div>`;
  }

  function contenidoTab() {
    switch (panel.tab) {
      case 'parcelas': return tabParcelas();
      case 'propietarios': return tabPropietarios();
      case 'compensacion': return tabCompensacion();
      case 'ayudas': return '<p>El catálogo de ayudas (Anexo I del convenio) define los códigos y los importes por campaña.</p><button type="button" class="btn primario" id="pc-ayudas">Editar catálogo de ayudas</button>';
      default: return tabConvenios();
    }
  }

  const nombreProp = (id) => ctl.datos.propietarios.find((o) => o.id === id)?.nombre ?? '—';

  function tabConvenios() {
    const f = panel.filtros;
    const d = ctl.datos;
    const campanas = [...new Set(d.contratos.map((c) => c.campana))].sort((a, b) => b - a);
    const lineasDe = (c) => d.lineas.filter((l) => l.contrato_id === c.id);
    const q = norm(f.q);
    const lista = d.contratos
      .filter((c) => (!f.campana || String(c.campana) === f.campana) && (!f.estado || c.estado === f.estado))
      .filter((c) => !q || norm(`${nombreProp(c.propietario_id)} ${c.zona_programa ?? ''}`).includes(q)
        || lineasDe(c).some((l) => norm(descripcionParcela(d.parcelas.find((p) => p.id === l.parcela_id))).includes(q)))
      .sort((a, b) => b.campana - a.campana || nombreProp(a.propietario_id).localeCompare(nombreProp(b.propietario_id), 'es'));
    return `<div class="barra-pc">
      <input type="search" id="pc-q" placeholder="Buscar propietario, parcela…" value="${esc(f.q)}" />
      <select id="pc-camp"><option value="">Todas las campañas</option>${campanas.map((c) => `<option value="${c}" ${String(c) === f.campana ? 'selected' : ''}>${c}</option>`).join('')}</select>
      <select id="pc-est"><option value="">Todos los estados</option>${ESTADOS_CONTRATO.map((e) => `<option value="${e}" ${e === f.estado ? 'selected' : ''}>${esc(ETIQUETA_ESTADO[e])}</option>`).join('')}</select>
      <span style="flex:1"></span>
      <button type="button" class="btn" id="pc-escaneo" title="Sube los PDF firmados: Mistral los lee y los asocia a lo ya registrado">Leer convenios firmados</button>
      <button type="button" class="btn primario" id="pc-nuevo-conv">+ Nuevo convenio</button></div>
      <table class="tabla-pc"><thead><tr><th>Campaña</th><th>Propietario</th><th>Parcelas</th><th class="n">Importe</th><th>Estado</th><th>Firma</th><th>Vigencia hasta</th></tr></thead><tbody>
      ${lista.map((c) => `<tr data-conv="${esc(c.id)}"><td>${esc(c.campana)}</td><td>${esc(nombreProp(c.propietario_id))}</td><td>${lineasDe(c).length}</td>
        <td class="n">${esc(formatoEuros(c.importe_total))}</td><td><span class="chip ${CLASE_ESTADO[c.estado] ?? ''}">${esc(ETIQUETA_ESTADO[c.estado])}</span></td>
        <td>${esc(c.fecha_firma ?? '')}</td><td>${esc(c.vigencia_hasta ?? '')}</td></tr>`).join('')
        || '<tr><td colspan="7" class="suave">Sin convenios. Crea uno nuevo o sube los PDF firmados.</td></tr>'}
      </tbody></table>`;
  }

  function tabParcelas() {
    const f = panel.filtros;
    const d = ctl.datos;
    const q = norm(f.q);
    const nidosPorParcela = new Map();
    const ix = indexarContratos(d);
    for (const n of obtenerNidos()) {
      const p = parcelaDeNido(n, ix);
      if (p) nidosPorParcela.set(p.id, (nidosPorParcela.get(p.id) ?? 0) + 1);
    }
    const campana = new Date().getFullYear();
    const lista = d.parcelas.filter((p) => !q || norm(`${descripcionParcela(p)} ${p.municipio ?? ''} ${p.provincia ?? ''} ${p.referencia_catastral ?? ''}`).includes(q));
    return `<div class="barra-pc"><input type="search" id="pc-q" placeholder="Buscar parcela, municipio, referencia…" value="${esc(f.q)}" /><span style="flex:1"></span>
      <button type="button" class="btn primario" id="pc-nueva-parcela">+ Nueva parcela</button></div>
      <table class="tabla-pc"><thead><tr><th>Parcela</th><th>Municipio</th><th>Provincia</th><th class="n">Sup. (ha)</th><th>Propietarios</th><th class="n">Nidos</th><th>Convenio ${campana}</th></tr></thead><tbody>
      ${lista.map((p) => {
    const props = d.titularidad.filter((t) => t.parcela_id === p.id).map((t) => nombreProp(t.propietario_id)).join(', ');
    const linea = d.lineas.find((l) => l.parcela_id === p.id && l.campana === campana);
    const c = linea ? d.contratos.find((x) => x.id === linea.contrato_id) : null;
    return `<tr data-parcela="${esc(p.id)}"><td>${esc(descripcionParcela(p))}</td><td>${esc(p.municipio ?? '')}</td><td>${esc(p.provincia ?? '')}</td>
          <td class="n">${esc(p.superficie_ha ?? '')}</td><td>${esc(props || '—')}</td><td class="n">${nidosPorParcela.get(p.id) ?? 0}</td>
          <td>${c ? `<span class="chip ${CLASE_ESTADO[c.estado] ?? ''}">${esc(ETIQUETA_ESTADO[c.estado])}</span>` : '<span class="suave">—</span>'}</td></tr>`;
  }).join('') || '<tr><td colspan="7" class="suave">Sin parcelas.</td></tr>'}
      </tbody></table>`;
  }

  function tabPropietarios() {
    const f = panel.filtros;
    const d = ctl.datos;
    const q = norm(f.q);
    const lista = d.propietarios.filter((o) => !q || norm(`${o.nombre} ${o.nif ?? ''} ${o.entidad ?? ''}`).includes(q));
    return `<div class="barra-pc"><input type="search" id="pc-q" placeholder="Buscar nombre, NIF…" value="${esc(f.q)}" /><span style="flex:1"></span>
      <button type="button" class="btn primario" id="pc-nuevo-prop">+ Nuevo propietario</button></div>
      <table class="tabla-pc"><thead><tr><th>Nombre</th><th>NIF</th><th>Tipo</th><th>Teléfono</th><th>Convenios</th><th>RGPD</th></tr></thead><tbody>
      ${lista.map((o) => `<tr data-prop="${esc(o.id)}"><td>${esc(o.nombre)}${o.entidad ? ` <span class="suave">· ${esc(o.entidad)}</span>` : ''}</td><td>${esc(o.nif ?? '')}</td>
        <td>${esc(TIPOS_PROPIETARIO[o.tipo] ?? o.tipo)}</td><td>${esc(o.telefono ?? '')}</td>
        <td>${d.contratos.filter((c) => c.propietario_id === o.id).length}</td><td>${o.rgpd_firmado ? '✔' : '<span class="suave">—</span>'}</td></tr>`).join('')
        || '<tr><td colspan="6" class="suave">Sin propietarios.</td></tr>'}
      </tbody></table>`;
  }

  function tabCompensacion() {
    const r = resumenCompensacion(ctl.datos.contratos, ctl.datos.pagos, ctl.datos.propietarios);
    return `<p class="info">Solo cuentan los convenios firmados (o caducados tras firmarse). «Pagado» suma los pagos marcados como pagados.</p>
      <h3>Por campaña</h3>
      <table class="tabla-pc"><thead><tr><th>Campaña</th><th class="n">Convenios</th><th class="n">Comprometido</th><th class="n">Pagado</th><th class="n">Pendiente</th></tr></thead><tbody>
      ${r.campanas.map((c) => `<tr><td>${esc(c.campana)}</td><td class="n">${c.contratos}</td><td class="n">${esc(formatoEuros(c.comprometido))}</td>
        <td class="n">${esc(formatoEuros(c.pagado))}</td><td class="n">${esc(formatoEuros(c.pendiente))}</td></tr>`).join('') || '<tr><td colspan="5" class="suave">Sin convenios firmados.</td></tr>'}
      </tbody></table>
      <h3>Por convenio</h3>
      <table class="tabla-pc"><thead><tr><th>Campaña</th><th>Propietario</th><th>Estado</th><th class="n">Comprometido</th><th class="n">Pagado</th><th class="n">Pendiente</th></tr></thead><tbody>
      ${r.filas.map((f) => `<tr data-conv="${esc(f.contrato_id)}"><td>${esc(f.campana)}</td><td>${esc(f.propietario)}</td><td>${esc(ETIQUETA_ESTADO[f.estado])}</td>
        <td class="n">${esc(formatoEuros(f.comprometido))}</td><td class="n">${esc(formatoEuros(f.pagado))}</td><td class="n">${esc(formatoEuros(f.pendiente))}</td></tr>`).join('')}
      </tbody></table>
      <button type="button" class="btn" id="pc-csv">Descargar CSV</button>`;
  }

  function enlazarTab(f) {
    const dlg = panel.dlg;
    const q = dlg.querySelector('#pc-q');
    if (q) {
      q.oninput = () => {
        f.q = q.value;
        const pos = q.selectionStart;
        dlg.querySelector('#pc-contenido').innerHTML = contenidoTab();
        enlazarTab(f);
        const nuevo = dlg.querySelector('#pc-q');
        nuevo.focus();
        nuevo.setSelectionRange(pos, pos);
      };
    }
    const camp = dlg.querySelector('#pc-camp');
    if (camp) camp.onchange = () => { f.campana = camp.value; pintarPanel(); };
    const est = dlg.querySelector('#pc-est');
    if (est) est.onchange = () => { f.estado = est.value; pintarPanel(); };
    const on = (sel, fn) => { const el = dlg.querySelector(sel); if (el) el.onclick = fn; };
    on('#pc-escaneo', () => importarEscaneado(ctl));
    on('#pc-nuevo-conv', () => editarConvenio(ctl));
    on('#pc-nueva-parcela', () => editarParcela(ctl));
    on('#pc-nuevo-prop', () => editarPropietario(ctl));
    on('#pc-ayudas', () => editarAyudas(ctl));
    on('#pc-csv', () => {
      const r = resumenCompensacion(ctl.datos.contratos, ctl.datos.pagos, ctl.datos.propietarios);
      guardarArchivo(compensacionACsv(r), `compensacion-aguiluchos-${new Date().toISOString().slice(0, 10)}.csv`, 'text/csv;charset=utf-8', 'csv');
    });
    dlg.querySelectorAll('[data-conv]').forEach((tr) => {
      tr.onclick = () => editarConvenio(ctl, { contrato: ctl.datos.contratos.find((c) => c.id === tr.dataset.conv) });
    });
    dlg.querySelectorAll('[data-parcela]').forEach((tr) => {
      tr.onclick = () => editarParcela(ctl, { parcela: ctl.datos.parcelas.find((p) => p.id === tr.dataset.parcela) });
    });
    dlg.querySelectorAll('[data-prop]').forEach((tr) => {
      tr.onclick = () => editarPropietario(ctl, { propietario: ctl.datos.propietarios.find((p) => p.id === tr.dataset.prop) });
    });
  }

  // ── Bloque «Parcela y contrato» en la ficha de un nido ──
  ctl.bloqueFicha = (contenedor, nido) => {
    const pintar = () => {
      if (!ctl.cargado) { contenedor.innerHTML = '<span class="info">Cargando contratos…</span>'; return; }
      if (!ctl.disponible) { contenedor.innerHTML = `<span class="info">${esc(ctl.error)}</span>`; return; }
      const ix = indexarContratos(ctl.datos);
      const est = ctl.estados().get(nido.id) ?? { codigo: 'sinparcela' };
      const explicito = ix.vinculo.has(nido.id);
      const parcelas = ctl.datos.parcelas;
      contenedor.innerHTML = `<div class="bloque-cab">${puntoSemaforo(est.codigo)} <b>${esc(SEMAFORO[est.codigo].etiqueta)}</b>
        ${est.campana ? `<span class="suave">· campaña ${est.campana}</span>` : ''}</div>
        ${est.parcela ? `<div class="bloque-fila">Parcela: <b>${esc(descripcionParcela(est.parcela))}</b>
          <button type="button" class="btn" data-acc="ver-parcela">Ver parcela</button>
          ${explicito ? '<button type="button" class="btn" data-acc="desvincular">Desvincular</button>' : '<span class="suave">(por referencia catastral)</span>'}</div>
          <div class="bloque-fila">${est.contrato
    ? `Convenio de ${esc(nombreProp(est.contrato.propietario_id))} · ${esc(ETIQUETA_ESTADO[est.contrato.estado])}${est.contrato.vigencia_hasta ? ` · hasta ${esc(est.contrato.vigencia_hasta)}` : ''}
              <button type="button" class="btn" data-acc="ver-convenio">Abrir convenio</button>`
    : `Sin convenio en ${est.campana}. <button type="button" class="btn primario" data-acc="crear-convenio">Crear convenio</button>`}</div>`
    : `<div class="bloque-fila"><select data-acc-sel><option value="">Vincular a una parcela existente…</option>${parcelas.map((p) => `<option value="${esc(p.id)}">${esc(descripcionParcela(p))}${p.municipio ? ` · ${esc(p.municipio)}` : ''}</option>`).join('')}</select>
          <button type="button" class="btn" data-acc="vincular">Vincular</button>
          <button type="button" class="btn primario" data-acc="crear-parcela">Crear parcela con los datos del nido</button></div>`}`;
      const on = (a, fn) => contenedor.querySelectorAll(`[data-acc="${a}"]`).forEach((b) => { b.onclick = fn; });
      on('ver-parcela', () => editarParcela(ctl, { parcela: est.parcela }));
      on('ver-convenio', () => editarConvenio(ctl, { contrato: est.contrato }));
      on('crear-convenio', () => editarConvenio(ctl, { parcelaInicial: est.parcela, campana: est.campana }));
      on('crear-parcela', () => editarParcela(ctl, { parcela: parcelaDesdeNido(nido), nidoParaVincular: nido, alGuardar: pintar }));
      on('desvincular', async () => {
        try { await desvincularNido(nido.id); await ctl.recargar(); pintar(); } catch (e) { alert(mensajeError(e)); }
      });
      on('vincular', async () => {
        const id = contenedor.querySelector('[data-acc-sel]').value;
        if (!id) return;
        try { await vincularNido(nido.id, id); await ctl.recargar(); pintar(); } catch (e) { alert(mensajeError(e)); }
      });
    };
    pintar();
  };

  return ctl;
}
