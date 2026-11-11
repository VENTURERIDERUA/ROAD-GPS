// Лінії поруч з віссю: кромки, бровки, підошви укосів, межі відводу.
// Для кожного ПК — де вони перетинають поперечник і де стоїть людина відносно них.
import 'package:flutter/material.dart';

import 'geometry.dart';

enum LineRole {
  edge('Кромка', Color(0xFF212121)),
  curb('Бордюр', Color(0xFF424242)),
  sidewalk('Тротуар', Color(0xFF9E9E9E)),
  brow('Бровка', Color(0xFF6D4C41)),
  toe('Підошва укосу', Color(0xFFA1887F)),
  ditch('Кювет, лоток', Color(0xFF0288D1)),
  row('Межа відводу', Color(0xFF8E24AA)),
  works('Межа робіт', Color(0xFFEF6C00)),
  gas('Газопровід', Color(0xFFFBC02D), utility: true),
  power('Кабель', Color(0xFFE53935), utility: true),
  water('Водопровід', Color(0xFF1E88E5), utility: true),
  sewer('Каналізація', Color(0xFF6D4C41), utility: true),
  other('Інша лінія', Color(0xFF757575));

  final String label;
  final Color color;

  /// Підземна мережа: на карті — пунктиром, попередження за замовчуванням — 2 м.
  final bool utility;
  const LineRole(this.label, this.color, {this.utility = false});
}

// Назви шарів українською, румунською, англійською (й російською — так буває в кресленнях).
final _guess = <LineRole, RegExp>{
  LineRole.gas: RegExp(r'газ|(^|[^a-z])(gaz|gas)([^a-z]|$)', caseSensitive: false, unicode: true),
  LineRole.power: RegExp(r'кабел|cablu|cable|electr|енерг', caseSensitive: false, unicode: true),
  LineRole.water: RegExp(r'водопров|water|(^|[^a-z])ap[aă]([^a-z]|$)|alimentare', caseSensitive: false, unicode: true),
  LineRole.sewer: RegExp(r'каналіз|канализ|canaliz|sewer', caseSensitive: false, unicode: true),
  LineRole.works: RegExp(r'межа робіт|limit[aă] (de )?lucr|work.?limit', caseSensitive: false, unicode: true),
  LineRole.row: RegExp(r'відвод|отвод|expropri|right.?of.?way|(^|[^a-z])row([^a-z]|$)|смуг', caseSensitive: false, unicode: true),
  LineRole.brow: RegExp(r'бровк|brow|crest|taluz.?sus|top.?of.?slope', caseSensitive: false, unicode: true),
  LineRole.toe: RegExp(r'підошв|подошв|(^|[^a-z])toe|taluz.?jos|bottom.?of.?slope', caseSensitive: false, unicode: true),
  LineRole.ditch: RegExp(r'кювет|лоток|rigol|[sș]an[tț]|ditch|gutter', caseSensitive: false, unicode: true),
  LineRole.sidewalk: RegExp(r'тротуар|trotuar|sidewalk|footway', caseSensitive: false, unicode: true),
  LineRole.curb: RegExp(r'бордюр|bordur|curb|kerb', caseSensitive: false, unicode: true),
  LineRole.edge: RegExp(r'кромк|edge|margin|carosabil|pavement|кп([^а-яіїє]|$)', caseSensitive: false, unicode: true),
};

/// Роль шару за назвою, або null — шар, найпевніше, не потрібен.
LineRole? guessRole(String layer) {
  for (final e in _guess.entries) {
    if (e.value.hasMatch(layer)) return e.key;
  }
  return null;
}

/// Одна нерозривна лінія (ліва кромка, права межа відводу…).
class RoadLine {
  final LineRole role;
  final String layer;
  final List<Segment> segs;
  final Box box;

  /// Попередити (вібрація й напис), коли людина ближче за стільки метрів до лінії; null — не попереджати.
  final double? alert;
  RoadLine(this.role, this.layer, this.segs, {this.alert}) : box = Box.of(segs);

  double get length => segs.fold(0.0, (a, s) => a + s.length);

  /// Найкоротша відстань від точки до лінії, м — у будь-якому напрямку (мережа може й перетинати дорогу).
  double distanceTo(Vec p) {
    var best = double.infinity;
    for (final s in segs) {
      final d = (s.pointAt(s.closest(p)) - p).length;
      if (d < best) best = d;
    }
    return best;
  }

