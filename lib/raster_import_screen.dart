// Етап 7: скан чи PDF без координат → вісь (план) або профіль (поздовжній профіль).
// Людина ставить точки прив'язки й обводить лінію, програма «прилипає» до лінії потрібного кольору.
// Нічого не береться без перевірки: похибки прив'язки — на екрані, результат — на карті об'єкта.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart';

import 'basemaps.dart';
import 'chainage.dart';
import 'crs.dart';
import 'crs_picker.dart';
import 'geometry.dart';
import 'i18n.dart';
import 'keyboards.dart';
import 'lines.dart';
import 'pdf_vector.dart';
import 'problem_card.dart';
import 'problems.dart';
import 'raster_geo.dart';
import 'road_object.dart';

enum RasterMode { plan, profile }

/// Найбільша сторона зображення в програмі: більше — повільно й не вміщається в пам'ять планшета.
const _maxSide = 6000;

/// Зображення (скан чи сторінка PDF): пікселі для прилипання й JPEG для показу й підкладки.
class RasterPage {
  final Raster raster;
  final Uint8List jpeg;
  const RasterPage(this.raster, this.jpeg);
}

RasterPage _decodeImage(Uint8List bytes) {
  var im = img.decodeImage(bytes);
  if (im == null) throw const FormatException('not an image');
  if (math.max(im.width, im.height) > _maxSide) {
    im = im.width >= im.height ? img.copyResize(im, width: _maxSide) : img.copyResize(im, height: _maxSide);
  }
  final rgba = im.convert(numChannels: 4).getBytes(order: img.ChannelOrder.rgba);
  return RasterPage(Raster(im.width, im.height, rgba), img.encodeJpg(im, quality: 85));
}

RasterPage _fromRgba((int, int, Uint8List) a) {
  final (w, h, rgba) = a;
  final im = img.Image.fromBytes(width: w, height: h, bytes: rgba.buffer, numChannels: 4, order: img.ChannelOrder.rgba);
  return RasterPage(Raster(w, h, rgba), img.encodeJpg(im, quality: 85));
}

/// Сторінка PDF → пікселі (PDFium). Розмір — щоб довга сторона була до 6000 пікселів (≈ 300 dpi для A2).
Future<RasterPage> _renderPdf(Uint8List bytes, String name, int pageIndex) async {
  await pdfrxFlutterInitialize();
  final doc = await PdfDocument.openData(bytes, sourceName: name);
  try {
    return await renderPdfPage(doc.pages[pageIndex.clamp(0, doc.pages.length - 1)]);
  } finally {
    await doc.dispose();
  }
}

/// Відкрита сторінка PDF → пікселі; спільне для плану, профілю й поперечників зі скану.
Future<RasterPage> renderPdfPage(PdfPage page) async {
  final scale = math.min(_maxSide / math.max(page.width, page.height), 300 / 72);
  final w = (page.width * scale).round(), h = (page.height * scale).round();
  final im = await page.render(fullWidth: w.toDouble(), fullHeight: h.toDouble(), backgroundColor: 0xFFFFFFFF);
  if (im == null) throw const FormatException('PDF page did not render');
  final p = im.pixels;
  final rgba = Uint8List(p.length);
  for (var i = 0; i < p.length; i += 4) {
    rgba[i] = p[i + 2];
    rgba[i + 1] = p[i + 1];
    rgba[i + 2] = p[i];
    rgba[i + 3] = 255;
  }
  im.dispose();
  return compute(_fromRgba, (w, h, rgba));
}

/// Точка прив'язки (план) чи масштабу (профіль): де на зображенні й що відомо.
class _Ref {
  final Vec px;
  final Vec? world; // план: X, Y у системі об'єкта
  final double? station, z; // профіль
  const _Ref(this.px, {this.world, this.station, this.z});
}

/// Обведена лінія: роль, колір, торкання й результат прилипання (у пікселях).
class _Trace {
  final LineRole? role; // null — вісь (план) чи лінія проєкту (профіль)
  int? color;
  final taps = <Vec>[];
  List<Vec> line = const [];
  _Trace(this.role);
}

