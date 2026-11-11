// Карта з віссю, рисками й підписами пікетажу, положенням телефона.
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'chainage.dart';
import 'crs.dart';
import 'geometry.dart';
import 'i18n.dart';
import 'lines.dart';
import 'map_layers.dart';

class Tick {
  final List<LatLng> line;
  final LatLng labelAt;
  final String label;
  final bool major;
  const Tick(this.line, this.labelAt, this.label, this.major);
}

/// Вісь, перерахована в WGS84 для карти. Рахується один раз на зміну осі, не на кожен кадр.
class AxisView {
  final List<LatLng> axis;
  final List<Tick> ticks;

  /// Риски кожні 10 м між пікетами («+10», «+20»…) — лише при великому наближенні.
  final List<Tick> minorTicks;

  /// Кромки, бровки, межі відводу — з роллю для кольору.
  final List<(LineRole, List<LatLng>)> lines;
  final LatLngBounds bounds;
  AxisView(this.axis, this.ticks, this.minorTicks, this.lines, this.bounds);

  factory AxisView.of(RoadAxis al, CoordSystem crs, ChainageStyle style, [List<RoadLine> roadLines = const []]) {
    final axis = [for (final p in al.densify(5)) toWgs84(crs, p)];
    final lines = [
      for (final l in roadLines)
        (l.role, [for (final p in RoadAxis(l.segs).densify(5)) toWgs84(crs, p)]),
    ];
    final ticks = <Tick>[];
    final minor = <Tick>[];
    for (var st = (al.startStation / 10).ceil() * 10.0; st <= al.endStation + 1e-6; st += 10) {
      final plus = (st % 100).round();
      if (plus == 0 || plus == 100) continue;
      final p = al.pointAtStation(st);
      final n = al.rightNormalAt(st);
      minor.add(Tick([toWgs84(crs, p - n * 2), toWgs84(crs, p + n * 2)], toWgs84(crs, p + n * 4), '+$plus', false));
    }
    final first = (al.startStation / 100).ceil() * 100;
    for (var st = first.toDouble(); st <= al.endStation + 1e-6; st += 100) {
      final major = (st % 1000).abs() < 1e-6;
      final p = al.pointAtStation(st);
      final n = al.rightNormalAt(st);
      final half = major ? 10.0 : 5.0;
      ticks.add(Tick(
        [toWgs84(crs, p - n * half), toWgs84(crs, p + n * half)],
        toWgs84(crs, p + n * (half + 4)),
        _tickLabel(st, style),
        major,
      ));
    }
    return AxisView(axis, ticks, minor, lines, LatLngBounds.fromPoints(axis));
  }
}

/// Відступи, коли вся вісь вписується в екран: зліва й справа — місце для підписів «Початок» / «Кінець».
const axisFitPadding = EdgeInsets.fromLTRB(90, 40, 90, 40);

String _tickLabel(double st, ChainageStyle style) {
  final m = st.round();
  return style == ChainageStyle.pk
      ? '${t('ПК')} ${m ~/ 100}'
      : '${m ~/ 1000}+${(m % 1000).toString().padLeft(3, '0')}';
}

class AxisMap extends StatefulWidget {
  final AxisView view;
  final MapController controller;
  final bool showOsm;

  /// Власна підкладка (ортофото, MBTiles) — показується замість OSM.
  final Widget? background;
  final LatLng? position;
  final double? accuracyM;

  /// Точки, позначені окремо (початок і кінець осі на екрані імпорту).
  final List<(LatLng, String, Color)> pins;

  /// Позначки на трасі: де, колір за типом, що робити при торканні.
  final List<(LatLng, Color, VoidCallback)> notes;

  /// Позначки-ділянки: лінія вздовж траси, колір.
  final List<(List<LatLng>, Color)> noteLines;

  /// Позначка, до якої ведемо: пунктир від «я» до неї й кільце навколо.
  final LatLng? target;
  final void Function(LatLng)? onTap;
  final VoidCallback? onUserMove;

  /// Плитка підкладки не завантажилась (немає інтернету чи сайт недоступний).
  final VoidCallback? onTilesFailed;

  /// Осі інших об'єктів поруч (примикання, з'їзди) — сірим, з назвою: лінія і де поставити назву.
  final List<(List<LatLng>, LatLng, String)> otherAxes;

  /// Почати з цього місця й наближення (після переходу на іншу вісь), а не з усієї осі.
  final (LatLng, double)? initialCamera;

  const AxisMap({
    super.key,
    required this.view,
    required this.controller,
    this.showOsm = true,
    this.background,
    this.position,
    this.accuracyM,
    this.pins = const [],
    this.notes = const [],
    this.noteLines = const [],
    this.target,
    this.onTap,
    this.onUserMove,
    this.onTilesFailed,
    this.otherAxes = const [],
    this.initialCamera,
  });

  @override
  State<AxisMap> createState() => _AxisMapState();
}

class _AxisMapState extends State<AxisMap> {
  late double _zoom = widget.initialCamera?.$2 ?? 14;

