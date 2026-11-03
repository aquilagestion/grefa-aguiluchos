// Borradores del convenio y del consentimiento RGPD a partir de los datos del convenio.
// El texto reproduce el modelo de GREFA («Compensatorias esteparias», Comunidad de Madrid) y se
// entrega como documento editable (se retoca en pantalla y se saca a PDF o Word).
import { documentoHtml, esc } from './informe.js';
import { aNumero, formatoEuros } from './contratos_logic.js';

export const PROGRAMA_CAM = 'PROGRAMA AGROAMBIENTAL PARA EL FOMENTO DE CULTIVOS COMPATIBLES CON LA PRESENCIA DE AVES ESTEPARIAS EN EL MARCO DE LAS MEDIDAS COMPENSATORIAS POR EL DESPLIEGUE DE MEDIDAS RENOVABLES EN LA COMUNIDAD DE MADRID';

export const ESPECIES_OBJETIVO = [
  'El sisón (Tetrax tetrax)',
  'La avutarda (Otis tarda)',
  'El aguilucho cenizo (Circus pygargus)',
  'El aguilucho pálido (Circus cyaneus)',
  'El cernícalo primilla (Falco naumanni)',
  'La ganga (Pterocles alchata)',
  'La ortega (Pterocles orientalis)',
];

export const GREFA_POR_DEFECTO = {
  nombre: 'José Fernando Garcés Toledano',
  cargo: 'Secretario General de GREFA',
  domicilio: 'Centro Directivo en calle Calle sin número, Monte del Pilar, Majadahonda, 28220',
  lugar: 'Majadahonda, Madrid',
};

const MESES = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
const blanco = (v, ancho = 22) => (v == null || String(v).trim() === '' ? '_'.repeat(ancho) : `<u>${esc(v)}</u>`);

function fechaPartes(f) {
  const d = f ? new Date(`${String(f).slice(0, 10)}T00:00:00`) : null;
  if (!d || Number.isNaN(d.getTime())) return { dia: null, mes: null, anio: null };
  return { dia: d.getDate(), mes: MESES[d.getMonth()], anio: d.getFullYear() };
}

const importeAyuda = (a) => {
  if (a.importe == null) return a.nota || 'Variable';
  const base = Number(a.importe).toLocaleString('es-ES');
  const texto = a.unidad === 'ha' ? `${base} €/ha` : a.unidad === 'anual' ? `${base} €/año` : `${base} €`;
  return a.nota ? `${texto} ${a.nota}` : texto;
};

/** Totales por código de ayuda a partir de las líneas del convenio. */
export function totalesPorAyuda(lineas, ayudas) {
  return ayudas.map((a) => {
    const usan = lineas.filter((l) => (l.ayudas ?? []).includes(a.codigo));
    const sup = usan.reduce((s, l) => s + (aNumero(l.superficie_ha) ?? 0), 0);
    let total = null;
    if (usan.length && a.importe != null) total = a.unidad === 'ha' ? a.importe * sup : a.importe * usan.length;
    return { ayuda: a, sup, total: total == null ? null : Math.round(total * 100) / 100 };
  });
}

/**
 * @param {{contrato:object, propietario:object, lineas:Array<{parcela:object, linea:object}>, ayudas:object[], grefa?:object}} d
 */
