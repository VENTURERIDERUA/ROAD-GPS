// Новий об'єкт з DXF: шар осі → ПК початку й напрям → система координат → перевірка на карті.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import 'axis_map.dart';
import 'chainage.dart';
import 'crs.dart';
import 'crs_picker.dart';
import 'dxf.dart';
import 'geometry.dart';
import 'i18n.dart';
import 'lines.dart';
import 'problem_card.dart';
import 'problems.dart';
import 'road_object.dart';
import 'keyboards.dart';

class ImportScreen extends StatefulWidget {
  final String fileName;
  final Uint8List bytes;

  /// Файл як вибрано (за замовчуванням — [bytes]); зберігається з об'єктом.
  final Uint8List? original;
  const ImportScreen({super.key, required this.fileName, required this.bytes, this.original});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

/// Шар, схожий на вісь, за назвою: «Ax», «Axa», «Axis», «Вісь», «Ось», «CL»…
final _axisName = RegExp(r'(^|[^a-zа-яіїє])(ax|axa|axis|вісь|ось|cl|centerline|center line)([^a-zа-яіїє]|$)',
    caseSensitive: false, unicode: true);

class _ImportScreenState extends State<ImportScreen> {
  DxfDrawing? _drawing;
  Problem? _error;
  List<DxfLayer> _layers = [];
  DxfLayer? _layer;
  ChainResult? _chain;
  StartGuess? _guess;
  Placement? _placement;

  CoordSystem _crs = stereo70;
  bool _swap = false;
  bool _reversed = false;
  ChainageStyle _style = ChainageStyle.pk;
  final _startCtl = TextEditingController();
  final _nameCtl = TextEditingController();
  String? _startError;

  /// Роль кожного шару (null — не брати) і лінії шару, зібрані один раз.
  final Map<String, LineRole?> _roles = {};
  final Map<String, List<RoadLine>> _layerLines = {};
  bool _allLayers = false;

  AxisView? _view;
  final _map = MapController();

  @override
  void initState() {
    super.initState();
    _nameCtl.text = widget.fileName.replaceAll(RegExp(r'\.dxf$', caseSensitive: false), '');
    _parse();
  }

  Future<void> _parse() async {
    try {
      final d = await compute(parseDxf, widget.bytes);
      final layers = d.layers.values.where((l) => l.segments.isNotEmpty).toList()
        ..sort((a, b) {
          final ga = _axisName.hasMatch(a.name) ? 0 : 1, gb = _axisName.hasMatch(b.name) ? 0 : 1;
          return ga != gb ? ga - gb : b.length.compareTo(a.length);
        });
      setState(() {
        _drawing = d;
        _layers = layers;
        for (final l in layers) {
          _roles[l.name] = guessRole(l.name);
        }
      });
      if (layers.isEmpty) {
        setState(() => _error = noLines);
      } else {
        _selectLayer(layers.first);
      }
    } on DxfException catch (e) {
      setState(() => _error = e.problem);
    } on FormatException catch (e) {
      setState(() => _error = notDxf(e.message));
    } catch (e) {
      setState(() => _error = notDxf('$e'));
    }
  }

  void _selectLayer(DxfLayer l) {
    final chain = buildChain(l.segments);
    // Підписи ПК — спершу на шарі осі; немає там — з усіх шарів (часто окремий шар «PK_TEXT»).
    final guess = guessStart(chain.segments, l.labels) ??
        guessStart(chain.segments, [for (final x in _drawing!.layers.values) ...x.labels]);
    final placement = chain.segments.isEmpty ? null : checkPlacement(_crs, chain.segments);
    setState(() {
      _layer = l;
      _chain = chain;
      _guess = guess;
      _placement = placement;
      _swap = placement == Placement.swapped;
      _reversed = guess?.reversed ?? false;
      _style = guess?.style ?? ChainageStyle.pk;
      _startCtl.text = formatStation(guess?.startStation ?? 0, _style).split(' ').last;
    });
    _rebuildView(fit: true);
  }