  @override
  Widget build(BuildContext context) {
    final v = widget.view;
    // Підписи: кожні 100 м зблизька, лише кілометри — здалеку, жодних — зовсім здалеку.
    final labelTicks = _zoom >= 16
        ? v.ticks
        : _zoom >= 13
            ? v.ticks.where((t) => t.major).toList()
            : const <Tick>[];
    final tickLines = [
      ...(_zoom >= 15 ? v.ticks : v.ticks.where((t) => t.major)),
      if (_zoom >= 17) ...v.minorTicks,
    ];
    final minorLabels = _zoom >= 18.5 ? v.minorTicks : const <Tick>[];
    // Рамки підписів — під збільшений шрифт телефону (налаштування «розмір шрифту»), інакше текст обрізається.
    final k = MediaQuery.textScalerOf(context).scale(1);
    return FlutterMap(
      mapController: widget.controller,
      options: MapOptions(
        initialCameraFit:
            widget.initialCamera == null ? CameraFit.bounds(bounds: v.bounds, padding: axisFitPadding) : null,
        initialCenter: widget.initialCamera?.$1 ?? const LatLng(50.5, 30.5),
        initialZoom: widget.initialCamera?.$2 ?? 13,
        maxZoom: 22, // ортофото з дрона буває 1–3 см на піксель
        backgroundColor: const Color(0xFFF2F0EB),
        onTap: widget.onTap == null ? null : (_, p) => widget.onTap!(p),
        onPositionChanged: (camera, hasGesture) {
          if (hasGesture) widget.onUserMove?.call();
          if ((camera.zoom - _zoom).abs() > 0.2) setState(() => _zoom = camera.zoom);
        },
      ),
      children: [
        if (widget.background != null)
          widget.background!
        else if (widget.showOsm)
          osmLayer(widget.onTilesFailed),
        PolylineLayer(polylines: [
          for (final (pts, _, _) in widget.otherAxes)
            Polyline(
              points: pts,
              color: const Color(0xFF616161),
              strokeWidth: 3,
              pattern: StrokePattern.dashed(segments: const [12, 6]),
            ),
          for (final (role, pts) in v.lines)
            Polyline(
              points: pts,
              color: role.color,
              strokeWidth: role == LineRole.row ? 2.5 : 2,
              pattern: role.utility
                  ? StrokePattern.dashed(segments: const [3, 5])
                  : role == LineRole.row || role == LineRole.toe || role == LineRole.works
                      ? StrokePattern.dashed(segments: const [10, 6])
                      : const StrokePattern.solid(),
            ),
          for (final (pts, color) in widget.noteLines)
            Polyline(points: pts, color: color.withValues(alpha: 0.55), strokeWidth: 9),
          Polyline(points: v.axis, color: const Color(0xFFD32F2F), strokeWidth: 3),
          if (widget.target != null && widget.position != null)
            Polyline(
              points: [widget.position!, widget.target!],
              color: const Color(0xFF1565C0),
              strokeWidth: 3,
              pattern: StrokePattern.dashed(segments: const [8, 6]),
            ),
          for (final t in tickLines)
            Polyline(
                points: t.line,
                color: const Color(0xFFD32F2F),
                strokeWidth: t.major ? 3 : 1.5),
        ]),
        if (widget.position != null && widget.accuracyM != null)
          CircleLayer(circles: [
            CircleMarker(
              point: widget.position!,
              radius: widget.accuracyM!,
              useRadiusInMeter: true,
              color: const Color(0x331E88E5),
              borderColor: const Color(0x881E88E5),
              borderStrokeWidth: 1,
            ),
          ]),
        MarkerLayer(markers: [
          if (_zoom >= 14)
            for (final (_, at, name) in widget.otherAxes)
              Marker(
                point: at,
                width: 160 * k,
                height: 22 * k,
                child: Center(child: _Label(name, color: const Color(0xFF424242))),
              ),
          for (final t in minorLabels)
            Marker(
              point: t.labelAt,
              width: 40 * k,
              height: 18 * k,
              alignment: Alignment.centerRight,
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(t.label, style: const TextStyle(fontSize: 11, color: Color(0xFFB71C1C)))),
            ),
          for (final t in labelTicks)
            Marker(
              point: t.labelAt,
              width: 90 * k,
              height: 22 * k,
              alignment: Alignment.centerRight,
              child: Align(alignment: Alignment.centerLeft, child: _Label(t.label, bold: t.major)),
            ),
          for (final (p, text, color) in widget.pins)
            Marker(
              point: p,
              width: 170 * k,
              height: 30 * k,
              child: Center(child: _Label(text, bold: true, color: color)),
            ),
          if (widget.target != null)
            Marker(
              point: widget.target!,
              width: 56,
              height: 56,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF1565C0), width: 4),
                  ),
                ),
              ),
            ),
          for (final (p, color, onTap) in widget.notes)
            Marker(
              point: p,
              width: 34,
              height: 34,
              alignment: Alignment.topCenter, // вістря шпильки — у точці
              child: GestureDetector(onTap: onTap, child: Icon(Icons.place, color: color, size: 34)),
            ),
          if (widget.position != null)
            Marker(
              point: widget.position!,
              width: 22,
              height: 22,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E88E5),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black38)],
                ),
              ),
            ),
        ]),
        if (widget.background == null && widget.showOsm)
          const Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: EdgeInsets.all(4),
              child: Text('© OpenStreetMap', style: TextStyle(fontSize: 10, color: Colors.black54)),
            ),
          ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  final bool bold;
  final Color color;
  const _Label(this.text, {this.bold = false, this.color = const Color(0xFFB71C1C)});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(text,
            maxLines: 1,
            style: TextStyle(
                fontSize: 12, color: color, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
      );
}
