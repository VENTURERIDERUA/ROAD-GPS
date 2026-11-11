// Поперечники з PDF: дотик до лінії проєктного профілю — у векторному PDF лінія береться з креслення, а масштаби,
// вісь і її відмітка — з чисел на аркуші; у скані лінія йде за кольором, масштаб і вісь задає людина (дві точки на
// відомій відстані, відмітка осі). Відмітки — для ознайомлення, не для винесення в натуру.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'chainage.dart';
import 'geometry.dart';
import 'i18n.dart';
import 'keyboards.dart';
import 'pdf_sections.dart';
import 'pdf_vector.dart';
import 'problem_card.dart';
import 'problems.dart';
import 'profile.dart';
import 'raster_geo.dart';
import 'raster_import_screen.dart' show RasterPage, renderPdfPage;
import 'xs_grid.dart';

enum _Tool { scale, axis, trace }

class XsScanScreen extends StatefulWidget {
  final Uint8List pdf;
  final PdfSections sections;
  final ChainageStyle style;

  /// Поздовжній профіль — підказка відмітки осі на ПК поперечника.
  final Profile? profile;

  /// Уже наявні поперечники — нові додаються до них (той самий ПК — замінюється).
  final CrossSections? existing;
  const XsScanScreen(
      {super.key, required this.pdf, required this.sections, required this.style, this.profile, this.existing});

  @override
  State<XsScanScreen> createState() => _XsScanScreenState();
}

class _XsScanScreenState extends State<XsScanScreen> {
  PdfDocument? _doc;
  Problem? _error;
  int _page = 0; // з нуля
  RasterPage? _img;
  double _pxPerPt = 1, _pageH = 0;
  final _view = TransformationController();
  // Звичайний стан — дотик вибирає лінію; масштаб і вісь — тимчасові, після них знову лінія.
  _Tool _tool = _Tool.trace;

  /// Пікселів на метр по горизонталі — для сторінок того самого розміру (аркуші одного формату).
  final _scaleBySize = <String, double>{};
  final _calib = <Vec>[];

  /// Масштаби аркуша, як на кресленні: 1:[_hScale] по горизонталі, 1:[_vScale] по вертикалі.
  final _hScale = TextEditingController(), _vScale = TextEditingController();
  String? _scaleNote;
  Vec? _axis;
  double? _zAxis;
  final _taps = <Vec>[];
  int? _color;
  List<Vec> _line = const [];

  /// Лінії сторінки векторного PDF (у пікселях зображення); скан — порожньо.
  List<PdfStroke> _vec = const [];

  /// Лінію взято з самого креслення (векторний PDF), а не з пікселів.
  bool _exact = false;

  /// Числа сторінки (з текстом PDF) і що з них знайдено для поточної лінії: масштаби, вісь, відмітка осі.
  List<SheetNumber> _nums = const [];
  SectionGrid? _grid;

  /// Підказку закрили хрестиком — більше не показувати (до вибору масштабу чи осі).
  bool _hintClosed = false;

  /// Колір лінії проєктного профілю, якої торкнулися (векторний PDF) — за ним «Взяти всі поперечники».
  int? _pickedRgb;
  double? _pk;

  /// Обведені поперечники: ПК → точки.
  final _done = <double, List<(double, double)>>{};

  String get _sizeKey => '${_img?.raster.width}x${_img?.raster.height}';

  double? _num(TextEditingController c) {
    final v = double.tryParse(c.text.trim().replaceAll(',', '.'));
    return v != null && v > 0 ? v : null;
  }

  /// Пікселів на метр по горизонталі: звірено двома дотиками — так; інакше — з горизонтального масштабу аркуша
  /// (вірно, лише коли PDF надруковано в масштабі, не «у розмір аркуша»).
  double? get _pxPerM {
    final h = _num(_hScale);
    return _grid?.pxPerMH ?? _scaleBySize[_sizeKey] ?? (h == null ? null : _pxPerPt * pointsPerMetre / h);
  }