enum _Tool { none, ref, trace }

class RasterImportScreen extends StatefulWidget {
  final String fileName;
  final Uint8List bytes;
  final RasterMode mode;

  /// Профіль: до якого об'єкта (пікетаж і назва для підказок).
  final RoadObject? object;
  const RasterImportScreen({super.key, required this.fileName, required this.bytes, required this.mode, this.object});

  @override
  State<RasterImportScreen> createState() => _RasterImportScreenState();
}

class _RasterImportScreenState extends State<RasterImportScreen> {
  RasterPage? _img;
  Problem? _error;
  final _view = TransformationController();
  CoordSystem _crs = stereo70;
  final _refs = <_Ref>[];
  final _traces = <_Trace>[];
  _Trace? _active;
  _Tool _tool = _Tool.none;
  bool _busy = false;
  bool _asBasemap = true;
  ChainageStyle _style = ChainageStyle.pk;
  final _startCtl = TextEditingController(text: '0+000');
  late final _nameCtl = TextEditingController(text: widget.fileName.replaceAll(RegExp(r'\.[^.]+$'), ''));

  bool get _plan => widget.mode == RasterMode.plan;
  bool get _pdf => widget.fileName.toLowerCase().endsWith('.pdf');

  @override
  void initState() {
    super.initState();
    if (widget.object != null) {
      _crs = widget.object!.crs;
      _style = widget.object!.style;
    }
    _load();
  }

  /// Підказку закрили хрестиком — більше не показувати (до вибору точки прив’язки чи масштабу).
  bool _hintClosed = false;

  /// Лінії сторінки векторного PDF (у пікселях зображення) — для профілю; скан — порожньо.
  List<PdfStroke> _vec = const [];

