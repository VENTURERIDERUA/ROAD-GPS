// Поперечники, намальовані в DXF (як аркуш поперечників проєктанта): біля кожного — підпис з ПК (і, буває,
// відміткою осі «Z=84.20»), вертикаль осі поперечника й лінія проєкту. Шари вибирає людина; програма знаходить
// для кожного підпису найближчу лінію проєкту й вісь і переводить точки лінії в «зміщення — відмітка».
import 'dart:math' as math;

import 'chainage.dart';
import 'dxf.dart';
import 'geometry.dart';
import 'i18n.dart';
import 'problems.dart';
import 'profile.dart';
import 'vidomist.dart' show XsResult;

/// Відмітка осі в підписі: «Z=84.20», «Z ax = 84,20», «Cota ax: 84.20», «відм. 84.20».
final _zLabel = RegExp(r'(?:\bz|cota|відм\w*|отм\w*)\s*(?:ax\w*|осі|оси)?\s*[=:.]?\s*(-?\d+(?:[.,]\d+)?)',
    caseSensitive: false, unicode: true);

/// ПК у підписі поперечника, де після нього буває ще текст: «PK 0+025.00  Z=84.20».
double? stationIn(String label) {
  final whole = parseChainageLabel(label);
  if (whole != null) return whole.$1;
  final m = RegExp(r'\d+\s*\+\s*\d+(?:[.,]\d+)?').firstMatch(label);
  return m == null ? null : parseChainageLabel(m[0]!)?.$1;
}

double? axisElevationIn(String label) {
  final m = _zLabel.firstMatch(label);
  return m == null ? null : double.tryParse(m[1]!.replaceAll(',', '.'));
}

/// Шари для розбору: лінія проєкту, підписи ПК, вісь поперечника (вертикальні лінії).
class XsLayers {
  final String design, labels, axis;
  const XsLayers(this.design, this.labels, this.axis);
}

/// Шари за назвами й вмістом: лінія проєкту — «design / proiect / проєкт / top»; підписи — шар, де найбільше
/// підписів з ПК і відміткою осі разом (інакше — з назвою поперечників, інакше — просто з ПК; на плані підписи ПК
/// теж є); вісь — шар з вертикальними лініями (першим — шар підписів).
XsLayers? guessXsLayers(DxfDrawing d) {
  final xsName = RegExp(r'xs|sec|попер|transv', caseSensitive: false);
  int score(DxfLayer l) {
    final pk = l.labels.where((p) => stationIn(p.text) != null);
    final withZ = pk.where((p) => axisElevationIn(p.text) != null).length;
    return withZ * 1000000 + (xsName.hasMatch(l.name) ? 1000 : 0) * pk.length.sign + pk.length;
  }

  final withPk = [
    for (final l in d.layers.values)
      if (l.labels.any((p) => stationIn(p.text) != null)) (l, score(l))
  ]..sort((a, b) => b.$2.compareTo(a.$2));
  if (withPk.isEmpty) return null;
  final labels = withPk.first.$1.name;
  final design = RegExp(r'design|proiect|проєкт|проект|top|(^|[^a-z])fg([^a-z]|$)|red', caseSensitive: false);
  final lines = d.layers.values.where((l) => l.segments.isNotEmpty).toList();
  final des = lines.where((l) => design.hasMatch(l.name) && xsName.hasMatch(l.name));
  final des2 = des.isNotEmpty ? des : lines.where((l) => design.hasMatch(l.name));
  final axisCandidates = lines.where((l) => _verticals(l.segments).isNotEmpty).toList()
    ..sort((a, b) => (b.name == labels ? 1 : 0).compareTo(a.name == labels ? 1 : 0));
  if (des2.isEmpty || axisCandidates.isEmpty) return null;
  return XsLayers(des2.first.name, labels, axisCandidates.first.name);
}

List<LineSeg> _verticals(List<Segment> segs) => [
      for (final s in segs)
        if (s is LineSeg && s.length > 1e-6 && (s.end.x - s.start.x).abs() < 1e-3 * s.length) s
    ];

