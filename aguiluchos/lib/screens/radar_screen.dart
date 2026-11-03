import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../app/app_services.dart';
import '../models/nido_filter.dart';
import '../models/nido_grefa_model.dart';
import '../services/location_service.dart';
import '../utils/radar.dart';
import '../widgets/maps_launcher.dart';
import '../widgets/nido_card.dart' show colorEstado;
import '../widgets/responsive.dart';
import 'nido_detail_screen.dart';

/// Radar de nidos: muestra los nidos cercanos a la posición GPS actual,
/// con radio ampliable/reducible (botones, deslizador o pellizco).
/// Funciona sin cobertura: usa los nidos guardados en el móvil y el GPS.
class RadarScreen extends StatefulWidget {
  const RadarScreen({super.key, this.animar = true});

  /// Barrido animado del radar (se desactiva en los tests).
  final bool animar;

  @override
  State<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _barrido =
      AnimationController(vsync: this, duration: const Duration(seconds: 4));
  StreamSubscription<Position>? _subGps;
  StreamSubscription<void>? _subDb;
  bool _didInit = false;

  List<NidoGrefaModel> _nidos = const [];
  Position? _pos;
  String? _error;
  int _idx = radioRadarInicial;
  double _radioBase = radiosRadarM[radioRadarInicial];
  String? _selId;

  double get _radio => radiosRadarM[_idx];

