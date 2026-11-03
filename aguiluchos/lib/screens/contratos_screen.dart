import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/app_services.dart';
import '../models/contratos.dart';
import '../models/nido_filter.dart';
import '../models/nido_grefa_model.dart';
import '../services/contratos_service.dart';

final _fmtFecha = DateFormat('dd/MM/yyyy');
String _f(DateTime? d) => d == null ? '—' : _fmtFecha.format(d);

Color colorEstadoConvenio(EstadoConvenio e) => switch (e) {
      EstadoConvenio.firmado => const Color(0xFF2E6B3A),
      EstadoConvenio.enviado || EstadoConvenio.borrador => const Color(0xFFE08A1E),
      EstadoConvenio.caducado || EstadoConvenio.rechazado => const Color(0xFFC0392B),
    };

Widget chipEtiqueta(String texto, Color color, {IconData? icono}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icono != null) ...[Icon(icono, size: 14, color: color), const SizedBox(width: 4)],
        Flexible(
          child: Text(texto,
              style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
        ),
      ]),
    );

Future<void> _abrir(BuildContext context, Uri uri) async {
  final messenger = ScaffoldMessenger.of(context);
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication)
      .catchError((_) => false);
  if (!ok) messenger.showSnackBar(SnackBar(content: Text('No se pudo abrir $uri')));
}

/// Fila con el titular y botones para llamar / escribir.
class FilaPropietario extends StatelessWidget {
  const FilaPropietario(this.p, {super.key});
  final Propietario p;

  @override
  Widget build(BuildContext context) {
    final nombre = (p.entidad != null && p.entidad!.isNotEmpty)
        ? '${p.nombre} (${p.entidad})'
        : p.nombre;
    return Row(children: [
      const Icon(Icons.person_outline, size: 18),
      const SizedBox(width: 8),
      Expanded(child: Text(nombre)),
      if (p.telefono != null)
        TextButton.icon(
          onPressed: () => _abrir(context, Uri(scheme: 'tel', path: p.telefono!.replaceAll(' ', ''))),
          icon: const Icon(Icons.call, size: 18),
          label: Text(p.telefono!),
        ),
      if (p.email != null)
        IconButton(
          tooltip: p.email,
          onPressed: () => _abrir(context, Uri(scheme: 'mailto', path: p.email)),
          icon: const Icon(Icons.mail_outline, size: 20),
        ),
    ]);
  }
}

/// Bloque «Parcela y contrato» de la ficha de un nido.
class BloqueContratoNido extends StatelessWidget {
  const BloqueContratoNido({super.key, required this.nido});
  final NidoGrefaModel nido;

  @override
  Widget build(BuildContext context) {
    final servicio = AppServices.of(context).contratos;
    if (servicio == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: servicio,
      builder: (context, _) {
        if (servicio.datos.vacio) {
          return _marco(context, servicio, [
            Text(servicio.hayOrigen
                ? 'Aún no hay datos de contratos en este dispositivo. Abre «Contratos y parcelas» con conexión para descargarlos.'
                : 'Contratos no disponibles (app sin conexión al servidor).'),
          ]);
        }
        final est = servicio.estadoDe(nido);
        final parcela = est.parcela;
        final conv = est.convenio;
        final titulares = parcela == null
            ? const <Propietario>[]
            : servicio.datos.titularesDe(parcela.id);
        final titular = conv == null ? null : servicio.datos.propietario(conv.propietarioId);
        return _marco(context, servicio, [
          Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            chipEtiqueta(est.codigo.etiqueta, est.codigo.color, icono: Icons.circle),
            Text('Campaña ${est.campana}', style: Theme.of(context).textTheme.bodySmall),
          ]),
          if (parcela != null) ...[
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.crop_square, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(parcela.descripcion)),
              if (parcela.mapaUri != null)
                IconButton(
                  tooltip: 'Ver parcela en el mapa',
                  onPressed: () => _abrir(context, parcela.mapaUri!),
                  icon: const Icon(Icons.map_outlined, size: 20),
                ),
            ]),
          ] else
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Este nido no está vinculado a ninguna parcela (ni coincide su referencia catastral).'),
            ),
          if (conv != null) ...[
            const SizedBox(height: 4),
            Text('Convenio ${conv.estado.etiqueta.toLowerCase()}'
                '${conv.fechaFirma != null ? ' · firmado el ${_f(conv.fechaFirma)}' : ''}'
                '${conv.vigenciaHasta != null ? ' · vigente hasta ${_f(conv.vigenciaHasta)}' : ''}'),
          ],
          for (final t in {?titular, ...titulares}) FilaPropietario(t),
        ]);
      },
    );
  }

  Widget _marco(BuildContext context, ContratosService s, List<Widget> hijos) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.description_outlined, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Parcela y contrato',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const ContratosScreen())),
              child: const Text('Ver todos'),
            ),
          ]),
          ...hijos,
        ]),
      ),
    );
  }
}

