// Головний екран на трасі: де я — ПК+плюс і зміщення від осі, на карті.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'axis_map.dart';
import 'chainage.dart';
import 'crs.dart';
import 'cross_strip.dart';
import 'geometry.dart';
import 'basemaps.dart';
import 'i18n.dart';
import 'lines.dart';
import 'map_layers.dart';
import 'nearest_axis.dart';
import 'notes.dart';
import 'notes_screens.dart';
import 'object_data_screen.dart';
import 'pdf_section_screen.dart';
import 'problem_card.dart';
import 'problems.dart';
import 'profile.dart';
import 'road_object.dart';
import 'settings.dart';
import 'surface.dart';
import 'vibrate.dart';

enum _Source { gps, tap }

/// Прочитати ЦММ і одразу побудувати сітку пошуку — усе в окремому потоці.
Surface _readySurface(Uint8List b) {
  final s = Surface.decode(b);
  s.bounds;
  return s;
}

/// З чим відкрити екран після переходу на іншу вісь: де людина, як дивилась на карту.
class RoadStart {
  final bool tap;
  final LatLng? gps, tapPoint;
  final double? accuracy;
  final bool follow;
  final (LatLng, double)? camera;
  const RoadStart({this.tap = false, this.gps, this.tapPoint, this.accuracy, this.follow = true, this.camera});
}

/// Екран траси з переходом між осями: кілька об'єктів поруч (основна дорога, примикання, з'їзди) —
/// показуємо ПК по тій осі, до якої людина ближча.
class RoadHost extends StatefulWidget {
  final List<RoadObject> objects;
  final RoadObject start;
  const RoadHost({super.key, required this.objects, required this.start});

  @override
  State<RoadHost> createState() => _RoadHostState();
}

class _RoadHostState extends State<RoadHost> {
  late RoadObject _cur = widget.start;
  RoadStart? _carry;

  void _switch(RoadObject to, RoadStart carry, {required bool auto}) {
    final from = _cur;
    setState(() {
      _cur = to;
      _carry = carry;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(auto
            ? t('Ближча вісь — «{name}»: ПК тепер по ній', {'name': to.name})
            : t('Вісь «{name}»', {'name': to.name})),
        action: auto
            ? SnackBarAction(
                label: t('Не перемикати'),
                onPressed: () {
                  settings.autoAxis = false;
                  saveSettings();
                  if (mounted) setState(() => _cur = from);
                },
              )
            : null,
      ));
  }

  @override
  Widget build(BuildContext context) => RoadScreen(
        key: ValueKey(_cur.id),
        object: _cur,
        others: [for (final o in widget.objects) if (o.id != _cur.id) o],
        start: _carry,
        onSwitch: _switch,
      );
}

class RoadScreen extends StatefulWidget {
  final RoadObject object;

  /// Інші об'єкти на пристрої — їхні осі поруч видно на карті, і на них можна перейти.
  final List<RoadObject> others;
  final RoadStart? start;
  final void Function(RoadObject to, RoadStart carry, {required bool auto})? onSwitch;
  const RoadScreen({super.key, required this.object, this.others = const [], this.start, this.onSwitch});

  @override
  State<RoadScreen> createState() => _RoadScreenState();
}

/// Інша вісь, до якої зараз недалеко.
typedef _NearAxis = (RoadObject object, StationResult r, double dist);

/// Показувати іншу вісь у панелі, коли до неї ближче за стільки метрів.
const _showOtherAxis = 30.0;

class _RoadScreenState extends State<RoadScreen> {
  late final RoadAxis _axis = widget.object.roadAxis;
  late final AxisView _view =
      AxisView.of(_axis, widget.object.crs, widget.object.style, widget.object.lines);
  final _map = MapController();

  /// Осі інших об'єктів (з переходом лише між об'єктами того самого виду робіт — сама).
  late final List<(RoadObject, RoadAxis)> _others = [for (final o in widget.others) (o, o.roadAxis)];
  late final List<(List<LatLng>, LatLng, String)> _otherLines = _otherAxesOnMap();
  final _switcher = AxisSwitcher();

  _Source _source = _Source.gps;
  /// Відкрита власна підкладка (MBTiles чи знімок) і перелік усіх.
  BasemapLayer? _bg;
  List<Basemap> _maps = [];
  List<Note> _notes = [];
  bool _follow = true;

  /// Позначка, до якої ведемо (null — не ведемо).
  Note? _target;

  /// ЦММ проєкту об'єкта (null — немає чи ще читається).
  Surface? _surface;

  /// Позначки, біля яких уже провібрували; знову — коли людина відійде вдвічі далі.
  final _buzzed = <String>{};