export function borradorConvenio(d) {
  const { contrato: c, propietario: p, lineas, ayudas } = d;
  const g = { ...GREFA_POR_DEFECTO, ...(d.grefa ?? {}) };
  const programa = (c.programa && c.programa.toUpperCase()) || PROGRAMA_CAM;
  const f = fechaPartes(c.fecha_firma);
  const lugar = c.lugar_firma || g.lugar;
  const representa = p.tipo === 'representante' || p.tipo === 'entidad';
  const total = aNumero(c.importe_total);
  const pct = c.pct_firma ?? 60;
  const tot = totalesPorAyuda(lineas.map((x) => x.linea), ayudas);

  const filasParcelas = lineas.map(({ parcela: pa, linea: l }) => `<tr>
      <td>${esc(pa.sigpac_municipio ?? '')}</td><td>${esc(pa.sigpac_poligono ?? '')}</td><td>${esc(pa.sigpac_parcela ?? '')}</td>
      <td>${esc(pa.sigpac_agregado ?? '')}</td><td>${esc(pa.sigpac_zona ?? '')}</td><td>${esc(pa.sigpac_recinto ?? '')}</td>
      <td>${esc(l.superficie_ha ?? pa.superficie_ha ?? '')}</td><td>${esc(l.uso ?? pa.uso ?? '')}</td>
      ${[1, 2, 3, 4, 5, 6, 7, 8, 9].map((k) => `<td>${(l.ayudas ?? []).includes(k) ? 'X' : ''}</td>`).join('')}</tr>`).join('');
  const vacias = Math.max(0, 6 - lineas.length);
  const filasVacias = Array.from({ length: vacias }, () => `<tr>${'<td>&nbsp;</td>'.repeat(17)}</tr>`).join('');

  const filasPrecio = tot.map(({ ayuda: a, sup, total: t }) => `<tr>
      <td><b>${a.codigo}</b></td><td>${sup ? sup.toLocaleString('es-ES') : '-'}</td><td>${esc(importeAyuda(a))}</td>
      <td>${t == null ? '' : esc(formatoEuros(t))}</td></tr>`).join('');

  return `
<h1 style="text-align:center">CONVENIO PARA LA IMPLEMENTACIÓN DE ACCIONES DEL PLAN DE CONSERVACIÓN DE AVES ESTEPARIAS DEL PROYECTO COMPENSATORIAS</h1>
<p><b>DE UNA PARTE:</b> D. ${blanco(g.nombre)}, en nombre y representación de GREFA (Grupo de Rehabilitación de la Fauna Autóctona y su Hábitat), con domicilio ${esc(g.domicilio)}; email ${blanco('')}, teléfono ${blanco('', 14)}.</p>
<p><b>Y DE OTRA:</b> D./Dña. ${blanco(p.nombre)} con DNI/NIF ${blanco(p.nif, 14)}. Núm. de REGEPA: ${blanco(p.regepa, 16)}.</p>
<p>En adelante EL TITULAR:</p>
<ul>
  <li>${representa ? '&#9744;' : '&#9746;'} De manera particular</li>
  <li>${representa ? '&#9746;' : '&#9744;'} Como representante de la C.B. / SAT / … ${representa ? blanco(p.entidad, 24) : ''}</li>
</ul>
<p>Reconociéndose ambas partes capacidad legal para obligarse</p>

<h2>EXPONEN:</h2>
<p><b>PRIMERO.</b> Que GREFA es la entidad responsable de promover y gestionar la implementación y acciones del Plan de Conservación de Aves Esteparias en torno a los proyectos de energía fotovoltaica en el marco del <b>${esc(programa)}</b>.</p>
<p><b>SEGUNDO.</b> RELACIÓN DE PARCELAS O RECINTOS SIGPAC DEL TITULAR OBJETO DEL PRESENTE CONTRATO</p>
<table class="t">
  <thead><tr><th>MUN</th><th>POL</th><th>PAR</th><th>AGR</th><th>ZONA</th><th>REC</th><th>SUP</th><th>USO</th>
  ${[1, 2, 3, 4, 5, 6, 7, 8, 9].map((k) => `<th>${k}</th>`).join('')}</tr></thead>
  <tbody>${filasParcelas}${filasVacias}</tbody>
</table>
<p class="nota">Las columnas 1 a 9 son el CÓDIGO DE LA AYUDA (ver Anexo I, descripción de las ayudas).</p>
<p><b>ANEXO:</b> Hoja Consulta Descriptiva y Gráfica de Datos Catastrales de Bien Inmueble de la Sede Electrónica del Catastro (https://www.sedecatastro.gob.es/). Todas las parcelas han de ir acompañadas a la firma del presente convenio de la salida gráfica SIGPAC donde quede reflejada la referencia catastral, así como los croquis descriptivos si los hubiera.</p>
<p>La superficie identificada catastralmente posee valores ecológicos, paisajísticos y naturales que la hacen merecedora de una adecuada gestión ambiental.</p>
<p>Que EL TITULAR conoce las actividades del Proyecto y es consciente de la importancia y necesidad de que en la sociedad actual exista el preservar la naturaleza y los sistemas tradicionales, practicando una gestión integral del medio que permita compatibilizar el desarrollo económico con la conservación de los valores ambientales existentes.</p>
<p><b>TERCERO.</b> Que interesando a todas las partes la gestión integrada del medio natural y el fomento y mantenimiento de usos tradicionales compatibles con la conservación de la Naturaleza, lo llevan a cabo conforme a las siguientes</p>

<h2 style="text-align:center">ESTIPULACIONES:</h2>
<p><b>PRIMERA.</b> GREFA (Grupo de Rehabilitación de la Fauna y su Hábitat), como entidad responsable de promover y gestionar la implementación y acciones del Plan de Conservación de Aves Esteparias del <b>${esc(programa)}</b>, identificará las siguientes medidas/condiciones que el TITULAR asume como obligaciones:</p>
<p>Las parcelas sujetas a la ayuda deberán estar incluidas en las zonas de importancia para las poblaciones de:</p>
<ol>${ESPECIES_OBJETIVO.map((e) => `<li>${e}</li>`).join('')}</ol>
<p>Y situado en ${c.zona_programa ? `la <b>${esc(c.zona_programa)}</b>` : blanco('', 30)}, incluida en las zonas de relevancia para la avifauna establecidas por la Comunidad de Madrid.</p>

<p><b>SEGUNDA. PRECIO.</b> Por el presente contrato GREFA abonará como contraprestación dineraria los pagos que se indican a continuación, sujetos al Procedimiento de la Agencia Tributaria <b>Modelo 346</b>. Declaración informativa. Subvenciones e Indemnizaciones satisfechas pro- Entidades Públicas/Privadas a agricultores o ganaderos.</p>
<table class="t">
  <thead><tr><th>COD. AYUDA</th><th>SUP / HA</th><th>IMPORTE</th><th>TOTALES / €</th></tr></thead>
  <tbody>${filasPrecio}<tr><td colspan="3" style="text-align:right"><b>TOTAL</b></td><td><b>${total == null ? '' : esc(formatoEuros(total))}</b></td></tr></tbody>
</table>
<ul>
  <li>Ayuda anual por ${blanco('', 8)} euros.</li>
  <li>Se abonará un ${pct} % a la firma del presente convenio y el ${100 - pct} % restante a la finalización de las obligaciones adquiridas, si se han cumplido todas las obligaciones adquiridas.</li>
  <li>PRECIO DEL CONTRATO: ${total == null ? blanco('', 8) : `<u>${esc(total.toLocaleString('es-ES', { minimumFractionDigits: 2 }))}</u>`} EUR.</li>
  <li>La cuenta bancaria acreditada del TITULAR (IBAN): ${blanco('', 30)}</li>
</ul>
<p><b>IMPRESCINDIBLE:</b> certificado de titularidad de la cuenta bancaria y fotocopia del DNI del titular.</p>

<p><b>TERCERA.</b> El TITULAR asume las obligaciones derivadas del presente contrato de común acuerdo con GREFA, al igual que la forma y acceso a la finca y los tiempos en que mejor se puedan llevar a cabo el estudio y censo de las aves.</p>
<p><b>CUARTA. DURACIÓN.</b> La vigencia de este convenio es anual coincidiendo con el ejercicio agrícola en curso${c.campana ? ` (campaña ${esc(c.campana)})` : ''}, salvo que sea denunciado previamente por las partes, por incumplimiento de alguna de las Estipulaciones mencionadas con anterioridad. A su finalización podrá prorrogarse por acuerdo expreso y por escrito de las partes.</p>
<p><b>QUINTA.</b> El presente contrato es fruto de la buena fe, por lo que toda discrepancia resultante de la colaboración será resuelta por acuerdo entre las partes. De no ser posible, las partes acuerdan someterse al Sistema Arbitral de Consumo de la Junta de Comunidades de la Comunidad de Madrid.</p>

<p>Todo lo cual firman, en prueba de conformidad en ${esc(lugar)}, a ${blanco(f.dia, 4)} de ${blanco(f.mes, 12)} de ${blanco(f.anio, 6)}.</p>
<table class="firmas"><tr>
  <td style="width:50%;text-align:center"><br><br><br>_______________________________<br>D. ${esc(c.firmante_grefa || g.nombre)}<br>${esc(c.cargo_firmante || g.cargo)}</td>
  <td style="width:50%;text-align:center"><br><br><br>_______________________________<br>D./Dña. ${esc(p.nombre)}<br>EL TITULAR</td>
</tr></table>`;
}