/// Ламані лінії проєкту: шматки, що йдуть один за одним кінець-у-початок, — одна ламана.
List<List<Vec>> _polylines(List<Segment> segs) {
  final out = <List<Vec>>[];
  for (final s in segs) {
    final pts = s is ArcSeg
        ? [for (var k = 0; k <= 8; k++) s.pointAt(s.length * k / 8)]
        : [s.start, s.end];
    if (out.isNotEmpty && out.last.last.dist(pts.first) < 1e-6) {
      out.last.addAll(pts.skip(1));
    } else {
      out.add([...pts]);
    }
  }
  return out;
}

/// Найменша відстань від точки до прямокутника, що охоплює ламану.
double _boxDist(Vec p, List<Vec> pl) {
  final xs = pl.map((v) => v.x), ys = pl.map((v) => v.y);
  final dx = math.max(0.0, math.max(xs.reduce(math.min) - p.x, p.x - xs.reduce(math.max)));
  final dy = math.max(0.0, math.max(ys.reduce(math.min) - p.y, p.y - ys.reduce(math.max)));
  return math.sqrt(dx * dx + dy * dy);
}

/// Висота лінії [pl] (у кресленні) над точкою x, або null — x поза лінією.
double? _yAt(List<Vec> pl, double x) {
  for (var i = 0; i < pl.length - 1; i++) {
    final a = pl[i], b = pl[i + 1];
    final lo = math.min(a.x, b.x), hi = math.max(a.x, b.x);
    if (x < lo - 1e-6 || x > hi + 1e-6) continue;
    if (hi - lo < 1e-9) return math.max(a.y, b.y);
    return a.y + (b.y - a.y) * (x - a.x) / (b.x - a.x);
  }
  return null;
}

