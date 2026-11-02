// Jerarquía administrativa derivada de los datos del nido: País > Comunidad
// autónoma > Provincia > Localidad. No hay columnas nuevas: se calcula a partir
// de `provincia` y `municipio` (y, si `provincia` trae una comunidad, se respeta).

export const PAIS = 'España';
export const SIN_DATO = 'Sin indicar';

/** comunidad -> provincias (nombre canónico). */
export const COMUNIDADES = {
  'Andalucía': ['Almería', 'Cádiz', 'Córdoba', 'Granada', 'Huelva', 'Jaén', 'Málaga', 'Sevilla'],
  'Aragón': ['Huesca', 'Teruel', 'Zaragoza'],
  'Principado de Asturias': ['Asturias'],
  'Illes Balears': ['Illes Balears'],
  'Canarias': ['Las Palmas', 'Santa Cruz de Tenerife'],
  'Cantabria': ['Cantabria'],
  'Castilla y León': ['Ávila', 'Burgos', 'León', 'Palencia', 'Salamanca', 'Segovia', 'Soria', 'Valladolid', 'Zamora'],
  'Castilla-La Mancha': ['Albacete', 'Ciudad Real', 'Cuenca', 'Guadalajara', 'Toledo'],
  'Cataluña': ['Barcelona', 'Girona', 'Lleida', 'Tarragona'],
  'Comunitat Valenciana': ['Alicante', 'Castellón', 'Valencia'],
  'Extremadura': ['Badajoz', 'Cáceres'],
  'Galicia': ['A Coruña', 'Lugo', 'Ourense', 'Pontevedra'],
  'Comunidad de Madrid': ['Madrid'],
  'Región de Murcia': ['Murcia'],
  'Comunidad Foral de Navarra': ['Navarra'],
  'País Vasco': ['Álava', 'Bizkaia', 'Gipuzkoa'],
  'La Rioja': ['La Rioja'],
  'Ceuta': ['Ceuta'],
  'Melilla': ['Melilla'],
};

/** Variantes escritas a mano -> nombre canónico (de provincia o de comunidad). */
const ALIAS_PROVINCIA = {
  'la coruna': 'A Coruña', coruna: 'A Coruña', 'a coruna': 'A Coruña',
  orense: 'Ourense', gerona: 'Girona', lerida: 'Lleida', alacant: 'Alicante', castello: 'Castellón',
  baleares: 'Illes Balears', 'islas baleares': 'Illes Balears', 'illes balears': 'Illes Balears',
  alava: 'Álava', araba: 'Álava', vizcaya: 'Bizkaia', guipuzcoa: 'Gipuzkoa',
  rioja: 'La Rioja', nafarroa: 'Navarra', 'santa cruz tenerife': 'Santa Cruz de Tenerife',
};
const ALIAS_COMUNIDAD = {
  andalucia: 'Andalucía', aragon: 'Aragón', asturias: 'Principado de Asturias',
  'castilla la mancha': 'Castilla-La Mancha', 'castilla y leon': 'Castilla y León',
  cataluna: 'Cataluña', catalunya: 'Cataluña',
  'comunidad valenciana': 'Comunitat Valenciana', 'comunitat valenciana': 'Comunitat Valenciana', valenciana: 'Comunitat Valenciana',
  'comunidad de madrid': 'Comunidad de Madrid', 'region de murcia': 'Región de Murcia',
  'comunidad foral de navarra': 'Comunidad Foral de Navarra',
  'pais vasco': 'País Vasco', euskadi: 'País Vasco', canarias: 'Canarias', 'islas canarias': 'Canarias',
  'illes balears': 'Illes Balears', baleares: 'Illes Balears',
};

/** Localidades cuyo nombre es una comarca/espacio y cuya provincia es conocida. */
const PROVINCIA_POR_LOCALIDAD = {
  limia: 'Ourense', xures: 'Ourense', 'a limia': 'Ourense',
};

export const norm = (s) => String(s ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g, '')
  .toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();

const PROV_A_COM = {};
const NORM_PROV = {};
const NORM_COM = {};
for (const [com, provs] of Object.entries(COMUNIDADES)) {
  NORM_COM[norm(com)] = com;
  for (const p of provs) { PROV_A_COM[p] = com; NORM_PROV[norm(p)] = p; }
}
for (const [k, v] of Object.entries(ALIAS_PROVINCIA)) NORM_PROV[k] = v;
for (const [k, v] of Object.entries(ALIAS_COMUNIDAD)) NORM_COM[k] = v;

/**
 * {pais, comunidad, provincia, localidad} de un nido. Siempre devuelve texto
 * (usa «Sin indicar» cuando el dato falta o no se reconoce).
 */
export function ubicacion(n) {
  const prov = String(n.provincia ?? '').trim();
  const loc = String(n.municipio ?? '').trim();
  const k = norm(prov);
  let provincia = SIN_DATO;
  let comunidad = SIN_DATO;

  if (prov && NORM_PROV[k]) {
    provincia = NORM_PROV[k];
    comunidad = PROV_A_COM[provincia] ?? SIN_DATO;
  } else if (prov && NORM_COM[k]) {
    // El campo «provincia» trae una comunidad (p. ej. «Galicia»).
    comunidad = NORM_COM[k];
  } else if (prov) {
    provincia = prov; // valor desconocido: se conserva tal cual
  }
  if (provincia === SIN_DATO) {
    const deducida = PROVINCIA_POR_LOCALIDAD[norm(loc)];
    if (deducida) {
      provincia = deducida;
      if (comunidad === SIN_DATO) comunidad = PROV_A_COM[deducida] ?? SIN_DATO;
    }
  }
  return { pais: PAIS, comunidad, provincia, localidad: loc || SIN_DATO };
}

const ordenar = (a) => [...a].sort((x, y) => x.localeCompare(y, 'es'));

/**
 * Opciones en cascada para los filtros. Cada nivel solo muestra lo que existe
 * dentro de la selección de los niveles superiores.
 * @param {object[]} nidos
 * @param {{pais?:string, comunidad?:string, provincia?:string}} sel
 */
export function opcionesCascada(nidos, sel = {}) {
  const u = nidos.map(ubicacion);
  const pasa = (x, hasta) => (!sel.pais || x.pais === sel.pais)
    && (hasta < 1 || !sel.comunidad || x.comunidad === sel.comunidad)
    && (hasta < 2 || !sel.provincia || x.provincia === sel.provincia);
  const uniq = (campo, hasta) => ordenar(new Set(u.filter((x) => pasa(x, hasta)).map((x) => x[campo])));
  return {
    paises: uniq('pais', 0),
    comunidades: uniq('comunidad', 0),
    provincias: uniq('provincia', 1),
    localidades: uniq('localidad', 2),
  };
}

/** Agrupa nidos por un nivel ('pais' | 'comunidad' | 'provincia' | 'localidad'). */
export function agruparPorNivel(nidos, nivel) {
  const m = new Map();
  for (const n of nidos) {
    const k = ubicacion(n)[nivel];
    if (!m.has(k)) m.set(k, []);
    m.get(k).push(n);
  }
  return [...m.entries()].sort((a, b) => b[1].length - a[1].length || a[0].localeCompare(b[0], 'es'));
}
