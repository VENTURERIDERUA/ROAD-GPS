// Вибір системи координат на екранах імпорту: список за країнами, «підходять для цієї осі»,
// і калібрування за точками, коли системи креслення немає в списку (умовна, місцева).
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'crs.dart';
import 'geometry.dart';
import 'i18n.dart';
import 'map_layers.dart';
import 'problem_card.dart';
import 'problems.dart';
import 'keyboards.dart';

/// Поточна система й кнопка «Змінити». [segs] — вісь у координатах файлу (без перестановки X/Y).
class CrsPicker extends StatelessWidget {
  final CoordSystem value;
  final List<Segment> segs;
  final void Function(CoordSystem c, bool swap) onChanged;
  const CrsPicker({super.key, required this.value, required this.segs, required this.onChanged});

  Future<void> _choose(BuildContext context) async {
    final fit = segs.isEmpty ? const <(CoordSystem, Placement)>[] : suggestCoordSystems(segs);
    final picked = await showModalBottomSheet<(CoordSystem, bool)?>(
      context: context,
      isScrollControlled: true,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        builder: (c, scroll) => RadioGroup<String>(
          groupValue: value.id,
          onChanged: (id) {
            final s = coordSystems.firstWhere((x) => x.id == id);
            Navigator.pop(c, (s, checkPlacement(s, segs) == Placement.swapped));
          },
          child: ListView(controller: scroll, children: [
          const ListTile(title: T('Система координат креслення', style: TextStyle(fontWeight: FontWeight.bold))),
          if (fit.isNotEmpty) ...[
            _Head(t('Підходять для цієї осі (вісь лягає в межі країни)')),
            for (final (s, p) in fit)
              ListTile(
                leading: const Icon(Icons.check_circle_outline, color: Color(0xFF2E7D32)),
                title: Text(crsName(s)),
                subtitle: Text([crsGroup(s), if (p == Placement.swapped) t('X і Y у файлі переставлені')].join(' · ')),
                onTap: () => Navigator.pop(c, (s, p == Placement.swapped)),
              ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: T('Кілька варіантів — звична річ: у сусідніх зонах ті самі числа. Перевірте вісь на карті.',
                  style: TextStyle(color: Colors.black54)),
            ),
          ] else if (segs.isNotEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: T('Жодна система зі списку не кладе вісь у межі країни — схоже, креслення в умовних '
                  '(місцевих) координатах. Прив’яжіть його за точками — пункт унизу.'),
            ),
          for (final g in {for (final s in coordSystems) s.group}) ...[
            _Head(t(g)),
            for (final s in coordSystems.where((s) => s.group == g))
              RadioListTile<String>(
                value: s.id,
                title: Text(crsName(s)),
                subtitle: Text(t('точність перерахунку ±{n} м', {'n': s.accuracyM.toStringAsFixed(0)})),
              ),
          ],
          _Head(t('Немає в списку')),
          ListTile(
            leading: const Icon(Icons.my_location),
            title: const T('Калібрувати за точками…'),
            subtitle: const T('Умовні чи місцеві координати: 2–4 точки креслення, які ви знайдете на місцевості'),
            onTap: () async {
              final cal = await Navigator.of(c).push<CoordSystem>(
                  MaterialPageRoute(builder: (_) => CalibrationScreen(segs: segs)));
              if (cal != null && c.mounted) Navigator.pop(c, (cal, false));
            },
          ),
          const SizedBox(height: 24),
        ]),
        ),
      ),
    );
    if (picked != null) onChanged(picked.$1, picked.$2);
  }

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          title: Text(crsName(value)),
          subtitle: Text([
            if (value.group.isNotEmpty) crsGroup(value),
            t('точність перерахунку ±{n} м', {'n': value.accuracyM.toStringAsFixed(0)}),
          ].join(' · ')),
          trailing: OutlinedButton(onPressed: () => _choose(context), child: const T('Змінити')),
        ),
      );
}

class _Head extends StatelessWidget {
  final String text;
  const _Head(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.black54)),
      );
}

// ---------- Калібрування ----------

enum _Where { start, end, middle, typed }

class _Pair {
  _Where where;
  final x = TextEditingController(), y = TextEditingController(), real = TextEditingController();
  _Pair(this.where);
}

/// «Широта, довгота» — як копіюють з Google Maps чи GPS-програми: «44.4512, 26.1035» або «44.4512 26.1035».
LatLng? parseLatLon(String s) {
  final m = RegExp(r'(-?\d{1,2}(?:[.,]\d+)?)\s*[,; ]\s*(-?\d{1,3}(?:[.,]\d+)?)').firstMatch(s.trim());
  if (m == null) return null;
  final a = double.parse(m[1]!.replaceAll(',', '.')), b = double.parse(m[2]!.replaceAll(',', '.'));
  if (a.abs() > 90 || b.abs() > 180) return null;
  return LatLng(a, b);
}

