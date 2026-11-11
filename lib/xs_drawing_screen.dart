// Поперечники з креслення (DXF): людина вибирає шари й вертикальне перебільшення, бачить, скільки
// поперечників вийшло й точки першого, — і лише тоді додає до об'єкта.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'chainage.dart';
import 'dxf.dart';
import 'i18n.dart';
import 'problem_card.dart';
import 'problems.dart';
import 'profile.dart';
import 'xs_drawing.dart';
import 'keyboards.dart';

class XsDrawingScreen extends StatefulWidget {
  final Uint8List dxf;
  final String fileName;
  final ChainageStyle style;

  /// Поздовжній профіль об'єкта — відмітка осі для поперечників, у підписі яких її немає.
  final Profile? profile;
  const XsDrawingScreen(
      {super.key, required this.dxf, required this.fileName, required this.style, this.profile});

  @override
  State<XsDrawingScreen> createState() => _XsDrawingScreenState();
}

class _XsDrawingScreenState extends State<XsDrawingScreen> {
  DxfDrawing? _d;
  Problem? _error;
  String? _design, _labels, _axis;
  /// Масштаби, як на кресленні: 1:[_h] по горизонталі, 1:[_vs] по вертикалі; не вписано — однакові.
  final _h = TextEditingController(), _vs = TextEditingController();
  String? _vNote;

  @override
  void initState() {
    super.initState();
    _parse();
  }

  Future<void> _parse() async {
    try {
      final d = await compute(parseDxf, widget.dxf);
      final g = guessXsLayers(d);
      final v = guessVScale(d, layer: g?.labels);
      setState(() {
        _d = d;
        _design = g?.design;
        _labels = g?.labels;
        _axis = g?.axis;
        if (v != null) {
          // «H 1:100 V 1:10» — масштаби як є; інший запис — горизонталь у стільки разів дрібніша.
          final h = RegExp(r'H\s*1\s*:\s*(\d+)', caseSensitive: false).firstMatch(v.$2);
          final vv = RegExp(r'V\s*1\s*:\s*(\d+)', caseSensitive: false).firstMatch(v.$2);
          if (h != null && vv != null) {
            _h.text = h[1]!;
            _vs.text = vv[1]!;
          } else {
            _h.text = v.$1 == v.$1.roundToDouble() ? v.$1.toStringAsFixed(0) : v.$1.toString();
            _vs.text = '1';
          }
          _vNote = v.$2;
        }
      });
    } on DxfException catch (e) {
      setState(() => _error = e.problem);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return Scaffold(
      appBar: AppBar(title: Text(t('Поперечники: {f}', {'f': widget.fileName}))),
      body: _error != null
          ? ListView(padding: const EdgeInsets.all(16), children: [ProblemCard(_error!)])
          : d == null
              ? const Center(child: CircularProgressIndicator())
              : _body(d),
    );
  }

  Widget _body(DxfDrawing d) {
    final lineLayers = [for (final l in d.layers.values) if (l.segments.isNotEmpty) l.name]..sort();
    final labelLayers = [for (final l in d.layers.values) if (l.labels.isNotEmpty) l.name]..sort();
    double? n(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.'));
    final hs = n(_h), vs = n(_vs);
    // У скільки разів вертикаль крупніша: H 1:100, V 1:10 → 10; не вписано — однаково.
    final v = hs == null || vs == null ? 1.0 : (hs > 0 && vs > 0 ? hs / vs : null);
    final ready = _design != null && _labels != null && _axis != null && v != null;
    final r = ready
        ? sectionsFromDrawing(d, XsLayers(_design!, _labels!, _axis!),
            vScale: v, profile: widget.profile, source: 'DXF: ${widget.fileName}')
        : null;
    final cs = r?.sections;
    Widget pick(String label, String? value, List<String> items, ValueChanged<String?> on) => Row(children: [
          SizedBox(width: 170, child: Text(label)),
          Expanded(
            child: DropdownButton<String>(
              isExpanded: true,
              value: items.contains(value) ? value : null,
              hint: const T('— виберіть шар —'),
              items: [for (final n in items) DropdownMenuItem(value: n, child: Text(n))],
              onChanged: (x) => setState(() => on(x)),
            ),
          ),
        ]);
    return ListView(padding: const EdgeInsets.all(16), children: [
      const T('Біля кожного поперечника в кресленні: підпис з ПК (і, буває, відміткою осі «Z=…»), вертикаль осі '
          'й лінія проєкту. Програма вибрала шари за назвами — перевірте.'),
      const SizedBox(height: 8),
      pick(t('Лінія проєкту'), _design, lineLayers, (x) => _design = x),
      pick(t('Підписи ПК'), _labels, labelLayers, (x) => _labels = x),
      pick(t('Вісь поперечника'), _axis, lineLayers, (x) => _axis = x),
      for (final (label, c) in [(t('Горизонтальний масштаб 1:'), _h), (t('Вертикальний масштаб 1:'), _vs)])
        Row(children: [
          SizedBox(width: 220, child: Text(label)),
          SizedBox(
            width: 90,
            child: TextField(
              controller: c,
              keyboardType: numberKeyboard,
              onChanged: (_) => setState(() {}),
            ),
          ),
        ]),
      Text(
          _vNote == null
              ? t('Напису масштабу не знайдено — впишіть масштаби з креслення (однакові — можна не вписувати).')
              : t('З напису в кресленні: «{n}».', {'n': _vNote!}),
          style: const TextStyle(color: Colors.black54)),
      if (widget.profile == null)
        const T('Профілю в об’єкта немає: поперечники без відмітки осі в підписі буде пропущено.',
            style: TextStyle(color: Colors.black54)),
      const SizedBox(height: 8),
      if (r != null) for (final p in r.problems) ProblemCard(p),
      if (cs != null) ...[
        Text(t('Поперечників: {n} (точок {p}), ПК {a}–{b} м.', {
          'n': cs.rows.length,
          'p': r!.pointsUsed,
          'a': cs.startStation.toStringAsFixed(1),
          'b': cs.endStation.toStringAsFixed(1),
        })),
        const SizedBox(height: 8),
        Text(t('Перший — {pk}: зміщення → відмітка', {'pk': formatStation(cs.rows.first.$1, widget.style)}),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        Wrap(spacing: 12, children: [
          for (final p in cs.rows.first.$2) Text('${p.$1.toStringAsFixed(2)} → ${p.$2.toStringAsFixed(2)}'),
        ]),
      ],
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: cs == null || r!.problems.any((p) => p.severity == Severity.error)
            ? null
            : () => Navigator.of(context).pop(cs),
        icon: const Icon(Icons.check),
        label: const T('Додати до об’єкта'),
      ),
    ]);
  }
}