  double? _startValue() {
    final t = _startCtl.text.trim();
    final label = parseChainageLabel(t);
    if (label != null) return label.$1;
    return double.tryParse(t.replaceAll(',', '.'));
  }

  /// Вісь так, як її буде збережено: X — схід, Y — північ, напрям — за зростанням ПК.
  List<Segment> _finalSegments() {
    var segs = _chain!.segments;
    if (_swap) segs = [for (final s in segs) s.swapXY()];
    if (_reversed) segs = [for (final s in segs.reversed) s.reversed()];
    return segs;
  }

  /// Вибрані лінії (крім шару осі) у тих самих координатах, що й вісь.
  List<RoadLine> _finalLines() {
    final out = <RoadLine>[];
    for (final l in _layers) {
      final role = _roles[l.name];
      if (role == null || l == _layer) continue;
      final lines = _layerLines[l.name] ??= linesOfLayer(LineRole.other, l.name, l.segments);
      out.addAll([for (final x in lines) RoadLine(role, x.layer, _swap ? x.swapXY().segs : x.segs)]);
    }
    return out;
  }

  void _rebuildView({bool fit = false}) {
    final start = _startValue();
    setState(() => _startError = start == null ? t('Приклад: 0+000, 125+43.2 або 12543.2') : null);
    if (_chain == null || _chain!.segments.isEmpty || start == null) return;
    final view = AxisView.of(RoadAxis(_finalSegments(), startStation: start), _crs, _style, _finalLines());
    setState(() => _view = view);
    if (fit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          _map.fitCamera(CameraFit.bounds(bounds: view.bounds, padding: axisFitPadding));
        } catch (_) {
          // Карта ще не намальована — підлаштується сама при першому показі.
        }
      });
    }
  }

  Future<void> _save() async {
    final start = _startValue();
    if (start == null || _chain == null) return;
    final o = RoadObject(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: _nameCtl.text.trim().isEmpty ? widget.fileName : _nameCtl.text.trim(),
      sourceFile: widget.fileName,
      axisLayer: _layer!.name,
      crsId: _crs.id,
      startStation: start,
      style: _style,
      axis: _finalSegments(),
      lines: _finalLines(),
      created: DateTime.now(),
    );
    await objectStore.save(o);
    await objectStore.saveDrawing(o.id, widget.original ?? widget.bytes);
    if (mounted) Navigator.of(context).pop(o);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('Новий об\'єкт: {name}', {'name': widget.fileName}))),
      body: _error != null
          ? ListView(padding: const EdgeInsets.all(16), children: [
              ProblemCard(_error!),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back),
                  label: const T('Вибрати інший файл'),
                ),
              ),
            ])
          : _drawing == null
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(builder: (context, c) {
                  final wide = c.maxWidth > c.maxHeight && c.maxWidth > 700;
                  final form = _form(context);
                  final map = _mapPreview();
                  return wide
                      ? Row(children: [SizedBox(width: 420, child: form), Expanded(child: map)])
                      : Column(children: [Expanded(flex: 5, child: form), Expanded(flex: 4, child: map)]);
                }),
    );
  }

  Widget _mapPreview() {
    final v = _view;
    if (v == null) return _Message(t('Тут з\'явиться вісь на карті.'));
    final st = _startValue() ?? 0;
    final len = _chain!.segments.fold(0.0, (a, s) => a + s.length);
    return AxisMap(
      key: ValueKey(_layer?.name),
      view: v,
      controller: _map,
      pins: [
        (v.axis.first, t('Початок {pk}', {'pk': formatStation(st, _style)}), const Color(0xFF2E7D32)),
        (v.axis.last, t('Кінець {pk}', {'pk': formatStation(st + len, _style)}), const Color(0xFF1565C0)),
      ],
    );
  }

  Widget _form(BuildContext context) {
    final chain = _chain;
    final l = _layer;
    final theme = Theme.of(context);
    final len = chain?.segments.fold(0.0, (a, s) => a + s.length) ?? 0;
    return ListView(padding: const EdgeInsets.all(16), children: [
      for (final p in _drawing!.problems) ProblemCard(p),
      Text(t('1. Шар з віссю'), style: theme.textTheme.titleMedium),
      const SizedBox(height: 6),
      DropdownButtonFormField<DxfLayer>(
        initialValue: l,
        isExpanded: true,
        decoration: const InputDecoration(border: OutlineInputBorder()),
        items: [
          for (final x in _layers)
            DropdownMenuItem(
              value: x,
              child: Text('${x.name} — ${t('{n} км', {'n': (x.length / 1000).toStringAsFixed(2)})}',
                  overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (x) => x == null ? null : _selectLayer(x),
      ),
      if (l != null && chain != null) ...[
        const SizedBox(height: 8),
        _Note(t('Вісь: {len} м з {n} шматків ({what}).',
            {'len': len.toStringAsFixed(1), 'n': chain.usedPieces, 'what': _describe(l.counts)})),
        if (chain.ignoredPieces > 0 && chain.secondLength <= _brokenAxis)
          _Note(t(
              'Пропущено {n} окремих шматків (разом {len} м), '
              'не з\'єднаних з віссю, — зазвичай це риски пікетів.',
              {'n': chain.ignoredPieces, 'len': chain.ignoredLength.toStringAsFixed(0)})),
        if (chain.secondLength > _brokenAxis) ProblemCard(axisBroken(len, l.length, chain.secondLength)),
        if (chain.branchNodes > 0) ProblemCard(axisBranches(chain.branchNodes)),
        if (chain.closed) const ProblemCard(axisClosed),
        if (l.unreadable > 0) ProblemCard(unreadableOnLayer(l.name, l.unreadableKinds)),
      ],
      const SizedBox(height: 16),
      Text(t('2. Система координат'), style: theme.textTheme.titleMedium),
      const SizedBox(height: 6),
      CrsPicker(
        value: _crs,
        segs: chain?.segments ?? const [],
        onChanged: (c, swap) {
          _crs = c;
          _swap = swap;
          _placement = chain == null || chain.segments.isEmpty ? null : checkPlacement(c, chain.segments);
          _rebuildView(fit: true);
        },
      ),
      if (_placement == Placement.outside && !_crs.calibrated) const ProblemCard(outsideCountry),
      if (_placement == Placement.swapped && !_crs.calibrated)
        _Note(t('X і Y у файлі, схоже, переставлені — програма поміняла їх місцями. Перевірте на карті.'),
            warn: true),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const T('Поміняти місцями X і Y'),
        subtitle: const T('Якщо вісь на карті не там, де дорога'),
        value: _swap,
        onChanged: _crs.calibrated ? null : (v) {
          _swap = v;
          _rebuildView(fit: true);
        },
      ),
      const SizedBox(height: 8),
      Text(t('3. Пікетаж'), style: theme.textTheme.titleMedium),
      const SizedBox(height: 6),
      if (_guess == null)
        const ProblemCard(noLabels)
      else if (!_guess!.exact && _guess!.spread > 5)
        ProblemCard(labelsDisagree(_guess!.spread))
      else
        _Note(_guess!.exact
            ? t('ПК початку взято з підпису біля початку осі (підписів: {n}).', {'n': _guess!.labelsUsed})
            : t('ПК початку оцінено за {n} підписами (розкид {s} м) — перевірте.',
                {'n': _guess!.labelsUsed, 's': _guess!.spread.toStringAsFixed(1)})),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _startCtl,
            decoration: InputDecoration(
              labelText: t('ПК початку'),
              border: const OutlineInputBorder(),
              errorText: _startError,
            ),
            readOnly: true,
            showCursor: true,
            onTap: () => showDigitPad(context, _startCtl, label: t('ПК початку'), onChanged: (_) => _rebuildView()),
          ),
        ),
        const SizedBox(width: 12),
        SegmentedButton<ChainageStyle>(
          segments: const [
            ButtonSegment(value: ChainageStyle.pk, label: T('ПК')),
            ButtonSegment(value: ChainageStyle.km, label: T('км')),
          ],
          selected: {_style},
          onSelectionChanged: (s) {
            final start = _startValue();
            _style = s.first;
            if (start != null) _startCtl.text = formatStation(start, _style).split(' ').last;
            _rebuildView();
          },
        ),
      ]),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const T('Пікетаж іде з іншого кінця'),
        subtitle: const T('Зелена позначка «Початок» має бути на ПК початку'),
        value: _reversed,
        onChanged: (v) {
          _reversed = v;
          _rebuildView();
        },
      ),
      const SizedBox(height: 8),
      Text(t('4. Кромки, бровки, межі відводу'), style: theme.textTheme.titleMedium),
      ..._linesSection(),
      const SizedBox(height: 8),
      Text(t('5. Назва об\'єкта'), style: theme.textTheme.titleMedium),
      const SizedBox(height: 6),
      TextField(controller: _nameCtl, decoration: const InputDecoration(border: OutlineInputBorder())),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: chain == null || chain.segments.isEmpty || _startError != null ? null : _save,
        icon: const Icon(Icons.check),
        label: const T('Вісь на карті там, де треба — зберегти'),
      ),
    ]);
  }

  List<Widget> _linesSection() {
    final others = _layers.where((l) => l != _layer).toList();
    final guessed = others.where((l) => guessRole(l.name) != null).toList();
    final rest = others.where((l) => guessRole(l.name) == null).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return [
      _Note(guessed.isEmpty
          ? t('За назвами шарів кромок і меж не знайдено — виберіть роль потрібним шарам у списку нижче.')
          : t('Програма позначила шари за назвами — перевірте. Лінії видно на карті своїм кольором.')),
      for (final l in guessed) _layerRow(l),
      if (rest.isNotEmpty)
        TextButton.icon(
          onPressed: () => setState(() => _allLayers = !_allLayers),
          icon: Icon(_allLayers ? Icons.expand_less : Icons.expand_more),
          label: Text(_allLayers ? t('Сховати решту шарів') : t('Решта шарів ({n})', {'n': rest.length})),
        ),
      if (_allLayers) for (final l in rest) _layerRow(l),
    ];
  }

  Widget _layerRow(DxfLayer l) {
    final role = _roles[l.name];
    return Row(children: [
      Container(width: 14, height: 4, color: role?.color ?? Colors.transparent),
      const SizedBox(width: 8),
      Expanded(
        child: Text('${l.name} — ${t('{n} км', {'n': (l.length / 1000).toStringAsFixed(2)})}',
            overflow: TextOverflow.ellipsis),
      ),
      DropdownButton<LineRole?>(
        value: role,
        underline: const SizedBox(),
        items: [
          const DropdownMenuItem(value: null, child: T('не брати')),
          for (final r in LineRole.values) DropdownMenuItem(value: r, child: Text(t(r.label))),
        ],
        onChanged: (r) {
          _roles[l.name] = r;
          _rebuildView();
        },
      ),
    ]);
  }
}

String _describe(Map<String, int> counts) {
  const names = {
    'LINE': 'відрізків',
    'ARC': 'дуг',
    'LWPOLYLINE': 'поліліній',
    'POLYLINE': 'поліліній',
    'TEXT': 'підписів',
    'MTEXT': 'підписів',
  };
  final merged = <String, int>{};
  for (final e in counts.entries) {
    final n = names[e.key] ?? 'інших';
    merged[n] = (merged[n] ?? 0) + e.value;
  }
  return merged.entries.map((e) => '${e.value} ${t(e.key)}').join(', ');
}

class _Note extends StatelessWidget {
  final String text;
  final bool warn;
  const _Note(this.text, {this.warn = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(warn ? Icons.warning_amber : Icons.info_outline,
              size: 18, color: warn ? Colors.orange.shade800 : Colors.black54),
          const SizedBox(width: 6),
          Expanded(child: Text(text)),
        ]),
      );
}

/// Найдовший з решти шматків довший за це — вісь розірвана, а не просто риски пікетів.
const _brokenAxis = 20.0;

class _Message extends StatelessWidget {
  final String text;
  const _Message(this.text);

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: Colors.black54)),
        ),
      );
}