  /// У скільки разів вертикаль крупніша за горизонталь: H 1:1000, V 1:100 → 10; не задано — однаково.
  double get _vRatio {
    final g = _grid;
    if (g != null) return g.pxPerMV / g.pxPerMH;
    final h = _num(_hScale), v = _num(_vScale);
    return h == null || v == null ? 1 : h / v;
  }
  List<SectionLabel> get _labels => [for (final l in widget.sections.labels) if (l.page == _page + 1) l];

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void dispose() {
    _doc?.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    try {
      await pdfrxFlutterInitialize();
      _doc = await PdfDocument.openData(widget.pdf, sourceName: widget.sections.fileName);
      final first = widget.sections.labels.isEmpty ? 1 : widget.sections.labels.first.page;
      await _show(first - 1);
    } catch (e) {
      if (mounted) setState(() => _error = Problem(Severity.error, t('PDF не відкрився'), detail: '$e'));
    }
  }

  Future<void> _show(int page) async {
    final doc = _doc!;
    page = page.clamp(0, doc.pages.length - 1);
    setState(() {
      _img = null;
      _page = page;
    });
    final p = doc.pages[page];
    final im = await renderPdfPage(p);
    final raw = await p.loadText();
    final text = raw?.fullText ?? '';
    final vec = await compute(pdfPageStrokesOf, (widget.pdf, page));
    // Символи з місцями — у пікселях зображення (Y — униз), для чисел сітки й таблиці.
    final k = im.raster.width / p.width;
    final chars = <SheetChar>[
      if (raw != null)
        for (var i = 0; i < raw.charRects.length && i < text.length; i++)
          (text[i], raw.charRects[i].left * k, (p.height - raw.charRects[i].top) * k, raw.charRects[i].right * k,
              (p.height - raw.charRects[i].bottom) * k)
    ];
    final v = sheetScale(text, vertical: true), h = sheetScale(text, vertical: false);
    if (!mounted) return;
    setState(() {
      _img = im;
      _pxPerPt = im.raster.width / p.width;
      _vec = vec == null ? const [] : scaleStrokes(vec.$1, im.raster.width / vec.$2);
      _nums = sheetNumbers(chars);
      _pageH = p.height;
      if (v != null && h != null) {
        _hScale.text = h.round().toString();
        _vScale.text = v.round().toString();
        _scaleNote = t('з напису на аркуші');
      }
      _resetSection();
      _pk = _labels.firstOrNull?.station;
    });
    // Сторінку — цілою за шириною поля; далі людина наближає пальцями до потрібного поперечника.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = _canvasSize;
      if (!mounted || s == null) return;
      final k = s.width / im.raster.width;
      _view.value = Matrix4.diagonal3Values(k, k, 1);
    });
  }

  /// Розмір поля зі сторінкою — для показу сторінки цілою.
  Size? _canvasSize;

  void _resetSection() {
    _grid = null;
    _axis = null;
    _zAxis = null;
    _taps.clear();
    _color = null;
    _line = const [];
  }

  /// Підпис ПК, найближчий до точки (на аркуші підпис — під поперечником).
  double? _nearestPk(Vec px) {
    SectionLabel? best;
    var bestD = double.infinity;
    for (final l in _labels) {
      final r = l.rect;
      if (r == null) continue;
      final c = Vec((r.left + r.right) / 2 * _pxPerPt, (_pageH - (r.top + r.bottom) / 2) * _pxPerPt);
      final d = c.dist(px) + (c.y < px.y ? 1e6 : 0); // підпис над віссю — не цього поперечника
      if (d < bestD) {
        bestD = d;
        best = l;
      }
    }
    return best?.station;
  }

  /// Підпис ПК цього поперечника: над чи під ним (буває по-різному), у межах його ширини, найближчий по висоті.
  double? _pkOfLine(List<Vec> line) {
    final x0 = line.first.x, x1 = line.last.x;
    final ys = line.map((p) => p.y);
    final top = ys.reduce(math.min), bottom = ys.reduce(math.max);
    SectionLabel? best;
    var bestD = double.infinity;
    for (final l in _labels) {
      final r = l.rect;
      if (r == null) continue;
      final c = Vec((r.left + r.right) / 2 * _pxPerPt, (_pageH - (r.top + r.bottom) / 2) * _pxPerPt);
      if (c.x < x0 - 0.25 * (x1 - x0) || c.x > x1 + 0.25 * (x1 - x0)) continue;
      final d = c.y < top ? top - c.y : (c.y > bottom ? c.y - bottom : 0.0);
      if (d < bestD) {
        bestD = d;
        best = l;
      }
    }
    return best?.station;
  }

  /// Підписи ПК поточної сторінки в пікселях зображення: (ПК, середина підпису).
  List<(double, Vec)> get _labelsPx => [
        for (final l in _labels)
          if (l.rect case final r?)
            (l.station, Vec((r.left + r.right) / 2 * _pxPerPt, (_pageH - (r.top + r.bottom) / 2) * _pxPerPt))
      ];

  /// ПК поперечника [g] векторного аркуша — як для всієї сторінки: поперечники стовпчика й підписи ПК за порядком
  /// згори вниз ([assignStations]); не вийшло — null.
  double? _stationOnPage(SectionGrid g) {
    final rgb = _pickedRgb;
    if (rgb == null || _vec.isEmpty || _axis == null) return null;
    for (final (_, sg, st) in pageSections(_vec, _nums, rgb, _labelsPx)) {
      if ((sg.xAxis - g.xAxis).abs() < 3 * _pxPerPt && (sg.zAxis - g.zAxis).abs() < 0.5) return st;
    }
    return null;
  }

  /// Усі поперечники векторного PDF за один раз: на кожній сторінці лінії того кольору, якої торкнулися, → масштаби,
  /// вісь і відмітка з чисел аркуша → ПК з підпису. Перед додаванням — перелік на перегляд; додане зберігається в
  /// об'єкт кнопкою «Готово», як і обведене вручну.
  Future<void> _takeAll() async {
    final rgb = _pickedRgb;
    if (rgb == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('Спершу торкніться лінії проєктного профілю на одному поперечнику — за її кольором програма '
              'знайде решту.'))));
      return;
    }
    final doc = _doc!;
    final progress = ValueNotifier<String>(t('Читаю лінії PDF…'));
    var cancel = false;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const T('Беру поперечники'),
        content: Row(children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 16),
          Expanded(child: ValueListenableBuilder<String>(valueListenable: progress, builder: (_, v, _) => Text(v))),
        ]),
        actions: [TextButton(onPressed: () => cancel = true, child: const T('Скасувати'))],
      ),
    );
    final found = <FoundSection>[];
    var labelled = 0;
    try {
      final all = await compute(pdfAllStrokesOf, widget.pdf);
      for (var i = 0; i < doc.pages.length && i < all.length && !cancel; i++) {
        progress.value = t('Сторінка {p} з {n} · знайдено {k}', {'p': i + 1, 'n': doc.pages.length, 'k': found.length});
        final v = all[i];
        final labels = [
          for (final l in widget.sections.labels)
            if (l.page == i + 1 && l.rect != null)
              (l.station, Vec((l.rect!.left + l.rect!.right) / 2, doc.pages[i].height - (l.rect!.top + l.rect!.bottom) / 2))
        ];
        labelled += labels.length;
        if (v == null || labels.isEmpty) continue;
        // У пунктах сторінки (лінії PDF — теж у пунктах): масштаб зображення тут не потрібен.
        final page = doc.pages[i];
        final raw = await page.loadText();
        final text = raw?.fullText ?? '';
        final chars = <SheetChar>[
          if (raw != null)
            for (var j = 0; j < raw.charRects.length && j < text.length; j++)
              (text[j], raw.charRects[j].left, page.height - raw.charRects[j].top, raw.charRects[j].right,
                  page.height - raw.charRects[j].bottom)
        ];
        found.addAll(await compute(sectionsOnPageOf, (v.$1, sheetNumbers(chars), rgb, labels)));
      }
    } finally {
      if (mounted) Navigator.of(context).pop();
    }
    if (!mounted || cancel) return;
    final byPk = {for (final f in found) f.$1: f};
    final list = byPk.values.toList()..sort((a, b) => a.$1.compareTo(b.$1));
    String pk(double v) => formatStation(v, widget.style);
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        scrollable: true,
        title: Text(t('Знайдено поперечників: {n}', {'n': list.length})),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (list.length < labelled)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                  t('Підписів ПК у PDF: {a}. Решту ({b}) програма сама не взяла — їх можна обвести вручну.',
                      {'a': labelled, 'b': labelled - list.length}),
                  style: const TextStyle(color: Colors.black54)),
            ),
          for (final f in list)
            Text(t('{pk}: відмітка осі {z} м, точок {n}{again}', {
              'pk': pk(f.$1),
              'z': f.$3.toStringAsFixed(2),
              'n': f.$2.length,
              'again': _done.containsKey(f.$1) ? t(' (замінить обведений)') : '',
            })),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const T('Скасувати')),
          FilledButton(
              onPressed: list.isEmpty ? null : () => Navigator.pop(c, true), child: const T('Додати всі')),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() {
      for (final f in list) {
        _done[f.$1] = f.$2;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t('Додано {n}. Щоб зберегти в об’єкт — «Готово» вгорі.', {'n': list.length}))));
  }

  /// Масштаби, вісь і її відмітка — з чисел на аркуші навколо лінії: рядок відстаней від осі, стовпчик відміток
  /// сітки чи рядок проєктних відміток таблиці. Не знайшлося — як було (задати вручну).
  void _autoGrid() {
    final g = fitSectionGrid(_nums, _line, grid: [for (final s in _vec) s.pts]);
    final y = g == null ? null : zOnLine([for (final p in _line) (p.x, p.y)], g.xAxis);
    if (g == null || y == null) {
      _grid = null;
      return;
    }
    _grid = g;
    _axis = Vec(g.xAxis, y);
    _zAxis = g.zAxis;
    _pk = _stationOnPage(g) ?? _pkOfLine(_line) ?? _pk;
    String scale(double pxPerM) {
      final s = _pxPerPt * pointsPerMetre / pxPerM;
      return (s - s.round()).abs() < 0.02 * s ? s.round().toString() : s.toStringAsFixed(1);
    }

    _hScale.text = scale(g.pxPerMH);
    _vScale.text = scale(g.pxPerMV);
    _scaleNote = t('з чисел на аркуші');
  }

  Future<void> _onTap(Offset local) async {
    final p = Vec(local.dx, local.dy);
    final im = _img;
    if (im == null) return;
    switch (_tool) {
      case _Tool.scale:
        setState(() => _calib.add(p));
        if (_calib.length == 2) {
          setState(() {
            _tool = _Tool.trace;
            _grid = null;
          });
          final d = await _askNumber(t('Відстань між точками, м'), t('напр. 4.00 — з рядка відстаней під поперечником'));
          if (d != null && d > 0 && (_calib[1].x - _calib[0].x).abs() > 5) {
            setState(() => _scaleBySize[_sizeKey] = (_calib[1].x - _calib[0].x).abs() / d);
          }
          setState(_calib.clear);
        }
      case _Tool.axis:
        setState(() => _tool = _Tool.trace);
        final pk = _nearestPk(p) ?? _pk;
        final hint = pk == null ? null : widget.profile?.elevationAt(pk);
        final z = await _askNumber(t('Відмітка осі (проєкт), м'),
            hint == null ? t('з таблиці під поперечником') : t('з профілю на цьому ПК: {z}', {'z': hint.toStringAsFixed(2)}),
            initial: hint);
        if (z != null) {
          setState(() {
            _axis = p;
            _zAxis = z;
            _pk = pk;
          });
        }
      case _Tool.trace:
        // Векторний PDF — лінія креслення, якої торкнулись, точно (кожне торкання — вибір лінії наново).
        if (_vec.isNotEmpty) {
          final l = pickVectorLine(_vec, p, radius: 24 / _view.value.getMaxScaleOnAxis());
          if (l.length >= 2) {
            _pickedRgb = pickVectorRgb(_vec, p, radius: 24 / _view.value.getMaxScaleOnAxis());
            setState(() {
              _taps
                ..clear()
                ..add(p);
              _line = l;
              _exact = true;
              _autoGrid();
            });
            return;
          }
          // Векторний аркуш: по пікселях іти немає сенсу (піде сіткою) — лише підказати.
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(t('Тут лінії не знайшлося — торкніться самої лінії проєктного профілю (можна наблизити).'))));
          return;
        }
        _exact = false;
        setState(() {
          _color ??= pickNearestColor(im.raster, p, radius: (24 / _view.value.getMaxScaleOnAxis()).clamp(6, 60).round());
          _taps.add(p);
          _line = traceFromTaps(im.raster, _taps, _color!);
          _autoGrid();
        });
        // Перше торкання повз лінію — колір і торкання скидаються, наступне торкання — наново.
        if (_taps.length == 1 && _line.length < 2) {
          setState(() {
            _taps.clear();
            _color = null;
          });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t('Тут лінії не знайшлося — торкніться самої лінії проєктного профілю (можна наблизити).'))));
        }
    }
  }

  Future<double?> _askNumber(String title, String hint, {double? initial}) async {
    final c = TextEditingController(text: initial?.toStringAsFixed(2) ?? '');
    final s = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: numberKeyboard,
          decoration: InputDecoration(hintText: hint, helperText: hint),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const T('Скасувати')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const T('Готово')),
        ],
      ),
    );
    return s == null ? null : double.tryParse(s.trim().replaceAll(',', '.'));
  }

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

  void _preview(List<Vec> line) {
    _exact = false;
    _line = line;
  }

  void _penUp(PointerUpEvent e) {
    if (!_pen) return;
    final im = _img;
    final long = _strokeLength > 20;
    setState(() {
      _pen = false;
      if (im == null || !long) {
        if (_stroke.length > 1) _line = const [];
        return;
      }
      final mid = _stroke[_stroke.length ~/ 2];
      // Векторний PDF — лінія креслення біля середини руху пера, точно.
      if (_vec.isNotEmpty) {
        final l = pickVectorLine(_vec, mid, radius: 24 / _zoom);
        if (l.length >= 2) {
          _pickedRgb = pickVectorRgb(_vec, mid, radius: 24 / _zoom);
          _taps
            ..clear()
            ..add(mid);
          _line = l;
          _exact = true;
          _autoGrid();
          return;
        }
      }
      // Скан — колір тієї лінії, з якої почали вести, і прилипання до нього вздовж усього руху.
      _color = pickNearestColor(im.raster, _stroke.first, radius: (24 / _zoom).clamp(6, 60).round());
      _taps
        ..clear()
        ..addAll(_stroke);
      _line = traceFromTaps(im.raster, _taps, _color!);
      _autoGrid();
    });
  }

  /// Поточний поперечник у метрах — коли все задано. Висота осі — з обведеної лінії в місці осі (торкання дає лише
  /// положення по горизонталі: палець на екрані — це кілька сантиметрів по висоті).
  List<(double, double)>? get _section {
    final k = _pxPerM, a = _axis, z = _zAxis;
    if (k == null || a == null || z == null || _line.length < 2) return null;
    final y = zOnLine([for (final p in _line) (p.x, p.y)], a.x);
    return sectionFromTrace(_line, Vec(a.x, y ?? a.y), z, k, k * _vRatio);
  }

  void _save() {
    final s = _section, pk = _pk;
    if (s == null || pk == null) return;
    setState(() {
      _done[pk] = s;
      _resetSection();
      // Далі — наступний ще не обведений підпис цієї сторінки.
      _pk = _labels.where((l) => !_done.containsKey(l.station)).firstOrNull?.station ?? _pk;
    });
  }

  CrossSections? _result() {
    if (_done.isEmpty) return null;
    final rows = <double, List<(double, double)>>{
      for (final r in widget.existing?.rows ?? const <(double, List<(double, double)>)>[]) r.$1: r.$2,
      ..._done,
    };
    return CrossSections('PDF: ${widget.sections.fileName}', [for (final e in rows.entries) (e.key, e.value)]);
  }

  @override
  Widget build(BuildContext context) {
    final im = _img;
    return Scaffold(
      appBar: AppBar(
        title: Text(t('Поперечники з PDF: {f}', {'f': widget.sections.fileName}), overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(
            onPressed: _done.isEmpty ? null : () => Navigator.of(context).pop(_result()),
            child: Text(t('Готово ({n})', {'n': _done.length})),
          ),
        ],
      ),
      body: _error != null
          ? ListView(padding: const EdgeInsets.all(16), children: [ProblemCard(_error!)])
          : im == null
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(builder: (context, c) {
                  final wide = c.maxWidth > c.maxHeight && c.maxWidth > 700;
                  final panel = _panel();
                  final canvas = _canvas(im);
                  return wide
                      ? Row(children: [SizedBox(width: 380, child: panel), Expanded(child: canvas)])
                      : Column(children: [Expanded(flex: 5, child: canvas), Expanded(flex: 4, child: panel)]);
                }),
    );
  }

  Widget _canvas(RasterPage im) => LayoutBuilder(builder: (context, c) {
        _canvasSize = c.biggest;
        return _canvasStack(im);
      });

  Widget _canvasStack(RasterPage im) => Stack(children: [
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
                          painter: _Overlay(_calib, _axis, _taps, _line, 1 / _view.value.getMaxScaleOnAxis())),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
        // Підказка — внизу (поперечники на аркуші вгорі, і картка зверху забирала торкання лінії); доки лінію не
        // вибрано чи коли задається масштаб або вісь; хрестик — сховати.
        if (!_hintClosed && (_tool != _Tool.trace || _line.isEmpty))
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
                    child: Text(switch (_tool) {
                  _Tool.scale => t('Торкніться двох точок на одній горизонталі з відомою відстанню між ними — '
                      'наприклад двох вертикалей переломів, між якими в таблиці «4.00».'),
                  _Tool.axis => t('Торкніться місця, де вісь (вертикаль) перетинає лінію проєктного профілю.'),
                  _ => t('Торкніться лінії проєктного профілю — програма сама пройде нею в обидва боки; пером можна й '
                      'провести по ній (з натиснутою кнопкою пера — рухати аркуш). Пішла не туди — торкніться ще кількох '
                      'точок уздовж лінії на тій ділянці.'),
                    }),
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

  Widget _panel() {
    final doc = _doc!;
    final s = _section;
    final labels = _labels;
    String pk(double v) => formatStation(v, widget.style);
    return ListView(padding: const EdgeInsets.all(12), children: [
      Row(children: [
        IconButton(
            onPressed: _page > 0 ? () => _show(_page - 1) : null, icon: const Icon(Icons.chevron_left), tooltip: t('Попередня сторінка')),
        Expanded(
          child: Text(t('Сторінка {p} з {n}', {'p': _page + 1, 'n': doc.pages.length}), textAlign: TextAlign.center),
        ),
        IconButton(
            onPressed: _page + 1 < doc.pages.length ? () => _show(_page + 1) : null,
            icon: const Icon(Icons.chevron_right),
            tooltip: t('Наступна сторінка')),
      ]),
      if (labels.isNotEmpty)
        Wrap(spacing: 6, children: [
          for (final l in labels)
            ChoiceChip(
              label: Text('${pk(l.station)}${_done.containsKey(l.station) ? ' ✓' : ''}'),
              selected: _pk == l.station,
              onSelected: (_) => setState(() => _pk = l.station),
            ),
        ])
      else
        const T('На цій сторінці підписів ПК не знайдено.', style: TextStyle(color: Colors.black54)),
      const Divider(),
      Row(children: [
        const CircleAvatar(radius: 12, child: Text('1', style: TextStyle(fontSize: 12))),
        const SizedBox(width: 12),
        Expanded(child: T('Масштаби')),
        if (_scaleNote != null) Text(_scaleNote!, style: const TextStyle(color: Colors.black54, fontSize: 12)),
      ]),
      for (final (label, c) in [(t('Горизонтальний 1:'), _hScale), (t('Вертикальний 1:'), _vScale)])
        Row(children: [
          const SizedBox(width: 36),
          Expanded(child: Text(label)),
          SizedBox(
              width: 90,
              child: TextField(
                  controller: c,
                  keyboardType: numberKeyboard,
                  onChanged: (_) => setState(() {
                        _scaleNote = null;
                        _grid = null;
                      }))),
        ]),
      Padding(
        padding: const EdgeInsets.only(left: 36),
        child: Row(children: [
          Expanded(
            child: Text(
                _grid != null
                    ? t('Масштаби, вісь і її відмітка — з чисел на аркуші ({how}).', {'how': t(_grid!.how)})
                    : _scaleBySize[_sizeKey] != null
                    ? t('Розмір звірено дотиками: 1 м = {k} пікс.', {'k': _scaleBySize[_sizeKey]!.toStringAsFixed(1)})
                    : _num(_hScale) != null
                        ? t('Розмір — за масштабом аркуша. PDF друкувався «у розмір аркуша» — звірте двома дотиками.')
                        : t('Впишіть масштаби з аркуша або звірте розмір двома дотиками.'),
                style: const TextStyle(color: Colors.black54, fontSize: 12)),
          ),
          TextButton(
              onPressed: () => setState(() {
                    _calib.clear();
                    _tool = _Tool.scale;
                    _hintClosed = false;
                  }),
              child: const T('Звірити')),
        ]),
      ),
      _step(
        '2',
        _axis == null
            ? t('Вісь і її відмітка: не задано')
            : t('Вісь: {z} м · {pk}', {'z': _zAxis!.toStringAsFixed(2), 'pk': _pk == null ? '—' : pk(_pk!)}),
        t('Вказати'),
        () => setState(() {
          _tool = _Tool.axis;
          _hintClosed = false;
        }),
      ),
      // Лінія — дотиком до аркуша (окремої кнопки не треба).
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          const CircleAvatar(radius: 12, child: Text('3', style: TextStyle(fontSize: 12))),
          const SizedBox(width: 12),
          Expanded(
            child: Text(_taps.isEmpty
                ? t('Лінія проєктного профілю: торкніться її на аркуші')
                : _exact
                    ? t('Лінія проєктного профілю: з креслення (точно)')
                    : t('Лінія проєктного профілю: торкань {n}', {'n': _taps.length})),
          ),
        ]),
      ),
      if (_taps.isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
              onPressed: () => setState(() {
                    _taps.clear();
                    _color = null;
                    _line = const [];
                  }),
              child: const T('Обвести заново')),
        ),
      if (s != null) ...[
        const SizedBox(height: 6),
        Text(t('{n} точок, {a} … {b} м від осі; краї: {za} і {zb} м', {
          'n': s.length,
          'a': s.first.$1.toStringAsFixed(1),
          'b': s.last.$1.toStringAsFixed(1),
          'za': s.first.$2.toStringAsFixed(2),
          'zb': s.last.$2.toStringAsFixed(2),
        })),
      ],
      const SizedBox(height: 8),
      FilledButton.icon(
        onPressed: s == null || _pk == null ? null : _save,
        icon: const Icon(Icons.check),
        label: Text(_pk == null ? t('Зберегти поперечник') : t('Зберегти поперечник {pk}', {'pk': pk(_pk!)})),
      ),
      if (_vec.isNotEmpty) ...[
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _takeAll,
          icon: const Icon(Icons.auto_awesome),
          label: Text(_pickedRgb == null
              ? t('Взяти всі поперечники (спершу торкніться лінії на одному)')
              : t('Взяти всі поперечники з PDF')),
        ),
      ],
      const SizedBox(height: 8),
      Text(t('Обведено: {n}. Масштаби переходять на наступні сторінки того самого розміру.',
          {'n': _done.length}), style: const TextStyle(color: Colors.black54)),
    ]);
  }

  Widget _step(String n, String status, String action, VoidCallback onPressed) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          CircleAvatar(radius: 12, child: Text(n, style: const TextStyle(fontSize: 12))),
          const SizedBox(width: 12),
          Expanded(child: Text(status)),
          OutlinedButton(onPressed: onPressed, child: Text(action)),
        ]),
      );
}

