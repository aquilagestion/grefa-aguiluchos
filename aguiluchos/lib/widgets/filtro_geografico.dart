import 'package:flutter/material.dart';

import '../models/nido_filter.dart';
import '../models/nido_grefa_model.dart';
import '../utils/geografia.dart';

/// Quita de [f] las selecciones geográficas que ya no existen en [todos]
/// (p. ej. tras borrar o editar un nido) y las que dependen de ellas.
NidoFilter sanearGeo(NidoFilter f, List<NidoGrefaModel> todos) {
  if (!f.tieneFiltroGeografico) return f;
  var pais = f.pais;
  var comunidad = f.comunidad;
  var provincia = f.provincia;
  var localidad = f.localidad;
  if (pais != null && !opcionesCascada(todos).paises.contains(pais)) {
    pais = comunidad = provincia = localidad = null;
  }
  if (comunidad != null &&
      !opcionesCascada(todos, pais: pais).comunidades.contains(comunidad)) {
    comunidad = provincia = localidad = null;
  }
  if (provincia != null &&
      !opcionesCascada(
        todos,
        pais: pais,
        comunidad: comunidad,
      ).provincias.contains(provincia)) {
    provincia = localidad = null;
  }
  if (localidad != null &&
      !opcionesCascada(
        todos,
        pais: pais,
        comunidad: comunidad,
        provincia: provincia,
      ).localidades.contains(localidad)) {
    localidad = null;
  }
  if (pais == f.pais &&
      comunidad == f.comunidad &&
      provincia == f.provincia &&
      localidad == f.localidad) {
    return f;
  }
  return f.conGeo(
    pais: pais,
    comunidad: comunidad,
    provincia: provincia,
    localidad: localidad,
  );
}

/// Texto resumen de la selección geográfica («España › Galicia › Ourense»).
String resumenGeo(NidoFilter f) => [
  f.pais,
  f.comunidad,
  f.provincia,
  f.localidad,
].whereType<String>().join(' › ');

/// Selectores en cascada País → Comunidad autónoma → Provincia → Localidad.
/// Cada nivel solo ofrece lo que existe dentro de la selección superior.
class FiltroGeografico extends StatelessWidget {
  const FiltroGeografico({
    super.key,
    required this.nidos,
    required this.filter,
    required this.onChanged,
    this.plegable = false,
  });

  /// Todos los nidos (sin filtrar) para calcular las opciones.
  final List<NidoGrefaModel> nidos;
  final NidoFilter filter;
  final ValueChanged<NidoFilter> onChanged;

  /// Si es `true` se muestra dentro de un panel desplegable (para móvil).
  final bool plegable;

  Widget _selector({
    required Key key,
    required String etiqueta,
    required String? valor,
    required List<String> opciones,
    required ValueChanged<String?> alCambiar,
  }) {
    final actual = valor != null && opciones.contains(valor) ? valor : null;
    return KeyedSubtree(
      key: key,
      child: DropdownButtonFormField<String?>(
        key: ValueKey('$etiqueta-$actual-${opciones.length}'),
        initialValue: actual,
        isExpanded: true,
        decoration: InputDecoration(labelText: etiqueta, isDense: true),
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('Todos')),
          for (final o in opciones)
            DropdownMenuItem<String?>(value: o, child: Text(o)),
        ],
        onChanged: alCambiar,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final f = filter;
    final o = opcionesCascada(
      nidos,
      pais: f.pais,
      comunidad: f.comunidad,
      provincia: f.provincia,
    );

    final pais = _selector(
      key: const Key('geo-pais'),
      etiqueta: 'País',
      valor: f.pais,
      opciones: o.paises,
      alCambiar: (v) => onChanged(f.conGeo(pais: v)),
    );
    final comunidad = _selector(
      key: const Key('geo-comunidad'),
      etiqueta: 'Comunidad autónoma',
      valor: f.comunidad,
      opciones: o.comunidades,
      alCambiar: (v) => onChanged(f.conGeo(pais: f.pais, comunidad: v)),
    );
    final provincia = _selector(
      key: const Key('geo-provincia'),
      etiqueta: 'Provincia',
      valor: f.provincia,
      opciones: o.provincias,
      alCambiar: (v) => onChanged(
        f.conGeo(pais: f.pais, comunidad: f.comunidad, provincia: v),
      ),
    );
    final localidad = _selector(
      key: const Key('geo-localidad'),
      etiqueta: 'Localidad',
      valor: f.localidad,
      opciones: o.localidades,
      alCambiar: (v) => onChanged(
        f.conGeo(
          pais: f.pais,
          comunidad: f.comunidad,
          provincia: f.provincia,
          localidad: v,
        ),
      ),
    );

    final cuerpo = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(child: pais),
            const SizedBox(width: 8),
            Expanded(child: comunidad),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: provincia),
            const SizedBox(width: 8),
            Expanded(child: localidad),
          ],
        ),
      ],
    );

    if (!plegable) return cuerpo;
    final resumen = resumenGeo(f);
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        key: const Key('geo-panel'),
        dense: true,
        initiallyExpanded: f.tieneFiltroGeografico,
        leading: const Icon(Icons.place_outlined),
        title: const Text('Ubicación'),
        subtitle: Text(
          resumen.isEmpty ? 'País, comunidad, provincia y localidad' : resumen,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [cuerpo],
      ),
    );
  }
}