/// Convenios y parcelas (solo lectura).
class ContratosScreen extends StatefulWidget {
  const ContratosScreen({super.key});

  @override
  State<ContratosScreen> createState() => _ContratosScreenState();
}

class _ContratosScreenState extends State<ContratosScreen> {
  final _busqueda = TextEditingController();
  Map<String, NidoGrefaModel> _nidos = const {};
  StreamSubscription<void>? _sub;
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final services = AppServices.of(context);
    _sub = services.db.changes.listen((_) => _cargarNidos());
    _cargarNidos();
    // Al entrar se intenta actualizar (si hay red); si no, se ve la caché.
    services.contratos?.refrescar();
  }

  Future<void> _cargarNidos() async {
    final todos = await AppServices.of(context).db.consultar(const NidoFilter());
    if (!mounted) return;
    setState(() => _nidos = {for (final n in todos) n.id: n});
  }

  @override
  void dispose() {
    _sub?.cancel();
    _busqueda.dispose();
    super.dispose();
  }

  String _etiquetaNido(String id) {
    final n = _nidos[id];
    if (n == null) return 'nido';
    final e = (n.etiqueta ?? '').isEmpty ? '(sin etiqueta)' : n.etiqueta!;
    return (n.municipio ?? '').isEmpty ? e : '$e · ${n.municipio}';
  }

  @override
  Widget build(BuildContext context) {
    final servicio = AppServices.of(context).contratos;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Contratos y parcelas'),
          actions: [
            if (servicio != null)
              ListenableBuilder(
                listenable: servicio,
                builder: (_, _) => servicio.cargando
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : IconButton(
                        tooltip: 'Actualizar',
                        onPressed: servicio.hayOrigen ? servicio.refrescar : null,
                        icon: const Icon(Icons.sync),
                      ),
              ),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Convenios'), Tab(text: 'Parcelas')]),
        ),
        body: servicio == null
            ? const Center(child: Text('Contratos no disponibles.'))
            : ListenableBuilder(
                listenable: servicio,
                builder: (context, _) => Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    child: TextField(
                      controller: _busqueda,
                      decoration: const InputDecoration(
                        labelText: 'Buscar propietario, parcela o nido',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  _Estado(servicio: servicio),
                  Expanded(
                    child: TabBarView(children: [
                      _ListaConvenios(
                          servicio: servicio,
                          consulta: _busqueda.text,
                          etiquetaNido: _etiquetaNido),
                      _ListaParcelas(
                          servicio: servicio,
                          consulta: _busqueda.text,
                          etiquetaNido: _etiquetaNido),
                    ]),
                  ),
                ]),
              ),
      ),
    );
  }
}

class _Estado extends StatelessWidget {
  const _Estado({required this.servicio});
  final ContratosService servicio;

  @override
  Widget build(BuildContext context) {
    final u = servicio.ultimaActualizacion;
    final texto = u == null
        ? 'Sin datos descargados todavía.'
        : 'Datos del ${DateFormat('dd/MM/yyyy HH:mm').format(u.toLocal())}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          servicio.error != null ? '$texto · ${servicio.error}' : texto,
          style: TextStyle(
              fontSize: 12,
              color: servicio.error != null
                  ? const Color(0xFFEF6C00)
                  : Theme.of(context).hintColor),
        ),
      ),
    );
  }
}

bool _coincide(String consulta, Iterable<String?> textos) {
  final q = consulta.trim().toLowerCase();
  if (q.isEmpty) return true;
  return textos.any((t) => (t ?? '').toLowerCase().contains(q));
}

class _ListaConvenios extends StatelessWidget {
  const _ListaConvenios(
      {required this.servicio, required this.consulta, required this.etiquetaNido});
  final ContratosService servicio;
  final String consulta;
  final String Function(String) etiquetaNido;