class _Overlay extends CustomPainter {
  final List<Vec> calib, taps, line;
  final Vec? axis;
  final double k; // 1 / масштаб — щоб лінії й точки були однакові на екрані
  _Overlay(this.calib, this.axis, this.taps, this.line, this.k);

  @override
  void paint(Canvas canvas, Size size) {
    if (line.length >= 2) {
      final path = Path()..moveTo(line.first.x, line.first.y);
      for (final p in line.skip(1)) {
        path.lineTo(p.x, p.y);
      }
      // Вибрана лінія — товстою зеленою (напівпрозорою, щоб під нею було видно креслення): видно, що взялася вся.
      // Щонайменше 5 пікселів аркуша — при наближенні ширша за саму лінію креслення, а не тонша.
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(18 * k, 5)
            ..strokeJoin = StrokeJoin.round
            ..strokeCap = StrokeCap.round
            ..color = const Color(0x9900C853));
    }
    for (final p in taps) {
      canvas.drawCircle(Offset(p.x, p.y), 4 * k, Paint()..color = const Color(0xFF1565C0));
    }
    final purple = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5 * k
      ..color = const Color(0xFF6A1B9A);
    for (final p in calib) {
      canvas.drawLine(Offset(p.x, p.y - 30 * k), Offset(p.x, p.y + 30 * k), purple);
    }
    final a = axis;
    if (a != null) {
      // Вісь — синя (зелена — вибрана лінія).
      final blue = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 * k
        ..color = const Color(0xFF1565C0);
      canvas.drawLine(Offset(a.x, a.y - 60 * k), Offset(a.x, a.y + 60 * k), blue);
      canvas.drawCircle(Offset(a.x, a.y), 8 * k, blue);
    }
  }

  @override
  bool shouldRepaint(_Overlay old) => true;
}