/// Поперечники з креслення. [vScale] — у скільки разів вертикаль перебільшено (V 2:1 → 2). Відмітка осі — з підпису,
/// інакше з [profile] на ПК підпису; немає ні того, ні того — поперечник пропускається.
XsResult sectionsFromDrawing(DxfDrawing d, XsLayers ly, {double vScale = 1, Profile? profile, String source = ''}) {
  final problems = <Problem>[];
  final des = d.layers[ly.design], lab = d.layers[ly.labels], ax = d.layers[ly.axis];
  if (des == null || lab == null || ax == null) {
    return XsResult(null, 0, [const Problem(Severity.error, 'Виберіть шари лінії проєкту, підписів ПК і осі поперечника')]);
  }
  final pls = _polylines(des.segments);
  final axes = _verticals(ax.segments);
  final labels = [
    for (final l in lab.labels)
      if (stationIn(l.text) case final pk?) (l, pk)
  ];
  if (labels.isEmpty) {
    return XsResult(null, 0, [
      Problem(Severity.error, t('На шарі «{l}» немає підписів ПК', {'l': ly.labels}),
          fixes: const ['Виберіть шар, де біля кожного поперечника написано «PK 0+025.00» чи «ПК 0+25».'])
    ]);
  }
  final rows = <(double, List<(double, double)>)>[];
  final used = <int>{};
  var noZ = 0, noAxis = 0, noLine = 0, points = 0;
  for (final (l, pk) in labels) {
    // Найближча ще не взята лінія проєкту.
    int? best;
    var bestD = double.infinity;
    for (var i = 0; i < pls.length; i++) {
      if (used.contains(i)) continue;
      final dd = _boxDist(l.pos, pls[i]);
      if (dd < bestD) {
        bestD = dd;
        best = i;
      }
    }
    if (best == null) {
      noLine++;
      continue;
    }
    var pl = pls[best];
    if (pl.last.x < pl.first.x) pl = pl.reversed.toList();
    final x0 = pl.first.x, x1 = pl.last.x;
    // Вісь — вертикаль у межах лінії, найближча до підпису.
    LineSeg? axis;
    var axD = double.infinity;
    for (final v in axes) {
      if (v.start.x < x0 - 1e-6 || v.start.x > x1 + 1e-6) continue;
      final dd = l.pos.dist((v.start + v.end) * 0.5);
      if (dd < axD) {
        axD = dd;
        axis = v;
      }
    }
    final yAxis = axis == null ? null : _yAt(pl, axis.start.x);
    if (axis == null || yAxis == null) {
      noAxis++;
      continue;
    }
    final zAxis = axisElevationIn(l.text) ?? profile?.elevationAt(pk);
    if (zAxis == null) {
      noZ++;
      continue;
    }
    used.add(best);
    final xa = axis.start.x;
    final pts = <(double, double)>[];
    for (final p in pl) {
      final off = p.x - xa;
      if (pts.isNotEmpty && off < pts.last.$1 - 1e-6) continue; // лінія не повертає назад
      pts.add((off, zAxis + (p.y - yAxis) / vScale));
    }
    if (pts.length < 2) {
      noLine++;
      continue;
    }
    points += pts.length;
    rows.add((pk, pts));
  }
  if (noLine > 0) {
    problems.add(Problem(Severity.warning, t('Без лінії проєкту: {n} підписів', {'n': noLine}),
        fixes: const ['Перевірте шар лінії проєкту: біля кожного підпису ПК має бути своя лінія.']));
  }
  if (noAxis > 0) {
    problems.add(Problem(Severity.warning, t('Не знайдено осі поперечника: {n}', {'n': noAxis}),
        fixes: const ['Виберіть шар, де вісь кожного поперечника — вертикальна лінія, що перетинає лінію проєкту.']));
  }
  if (noZ > 0) {
    problems.add(Problem(Severity.warning, t('Без відмітки осі: {n} поперечників — пропущено', {'n': noZ}),
        fixes: const [
          'Відмітка осі береться з підпису («Z=84.20», «Cota ax 84.20») або з поздовжнього профілю об’єкта.',
          'Додайте профіль («З LandXML», «З відомості») — і розберіть поперечники ще раз.',
        ]));
  }
  if (rows.isEmpty) {
    problems.add(const Problem(Severity.error, 'Жодного поперечника не вийшло',
        fixes: ['Перевірте вибрані шари й вертикальний масштаб.']));
    return XsResult(null, points, problems);
  }
  final seen = <int>{};
  final unique = [for (final r in rows) if (seen.add((r.$1 * 1000).round())) r];
  if (unique.length < rows.length) {
    problems.add(Problem(Severity.warning, t('Однакові ПК у підписах: {n}', {'n': rows.length - unique.length}),
        fixes: const ['Береться перший; перевірте підписи в кресленні.']));
  }
  return XsResult(CrossSections(source, unique), points, problems);
}

/// Вертикальне перебільшення з напису в кресленні: «H 1:100 V 1:10» → 10, «H 1:1 V 2:1» → 2. Спершу — написи на шарі
/// [layer] (підписи поперечників): на аркуші буває й напис масштабу профілю. Перебільшення, меншого за 1, у
/// дорожніх кресленнях не буває, тож «H 1:1 V 1:10» (записане навпаки) — теж 10. null — напису немає.
(double, String)? guessVScale(DxfDrawing d, {String? layer}) {
  final r = RegExp(r'\b([HV])\s*(\d+(?:[.,]\d+)?)\s*:\s*(\d+(?:[.,]\d+)?)', caseSensitive: false);
  double n(String s) => double.parse(s.replaceAll(',', '.'));
  final all = [
    ...?d.layers[layer]?.labels,
    for (final l in d.layers.values)
      if (l.name != layer) ...l.labels,
  ];
  for (final l in all) {
    final ms = r.allMatches(l.text).toList();
    final h = ms.where((m) => m[1]!.toUpperCase() == 'H').firstOrNull;
    final v = ms.where((m) => m[1]!.toUpperCase() == 'V').firstOrNull;
    if (h == null || v == null) continue;
    // Масштаб a:b — a одиниць креслення на b одиниць місцевості; перебільшення = масштаб V / масштаб H.
    final k = (n(v[2]!) / n(v[3]!)) / (n(h[2]!) / n(h[3]!));
    if (k > 0 && k.isFinite) return (k < 1 ? 1 / k : k, l.text);
  }
  return null;
}
