import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart' show FilePicker;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../app/app_services.dart';
import '../models/nido_constants.dart';
import '../models/nido_filter.dart';
import '../models/nido_grefa_model.dart';
import '../services/export_service.dart';
import '../widgets/responsive.dart';

/// Exportación a Excel y PDF con filtros y selector de columnas a la carta.
class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

enum _Entrega { compartir, guardar }

class _Archivo {
  const _Archivo({
    required this.nombre,
    required this.mime,
    required this.ext,
    required this.bytes,
  });
  final String nombre;
  final String mime;
  final String ext;
  final Uint8List bytes;
}

class _ExportScreenState extends State<ExportScreen> {
  static const _estados = [
    EstadoReproductivo.todos,
    EstadoReproductivo.exito,
    EstadoReproductivo.fracaso,
  ];

  DateTimeRange? _rango;
  final Set<String> _municipiosSel = {};
  List<String> _municipios = const [];
  EstadoReproductivo _estado = EstadoReproductivo.todos;
  final Set<String> _columnas = {for (final c in nidoColumns) c.key};
  int? _coinciden;
  bool _busy = false;
  bool _didInit = false;

  NidoFilter get _filter => NidoFilter(
        municipios: _municipiosSel,
        estado: _estado,
        fechaDesde: _rango?.start,
        fechaHasta: _rango?.end,
      );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInit) return;
    _didInit = true;
    final db = AppServices.of(context).db;
    db.municipios().then((m) {
      if (mounted) setState(() => _municipios = m);
    });
    _contar();
  }

  Future<void> _contar() async {
    final n = await AppServices.of(context).db.consultar(_filter);
    if (mounted) setState(() => _coinciden = n.length);
  }

  String get _descripcionFiltros {
    final f = DateFormat('dd/MM/yyyy');
    return [
      if (_rango != null)
        'campaña ${f.format(_rango!.start)} - ${f.format(_rango!.end)}',
      if (_municipiosSel.isNotEmpty) 'municipios: ${_municipiosSel.join(', ')}',
      if (_estado != EstadoReproductivo.todos) 'estado: ${_estado.etiqueta}',
    ].join(' | ');
  }

  List<NidoColumn> get _columnasSeleccionadas =>
      nidoColumns.where((c) => _columnas.contains(c.key)).toList();

  Future<void> _elegirRango() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 2),
      initialDateRange: _rango,
      locale: const Locale('es', 'ES'),
      helpText: 'Rango de fechas de la campaña',
    );
    if (r != null) {
      setState(() => _rango = r);
      _contar();
    }
  }

  Future<_Archivo?> _prepararExcel(List<NidoGrefaModel> nidos) async {
    final bytes = AppServices.of(context)
        .export
        .generarExcel(nidos, _columnasSeleccionadas);
    return _Archivo(
      nombre: ExportService.nombreArchivo('nidos_aguiluchos', 'xlsx'),
      mime: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      ext: 'xlsx',
      bytes: bytes,
    );
  }

  Future<_Archivo?> _prepararPdf(List<NidoGrefaModel> nidos) async {
    final bytes = await AppServices.of(context).export.generarPdf(
          nidos,
          descripcionFiltros: _descripcionFiltros,
        );
    return _Archivo(
      nombre: ExportService.nombreArchivo('informe_aguiluchos', 'pdf'),
      mime: 'application/pdf',
      ext: 'pdf',
      bytes: bytes,
    );
  }

  Future<void> _exportarExcel() => _generar(excel: true, pdf: false);

  Future<void> _exportarPdf() => _generar(excel: false, pdf: true);

  Future<void> _exportarAmbos() => _generar(excel: true, pdf: true);

  Future<void> _generar({required bool excel, required bool pdf}) async {
    if (excel && _columnas.isEmpty) {
      _snack('Selecciona al menos una columna.');
      return;
    }
    final services = AppServices.of(context);
    setState(() => _busy = true);
    final archivos = <_Archivo>[];
    try {
      final nidos = await services.db.consultar(_filter);
      if (nidos.isEmpty) {
        _snack('No hay nidos que cumplan los filtros.');
        return;
      }
      if (excel) archivos.add((await _prepararExcel(nidos))!);
      if (pdf) archivos.add((await _prepararPdf(nidos))!);
    } catch (e) {
      _snack('Error al generar el archivo: $e');
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    await _entregar(archivos);
  }

  /// Pregunta al usuario qué hacer con los informes generados: compartirlos o
  /// guardarlos eligiendo dónde (carpeta y nombre) para cada uno.
  Future<void> _entregar(List<_Archivo> archivos) async {
    final choice = await showModalBottomSheet<_Entrega>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final a in archivos)
            ListTile(
              dense: archivos.length > 1,
              leading: Icon(a.ext == 'pdf'
                  ? Icons.picture_as_pdf
                  : Icons.table_chart),
              title: Text(a.nombre,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${(a.bytes.length / 1024).toStringAsFixed(1)} KB'),
            ),
          const Divider(height: 1),
          ListTile(
            key: const Key('entrega-guardar'),
            leading: const Icon(Icons.save_alt),
            title: const Text('Guardar en…'),
            subtitle: Text(archivos.length > 1
                ? 'Elegirás carpeta y nombre de cada informe'
                : 'Elige carpeta y nombre del informe'),
            onTap: () => Navigator.pop(ctx, _Entrega.guardar),
          ),
          ListTile(
            key: const Key('entrega-compartir'),
            leading: const Icon(Icons.share),
            title: const Text('Compartir'),
            subtitle: const Text('WhatsApp, correo electrónico, Drive…'),
            onTap: () => Navigator.pop(ctx, _Entrega.compartir),
          ),
        ]),
      ),
    );
    if (choice == null || !mounted) return;

    try {
      if (choice == _Entrega.guardar) {
        await _guardarEn(archivos);
      } else {
        await _compartir(archivos);
      }
    } catch (e) {
      _snack('No se pudo completar la acción: $e');
    }
  }

  Future<void> _compartir(List<_Archivo> archivos) async {
    final export = AppServices.of(context).export;
    try {
      final xfiles = <XFile>[];
      for (final a in archivos) {
        final f = await export.guardarTemporal(a.bytes, a.nombre);
        xfiles.add(XFile(f.path, mimeType: a.mime, name: a.nombre));
      }
      await SharePlus.instance.share(ShareParams(
        files: xfiles,
        subject: 'Aguiluchos GREFA - ${archivos.map((a) => a.nombre).join(', ')}',
        text: 'Informe de la campaña Aguilucho (GREFA).',
      ));
    } on UnimplementedError {
      _snack('Compartir archivos no está disponible en este sistema; elige dónde guardarlo.');
      await _guardarEn(archivos);
    }
  }

  /// Muestra el selector del sistema para cada informe (carpeta + nombre).
  Future<void> _guardarEn(List<_Archivo> archivos) async {
    final guardados = <String>[];
    for (final a in archivos) {
      final destino = await _elegirDestino(a);
      if (destino == null) {
        // El usuario canceló: no se sigue preguntando por el resto.
        break;
      }
      guardados.add(destino);
    }
    if (guardados.isEmpty) {
      _snack('Guardado cancelado.');
    } else {
      _snack(guardados.length == 1
          ? 'Guardado en ${guardados.first}'
          : 'Guardados ${guardados.length} informes:\n${guardados.join('\n')}');
    }
  }

  /// Devuelve la ruta/URI donde se guardó o `null` si se canceló.
  Future<String?> _elegirDestino(_Archivo a) async {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      final loc = await getSaveLocation(
        suggestedName: a.nombre,
        acceptedTypeGroups: [
          XTypeGroup(label: a.ext.toUpperCase(), extensions: [a.ext]),
        ],
      );
      if (loc == null) return null;
      await File(loc.path).writeAsBytes(a.bytes, flush: true);
      return loc.path;
    }
    // Android / iOS: selector del sistema (Storage Access Framework).
    final uri = await FilePicker.saveFile(
      fileName: a.nombre,
      bytes: a.bytes,
      mimeType: a.mime,
      dialogTitle: 'Guardar ${a.nombre}',
    );
    return uri == null ? null : (uri.scheme == 'file' ? uri.toFilePath() : a.nombre);
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  Widget _filtros() {
    final f = DateFormat('dd/MM/yyyy');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Filtros', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          OutlinedButton.icon(
            onPressed: _elegirRango,
            icon: const Icon(Icons.date_range),
            label: Text(_rango == null
                ? 'Rango de fechas de campaña'
                : '${f.format(_rango!.start)} - ${f.format(_rango!.end)}'),
          ),
          if (_rango != null)
            IconButton(
              tooltip: 'Quitar rango',
              icon: const Icon(Icons.clear),
              onPressed: () {
                setState(() => _rango = null);
                _contar();
              },
            ),
        ]),
        const SizedBox(height: 16),
        Text('Estado reproductivo', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        SegmentedButton<EstadoReproductivo>(
          showSelectedIcon: false,
          segments: [
            for (final e in _estados)
              ButtonSegment(value: e, label: Text(e.etiqueta)),
          ],
          selected: {_estado},
          onSelectionChanged: (s) {
            setState(() => _estado = s.first);
            _contar();
          },
        ),
        const SizedBox(height: 16),
        Text('Municipios (vacío = todos)',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        if (_municipios.isEmpty)
          const Text('Aún no hay municipios registrados.')
        else
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final m in _municipios)
              FilterChip(
                label: Text(m),
                selected: _municipiosSel.contains(m),
                onSelected: (sel) {
                  setState(() => sel
                      ? _municipiosSel.add(m)
                      : _municipiosSel.remove(m));
                  _contar();
                },
              ),
          ]),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const Icon(Icons.fact_check_outlined),
            title: Text(_coinciden == null
                ? 'Calculando…'
                : '$_coinciden nidos coinciden con los filtros'),
          ),
        ),
      ],
    );
  }

  Widget _selectorColumnas() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: Text('Columnas (${_columnas.length}/${nidoColumns.length})',
                style: Theme.of(context).textTheme.titleLarge),
          ),
          TextButton(
            onPressed: () => setState(
                () => _columnas.addAll(nidoColumns.map((c) => c.key))),
            child: const Text('Todas'),
          ),
          TextButton(
            onPressed: () => setState(_columnas.clear),
            child: const Text('Ninguna'),
          ),
        ]),
        for (final fase in NidoFase.values) _grupoFase(fase),
      ],
    );
  }

  Widget _grupoFase(NidoFase fase) {
    final cols = nidoColumnsPorFase[fase]!;
    final marcadas = cols.where((c) => _columnas.contains(c.key)).length;
    final bool? valor =
        marcadas == cols.length ? true : (marcadas == 0 ? false : null);
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: ExpansionTile(
        key: PageStorageKey('fase-${fase.name}'),
        initiallyExpanded: fase == NidoFase.ubicacion,
        leading: Checkbox(
          tristate: true,
          value: valor,
          onChanged: (_) => setState(() {
            if (valor == true) {
              _columnas.removeAll(cols.map((c) => c.key));
            } else {
              _columnas.addAll(cols.map((c) => c.key));
            }
          }),
        ),
        title: Text(fase.titulo),
        subtitle: Text('$marcadas de ${cols.length} columnas'),
        children: [
          for (final c in cols)
            CheckboxListTile(
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(c.label),
              subtitle: Text(c.key, style: const TextStyle(fontSize: 11)),
              value: _columnas.contains(c.key),
              onChanged: (v) => setState(() =>
                  v == true ? _columnas.add(c.key) : _columnas.remove(c.key)),
            ),
        ],
      ),
    );
  }

  Widget _acciones() => Wrap(spacing: 12, runSpacing: 8, children: [
        FilledButton.icon(
          onPressed: _busy ? null : _exportarExcel,
          icon: const Icon(Icons.table_chart),
          label: const Text('Exportar a Excel (.xlsx)'),
        ),
        FilledButton.tonalIcon(
          onPressed: _busy ? null : _exportarPdf,
          icon: const Icon(Icons.picture_as_pdf),
          label: const Text('Generar Informe PDF'),
        ),
        OutlinedButton.icon(
          key: const Key('exportar-ambos'),
          onPressed: _busy ? null : _exportarAmbos,
          icon: const Icon(Icons.library_books_outlined),
          label: const Text('Excel + PDF'),
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    final wide = Breakpoints.isWide(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Exportar datos')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_busy) const LinearProgressIndicator(),
            const SizedBox(height: 8),
            _acciones(),
          ]),
        ),
      ),
      body: wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                  flex: 2,
                  child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16), child: _filtros())),
              const VerticalDivider(width: 1),
              Expanded(
                  flex: 3,
                  child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: _selectorColumnas())),
            ])
          : ListView(padding: const EdgeInsets.all(16), children: [
              _filtros(),
              const SizedBox(height: 16),
              _selectorColumnas(),
            ]),
    );
  }
}