  @override
  Widget build(BuildContext context) {
    final d = servicio.datos;
    final convenios = d.convenios.where((c) {
      final prop = d.propietario(c.propietarioId);
      final parcelas = [
        for (final l in d.lineasDeConvenio(c.id)) d.parcela(l.parcelaId),
      ].whereType<Parcela>();
      final nidos = [
        for (final p in parcelas) ...d.nidosDeParcela(p.id).map(etiquetaNido),
      ];
      return _coincide(consulta, [
        prop?.nombre,
        prop?.entidad,
        ...parcelas.map((p) => p.descripcion),
        ...nidos,
      ]);
    }).toList()
      ..sort((a, b) {
        final c = b.campana.compareTo(a.campana);
        if (c != 0) return c;
        final e = a.estado.prioridad.compareTo(b.estado.prioridad);
        if (e != 0) return e;
        return (d.propietario(a.propietarioId)?.nombre ?? '')
            .compareTo(d.propietario(b.propietarioId)?.nombre ?? '');
      });

    if (convenios.isEmpty) {
      return _Vacio(
          d.vacio ? 'No hay convenios descargados todavía.' : 'Ningún convenio coincide.');
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      itemCount: convenios.length,
      itemBuilder: (context, i) {
        final c = convenios[i];
        final prop = d.propietario(c.propietarioId);
        final lineas = d.lineasDeConvenio(c.id);
        return Card(
          child: ExpansionTile(
            shape: const Border(),
            collapsedShape: const Border(),
            title: Text(prop?.nombre ?? '(sin propietario)',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('Campaña ${c.campana} · ${lineas.length} parcela${lineas.length == 1 ? '' : 's'}'),
            trailing: chipEtiqueta(c.estado.etiqueta, colorEstadoConvenio(c.estado)),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            children: [
              if (prop != null) FilaPropietario(prop),
              if (c.programa != null) Text(c.programa!),
              Text('Firma: ${_f(c.fechaFirma)} · Vigencia: ${_f(c.vigenciaDesde)} – ${_f(c.vigenciaHasta)}'),
              const SizedBox(height: 8),
              for (final l in lineas) _LineaParcela(servicio: servicio, linea: l, etiquetaNido: etiquetaNido),
            ],
          ),
        );
      },
    );
  }
}

class _LineaParcela extends StatelessWidget {
  const _LineaParcela(
      {required this.servicio, required this.linea, required this.etiquetaNido});
  final ContratosService servicio;
  final LineaConvenio linea;
  final String Function(String) etiquetaNido;

  @override
  Widget build(BuildContext context) {
    final p = servicio.datos.parcela(linea.parcelaId);
    final nidos = servicio.datos.nidosDeParcela(linea.parcelaId);
    final detalles = [
      if (linea.superficieHa != null) '${linea.superficieHa} ha',
      if (linea.uso != null) 'uso ${linea.uso}',
      if (linea.ayudas.isNotEmpty) 'ayudas ${linea.ayudas.join(', ')}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.crop_square, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p?.descripcion ?? 'Parcela'),
            if (detalles.isNotEmpty)
              Text(detalles, style: Theme.of(context).textTheme.bodySmall),
            if (nidos.isNotEmpty)
              Text('Nidos: ${nidos.map(etiquetaNido).join(', ')}',
                  style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
        if (p?.mapaUri != null)
          IconButton(
            tooltip: 'Ver en el mapa',
            onPressed: () => _abrir(context, p!.mapaUri!),
            icon: const Icon(Icons.map_outlined, size: 20),
          ),
      ]),
    );
  }
}

class _ListaParcelas extends StatelessWidget {
  const _ListaParcelas(
      {required this.servicio, required this.consulta, required this.etiquetaNido});
  final ContratosService servicio;
  final String consulta;
  final String Function(String) etiquetaNido;

  @override
  Widget build(BuildContext context) {
    final d = servicio.datos;
    final parcelas = d.parcelas.where((p) {
      return _coincide(consulta, [
        p.descripcion,
        ...d.titularesDe(p.id).map((t) => t.nombre),
        ...d.nidosDeParcela(p.id).map(etiquetaNido),
      ]);
    }).toList()
      ..sort((a, b) => a.descripcion.compareTo(b.descripcion));

    if (parcelas.isEmpty) {
      return _Vacio(
          d.vacio ? 'No hay parcelas descargadas todavía.' : 'Ninguna parcela coincide.');
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      itemCount: parcelas.length,
      itemBuilder: (context, i) {
        final p = parcelas[i];
        final titulares = d.titularesDe(p.id);
        final lineas = [...d.lineasDeParcela(p.id)]
          ..sort((a, b) => b.campana.compareTo(a.campana));
        final nidos = d.nidosDeParcela(p.id);
        return Card(
          child: ExpansionTile(
            shape: const Border(),
            collapsedShape: const Border(),
            title: Text(p.descripcion, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text([
              if (titulares.isNotEmpty) titulares.map((t) => t.nombre).join(', '),
              if (p.superficieHa != null) '${p.superficieHa} ha',
            ].join(' · ')),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            children: [
              for (final t in titulares) FilaPropietario(t),
              if (lineas.isEmpty) const Text('Sin convenios.'),
              for (final l in lineas)
                if (d.convenio(l.contratoId) case final c?)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Text('Campaña ${c.campana}'),
                      chipEtiqueta(c.estado.etiqueta, colorEstadoConvenio(c.estado)),
                      if (c.vigenciaHasta != null) Text('hasta ${_f(c.vigenciaHasta)}'),
                    ]),
                  ),
              if (nidos.isNotEmpty) Text('Nidos: ${nidos.map(etiquetaNido).join(', ')}'),
              if (p.mapaUri != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _abrir(context, p.mapaUri!),
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Ver en el mapa'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Vacio extends StatelessWidget {
  const _Vacio(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(texto, textAlign: TextAlign.center),
        ),
      );
}