  Future<void> _load() async {
    try {
      final l = _pdf ? await _renderPdf(widget.bytes, widget.fileName, 0) : await compute(_decodeImage, widget.bytes);
      final vec = _pdf && !_plan ? await compute(pdfPageStrokesOf, (widget.bytes, 0)) : null;
      if (mounted) {
        setState(() {
          _img = l;
          _vec = vec == null ? const [] : scaleStrokes(vec.$1, l.raster.width / vec.$2);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = Problem(Severity.error, t('Зображення не відкрилось'), detail: '$e', fixes: [
              t('Підтримуються JPG, PNG і PDF. TIFF збережіть як PNG (будь-яким переглядачем зображень).'),
              t('Дуже великий скан зменште до 6000 пікселів по довшій стороні.'),
            ]));
      }
    }
  }

  // ---------- Розрахунки ----------

  ImageFit? get _fit {
    if (!_plan) return null;
    final pairs = [for (final r in _refs) if (r.world != null) (r.px, r.world!)];
    if (pairs.length < 2) return null;
    try {
      return fitImage(pairs);
    } catch (_) {
      return null;
    }
  }

  ProfileScale? get _scale {
    if (_plan) return null;
    final h = [for (final r in _refs) if (r.station != null) (r.px.x, r.station!)];
    final v = [for (final r in _refs) if (r.z != null) (r.px.y, r.z!)];
    if (h.length < 2 || v.length < 2) return null;
    // Найдальші пари — найточніший масштаб.
    h.sort((a, b) => a.$1.compareTo(b.$1));
    v.sort((a, b) => a.$1.compareTo(b.$1));
    final s = ProfileScale(h.first, h.last, v.first, v.last);
    return s.valid ? s : null;
  }

  _Trace? get _axis => _traces.where((x) => x.role == null && x.line.length >= 2).firstOrNull;

  /// Лінія за торканнями: план — у будь-якому напрямку, через торкання; профіль іде зліва направо — від першого
  /// торкання програма сама йде лінією, наступні торкання поправляють, як у поперечниках.
  List<Vec> _traced(_Trace tr) =>
      _plan ? traceLine(_img!.raster, tr.taps, tr.color!) : traceFromTaps(_img!.raster, tr.taps, tr.color!);

  // ---------- Перо ----------

  /// Перо веде лінію (палець — рухає й наближає аркуш); відпустили — лінія прилипає до кольору тієї, яку обводили.
  bool _pen = false;
  final _stroke = <Vec>[];

  static bool _isPen(PointerEvent e) => e.kind == PointerDeviceKind.stylus || e.kind == PointerDeviceKind.invertedStylus;

  double get _zoom => _view.value.getMaxScaleOnAxis();

  /// Перо з натиснутою кнопкою — рухає аркуш (як палець); без кнопки — веде лінію.
  void _penDown(PointerDownEvent e) {
    if (!_isPen(e) || _tool != _Tool.trace) return;
    if (e.buttons & (kPrimaryStylusButton | kSecondaryStylusButton) != 0) return;
    setState(() {
      _pen = true;
      _stroke
        ..clear()
        ..add(Vec(e.localPosition.dx, e.localPosition.dy));
    });
  }

  void _penMove(PointerMoveEvent e) {
    if (!_pen) return;
    final p = Vec(e.localPosition.dx, e.localPosition.dy);
    if (p.dist(_stroke.last) * _zoom < 4) return;
    setState(() {
      _stroke.add(p);
      _preview(List.of(_stroke));
    });
  }

  /// Довжина руху пера на екрані, пікселів: коротше — це торкання (його обробляє onTapUp).
  double get _strokeLength {
    var d = 0.0;
    for (var i = 1; i < _stroke.length; i++) {
      d += _stroke[i].dist(_stroke[i - 1]);
    }
    return d * _zoom;
  }

  void _preview(List<Vec> line) => _active?.line = line;

  void _penUp(PointerUpEvent e) {
    if (!_pen) return;
    final im = _img, tr = _active;
    final long = _strokeLength > 20;
    setState(() {
      _pen = false;
      if (im == null || tr == null || !long) return;
      final mid = _stroke[_stroke.length ~/ 2];
      // Векторний PDF профілю — лінія креслення біля середини руху пера, точно.
      if (!_plan && _vec.isNotEmpty) {
        final l = pickVectorLine(_vec, mid, radius: 24 / _zoom);
        if (l.length >= 2) {
          tr.taps
            ..clear()
            ..add(mid);
          tr.line = l;
          return;
        }
      }
      // Колір тієї лінії, з якої почали вести, і прилипання до нього вздовж усього руху.
      tr.color = pickNearestColor(im.raster, _stroke.first, radius: (24 / _zoom).clamp(6, 60).round());
      tr.taps
        ..clear()
        ..addAll(_stroke);
      tr.line = _traced(tr);
    });
  }

  // ---------- Торкання ----------

  Future<void> _onTap(Offset local) async {
    final p = Vec(local.dx, local.dy);
    final im = _img;
    if (im == null) return;
    switch (_tool) {
      case _Tool.ref:
        setState(() => _tool = _Tool.none);
        final r = _plan ? await _askWorld(p) : await _askProfile(p);
        if (r != null) setState(() => _refs.add(r));
      case _Tool.trace:
        final tr = _active!;
        // Векторний PDF профілю — лінія креслення, якої торкнулись, точно (кожне торкання — вибір лінії наново).
        if (!_plan && _vec.isNotEmpty) {
          final l = pickVectorLine(_vec, p, radius: 24 / _view.value.getMaxScaleOnAxis());
          if (l.length >= 2) {
            setState(() {
              tr.taps
                ..clear()
                ..add(p);
              tr.line = l;
            });
            return;
          }
          // Векторний аркуш: по пікселях іти немає сенсу (піде сіткою) — лише підказати.
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(t('Тут лінії не знайшлося — торкніться самої лінії проєктного профілю (можна наблизити).'))));
          return;
        }
        setState(() {
          // Колір — тієї лінії, якої торкнулись (не найконтрастнішої поруч: червона лінія проєкту над чорною).
          tr.color ??= pickNearestColor(im.raster, p, radius: (24 / _view.value.getMaxScaleOnAxis()).clamp(6, 60).round());
          tr.taps.add(p);
          tr.line = _traced(tr);
        });
        // Перше торкання повз лінію — колір і торкання скидаються, наступне торкання — наново.
        if (!_plan && tr.taps.length == 1 && tr.line.length < 2) {
          setState(() {
            tr.taps.clear();
            tr.color = null;
          });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('Тут лінії не знайшлося — торкніться самої лінії проєктного профілю (можна наблизити).'))));
        }
      case _Tool.none:
        break;
    }
  }

  Future<_Ref?> _askWorld(Vec px) async {
    final x = TextEditingController(), y = TextEditingController(), ll = TextEditingController();
    var byLatLon = false;
    return showDialog<_Ref>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          // Прокрутка: з клавіатурою й великим шрифтом поле введення лишається на виду.
          scrollable: true,
          title: T('Координати цієї точки'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text(t('X, Y креслення'))),
                ButtonSegment(value: true, label: Text(t('Широта, довгота'))),
              ],
              selected: {byLatLon},
              onSelectionChanged: (s) => set(() => byLatLon = s.first),
            ),
            if (!byLatLon) ...[
              TextField(controller: x, keyboardType: numberKeyboard, decoration: InputDecoration(labelText: t('X (схід)'))),
              TextField(controller: y, keyboardType: numberKeyboard, decoration: InputDecoration(labelText: t('Y (північ)'))),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(t('Система: {s}', {'s': crsName(_crs)}), style: const TextStyle(color: Colors.black54)),
              ),
            ] else
              TextField(
                  controller: ll,
                  readOnly: true,
                  showCursor: true,
                  onTap: () => showDigitPad(c, ll, label: t('широта, довгота'), keys: latLonKeys),
                  decoration: InputDecoration(labelText: t('широта, довгота'), hintText: '44.4512345, 26.1034567')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: T('Скасувати')),
            FilledButton(
              onPressed: () {
                Vec? w;
                if (byLatLon) {
                  final g = parseLatLon(ll.text);
                  if (g != null) w = fromWgs84(_crs, g);
                } else {
                  final a = double.tryParse(x.text.replaceAll(',', '.').replaceAll(' ', ''));
                  final b = double.tryParse(y.text.replaceAll(',', '.').replaceAll(' ', ''));
                  if (a != null && b != null) w = Vec(a, b);
                }
                if (w != null) Navigator.pop(c, _Ref(px, world: w));
              },
              child: T('Додати'),
            ),
          ],
        ),
      ),
    );
  }

  Future<_Ref?> _askProfile(Vec px) async {
    final st = TextEditingController(), z = TextEditingController();
    return showDialog<_Ref>(
      context: context,
      builder: (c) => AlertDialog(
        // Прокрутка й поля першими: з клавіатурою й великим шрифтом поле введення лишається на виду.
        scrollable: true,
        title: T('Що відомо в цій точці'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: st,
              readOnly: true,
              showCursor: true,
              onTap: () => showDigitPad(c, st, label: t('ПК')),
              decoration: InputDecoration(labelText: t('ПК'), hintText: '0+100')),
          TextField(
              controller: z,
              keyboardType: numberKeyboard,
              decoration: InputDecoration(labelText: t('Відмітка, м'))),
          const SizedBox(height: 8),
          T('Точка на сітці профілю: ПК під нею і/або відмітка навпроти. Одне з двох можна лишити порожнім. '
              'Точки на лінії проєкту з ПК і відміткою з таблиці — найкращі: що більше таких, то точніше (скан '
              'буває перекошений — між ними програма вирівнює).',
              style: TextStyle(color: Colors.black54)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: T('Скасувати')),
          FilledButton(
            onPressed: () {
              final s = st.text.trim();
              final sv = s.isEmpty ? null : (parseChainageLabel(s)?.$1 ?? double.tryParse(s.replaceAll(',', '.')));
              final zv = double.tryParse(z.text.trim().replaceAll(',', '.'));
              if (sv != null || zv != null) Navigator.pop(c, _Ref(px, station: sv, z: zv));
            },
            child: T('Додати'),
          ),
        ],
      ),
    );
  }

  void _startTrace(LineRole? role) => setState(() {
        _active = _Trace(role);
        _traces.add(_active!);
        _tool = _Tool.trace;
      });

  void _finishTrace() => setState(() {
        if (_active != null && _active!.line.length < 2) _traces.remove(_active);
        _active = null;
        _tool = _Tool.none;
      });

  // ---------- Збереження ----------

  Future<void> _savePlan() async {
    final fit = _fit, axis = _axis, im = _img;
    final start = parseChainageLabel(_startCtl.text.trim())?.$1 ?? double.tryParse(_startCtl.text.trim().replaceAll(',', '.'));
    if (fit == null || axis == null || im == null || start == null) return;
    setState(() => _busy = true);
    try {
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      final o = RoadObject(
        id: id,
        name: _nameCtl.text.trim().isEmpty ? widget.fileName : _nameCtl.text.trim(),
        sourceFile: widget.fileName,
        axisLayer: t('Скан: обведена вісь'),
        crsId: _crs.id,
        startStation: start,
        style: _style,
        axis: toSegments(axis.line, fit.affine),
        lines: [
          for (final tr in _traces)
            if (tr.role != null && tr.line.length >= 2) RoadLine(tr.role!, t('скан'), toSegments(tr.line, fit.affine)),
        ],
        created: DateTime.now(),
      );
      if (_asBasemap) {
        try {
          final bid = 'i$id';
          final m = describeImage(bid, o.name, 'jpg', fit.affine.worldFile, im.raster.width, im.raster.height, _crs);
          if (kIsWeb) {
            basemapStore.keepInMemory(bid, im.jpeg);
          } else {
            await File(await basemapStore.pathOf(m)).writeAsBytes(im.jpeg);
          }
          await basemapStore.add(m);
          o.basemap = m.id;
        } on BasemapException catch (e) {
          if (mounted) await showProblemDialog(context, e.problem);
        }
      }
      await objectStore.save(o);
      if (mounted) Navigator.of(context).pop(o);
    } catch (e) {
      if (mounted) {
        await showProblemDialog(context, Problem(Severity.error, t('Об’єкт не зберігся'), detail: '$e',
            fixes: [t('Перевірте вільне місце на пристрої й спробуйте ще раз.')]));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _saveProfile() {
    final s = _scale, line = _axis;
    if (s == null || line == null) return;
    // Точки з ПК і відміткою разом — опорні: між ними профіль вирівнюється по відомих відмітках.
    final anchors = [
      for (final r in _refs)
        if (r.station != null && r.z != null) (r.station!, r.z! - s.z(r.px.y))
    ];
    Navigator.of(context)
        .pop(profileFromTrace(line.line, s, t('Скан профілю: {f}', {'f': widget.fileName}), anchors: anchors));
  }

  // ---------- Екран ----------

  @override
  Widget build(BuildContext context) {
    final err = _error;
    final title = _plan ? t('План зі скану: {f}', {'f': widget.fileName}) : t('Профіль зі скану: {f}', {'f': widget.fileName});
    if (err != null) {
      return Scaffold(appBar: AppBar(title: Text(title)), body: ListView(padding: const EdgeInsets.all(16), children: [ProblemCard(err)]));
    }
    final im = _img;
    return Scaffold(
      appBar: AppBar(title: Text(title, overflow: TextOverflow.ellipsis)),
      body: im == null
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const CircularProgressIndicator(), const SizedBox(height: 12), T('Відкриваю зображення…')]))
          : LayoutBuilder(builder: (context, c) {
              final wide = c.maxWidth > c.maxHeight && c.maxWidth > 700;
              final panel = _panel(context);
              final canvas = _canvas(im);
              return wide
                  ? Row(children: [SizedBox(width: 380, child: panel), Expanded(child: canvas)])
                  : Column(children: [Expanded(flex: 5, child: canvas), Expanded(flex: 4, child: panel)]);
            }),
    );
  }

  Widget _canvas(RasterPage im) => Stack(children: [
        InteractiveViewer(
          transformationController: _view,
          constrained: false,
          minScale: 0.02,
          maxScale: 12,
          boundaryMargin: const EdgeInsets.all(2000),
          // Перо веде лінію — аркуш під ним не рухається (палець і далі рухає й наближає).
          panEnabled: !_pen,
          child: Listener(
            onPointerDown: _penDown,
            onPointerMove: _penMove,
            onPointerUp: _penUp,
            onPointerCancel: (_) => setState(() => _pen = false),
            child: GestureDetector(
              onTapUp: (d) => _onTap(d.localPosition),
              child: SizedBox(
                width: im.raster.width.toDouble(),
                height: im.raster.height.toDouble(),
                child: Stack(children: [
                  Positioned.fill(child: Image.memory(im.jpeg, fit: BoxFit.fill, gaplessPlayback: true)),
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _view,
                      builder: (_, _) => CustomPaint(
                          painter: _Overlay(_refs, _traces, _active, 1 / _view.value.getMaxScaleOnAxis(), _plan ? _fit : null)),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
        // Підказка — внизу: угорі аркуша зазвичай саме креслення, і картка забирала б торкання.
        if (!_hintClosed && _tool != _Tool.none)
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: Card(
              color: const Color(0xFFFFF8E1),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 0, 4),
                child: Row(children: [
                  Expanded(
                    child: Text(_tool == _Tool.ref
                    ? (_plan
                        ? t('Торкніться точки з відомими координатами: хрест сітки, репер, підписаний ПК.')
                        : t('Торкніться точки на сітці профілю, де відомий ПК і/або відмітка.'))
                    : _plan
                        ? t('Торкайтесь уздовж лінії кожні 2–3 см екрана — програма прилипає до лінії того кольору, '
                            'якого торкнулись уперше.')
                        : t('Торкніться лінії проєктного профілю — програма сама пройде нею в обидва боки; пером можна й '
                            'провести по ній (з натиснутою кнопкою пера — рухати аркуш). Пішла не туди — торкніться ще кількох '
                            'точок уздовж лінії на тій ділянці.')),
                  ),
                  IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: t('Сховати підказку'),
                      onPressed: () => setState(() => _hintClosed = true)),
                ]),
              ),
            ),
          ),
      ]);

  Widget _panel(BuildContext context) {
    final theme = Theme.of(context);
    final fit = _fit, scale = _scale, axis = _axis;
    final refs = _refs.length;
    final children = <Widget>[];
    if (_plan) {
      children.addAll([
        Text(t('1. Система координат'), style: theme.textTheme.titleMedium),
        const SizedBox(height: 6),
        CrsPicker(value: _crs, segs: const [], onChanged: (c, _) => setState(() => _crs = c)),
        const SizedBox(height: 12),
        Text(t('2. Прив’язка: точки з відомими координатами'), style: theme.textTheme.titleMedium),
        T('Хрести сітки, репери, точки з таблиці координат. Дві — мінімум (скан без перекосу); '
            'чотири по кутах аркуша — видно похибку кожної.', style: TextStyle(color: Colors.black54)),
      ]);
    } else {
      children.addAll([
        Text(t('1. Масштаб профілю'), style: theme.textTheme.titleMedium),
        T('Дві точки з підписаним ПК (якомога далі одна від одної) і дві — з підписаною відміткою (по вертикалі).',
            style: TextStyle(color: Colors.black54)),
      ]);
    }
    for (final (i, r) in _refs.indexed) {
      final res = fit != null && fit.residuals.length == _refs.where((x) => x.world != null).length ? fit.residuals[i] : null;
      children.add(ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(radius: 12, child: Text('${i + 1}', style: const TextStyle(fontSize: 12))),
        title: Text(_plan
            ? 'X ${r.world!.x.toStringAsFixed(2)}  Y ${r.world!.y.toStringAsFixed(2)}'
            : [if (r.station != null) formatStation(r.station!, _style), if (r.z != null) '${r.z!.toStringAsFixed(2)} м'].join(' · ')),
        subtitle: res == null ? null : Text(t('похибка {m} м', {'m': res.toStringAsFixed(2)}),
            style: TextStyle(color: res > 2 ? Colors.red.shade800 : Colors.green.shade800)),
        trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => setState(() => _refs.removeAt(i))),
      ));
    }
    children.add(Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: () => setState(() {
          _tool = _tool == _Tool.ref ? _Tool.none : _Tool.ref;
          _hintClosed = false;
        }),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: Text(_tool == _Tool.ref ? t('Скасувати') : (_plan ? t('Точка прив’язки') : t('Точка масштабу'))),
      ),
    ));
    if (_plan && fit != null) {
      children.add(Text(
          refs < 4
              ? t('Прив’язка є; піксель ≈ {p} м. Додайте ще точку — буде видно похибку.', {'p': fit.affine.pixelSize.toStringAsFixed(3)})
              : t('Середня похибка {m} м; піксель ≈ {p} м.', {'m': fit.rms.toStringAsFixed(2), 'p': fit.affine.pixelSize.toStringAsFixed(3)}),
          style: const TextStyle(fontWeight: FontWeight.w600)));
      if (fit.rms > 2) {
        children.add(ProblemCard(Problem(Severity.warning, t('Точки прив’язки не узгоджуються (похибка понад 2 м)'), fixes: [
          t('Червона похибка — у точки, яку, мабуть, поставлено не на той хрест чи з помилкою в координатах: виправте чи приберіть її.'),
          t('Перевірте систему координат — вона має бути та, в якій підписані хрести сітки.'),
        ])));
      }
    }
    if (!_plan && scale == null && refs > 0) {
      children.add(T('Ще потрібні: два різні ПК і дві різні відмітки.', style: TextStyle(color: Colors.black54)));
    }

    children.addAll([
      const SizedBox(height: 12),
      Text(_plan ? t('3. Обведіть лінії') : t('2. Обведіть лінію проєкту'), style: theme.textTheme.titleMedium),
    ]);
    for (final tr in _traces) {
      final name = tr.role == null ? (_plan ? t('Вісь') : t('Лінія проєкту')) : t(tr.role!.label);
      children.add(ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Container(
            width: 18, height: 18, decoration: BoxDecoration(color: tr.color == null ? null : Color(0xFF000000 | tr.color!), border: Border.all())),
        title: Text(name),
        subtitle: Text(t('торкань {n}, точок лінії {k}', {'n': tr.taps.length, 'k': tr.line.length})),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (tr == _active && tr.taps.isNotEmpty)
            IconButton(
              tooltip: t('Скасувати останнє торкання'),
              icon: const Icon(Icons.undo),
              onPressed: () => setState(() {
                tr.taps.removeLast();
                if (tr.taps.isEmpty) tr.color = null;
                tr.line = tr.taps.isEmpty ? const [] : _traced(tr);
              }),
            ),
          IconButton(
              tooltip: t('Прибрати лінію'),
              icon: const Icon(Icons.delete_outline),
              onPressed: () => setState(() {
                    _traces.remove(tr);
                    if (_active == tr) {
                      _active = null;
                      _tool = _Tool.none;
                    }
                  })),
        ]),
      ));
    }
    if (_active != null) {
      children.add(FilledButton.icon(onPressed: _finishTrace, icon: const Icon(Icons.check), label: T('Лінію обведено')));
    } else {
      children.add(Wrap(spacing: 8, runSpacing: 4, children: [
        if (axis == null) FilledButton.tonalIcon(onPressed: () => _startTrace(null), icon: const Icon(Icons.gesture), label: Text(_plan ? t('Обвести вісь') : t('Обвести лінію'))),
        if (_plan)
          for (final r in [LineRole.edge, LineRole.brow, LineRole.toe, LineRole.row])
            OutlinedButton(onPressed: () => _startTrace(r), child: Text(t(r.label))),
      ]));
    }

    if (_plan) {
      children.addAll([
        const SizedBox(height: 12),
        Text(t('4. Пікетаж і назва'), style: theme.textTheme.titleMedium),
        T('Вісь іде від першого торкання до останнього — у бік зростання пікетажу.', style: TextStyle(color: Colors.black54)),
        Row(children: [
          Expanded(
              child: TextField(
                  controller: _startCtl,
                  readOnly: true,
                  showCursor: true,
                  onTap: () => showDigitPad(context, _startCtl, label: t('ПК початку осі'), onChanged: (_) => setState(() {})),
                  decoration: InputDecoration(labelText: t('ПК початку осі')))),
          const SizedBox(width: 8),
          SegmentedButton<ChainageStyle>(
            segments: [
              ButtonSegment(value: ChainageStyle.pk, label: Text(t('ПК'))),
              ButtonSegment(value: ChainageStyle.km, label: Text(t('км'))),
            ],
            selected: {_style},
            onSelectionChanged: (s) => setState(() => _style = s.first),
          ),
        ]),
        TextField(controller: _nameCtl, decoration: InputDecoration(labelText: t('Назва об’єкта'))),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: T('Скан — підкладкою об’єкта'),
          subtitle: T('Видно поверх карти, щоб звірити вісь із кресленням'),
          value: _asBasemap,
          onChanged: (v) => setState(() => _asBasemap = v),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: fit != null && axis != null && !_busy ? _savePlan : null,
          icon: const Icon(Icons.check),
          label: T('Створити об’єкт'),
        ),
        if (fit == null || axis == null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
                [if (fit == null) t('потрібні 2+ точки прив’язки'), if (axis == null) t('потрібна обведена вісь')].join(' · '),
                style: const TextStyle(color: Colors.black54)),
          ),
      ]);
    } else {
      children.addAll([
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: scale != null && axis != null ? _saveProfile : null,
          icon: const Icon(Icons.check),
          label: T('Взяти профіль'),
        ),
        if (scale != null && axis != null)
          Builder(builder: (_) {
            final p = profileFromTrace(axis.line, scale, '');
            return Text(t('{n} точок перелому, {a} – {b}', {
              'n': p.pvis.length,
              'a': formatStation(p.startStation, _style),
              'b': formatStation(p.endStation, _style),
            }));
          }),
      ]);
    }
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: ListView(padding: const EdgeInsets.all(12), children: children),
    );
  }
}