  Map<String, dynamic> toJson() => {
        'role': role.name,
        'layer': layer,
        'segs': [for (final s in segs) s.toJson()],
        if (alert != null) 'alert': alert,
      };

  factory RoadLine.fromJson(Map<String, dynamic> j) => RoadLine(
        // Невідома роль (файл з новішої версії) — «Інша лінія», а не помилка.
        LineRole.values.asNameMap()[j['role'] as String] ?? LineRole.other,
        j['layer'] as String,
        [for (final s in j['segs'] as List) Segment.fromJson(s as Map<String, dynamic>)],
        alert: (j['alert'] as num?)?.toDouble(),
      );

  RoadLine swapXY() => RoadLine(role, layer, [for (final s in segs) s.swapXY()], alert: alert);

  RoadLine withRole(LineRole role, double? alert) => RoadLine(role, layer, segs, alert: alert);
}

/// Усі лінії шару як окремі [RoadLine]; коротші за [minLength] м (риски, обривки) — пропускаються,
/// петлі на поворотах ([removeLoops]) — зрізаються.
List<RoadLine> linesOfLayer(LineRole role, String layer, List<Segment> pieces, {double minLength = 1}) => [
      for (final c in chainAll(pieces))
        if (c.fold(0.0, (a, s) => a + s.length) >= minLength) RoadLine(role, layer, removeLoops(c)),
    ];

/// Лінія на поперечнику: відстань від осі, м («+» — праворуч, «−» — ліворуч).
class CrossHit {
  final LineRole role;
  final String layer;
  final double offset;
  const CrossHit(this.role, this.layer, this.offset);
}

/// Перетини ліній з поперечником на ПК [station] у межах [reach] м від осі, зліва направо.
List<CrossHit> crossSection(RoadAxis axis, List<RoadLine> lines, double station, {double reach = 150}) {
  final p = axis.pointAtStation(station);
  final n = axis.rightNormalAt(station);
  final out = <CrossHit>[];
  for (final l in lines) {
    if (!l.box.near(p, reach)) continue;
    final ts = <double>[];
    for (final s in l.segs) {
      for (final t in crossLine(s, p, n)) {
        // Поперечник через вершину лінії зачіпає обидва сусідні шматки — це один перетин.
        if (t.abs() <= reach && ts.every((x) => (x - t).abs() > 0.1) && !_otherPart(axis, station, p + n * t, t)) {
          ts.add(t);
        }
      }
    }
    out.addAll([for (final t in ts) CrossHit(l.role, l.layer, t)]);
  }
  out.sort((a, b) => a.offset.compareTo(b.offset));
  return out;
}

/// Перетин далеко від осі, що лежить біля іншої частини траси (на повороті поперечник «дістає» вулицю
/// після повороту), — не з цього поперечника. Близькі перетини (до 15 м) лишаються: біля внутрішнього кута
/// повороту справжня кромка теж ближча до сусідньої ділянки осі.
bool _otherPart(RoadAxis axis, double station, Vec q, double t) {
  if (t.abs() <= 15) return false;
  final r = axis.locate(q);
  final near = r.beyond ? double.infinity : r.offset.abs();
  return (r.station - station).abs() > 5 && near < 0.5 * t.abs();
}

/// Де людина відносно ліній поперечника.
class Whereabouts {
  /// Найближча лінія ліворуч і праворуч від людини та відстань до неї, м.
  final (CrossHit, double)? left, right;

  /// На скільки метрів людина за межею відводу (null — у межах або межі на цьому боці немає).
  final double? outsideRow;
  const Whereabouts(this.left, this.right, this.outsideRow);
}

Whereabouts whereabouts(List<CrossHit> hits, double offset) {
  (CrossHit, double)? left, right;
  for (final h in hits) {
    if (h.offset <= offset) {
      left = (h, offset - h.offset);
    } else {
      right ??= (h, h.offset - offset);
    }
  }
  double? outside;
  final rows = hits.where((h) => h.role == LineRole.row);
  if (offset < 0) {
    final leftRows = rows.where((h) => h.offset < 0);
    // Найдальша межа ліворуч — зовнішня; людина ще лівіше — поза відводом.
    if (leftRows.isNotEmpty) {
      final outer = leftRows.first.offset;
      if (offset < outer) outside = outer - offset;
    }
  } else {
    final rightRows = rows.where((h) => h.offset > 0);
    if (rightRows.isNotEmpty) {
      final outer = rightRows.last.offset;
      if (offset > outer) outside = offset - outer;
    }
  }
  return Whereabouts(left, right, outside);
}