class CalibrationScreen extends StatefulWidget {
  final List<Segment> segs;
  const CalibrationScreen({super.key, required this.segs});

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  late final _pairs = [_Pair(_Where.start), _Pair(_Where.end)];

  Vec? _drawing(_Pair p) {
    final s = widget.segs;
    switch (p.where) {
      case _Where.start:
        return s.isEmpty ? null : s.first.start;
      case _Where.end:
        return s.isEmpty ? null : s.last.end;
      case _Where.middle:
        if (s.isEmpty) return null;
        final ax = RoadAxis(s);
        return ax.pointAtStation(ax.startStation + (ax.endStation - ax.startStation) / 2);
      case _Where.typed:
        final x = double.tryParse(p.x.text.replaceAll(',', '.').replaceAll(' ', ''));
        final y = double.tryParse(p.y.text.replaceAll(',', '.').replaceAll(' ', ''));
        return x == null || y == null ? null : Vec(x, y);
    }
  }

  List<(Vec, LatLng)> get _complete => [
        for (final p in _pairs)
          if ((_drawing(p), parseLatLon(p.real.text)) case (final Vec d, final LatLng r)) (d, r),
      ];

  Future<void> _gps(_Pair p) async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        if (mounted) await showProblemDialog(context, gpsDenied);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.best));
      setState(() => p.real.text = '${pos.latitude.toStringAsFixed(7)}, ${pos.longitude.toStringAsFixed(7)}');
      if (pos.accuracy > 5 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(t(
                'GPS зараз ±{n} м — зачекайте хвилину й натисніть ще раз, '
                'щоб калібрування було точнішим.',
                {'n': pos.accuracy.toStringAsFixed(0)}))));
      }
    } catch (e) {
      if (mounted) {
        await showProblemDialog(context, Problem(Severity.error, 'GPS не дав місця', detail: '$e',
            fixes: const ['Увімкніть геолокацію й спробуйте ще раз.', 'Або виберіть точку на карті.']));
      }
    }
  }

  Future<void> _onMap(_Pair p) async {
    final known = [for (final x in _pairs) ?parseLatLon(x.real.text)];
    final r = await Navigator.of(context).push<LatLng>(MaterialPageRoute(
        builder: (_) => MapPickScreen(start: parseLatLon(p.real.text) ?? known.firstOrNull)));
    if (r != null) {
      setState(() => p.real.text = '${r.latitude.toStringAsFixed(7)}, ${r.longitude.toStringAsFixed(7)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = _complete;
    Calibration? cal;
    String? fail;
    if (done.length >= 2) {
      try {
        cal = fitCalibration(done);
      } catch (e) {
        fail = t('Точки креслення збігаються — виберіть різні.');
      }
    }
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const T('Калібрування за точками')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const T('Для кожної точки: що це на кресленні (початок чи кінець осі, або координати з креслення) і де вона '
            'на місцевості — станьте на неї з телефоном («Мій GPS»), виберіть на карті чи вставте «широта, довгота» '
            '(з Google Maps, з геодезичного звіту). Дві точки — мінімум; три-чотири, якомога далі одна від одної, — '
            'видно похибку кожної.'),
        const SizedBox(height: 12),
        for (final (i, p) in _pairs.indexed)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(t('Точка {n}', {'n': i + 1}), style: theme.textTheme.titleMedium),
                  const Spacer(),
                  if (_pairs.length > 2)
                    IconButton(
                        tooltip: t('Прибрати точку'),
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => setState(() => _pairs.removeAt(i))),
                ]),
                Wrap(spacing: 6, children: [
                  for (final (w, label) in const [
                    (_Where.start, 'Початок осі'),
                    (_Where.end, 'Кінець осі'),
                    (_Where.middle, 'Середина осі'),
                    (_Where.typed, 'Координати з креслення'),
                  ])
                    ChoiceChip(label: Text(t(label)), selected: p.where == w, onSelected: (_) => setState(() => p.where = w)),
                ]),
                if (p.where == _Where.typed)
                  Row(children: [
                    Expanded(
                        child: TextField(
                            controller: p.x,
                            onChanged: (_) => setState(() {}),
                            keyboardType: numberKeyboard,
                            decoration: InputDecoration(labelText: t('X (схід)')))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: TextField(
                            controller: p.y,
                            onChanged: (_) => setState(() {}),
                            keyboardType: numberKeyboard,
                            decoration: InputDecoration(labelText: t('Y (північ)')))),
                  ])
                else if (_drawing(p) case final d?)
                  Text(t('На кресленні: X {x}  Y {y}', {'x': d.x.toStringAsFixed(2), 'y': d.y.toStringAsFixed(2)}),
                      style: const TextStyle(color: Colors.black54)),
                const SizedBox(height: 8),
                TextField(
                  controller: p.real,
                  readOnly: true,
                  showCursor: true,
                  onTap: () => showDigitPad(context, p.real,
                      label: t('На місцевості: широта, довгота'), keys: latLonKeys, onChanged: (_) => setState(() {})),
                  decoration: InputDecoration(
                    labelText: t('На місцевості: широта, довгота'),
                    hintText: '44.4512345, 26.1034567',
                    errorText: p.real.text.trim().isNotEmpty && parseLatLon(p.real.text) == null
                        ? t('Не розібрав — потрібно «широта, довгота» в градусах')
                        : null,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(spacing: 8, children: [
                  OutlinedButton.icon(onPressed: () => _gps(p), icon: const Icon(Icons.gps_fixed), label: const T('Мій GPS')),
                  OutlinedButton.icon(onPressed: () => _onMap(p), icon: const Icon(Icons.map), label: const T('На карті')),
                ]),
                if (cal != null && cal.residuals.length == done.length && done.length >= 3)
                  if (_complete.indexWhere((x) => x.$1 == _drawing(p)) case final k when k >= 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(t('Похибка цієї точки: {n} м', {'n': cal.residuals[k].toStringAsFixed(2)}),
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: cal.residuals[k] > 5 ? Colors.red.shade800 : Colors.green.shade800)),
                    ),
              ]),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
              onPressed: () => setState(() => _pairs.add(_Pair(_Where.typed))),
              icon: const Icon(Icons.add),
              label: const T('Ще точка')),
        ),
        const SizedBox(height: 8),
        if (fail != null) Text(fail, style: TextStyle(color: Colors.red.shade800)),
        if (cal != null) ...[
          Text(
              done.length < 3
                  ? t('Дві точки: прив’язка є, але перевірити її нічим — додайте третю, якщо можете.')
                  : t('Середня похибка {n} м на {k} точках.', {'n': cal.rms.toStringAsFixed(2), 'k': done.length}),
              style: theme.textTheme.titleMedium),
          Text(
              t('Масштаб креслення ×{s}, поворот {r}°.',
                  {'s': cal.scale.toStringAsFixed(4), 'r': cal.rotationDeg.toStringAsFixed(2)}),
              style: const TextStyle(color: Colors.black54)),
          if ((cal.scale - 1).abs() > 0.02)
            ProblemCard(Problem(Severity.warning, t('Масштаб креслення не 1:1 (×{s})', {'s': cal.scale.toStringAsFixed(3)}),
                fixes: const [
                  'Перевірте, чи точки не переплутані (початок ↔ кінець осі).',
                  'Креслення в міліметрах чи сантиметрах — попросіть проєктанта зберегти в метрах.',
                  'Якщо масштаб справді такий (умовне креслення), можна продовжити — програма його врахує.',
                ])),
          if (cal.rms > 5)
            const ProblemCard(Problem(Severity.warning, 'Точки не узгоджуються між собою (похибка понад 5 м)',
                fixes: [
                  'Найбільша похибка — у точки, яку, мабуть, знайдено не там: перевірте її чи приберіть.',
                  'Для «Мій GPS» зачекайте, поки точність стане ±3 м і краще.',
                ])),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, cal!.system),
            icon: const Icon(Icons.check),
            label: const T('Застосувати калібрування'),
          ),
        ],
      ]),
    );
  }
}

/// Вибрати точку на карті OpenStreetMap торканням.
class MapPickScreen extends StatefulWidget {
  final LatLng? start;
  const MapPickScreen({super.key, this.start});

  @override
  State<MapPickScreen> createState() => _MapPickScreenState();
}

class _MapPickScreenState extends State<MapPickScreen> {
  LatLng? _p;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const T('Торкніться точки на карті'), actions: [
          TextButton(onPressed: _p == null ? null : () => Navigator.pop(context, _p), child: const T('Готово')),
        ]),
        body: FlutterMap(
          options: MapOptions(
            initialCenter: widget.start ?? const LatLng(47.5, 27),
            initialZoom: widget.start == null ? 6 : 17,
            maxZoom: 20,
            onTap: (_, p) => setState(() => _p = p),
          ),
          children: [
            osmLayer(null),
            if (_p != null)
              MarkerLayer(markers: [
                Marker(
                    point: _p!,
                    width: 40,
                    height: 40,
                    alignment: Alignment.topCenter,
                    child: const Icon(Icons.place, color: Color(0xFFD32F2F), size: 40)),
              ]),
          ],
        ),
      );
}