  @override
  void initState() {
    super.initState();
    if (widget.animar) _barrido.repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInit) return;
    _didInit = true;
    final s = AppServices.of(context);
    _subDb = s.db.changes.listen((_) => _cargar());
    _cargar();
    _iniciarGps(s.location);
  }

  @override
  void dispose() {
    _subGps?.cancel();
    _subDb?.cancel();
    _barrido.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final todos = await AppServices.of(context).db.consultar(const NidoFilter());
    if (mounted) setState(() => _nidos = todos);
  }

  void _iniciarGps(LocationService location) {
    _subGps?.cancel();
    setState(() => _error = null);
    _subGps = location.posiciones().listen(
      (p) {
        if (mounted) setState(() => _pos = p);
      },
      onError: (Object e) {
        if (mounted) {
          setState(() => _error = e is LocationException ? e.message : e.toString());
        }
      },
    );
  }

  void _setIdx(int i) {
    final n = i.clamp(0, radiosRadarM.length - 1);
    if (n != _idx) setState(() => _idx = n);
  }

  Future<void> _abrirNido(NidoGrefaModel n) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => NidoDetailScreen(nido: n)));
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final pos = _pos;
    final items = pos == null ? const <NidoEnRadio>[] : nidosEnRadio(_nidos, pos.latitude, pos.longitude, _radio);
    final sinCoord = _nidos.where((n) => !n.isDeleted && !n.tieneCoordenadas).length;
    NidoEnRadio? sel;
    for (final i in items) {
      if (i.nido.id == _selId) sel = i;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Radar de nidos')),
      body: SafeArea(
        child: _error != null
            ? _Mensaje(
                icono: Icons.location_off,
                texto: _error!,
                accion: FilledButton.icon(
                  key: const Key('radar-reintentar'),
                  onPressed: () => _iniciarGps(AppServices.of(context).location),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'),
                ),
              )
            : pos == null
                ? const _Mensaje(
                    icono: Icons.gps_not_fixed,
                    texto: 'Buscando tu posición GPS…\nSal a un lugar abierto para mejorar la señal.',
                    cargando: true,
                  )
                : LayoutBuilder(builder: (context, c) {
                    final radar = _panelRadar(pos, items, sinCoord, c, sel);
                    final lista = _lista(items, sel);
                    if (Breakpoints.isWide(context)) {
                      return Row(children: [
                        Expanded(child: radar),
                        const VerticalDivider(width: 1),
                        Expanded(child: lista),
                      ]);
                    }
                    return Column(children: [
                      SizedBox(height: math.min(c.maxWidth, c.maxHeight * 0.5) + 140, child: radar),
                      Expanded(child: lista),
                    ]);
                  }),
      ),
    );
  }

  Widget _panelRadar(Position pos, List<NidoEnRadio> items, int sinCoord, BoxConstraints c, NidoEnRadio? sel) {
    final texto = StringBuffer('GPS ±${pos.accuracy.round()} m · ')
      ..write(items.isEmpty
          ? 'ningún nido a menos de ${etiquetaRadio(_radio)}'
          : '${items.length} ${items.length == 1 ? 'nido' : 'nidos'} a menos de ${etiquetaRadio(_radio)}');
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Text(texto.toString(),
            key: const Key('radar-resumen'),
            style: Theme.of(context).textTheme.titleSmall,
            textAlign: TextAlign.center),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Center(
            child: AspectRatio(
              aspectRatio: 1,
              child: _RadarVista(
                key: const Key('radar-vista'),
                items: items,
                radioM: _radio,
                precisionM: pos.accuracy,
                selId: _selId,
                barrido: _barrido,
                onSelect: (id) => setState(() => _selId = id),
                onEscalaInicio: () => _radioBase = _radio,
                onEscala: (e) => _setIdx(indiceRadioCercano(_radioBase / e)),
              ),
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: [
          IconButton.filledTonal(
            key: const Key('radar-reducir'),
            tooltip: 'Reducir radio',
            onPressed: _idx > 0 ? () => _setIdx(_idx - 1) : null,
            icon: const Icon(Icons.remove),
          ),
          Expanded(
            child: Slider(
              key: const Key('radar-radio'),
              value: _idx.toDouble(),
              min: 0,
              max: (radiosRadarM.length - 1).toDouble(),
              divisions: radiosRadarM.length - 1,
              label: etiquetaRadio(_radio),
              onChanged: (v) => _setIdx(v.round()),
            ),
          ),
          IconButton.filledTonal(
            key: const Key('radar-ampliar'),
            tooltip: 'Ampliar radio',
            onPressed: _idx < radiosRadarM.length - 1 ? () => _setIdx(_idx + 1) : null,
            icon: const Icon(Icons.add),
          ),
        ]),
      ),
      Text('Radio: ${etiquetaRadio(_radio)}',
          key: const Key('radar-radio-texto'), style: const TextStyle(fontWeight: FontWeight.w600)),
      if (sinCoord > 0)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
          child: Text('$sinCoord ${sinCoord == 1 ? 'nido sin coordenadas no aparece' : 'nidos sin coordenadas no aparecen'}.',
              style: Theme.of(context).textTheme.bodySmall),
        ),
      const SizedBox(height: 6),
    ]);
  }

  Widget _lista(List<NidoEnRadio> items, NidoEnRadio? sel) {
    if (items.isEmpty) {
      return const _Mensaje(
        icono: Icons.radar,
        texto: 'No hay nidos dentro de este radio.\nAmplía el radio para ver más.',
      );
    }
    return ListView(
      key: const Key('radar-lista'),
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        if (sel != null) _AccionesSeleccion(sel: sel, onFicha: () => _abrirNido(sel.nido)),
        for (final i in items)
          ListTile(
            key: Key('radar-item-${i.nido.id}'),
            selected: i.nido.id == _selId,
            selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
            leading: CircleAvatar(
              backgroundColor: colorEstado(i.nido.estadoReproductivo).withValues(alpha: 0.15),
              child: Icon(Icons.egg_alt, color: colorEstado(i.nido.estadoReproductivo)),
            ),
            title: Text((i.nido.etiqueta ?? '').isEmpty ? '(sin etiqueta)' : i.nido.etiqueta!,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text([
              if ((i.nido.municipio ?? '').isNotEmpty) i.nido.municipio!,
              if ((i.nido.especie ?? '').isNotEmpty) i.nido.especie!,
              i.nido.estadoReproductivo.etiqueta,
            ].join(' · ')),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatoDistancia(i.metros), style: const TextStyle(fontWeight: FontWeight.w700)),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Transform.rotate(angle: i.rumbo * math.pi / 180, child: const Icon(Icons.navigation, size: 14)),
                  const SizedBox(width: 3),
                  Text(puntoCardinal(i.rumbo), style: Theme.of(context).textTheme.bodySmall),
                ]),
              ],
            ),
            onTap: () => setState(() => _selId = i.nido.id),
            onLongPress: () => _abrirNido(i.nido),
          ),
      ],
    );
  }
}