/// Точки прив'язки й обведені лінії поверх зображення; товщина не залежить від наближення.
class _Overlay extends CustomPainter {
  final List<_Ref> refs;
  final List<_Trace> traces;
  final _Trace? active;
  final double k; // 1 / масштаб — щоб лінії й точки були однакові на екрані
  final ImageFit? fit;
  _Overlay(this.refs, this.traces, this.active, this.k, this.fit);

  @override
  void paint(Canvas canvas, Size size) {
    for (final tr in traces) {
      // Вісь (план) і лінія проєктного профілю — товстою зеленою, щоб було видно, що взялася вся; лінії плану — своїм
      // кольором.
      final main = tr.role == null;
      if (tr.line.length >= 2) {
        final path = Path()..moveTo(tr.line.first.x, tr.line.first.y);
        for (final p in tr.line.skip(1)) {
          path.lineTo(p.x, p.y);
        }
        canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              // Щонайменше 5 пікселів аркуша: при наближенні ширша за саму лінію креслення.
              ..strokeWidth = main ? math.max(18 * k, 5) : 4 * k
              ..strokeJoin = StrokeJoin.round
              ..strokeCap = StrokeCap.round
              ..color = main ? const Color(0x9900C853) : tr.role!.color.withValues(alpha: 0.75));
      }
      if (tr == active) {
        for (final p in tr.taps) {
          canvas.drawCircle(Offset(p.x, p.y), 5 * k, Paint()..color = const Color(0xFF1565C0));
        }
      }
    }
    for (final (i, r) in refs.indexed) {
      final o = Offset(r.px.x, r.px.y);
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 * k
        ..color = const Color(0xFF6A1B9A);
      canvas.drawCircle(o, 10 * k, p);
      canvas.drawLine(o - Offset(16 * k, 0), o + Offset(16 * k, 0), p);
      canvas.drawLine(o - Offset(0, 16 * k), o + Offset(0, 16 * k), p);
      final tp = TextPainter(
        text: TextSpan(text: '${i + 1}', style: TextStyle(color: const Color(0xFF6A1B9A), fontSize: 16 * k, fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, o + Offset(12 * k, -26 * k));
    }
  }

  @override
  bool shouldRepaint(_Overlay old) => true;
}