/** Consentimiento informado para el tratamiento de datos personales (modelo de GREFA). */
export function borradorRgpd(d) {
  const { contrato: c, propietario: p } = d;
  const g = { ...GREFA_POR_DEFECTO, ...(d.grefa ?? {}) };
  const programa = (c?.programa && c.programa.toUpperCase()) || PROGRAMA_CAM;
  const f = fechaPartes(c?.fecha_firma);
  return `
<h1 style="text-align:center">CONSENTIMIENTO INFORMADO PARA EL TRATAMIENTO DE DATOS PERSONALES</h1>
<p>${esc(GREFA_POR_DEFECTO.lugar.split(',')[1]?.trim() || 'Madrid')}, ${blanco(f.dia, 4)} de ${blanco(f.mes, 12)} de ${blanco(f.anio, 6)}</p>
<h2>CLÁUSULA DEL DEBER DE INFORMAR</h2>
<ol>
<li><b>Responsable del tratamiento de sus datos.</b> Responsable: ${esc(g.nombre)}. Contacto Delegado de Protección de Datos: ${esc(g.nombre)}.</li>
<li><b>¿En qué actividad de tratamiento están incluidos mis datos personales y con qué fines se tratarán?</b> Actividad propia, productos y servicios de GREFA. En cumplimiento de lo establecido por el Reglamento (UE) 2016/679, de Protección de Datos Personales, sus datos serán tratados para la siguiente finalidad: Colaboración en proyectos ambientales, Acuerdo de Colaboración en el del <b>${esc(programa)}</b>, para la conservación de las aves esteparias en la Comunidad de Madrid.
  <br><i>¿Cuál es la legitimación en la cual se basa la licitud del tratamiento?</i> Base jurídica: Art. 6.1.c RGPD. El tratamiento es necesario para la ejecución de un contrato en el que el interesado es parte o para la aplicación a petición de éste de medidas precontractuales.
  <br><i>¿Cómo ejercer sus derechos? ¿Cuáles son sus derechos cuando nos facilita sus datos?</i> Puede ejercitar, si lo desea, los derechos de acceso, rectificación y supresión de sus datos, así como solicitar que se limite el tratamiento de sus datos personales, oponerse al mismo, así como a no ser objeto de una decisión individual basada únicamente en el tratamiento automatizado ni a la segmentación de perfiles.</li>
<li><b>¿Por cuánto tiempo conservaremos sus datos?</b> Los datos se mantendrán durante la duración del Acuerdo de Colaboración del <b>${esc(programa)}</b>, para la conservación de las aves esteparias en la Comunidad de Madrid y su conclusión de forma indeterminada en tanto el interesado no solicite su supresión o ejercite su derecho de oposición.</li>
<li><b>¿A qué destinatarios se comunicarán sus datos?</b> A otras entidades públicas y privadas que participan como socios del Proyecto, a la Red de Autoridades Ambientales, y a requerimiento de Jueces y Tribunales.</li>
<li><b>Derecho a presentar una reclamación ante la Autoridad de Control.</b> Tiene derecho a presentar una reclamación ante la Agencia Española de Protección de Datos www.aepd.es si no está conforme con el tratamiento que se hace de sus datos personales.</li>
<li><b>Categoría de datos objeto de tratamiento.</b></li>
<li>Datos de carácter identificativo: nombre, apellidos, imagen, de contacto: número de teléfono, dirección de correo electrónico y en su caso económicos: datos bancarios.</li>
<li><b>Fuente de la que procedan los datos.</b> El propio interesado.</li>
<li><b>Información adicional.</b> Pueden consultar la información adicional y detallada de la información y de la normativa aplicable en materia de protección de datos en la web de la Comunidad de Madrid.</li>
</ol>
<p>Fdo.: EL INTERESADO<br><br>Nombre ${blanco(p.nombre, 30)} &nbsp; DNI: ${blanco(p.nif, 14)}<br><br><br>_______________________________</p>`;
}

export const htmlBorrador = (cuerpo, titulo) => documentoHtml(cuerpo, titulo);