class _AccionesSeleccion extends StatelessWidget {
  const _AccionesSeleccion({required this.sel, required this.onFicha});
  final NidoEnRadio sel;
  final VoidCallback onFicha;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            '${(sel.nido.etiqueta ?? '').isEmpty ? '(sin etiqueta)' : sel.nido.etiqueta!} · '
            '${formatoDistancia(sel.metros)} al ${puntoCardinal(sel.rumbo)} (${sel.rumbo.round()}°)',
            key: const Key('radar-seleccion'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            FilledButton.icon(
              key: const Key('radar-ficha'),
              onPressed: onFicha,
              icon: const Icon(Icons.edit_note),
              label: const Text('Ver ficha'),
            ),
            OutlinedButton.icon(
              onPressed: () => abrirEnGoogleMaps(context, sel.nido),
              icon: const Icon(Icons.map),
              label: const Text('Cómo llegar'),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _Mensaje extends StatelessWidget {
  const _Mensaje({required this.icono, required this.texto, this.accion, this.cargando = false});
  final IconData icono;
  final String texto;
  final Widget? accion;
  final bool cargando;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icono, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(texto, textAlign: TextAlign.center),
            if (cargando) ...[const SizedBox(height: 16), const CircularProgressIndicator()],
            if (accion != null) ...[const SizedBox(height: 16), accion!],
          ]),
        ),
      );
}

/// Lienzo del radar con selección por toque y zoom por pellizco.
class _RadarVista extends StatelessWidget {
  const _RadarVista({
    super.key,
    required this.items,
    required this.radioM,
    required this.precisionM,
    required this.selId,
    required this.barrido,
    required this.onSelect,
    required this.onEscalaInicio,
    required this.onEscala,
  });

  final List<NidoEnRadio> items;
  final double radioM;
  final double precisionM;
  final String? selId;
  final Animation<double> barrido;
  final ValueChanged<String?> onSelect;
  final VoidCallback onEscalaInicio;
  final ValueChanged<double> onEscala;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final lado = math.min(c.maxWidth, c.maxHeight);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: (_) => onEscalaInicio(),
        onScaleUpdate: (d) {
          if (d.pointerCount >= 2) onEscala(d.scale);
        },
        onTapUp: (d) {
          final centro = Offset(lado / 2, lado / 2);
          final r = _PintorRadar.radioPx(lado);
          String? mejor;
          var dist = 26.0; // tolerancia táctil en píxeles
          for (final i in items) {
            final p = posicionEnRadar(i.metros, i.rumbo, radioM);
            final dd = (centro + Offset(p.x * r, p.y * r) - d.localPosition).distance;
            if (dd < dist) {
              dist = dd;
              mejor = i.nido.id;
            }
          }
          onSelect(mejor);
        },
        child: CustomPaint(
          size: Size.square(lado),
          painter: _PintorRadar(
              items: items, radioM: radioM, precisionM: precisionM, selId: selId, barrido: barrido),
        ),
      );
    });
  }
}

class _PintorRadar extends CustomPainter {
  _PintorRadar({
    required this.items,
    required this.radioM,
    required this.precisionM,
    required this.selId,
    required this.barrido,
  }) : super(repaint: barrido);

  final List<NidoEnRadio> items;
  final double radioM;
  final double precisionM;
  final String? selId;
  final Animation<double> barrido;

  static double radioPx(double lado) => lado / 2 - 18;