  StreamSubscription<Position>? _sub;
  Timer? _waitTimer;

  /// Чому GPS не дає місця (null — усе гаразд або ще шукаємо).
  Problem? _gpsProblem;
  bool _tilesFailed = false;
  LatLng? _gpsPoint;
  double? _gpsAccuracy;
  LatLng? _tapPoint;

  @override
  void initState() {
    super.initState();
    final s = widget.start;
    if (s != null) {
      _source = s.tap ? _Source.tap : _Source.gps;
      _gpsPoint = s.gps;
      _gpsAccuracy = s.accuracy;
      _tapPoint = s.tapPoint;
      _follow = s.follow;
    }
    _loadBasemap();
    _loadNotes();
    _loadSurface();
    _startGps();
  }

  @override
  void dispose() {
    _bg?.dispose();
    _sub?.cancel();
    _waitTimer?.cancel();
    super.dispose();
  }

  Future<void> _startGps() async {
    await _sub?.cancel();
    _waitTimer?.cancel();
    setState(() => _gpsProblem = null);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() => _gpsProblem = gpsOff);
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        setState(() => _gpsProblem = gpsDenied);
        return;
      }
      _waitTimer = Timer(const Duration(seconds: 30), () {
        if (mounted && _gpsPoint == null && _gpsProblem == null) setState(() => _gpsProblem = gpsWaiting);
      });
      _sub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 0),
      ).listen((p) {
        setState(() {
          _gpsPoint = LatLng(p.latitude, p.longitude);
          _gpsAccuracy = p.accuracy;
          _gpsProblem = null;
        });
        _checkNear();
        _checkLines();
        if (_checkAxes()) return;
        if (_source == _Source.gps && _follow) {
          try {
            _map.move(_gpsPoint!, _map.camera.zoom);
          } catch (_) {
            // Карта ще не намальована — перший кадр прийде з наступним визначенням.
          }
        }
      }, onError: (e) => setState(() => _gpsProblem = _gpsFailed(e)));
    } catch (e) {
      setState(() => _gpsProblem = _gpsFailed(e));
    }
  }

  LatLng? get _point => _source == _Source.gps ? _gpsPoint : _tapPoint;

  /// Інші осі не далі [_showOtherAxis] м від точки — найближча перша.
  List<_NearAxis> _nearAxes(LatLng p) {
    final out = <_NearAxis>[
      for (final (o, ax) in _others)
        if (ax.locate(fromWgs84(o.crs, p)) case final r)
          if (distanceToAxis(ax, r) case final d when d <= _showOtherAxis) (o, r, d)
    ]..sort((a, b) => a.$3.compareTo(b.$3));
    return out;
  }

  /// За GPS інша вісь того самого виду робіт помітно ближча кілька разів поспіль — переходимо на неї.
  /// true — перейшли (цей екран зараз зміниться іншим).
  bool _checkAxes() {
    final p = _gpsPoint, go = widget.onSwitch;
    // Ведемо до позначки цього об'єкта — не перемикаємо, щоб не загубити її.
    if (p == null || go == null || !settings.autoAxis || _source != _Source.gps || _target != null) return false;
    final mine = distanceToAxis(_axis, _axis.locate(fromWgs84(widget.object.crs, p)));
    final id = _switcher.update(mine, [
      for (final (o, ax) in _others)
        if (o.work == widget.object.work) (o.id, distanceToAxis(ax, ax.locate(fromWgs84(o.crs, p))))
    ], accuracy: _gpsAccuracy);
    if (id == null) return false;
    go(_others.firstWhere((x) => x.$1.id == id).$1, _carry(), auto: true);
    return true;
  }

  RoadStart _carry() {
    (LatLng, double)? camera;
    try {
      camera = (_follow && _point != null ? _point! : _map.camera.center, _map.camera.zoom);
    } catch (_) {
      // Карта ще не намальована.
    }
    return RoadStart(
        tap: _source == _Source.tap,
        gps: _gpsPoint,
        tapPoint: _tapPoint,
        accuracy: _gpsAccuracy,
        follow: _follow,
        camera: camera);
  }

  /// Осі інших об'єктів, що лежать біля цього (рамка осі + 1 км), — для карти; назва — посередині.
  List<(List<LatLng>, LatLng, String)> _otherAxesOnMap() {
    final b = _view.bounds;
    const pad = 0.01; // ≈ 1 км
    final out = <(List<LatLng>, LatLng, String)>[];
    for (final (o, ax) in _others) {
      final pts = [for (final v in ax.densify(10)) toWgs84(o.crs, v)];
      if (!pts.any((q) =>
          q.latitude > b.south - pad &&
          q.latitude < b.north + pad &&
          q.longitude > b.west - pad &&
          q.longitude < b.east + pad)) {
        continue;
      }
      out.add((pts, toWgs84(o.crs, ax.pointAtStation(ax.startStation + ax.length / 2)), o.name));
    }
    return out;
  }

  /// Рядки «поруч інша вісь» у панелі: ПК і зміщення по ній, торкання — перейти на неї.
  List<Widget> _otherAxesInfo() {
    final p = _point, go = widget.onSwitch;
    if (p == null || go == null || _others.isEmpty) return const [];
    final near = _nearAxes(p);
    if (near.isEmpty) return const [];
    return [
      const SizedBox(height: 6),
      for (final (o, r, _) in near.take(3))
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
            icon: const Icon(Icons.alt_route),
            label: Text(
              [
                t('Поруч вісь «{name}»', {'name': o.name}),
                '${formatStation(r.station, o.style)}, ${_offsetText(r.offset)}',
                if (o.work != widget.object.work) t(o.work.label),
              ].join(' · '),
            ),
            onPressed: () => go(o, _carry(), auto: false),
          ),
        ),
      Row(children: [
        Switch(
          value: settings.autoAxis,
          onChanged: (v) {
            setState(() => settings.autoAxis = v);
            _switcher.reset();
            saveSettings();
          },
        ),
        const SizedBox(width: 6),
        const Expanded(child: T('Сама переходити на ближчу вісь (за GPS)')),
      ]),
    ];
  }

  /// Біля неусуненої позначки (за GPS, не за точкою на карті) — вібрація й напис, один раз на підхід.
  void _checkNear() {
    final p = _gpsPoint, r = settings.nearNote;
    if (p == null || r <= 0) return;
    const d = Distance();
    for (final n in _notes) {
      if (n.status == NoteStatus.fixed) continue;
      final m = d.as(LengthUnit.Meter, p, LatLng(n.lat, n.lon));
      if (m > r * 2) {
        _buzzed.remove(n.id);
      } else if (m <= r && _buzzed.add(n.id)) {
        vibrate();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('Позначка за {m} м: {what}', {'m': m.toStringAsFixed(0), 'what': n.text.trim().isNotEmpty ? n.text.trim() : t(n.kind.label)})),
          action: SnackBarAction(label: t('Відкрити'), onPressed: () => _openNote(n)),
        ));
      }
    }
  }

  final _lineBuzzed = <RoadLine>{};

  /// Біля лінії з попередженням (мережа, межа робіт…) — вібрація й напис, один раз на підхід (за GPS, як
  /// позначки). Відходите далі ніж у півтора раза — наступний підхід знову попередить.
  void _checkLines() {
    final p = _gpsPoint;
    if (p == null) return;
    final g = fromWgs84(widget.object.crs, p);
    for (final l in widget.object.lines) {
      final a = l.alert;
      if (a == null) continue;
      final d = l.box.near(g, a * 1.5 + 1) ? l.distanceTo(g) : double.infinity;
      if (d > a * 1.5 + 1) {
        _lineBuzzed.remove(l);
      } else if (d <= a && _lineBuzzed.add(l)) {
        vibrate();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(t('{role} «{layer}» — за {m} м', {'role': t(l.role.label), 'layer': l.layer, 'm': d.toStringAsFixed(1)}))));
      }
    }
  }

  /// Лінії з попередженням, ближчі за задану відстань: «⚠ Газопровід «…» — 1.4 м».
  List<Widget> _alertsInfo() {
    final p = _point;
    if (p == null) return const [];
    final g = fromWgs84(widget.object.crs, p);
    final near = <(RoadLine, double)>[
      for (final l in widget.object.lines)
        if (l.alert != null && l.box.near(g, l.alert!))
          if (l.distanceTo(g) case final d when d <= l.alert!) (l, d)
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    return [
      for (final (l, d) in near)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(t('⚠ {role} «{layer}» — {m} м', {'role': t(l.role.label), 'layer': l.layer, 'm': d.toStringAsFixed(1)}),
              style: TextStyle(color: Colors.red.shade800, fontWeight: FontWeight.bold, fontSize: 18)),
        ),
    ];
  }

  StationResult? get _result {
    final p = _point;
    return p == null ? null : _axis.locate(fromWgs84(widget.object.crs, p));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.object.name),
        actions: [
          IconButton(
            tooltip: t('Дані об’єкта: профіль, поперечники, ЦММ, PDF'),
            icon: const Icon(Icons.tune),
            onPressed: () async {
              await Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => ObjectDataScreen(object: widget.object)));
              // Там могли додати чи змінити підкладку.
              await _loadBasemap();
              await _loadSurface();
            },
          ),
          IconButton(
            tooltip: t('Позначки: список і експорт в Excel'),
            icon: Badge(
              isLabelVisible: _notes.isNotEmpty,
              label: Text('${_notes.length}'),
              child: const Icon(Icons.list_alt),
            ),
            onPressed: () async {
              await Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => NotesListScreen(
                      object: widget.object, hereStation: () => _result?.station, onGuide: _guideTo)));
              await _loadNotes();
            },
          ),
          IconButton(
            tooltip: t('Підкладка: OSM, ортофото, без підкладки'),
            icon: Icon(widget.object.basemap == bgNone ? Icons.layers_clear : Icons.layers),
            onPressed: _chooseBackground,
          ),
          IconButton(
            tooltip: t('Уся вісь'),
            icon: const Icon(Icons.zoom_out_map),
            onPressed: () {
              setState(() => _follow = false);
              _map.fitCamera(CameraFit.bounds(bounds: _view.bounds, padding: axisFitPadding));
            },
          ),
        ],
      ),
      body: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth > c.maxHeight && c.maxWidth > 600;
        final panel = _panel(context, wide);
        final map = Stack(children: [
          AxisMap(
            view: _view,
            controller: _map,
            otherAxes: _otherLines,
            initialCamera: widget.start?.camera,
            showOsm: widget.object.basemap == bgOsm,
            background: _bg?.build(),
            notes: [for (final n in _notes) (LatLng(n.lat, n.lon), noteColor(n), () => _openNote(n))],
            noteLines: [
              for (final n in _notes)
                if (n.toStation != null) (_alongAxis(n.station, n.toStation!, n.offset), noteColor(n)),
            ],
            target: _target == null ? null : LatLng(_target!.lat, _target!.lon),
            position: _point,
            accuracyM: _source == _Source.gps ? _gpsAccuracy : null,
            onTap: _source == _Source.tap ? (p) => setState(() => _tapPoint = p) : null,
            onUserMove: () {
              if (_follow) setState(() => _follow = false);
            },
            onTilesFailed: () {
              if (!_tilesFailed) setState(() => _tilesFailed = true);
            },
          ),
          if (_source == _Source.gps)
            Positioned(
              right: 12,
              bottom: 24,
              child: FloatingActionButton(
                tooltip: t('Слідувати за мною'),
                backgroundColor: _follow ? Theme.of(context).colorScheme.primary : null,
                onPressed: () {
                  setState(() => _follow = true);
                  if (_gpsPoint != null) _map.move(_gpsPoint!, _map.camera.zoom < 16 ? 17 : _map.camera.zoom);
                },
                child: Icon(Icons.my_location, color: _follow ? Colors.white : null),
              ),
            ),
        ]);
        return wide
            ? Row(children: [SizedBox(width: 340, child: panel), Expanded(child: map)])
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [panel, Expanded(child: map)]);
      }),
    );
  }

  Widget _panel(BuildContext context, bool wide) {
    final o = widget.object;
    final r = _result;
    final theme = Theme.of(context);
    final big = TextStyle(fontSize: wide ? 40 : 34, fontWeight: FontWeight.bold, height: 1.1);
    final mid = TextStyle(fontSize: wide ? 26 : 22, fontWeight: FontWeight.w600);

    final lines = <Widget>[];
    if (_target != null) lines.add(_guideCard(r));
    if (r == null) {
      if (_source == _Source.gps && _gpsProblem != null) {
        lines.add(ProblemCard(_gpsProblem!, actions: [
          if (_gpsProblem == gpsOff) (t('Налаштування геолокації'), () => Geolocator.openLocationSettings()),
          if (_gpsProblem == gpsDenied) (t('Налаштування програми'), () => Geolocator.openAppSettings()),
          (t('Спробувати ще раз'), _startGps),
        ]));
      } else {
        lines.add(Text(
          _source == _Source.gps ? t('Шукаю GPS…') : t('Торкніться карти, щоб побачити ПК точки.'),
          style: theme.textTheme.titleMedium,
        ));
      }
    } else {
      lines.add(FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
          child: Text(formatStation(r.station, o.style), style: big)));
      lines.add(const SizedBox(height: 4));
      lines.add(Text(_offsetText(r.offset), style: mid.copyWith(color: _offsetColor(r.offset))));
      if (r.beyond) {
        final toStart = r.station < _axis.startStation;
        final d = toStart ? _axis.startStation - r.station : r.station - _axis.endStation;
        lines.add(_warn(toStart
            ? t('Перед початком осі: ще {n} м до {pk}',
                {'n': d.toStringAsFixed(0), 'pk': formatStation(_axis.startStation, o.style)})
            : t('За кінцем осі: {n} м після {pk}',
                {'n': d.toStringAsFixed(0), 'pk': formatStation(_axis.endStation, o.style)})));
      } else if (r.offset.abs() > 300) {
        lines.add(_warn(t('Далеко від осі — {n} км.', {'n': (r.offset.abs() / 1000).toStringAsFixed(1)})));
      }
      lines.addAll(_otherAxesInfo());
      lines.addAll(_alertsInfo());
      if (!r.beyond) {
        final hits = _hitsAt(r);
        lines.addAll(_elevationInfo(r, mid));
        if (hits.isNotEmpty) lines.addAll(_linesInfo(r, hits));
      }
      lines.addAll(_pdfButton(r));
      lines.add(Padding(
        padding: const EdgeInsets.only(top: 6),
        child: FilledButton.tonalIcon(
          onPressed: () => _addNote(r),
          icon: const Icon(Icons.add_location_alt),
          label: const T('Позначка тут'),
        ),
      ));
    }
    lines.add(const SizedBox(height: 8));
    lines.add(Text(
      _source == _Source.gps
          ? (_gpsAccuracy == null
              ? t('GPS: чекаю першого визначення')
              : t('GPS: точність ±{n} м', {'n': _gpsAccuracy!.toStringAsFixed(0)}))
          : t('Точка, якої торкнулися на карті'),
      style: theme.textTheme.bodyMedium,
    ));
    if (_source == _Source.gps && (_gpsAccuracy ?? 0) > 10) lines.add(_problemLink(gpsPoor(_gpsAccuracy!)));
    if (widget.object.basemap == bgOsm && _tilesFailed) lines.add(_problemLink(tilesFailed));
    lines.add(Text(
        t('{crs}: перерахунок ±{n} м', {'crs': crsName(o.crs), 'n': o.crs.accuracyM.toStringAsFixed(0)}),
        style: theme.textTheme.bodySmall));
    lines.add(const SizedBox(height: 8));
    lines.add(SegmentedButton<_Source>(
      segments: const [
        ButtonSegment(value: _Source.gps, label: Text('GPS'), icon: Icon(Icons.gps_fixed)),
        ButtonSegment(value: _Source.tap, label: T('Точка на карті'), icon: Icon(Icons.touch_app)),
      ],
      selected: {_source},
      onSelectionChanged: (s) => setState(() => _source = s.first),
    ));

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: SafeArea(
        bottom: false,
        child: wide
            ? ListView(padding: const EdgeInsets.all(16), children: lines)
            : ConstrainedBox(
                // Вертикально панель не забирає більше половини екрана — решта для карти.
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: lines),
                ),
              ),
      ),
    );
  }

  /// Лінії плану, які перетинає поперечник через людину, — на будь-якій відстані від осі: пошук сягає
  /// щонайменше на 100 м далі за місце, де людина стоїть. Це лише лінії для огляду, прив'язка — тільки до осі.
  List<CrossHit> _hitsAt(StationResult r) =>
      crossSection(_axis, widget.object.lines, r.station, reach: math.max(150, r.offset.abs() + 100));

  /// Лінія проєкту поперек дороги на ПК людини, відмітка там, де людина, і звідки: з ЦММ, якщо людина на ній
  /// (лінія — зрізом ЦММ через кожні 0.5 м); інакше з поперечника ([CrossSections.lineAt]); null — ні того, ні того.
  (List<(double, double)>, double?, String)? _designLine(StationResult r) {
    final o = widget.object;
    // ЦММ землі проєктної відмітки не дає — вона окремим рядком у [_elevationInfo].
    final tin = o.surfaceGround ? null : _surface;
    if (tin != null) {
      final c = _axis.pointAtStation(r.station), n = _axis.rightNormalAt(r.station);
      final here = tin.elevationAt(c + n * r.offset);
      if (here != null) {
        final lo = math.min(-10.0, r.offset - 5), hi = math.max(10.0, r.offset + 5);
        final step = math.max(0.5, (hi - lo) / 200);
        final line = <(double, double)>[
          for (var off = lo; off <= hi + 1e-9; off += step)
            if (tin.elevationAt(c + n * off) case final z?) (off, z)
        ];
        return (line, here, t('з ЦММ'));
      }
    }
    final cs = o.crossSections?.lineAt(r.station);
    if (cs == null) return null;
    return (
      cs.$1,
      zOnLine(cs.$1, r.offset),
      cs.$2 == cs.$3
          ? t('за поперечником {pk}', {'pk': formatStation(cs.$2, o.style)})
          : t('між поперечниками {a} і {b}', {'a': formatStation(cs.$2, o.style), 'b': formatStation(cs.$3, o.style)})
    );
  }

  /// Яку відмітку показувати, коли є і проєктна, і земля (кнопка вибору).
  bool _showGround = false;

  /// Відмітка там, де людина: проєктна (ЦММ проєкту чи поперечник, [_designLine]) або земля (ЦММ зйомки). Є обидві —
  /// кнопка вибору; немає жодної (лише вісь — з профілем чи без) — нічого.
  List<Widget> _elevationInfo(StationResult r, TextStyle mid) {
    final d = _designLine(r);
    final zp = d?.$2;
    final g = widget.object.surfaceGround ? _surface : null;
    final zg = g?.elevationAt(_axis.pointAtStation(r.station) + _axis.rightNormalAt(r.station) * r.offset);
    if (zp == null && zg == null) return const [];
    final ground = zp == null || (zg != null && _showGround);
    return [
      const SizedBox(height: 4),
      if (zp != null && zg != null)
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: false, label: Text(t('Проєкт'))),
            ButtonSegment(value: true, label: Text(t('Земля'))),
          ],
          selected: {_showGround},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _showGround = s.first),
        ),
      Text(
          ground
              ? t('Відмітка землі {z} м', {'z': zg!.toStringAsFixed(2)})
              : t('Проєктна відмітка {z} м', {'z': zp.toStringAsFixed(2)}),
          style: mid.copyWith(fontSize: (mid.fontSize ?? 22) - 2, color: ground ? Colors.brown : null)),
      Text(ground ? t('ЦММ зйомки') : d!.$3, style: const TextStyle(color: Colors.black54)),
    ];
  }

  /// Кнопка «поперечник з PDF» для найближчого підписаного ПК.
  List<Widget> _pdfButton(StationResult r) {
    final o = widget.object;
    final s = o.sections;
    if (s == null) return const [];
    // Найближчий — завжди, хоч би й далеко; відстань видно на кнопці.
    final l = s.nearest(r.station, maxGap: double.infinity);
    if (l == null) return const [];
    final gap = (l.station - r.station).abs();
    return [
      const SizedBox(height: 6),
      OutlinedButton.icon(
        icon: const Icon(Icons.picture_as_pdf),
        label: Text(gap < 1
            ? t('Поперечник {pk} (PDF)', {'pk': formatStation(l.station, o.style)})
            : t('Найближчий поперечник — {pk}, за {m} м (PDF)',
                {'pk': formatStation(l.station, o.style), 'm': gap.toStringAsFixed(0)})),
        onPressed: () async {
          final bytes = await objectStore.loadPdf(o.id);
          if (!mounted) return;
          if (bytes == null) {
            await showProblemDialog(context, const Problem(Severity.error, 'PDF поперечників не знайдено в пам’яті',
                fixes: ['Додайте його ще раз: «Дані об’єкта» → «Додати PDF».']));
            return;
          }
          await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => PdfSectionScreen(bytes: bytes, sections: s, start: l, style: o.style)));
        },
      ),
    ];
  }

  /// Схема поперечника, найближчі лінії з обох боків і вихід за межу відводу.
  List<Widget> _linesInfo(StationResult r, List<CrossHit> hits) {
    final w =whereabouts(hits, r.offset);
    final d = _designLine(r);
    final section = d?.$1;
    final myZ = d?.$2;
    String side((CrossHit, double)? x) =>
        x == null ? '—' : t('{role} {n} м', {'role': t(x.$1.role.label).toLowerCase(), 'n': x.$2.toStringAsFixed(1)});
    return [
      if (w.outsideRow != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(t('За межею відводу на {n} м', {'n': w.outsideRow!.toStringAsFixed(1)}),
              style: TextStyle(color: Colors.red.shade800, fontWeight: FontWeight.bold, fontSize: 18)),
        ),
      const SizedBox(height: 6),
      CrossStrip(hits: hits, offset: r.offset, section: section, myZ: myZ),
      Row(children: [
        Expanded(child: Text('← ${side(w.left)}')),
        Expanded(child: Text('${side(w.right)} →', textAlign: TextAlign.right)),
      ]),
    ];
  }

  Future<void> _loadNotes() async {
    final l = await noteStore.load(widget.object.id);
    if (mounted) setState(() => _notes = l);
  }

  /// Нова позначка там, де зараз точка (GPS чи вибрана на карті).
  Future<void> _addNote(StationResult r) async {
    final p = _point;
    if (p == null) return;
    final g = fromWgs84(widget.object.crs, p);
    final n = Note(
      id: 'n${DateTime.now().microsecondsSinceEpoch}',
      created: DateTime.now(),
      kind: widget.object.work.kinds.first,
      status: widget.object.work.kinds.first == NoteKind.defect ? NoteStatus.open : null,
      text: '',
      station: r.station,
      offset: r.offset,
      lat: p.latitude,
      lon: p.longitude,
      east: g.x,
      north: g.y,
      accuracy: _source == _Source.gps ? _gpsAccuracy : null,
      // Лабораторія — одразу наступний номер проби (у позначці можна свій чи без номера).
      sampleNo: widget.object.work == WorkType.lab ? nextSampleNo(_notes) : null,
    );
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => NoteEditScreen(
            object: widget.object, note: n, isNew: true, hereStation: () => _result?.station)));
    await _loadNotes();
  }

  Future<void> _openNote(Note n) async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => NoteEditScreen(
            object: widget.object, note: n, hereStation: () => _result?.station, onGuide: _guideTo)));
    await _loadNotes();
  }

  /// Повернутися на цей екран і вести до позначки.
  void _guideTo(Note n) {
    final me = ModalRoute.of(context);
    Navigator.of(context).popUntil((r) => r == me);
    setState(() => _target = n);
    _loadNotes();
    final p = _point;
    try {
      _map.fitCamera(CameraFit.coordinates(
          coordinates: [LatLng(n.lat, n.lon), ?p], padding: const EdgeInsets.all(60), maxZoom: 18));
      _follow = false;
    } catch (_) {
      // Карта ще не намальована.
    }
  }

  /// Лінія ділянки вздовж осі на тому ж зміщенні, що й позначка.
  List<LatLng> _alongAxis(double from, double to, double offset) {
    final a = math.max(math.min(from, to), _axis.startStation), b = math.min(math.max(from, to), _axis.endStation);
    if (b <= a) return const [];
    final n = math.max(2, ((b - a) / 5).ceil() + 1);
    return [
      for (var i = 0; i < n; i++)
        toWgs84(widget.object.crs,
            _axis.pointAtStation(a + (b - a) * i / (n - 1)) + _axis.rightNormalAt(a + (b - a) * i / (n - 1)) * offset),
    ];
  }

  /// Як дійти до позначки: напрям і відстань, і те саме «мовою траси» — вперед / назад по ПК і вбік.
  Widget _guideCard(StationResult? r) {
    final tg = _target!;
    final o = widget.object;
    final p = _point;
    final out = <Widget>[
      Row(children: [
        Icon(Icons.navigation, color: noteColor(tg)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(t('До позначки: {what}', {'what': '${noteKindText(tg)}${tg.text.isEmpty ? '' : ' — ${tg.text}'}'}),
              maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        IconButton(
          tooltip: t('Більше не вести'),
          icon: const Icon(Icons.close),
          onPressed: () => setState(() => _target = null),
        ),
      ]),
      Text(noteWhere(tg, o.style)),
    ];
    if (p == null || r == null) {
      out.add(const T('Чекаю, де ви: GPS чи точка на карті.', style: TextStyle(color: Colors.black54)));
    } else {
      final d = const Distance().as(LengthUnit.Meter, p, LatLng(tg.lat, tg.lon));
      final reach = math.max(5.0, (_source == _Source.gps ? _gpsAccuracy : null) ?? 0);
      if (d <= reach) {
        out.add(Text(t('Ви на місці (до позначки {n} м)', {'n': d.toStringAsFixed(0)}),
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green.shade800)));
      } else {
        final az = (const Distance().bearing(p, LatLng(tg.lat, tg.lon)) + 360) % 360;
        out.add(Text('${_distText(d)} · ${_compass(az)} (${az.toStringAsFixed(0)}°)',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)));
        final ds = tg.station - r.station;
        final side = tg.offset - r.offset;
        final n = side.abs().toStringAsFixed(0);
        out.add(Text([
          ds.abs() < 3
              ? t('Ви навпроти позначки')
              : ds > 0
                  ? t('По трасі вперед (ПК зростає) {d}', {'d': _distText(ds.abs())})
                  : t('По трасі назад (ПК меншає) {d}', {'d': _distText(ds.abs())}),
          if (side.abs() >= 1) side > 0 ? t('потім {n} м праворуч', {'n': n}) : t('потім {n} м ліворуч', {'n': n}),
        ].join(', ')));
      }
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: const Color(0xFFE3F2FD),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: out),
      ),
    );
  }

  /// ЦММ об'єкта: читається окремим потоком (сотні тисяч трикутників), там же будується сітка пошуку.
  Future<void> _loadSurface() async {
    final b = widget.object.surfaceSource == null ? null : await objectStore.loadSurface(widget.object.id);
    final s = b == null ? null : await compute(_readySurface, b);
    if (mounted) setState(() => _surface = s);
  }

  Future<void> _loadBasemap() async {
    final o = widget.object;
    final maps = await basemapStore.list();
    await _bg?.dispose();
    _bg = null;
    Problem? problem;
    if (o.basemap != bgNone && o.basemap != bgOsm) {
      final m = maps.where((x) => x.id == o.basemap).firstOrNull;
      if (m == null) {
        o.basemap = bgOsm; // підкладку видалили — повертаємось до OSM
      } else {
        try {
          _bg = await BasemapLayer.open(m);
        } catch (e) {
          problem = Problem(Severity.error, t('Підкладка «{name}» не відкрилась', {'name': m.name}), detail: '$e',
              fixes: const ['Видаліть її в «Даних об’єкта» й додайте файл ще раз.']);
          o.basemap = bgOsm;
        }
      }
    }
    if (!mounted) return;
    setState(() => _maps = maps);
    if (problem != null) await showProblemDialog(context, problem);
  }

  /// Вибір підкладки: без неї, OSM чи власна (ортофото, MBTiles).
  Future<void> _chooseBackground() async {
    final o = widget.object;
    final b = _view.bounds;
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: RadioGroup<String>(
          groupValue: o.basemap,
          onChanged: (v) => Navigator.pop(c, v),
          child: ListView(shrinkWrap: true, children: [
            const ListTile(title: T('Підкладка', style: TextStyle(fontWeight: FontWeight.bold))),
            const RadioListTile<String>(
                value: bgNone, title: T('Без підкладки'), subtitle: T('Лише вісь і лінії')),
            const RadioListTile<String>(
              value: bgOsm,
              title: Text('OpenStreetMap'),
              subtitle: T('Потрібен інтернет; переглянуте раніше видно й без нього'),
            ),
            for (final m in _maps)
              RadioListTile<String>(
                value: m.id,
                title: Text(m.name),
                subtitle: Text([
                  switch (m.kind) {
                    BasemapKind.mbtiles => t('MBTiles, наближення {a}–{b}', {'a': m.minZoom, 'b': m.maxZoom}),
                    BasemapKind.pmtiles => m.format == 'mvt'
                        ? t('карта без інтернету (векторна)')
                        : t('PMTiles, наближення {a}–{b}', {'a': m.minZoom, 'b': m.maxZoom}),
                    BasemapKind.image => t('знімок з файлом прив’язки'),
                  },
                  if (!m.overlaps(b.south, b.west, b.north, b.east)) t('не перетинається з цим об’єктом'),
                ].join(' · ')),
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const T('Додати ортофото чи карту (MBTiles, знімок)…'),
              onTap: () => Navigator.pop(c, '+'),
            ),
          ]),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    if (picked == '+') {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ObjectDataScreen(object: o)));
      await _loadBasemap();
      return;
    }
    o.basemap = picked;
    setState(() => _tilesFailed = false);
    await objectStore.save(o);
    await _loadBasemap();
  }

  /// Короткий рядок-попередження; торкання — повне пояснення з порадами.
  Widget _problemLink(Problem p) => InkWell(
        onTap: () => showProblemDialog(context, p),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Icon(Icons.warning_amber, size: 18, color: Colors.orange.shade900),
            const SizedBox(width: 6),
            Expanded(child: Text(t(p.title), style: TextStyle(color: Colors.orange.shade900))),
            const Icon(Icons.help_outline, size: 18, color: Colors.black45),
          ]),
        ),
      );

  Widget _warn(String text) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(text, style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.w600)),
      );
}

String _distText(double m) => m >= 1000
    ? t('{n} км', {'n': (m / 1000).toStringAsFixed(1)})
    : t('{n} м', {'n': m.toStringAsFixed(0)});

String _compass(double az) => t(const [
      'на північ', 'на північний схід', 'на схід', 'на південний схід', //
      'на південь', 'на південний захід', 'на захід', 'на північний захід',
    ][((az + 22.5) % 360 ~/ 45)]);

String _offsetText(double o) {
  if (o.abs() < 0.05) return t('на осі');
  final n = o.abs().toStringAsFixed(1);
  return o > 0 ? t('{n} м праворуч', {'n': n}) : t('{n} м ліворуч', {'n': n});
}

Color _offsetColor(double o) =>
    o.abs() < 0.05 ? Colors.green.shade800 : (o > 0 ? Colors.indigo.shade700 : Colors.teal.shade800);

Problem _gpsFailed(Object e) => Problem(Severity.error, 'GPS повідомив про помилку',
    detail: '$e',
    fixes: const ['Вимкніть і знову увімкніть геолокацію, потім «Спробувати ще раз».', 'Перезапустіть програму.']);
