// Новий об'єкт з LandXML: вісь (з її ПК початку) і профіль — одним файлом; перевірка на карті.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import 'axis_map.dart';
import 'chainage.dart';
import 'crs.dart';
import 'crs_picker.dart';
import 'geometry.dart';
import 'i18n.dart';
import 'landxml.dart';
import 'problem_card.dart';
import 'problems.dart';
import 'road_object.dart';

class LandXmlImportScreen extends StatefulWidget {
  final String fileName;
  final Uint8List bytes;
  const LandXmlImportScreen({super.key, required this.fileName, required this.bytes});

  @override
  State<LandXmlImportScreen> createState() => _LandXmlImportScreenState();
}

class _LandXmlImportScreenState extends State<LandXmlImportScreen> {
  List<LxAlignment> _axes = [];
  Problem? _error;
  LxAlignment? _a;
  CoordSystem _crs = stereo70;
  bool _swap = false;
  ChainageStyle _style = ChainageStyle.pk;
  final _nameCtl = TextEditingController();
  final _map = MapController();
  AxisView? _view;
  Placement? _placement;

  @override
  void initState() {
    super.initState();
    try {
      _axes = parseLandXml(widget.bytes);
      _select(_axes.first);
    } on LandXmlException catch (e) {
      _error = e.problem;
    }
  }

  void _select(LxAlignment a) {
    _a = a;
    _nameCtl.text = a.name;
    _placement = checkPlacement(_crs, a.segs);
    _swap = _placement == Placement.swapped;
    _rebuild();
  }

  List<Segment> _segs() => _swap ? [for (final s in _a!.segs) s.swapXY()] : _a!.segs;

  void _rebuild() {
    final v = AxisView.of(RoadAxis(_segs(), startStation: _a!.staStart), _crs, _style);
    setState(() => _view = v);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _map.fitCamera(CameraFit.bounds(bounds: v.bounds, padding: axisFitPadding));
      } catch (_) {
        // Карта ще не намальована — підлаштується сама.
      }
    });
  }

  Future<void> _save() async {
    final a = _a!;
    final o = RoadObject(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: _nameCtl.text.trim().isEmpty ? a.name : _nameCtl.text.trim(),
      sourceFile: widget.fileName,
      axisLayer: 'LandXML: ${a.name}',
      crsId: _crs.id,
      startStation: a.staStart,
      style: _style,
      axis: _segs(),
      profile: a.profiles.firstOrNull,
      crossSections: a.sections,
      created: DateTime.now(),
    );
    await objectStore.save(o);
    if (mounted) Navigator.of(context).pop(o);
  }

  @override
  Widget build(BuildContext context) {
    final err = _error;
    if (err != null) {
      return Scaffold(
        appBar: AppBar(title: Text('LandXML: ${widget.fileName}')),
        body: ListView(padding: const EdgeInsets.all(16), children: [ProblemCard(err)]),
      );
    }
    final a = _a!;
    final v = _view;
    final form = ListView(padding: const EdgeInsets.all(16), children: [
      if (_axes.length > 1)
        DropdownButtonFormField<LxAlignment>(
          initialValue: a,
          isExpanded: true,
          decoration: InputDecoration(labelText: t('Вісь'), border: const OutlineInputBorder()),
          items: [for (final x in _axes) DropdownMenuItem(value: x, child: Text(x.name))],
          onChanged: (x) => x == null ? null : _select(x),
        ),
      const SizedBox(height: 8),
      Text(t('Вісь «{name}»: {len} м, ПК початку {pk}.',
          {'name': a.name, 'len': a.length.toStringAsFixed(1), 'pk': formatStation(a.staStart, _style)})),
      Text(a.profiles.isEmpty
          ? t('Профілю в файлі немає — відмітки можна додати пізніше з відомості.')
          : t('Профіль: {name} (точок {n}).', {
              'name': a.profiles.first.source.replaceFirst('LandXML: ', ''),
              'n': a.profiles.first.pvis.length,
            })),
      if (a.sections != null) Text(t('Поперечників з відмітками: {n}.', {'n': a.sections!.rows.length})),
      for (final p in a.problems) ProblemCard(p),
      if (_placement == Placement.outside && !_crs.calibrated) const ProblemCard(outsideCountry),
      const SizedBox(height: 8),
      CrsPicker(
        value: _crs,
        segs: a.segs,
        onChanged: (c, swap) {
          _crs = c;
          _swap = swap;
          _placement = checkPlacement(c, a.segs);
          _rebuild();
        },
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const T('Поміняти місцями X і Y'),
        subtitle: const T('Якщо вісь на карті не там, де дорога'),
        value: _swap,
        onChanged: _crs.calibrated ? null : (x) {
          _swap = x;
          _rebuild();
        },
      ),
      Row(children: [
        const T('Запис пікетажу: '),
        SegmentedButton<ChainageStyle>(
          segments: const [
            ButtonSegment(value: ChainageStyle.pk, label: T('ПК')),
            ButtonSegment(value: ChainageStyle.km, label: T('км')),
          ],
          selected: {_style},
          onSelectionChanged: (s) {
            _style = s.first;
            _rebuild();
          },
        ),
      ]),
      const SizedBox(height: 8),
      TextField(controller: _nameCtl, decoration: InputDecoration(labelText: t('Назва об’єкта'), border: const OutlineInputBorder())),
      const SizedBox(height: 16),
      FilledButton.icon(onPressed: _save, icon: const Icon(Icons.check), label: const T('Вісь на карті там, де треба — зберегти')),
    ]);
    final map = v == null
        ? const SizedBox()
        : AxisMap(view: v, controller: _map, pins: [
            (v.axis.first, t('Початок {pk}', {'pk': formatStation(a.staStart, _style)}), const Color(0xFF2E7D32)),
            (v.axis.last, t('Кінець {pk}', {'pk': formatStation(a.staStart + a.length, _style)}), const Color(0xFF1565C0)),
          ]);
    return Scaffold(
      appBar: AppBar(title: Text('LandXML: ${widget.fileName}')),
      body: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth > c.maxHeight && c.maxWidth > 700;
        return wide
            ? Row(children: [SizedBox(width: 420, child: form), Expanded(child: map)])
            : Column(children: [Expanded(flex: 5, child: form), Expanded(flex: 4, child: map)]);
      }),
    );
  }
}