  @override
  void paint(Canvas canvas, Size size) {
    final centro = size.center(Offset.zero);
    final r = radioPx(size.shortestSide);
    const verde = Color(0xFF39FF6E);

    // Fondo y anillos.
    canvas.drawCircle(centro, r, Paint()..color = const Color(0xFF0B2A14));
    final linea = Paint()
      ..color = verde.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final f in [1 / 3, 2 / 3, 1.0]) {
      canvas.drawCircle(centro, r * f, linea);
    }
    canvas.drawLine(centro - Offset(r, 0), centro + Offset(r, 0), linea);
    canvas.drawLine(centro - Offset(0, r), centro + Offset(0, r), linea);

    // Barrido.
    final ang = barrido.value * 2 * math.pi;
    final rect = Rect.fromCircle(center: centro, radius: r);
    canvas.drawCircle(
      centro,
      r,
      Paint()
        ..shader = SweepGradient(
          colors: [Colors.transparent, verde.withValues(alpha: 0.30)],
          stops: const [0.75, 1.0],
          transform: GradientRotation(ang),
        ).createShader(rect),
    );
    canvas.drawLine(centro, centro + Offset(math.cos(ang), math.sin(ang)) * r,
        Paint()..color = verde.withValues(alpha: 0.7)..strokeWidth = 1.5);

    // Marcas de distancia y puntos cardinales.
    _texto(canvas, etiquetaRadio(radioM), centro + Offset(4, -r + 2), 10, verde.withValues(alpha: 0.9));
    _texto(canvas, etiquetaRadio(radioM * 2 / 3), centro + Offset(4, -r * 2 / 3 + 2), 10, verde.withValues(alpha: 0.7));
    _texto(canvas, etiquetaRadio(radioM / 3), centro + Offset(4, -r / 3 + 2), 10, verde.withValues(alpha: 0.7));
    const cardinales = {'N': Offset(0, -1), 'E': Offset(1, 0), 'S': Offset(0, 1), 'O': Offset(-1, 0)};
    cardinales.forEach((t, v) {
      _texto(canvas, t, centro + v * (r + 10), 13, const Color(0xFF455A4B), centrado: true, negrita: true);
    });

    // Precisión del GPS.
    final pp = precisionM / radioM * r;
    if (pp > 6) {
      canvas.drawCircle(centro, math.min(pp, r), Paint()..color = const Color(0xFF42A5F5).withValues(alpha: 0.18));
    }

    // Nidos.
    for (final i in items) {
      final p = posicionEnRadar(i.metros, i.rumbo, radioM);
      final o = centro + Offset(p.x * r, p.y * r);
      final color = colorEstado(i.nido.estadoReproductivo);
      final sel = i.nido.id == selId;
      if (sel) {
        canvas.drawCircle(o, 13, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2);
      }
      canvas.drawCircle(o, sel ? 9 : 7.5, Paint()..color = Colors.white);
      canvas.drawCircle(o, sel ? 7.5 : 6, Paint()..color = color);
      if (sel) {
        final et = (i.nido.etiqueta ?? '').isEmpty ? '(sin etiqueta)' : i.nido.etiqueta!;
        _texto(canvas, et, o + const Offset(0, -26), 12, Colors.white, centrado: true, negrita: true);
      }
    }

    // Tú.
    canvas.drawCircle(centro, 8, Paint()..color = Colors.white);
    canvas.drawCircle(centro, 6, Paint()..color = const Color(0xFF1E88E5));
  }

  void _texto(Canvas canvas, String t, Offset pos, double tam, Color color,
      {bool centrado = false, bool negrita = false}) {
    final tp = TextPainter(
      text: TextSpan(
          text: t,
          style: TextStyle(color: color, fontSize: tam, fontWeight: negrita ? FontWeight.w700 : FontWeight.w400)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, centrado ? pos - Offset(tp.width / 2, tp.height / 2) : pos);
  }

  @override
  bool shouldRepaint(_PintorRadar old) =>
      old.items != items || old.radioM != radioM || old.selId != selId || old.precisionM != precisionM;
}
