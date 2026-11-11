// Поздовжній профіль (проєктна відмітка осі на ПК) і ширини проїзної частини за ПК.
import 'dart:math' as math;

/// Точка перелому профілю. [curve] — довжина вертикальної кривої (парабола), 0 — без кривої.
class Pvi {
  final double station, z, curve;
  const Pvi(this.station, this.z, [this.curve = 0]);
}

class Profile {
  /// Звідки: «CSV: файл.csv», «LandXML: назва профілю».
  final String source;
  final List<Pvi> pvis;
  Profile(this.source, List<Pvi> pvis) : pvis = List.unmodifiable([...pvis]..sort((a, b) => a.station.compareTo(b.station)));

  double get startStation => pvis.first.station;
  double get endStation => pvis.last.station;
  /// 1 см за кінцями — ще профіль: ПК у різних файлах округлюють по-різному.
  bool covers(double st) => st >= startStation - 0.01 && st <= endStation + 0.01;

  double _grade(int i) => (pvis[i + 1].z - pvis[i].z) / (pvis[i + 1].station - pvis[i].station);

  /// Проєктна відмітка на ПК [st], або null поза профілем.
  double? elevationAt(double st) => _at(st)?.$1;

  /// Поздовжній ухил на ПК [st] (0.0042 = 4.2 ‰), або null поза профілем.
  double? gradeAt(double st) => _at(st)?.$2;

  (double, double)? _at(double st) {
    if (pvis.length < 2 || !covers(st)) return null;
    st = st.clamp(startStation, endStation);
    // Усередині вертикальної кривої — парабола між сусідніми ухилами.
    for (var i = 1; i < pvis.length - 1; i++) {
      final p = pvis[i];
      if (p.curve <= 0) continue;
      final bvc = p.station - p.curve / 2;
      if (st >= bvc && st <= p.station + p.curve / 2) {
        final g1 = _grade(i - 1), g2 = _grade(i);
        final x = st - bvc;
        final zBvc = p.z - g1 * p.curve / 2;
        return (zBvc + g1 * x + (g2 - g1) / (2 * p.curve) * x * x, g1 + (g2 - g1) * x / p.curve);
      }
    }
    var i = 0;
    while (i < pvis.length - 2 && pvis[i + 1].station < st) {
      i++;
    }
    final g = _grade(i);
    return (pvis[i].z + g * (st - pvis[i].station), g);
  }

  Map<String, dynamic> toJson() => {
        'source': source,
        'pvi': [for (final p in pvis) [p.station, p.z, p.curve]],
      };

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(j['source'] as String, [
        for (final v in j['pvi'] as List)
          Pvi((v[0] as num).toDouble(), (v[1] as num).toDouble(), (v[2] as num).toDouble())
      ]);
}

/// Напівширини проїзної частини ліворуч і праворуч від осі за ПК (з відомості), м.
class Widths {
  final String source;
  final List<(double station, double left, double right)> rows;
  Widths(this.source, List<(double, double, double)> rows)
      : rows = List.unmodifiable([...rows]..sort((a, b) => a.$1.compareTo(b.$1)));

  /// Напівширини на ПК [st] (лінійно між рядками), або null поза відомістю.
  (double, double)? at(double st) {
    if (rows.isEmpty || st < rows.first.$1 - 1e-6 || st > rows.last.$1 + 1e-6) return null;
    if (rows.length == 1) return (rows.first.$2, rows.first.$3);
    var i = 0;
    while (i < rows.length - 2 && rows[i + 1].$1 < st) {
      i++;
    }
    final a = rows[i], b = rows[i + 1];
    final t = b.$1 == a.$1 ? 0.0 : ((st - a.$1) / (b.$1 - a.$1)).clamp(0.0, 1.0);
    return (a.$2 + (b.$2 - a.$2) * t, a.$3 + (b.$3 - a.$3) * t);
  }

  Map<String, dynamic> toJson() => {
        'source': source,
        'rows': [for (final r in rows) [r.$1, r.$2, r.$3]],
      };

  factory Widths.fromJson(Map<String, dynamic> j) => Widths(j['source'] as String, [
        for (final v in j['rows'] as List) ((v[0] as num).toDouble(), (v[1] as num).toDouble(), (v[2] as num).toDouble())
      ]);
}

/// Ухил у проміле для показу: 0.0042 → «+4.2 ‰».
String gradeText(double g) {
  final v = g * 1000;
  return '${v >= 0 ? '+' : '−'}${v.abs().toStringAsFixed(1)} ‰';
}

// ---------- Поперечник: відмітка за кромкою ----------

/// Відмітка на лінії проєкту [line] (зміщення, відмітка — зліва направо) у точці [offset], або null поза нею.
double? zOnLine(List<(double, double)> line, double offset) {
  if (line.length < 2 || offset < line.first.$1 - 1e-6 || offset > line.last.$1 + 1e-6) return null;
  for (var i = 0; i < line.length - 1; i++) {
    final a = line[i], b = line[i + 1];
    if (offset <= b.$1 + 1e-6) {
      if (b.$1 - a.$1 < 1e-9) return b.$2;
      return a.$2 + (b.$2 - a.$2) * ((offset - a.$1) / (b.$1 - a.$1)).clamp(0.0, 1.0);
    }
  }
  return line.last.$2;
}

/// Поперечники з відмітками (LandXML CrossSects): на ПК — лінія проєкту (зміщення, відмітка), «+» — праворуч.
class CrossSections {
  final String source;
  final List<(double station, List<(double, double)> line)> rows;
  CrossSections(this.source, List<(double, List<(double, double)>)> rows)
      : rows = List.unmodifiable([...rows]..sort((a, b) => a.$1.compareTo(b.$1)));

  double get startStation => rows.first.$1;
  double get endStation => rows.last.$1;

  /// Поперечник «для цього місця»: ближчий за 1 м — він сам; між двома сусідніми, не далі [maxGap] м один від
  /// одного, — відмітки на тих самих зміщеннях, лінійно за ПК. Інакше null (поперечника тут немає).
  /// Разом з лінією — ПК поперечників, з яких вона взята (той самий двічі, якщо поперечник тут).
  (List<(double, double)>, double, double)? lineAt(double st, {double maxGap = 50}) {
    if (rows.isEmpty) return null;
    var i = 0;
    while (i < rows.length - 1 && rows[i + 1].$1 <= st) {
      i++;
    }
    final a = rows[i];
    if ((a.$1 - st).abs() <= 1) return (a.$2, a.$1, a.$1);
    if (i + 1 < rows.length && (rows[i + 1].$1 - st).abs() <= 1) {
      return (rows[i + 1].$2, rows[i + 1].$1, rows[i + 1].$1);
    }
    if (st < a.$1 || i + 1 >= rows.length) return null;
    final b = rows[i + 1];
    if (b.$1 - a.$1 > maxGap) return null;
    final k = (st - a.$1) / (b.$1 - a.$1);
    final (la, lb) = align(a.$2, b.$2);
    final line = [for (var i = 0; i < la.length; i++) (la[i].$1, la[i].$2 + (lb[i].$2 - la[i].$2) * k)];
    return line.length < 2 ? null : (line, a.$1, b.$1);
  }

  /// Два поперечники на спільних зміщеннях (у межах, де є обидва) — однакової довжини, точка до точки. Уступ
  /// (бордюр: дві точки з одним зміщенням) в одному з них — дві точки в обох: «зліва» й «справа» від уступу.
  static (List<(double, double)>, List<(double, double)>) align(List<(double, double)> a, List<(double, double)> b) {
    final lo = math.max(a.first.$1, b.first.$1), hi = math.min(a.last.$1, b.last.$1);
    final offs = {for (final p in [...a, ...b]) if (p.$1 >= lo - 1e-6 && p.$1 <= hi + 1e-6) p.$1}.toList()..sort();
    final la = <(double, double)>[], lb = <(double, double)>[];
    for (final o in offs) {
      final al = _side(a, o, false), ar = _side(a, o, true), bl = _side(b, o, false), br = _side(b, o, true);
      la.add((o, al));
      lb.add((o, bl));
      if ((ar - al).abs() > 1e-9 || (br - bl).abs() > 1e-9) {
        la.add((o, ar));
        lb.add((o, br));
      }
    }
    return (la, lb);
  }

  /// Відмітка лінії на зміщенні [o]; на уступі — нижня чи верхня його точка: [right] — та, що далі за порядком.
  static double _side(List<(double, double)> line, double o, bool right) {
    final at = [for (final p in line) if ((p.$1 - o).abs() < 1e-9) p.$2];
    return at.isEmpty ? zOnLine(line, o)! : (right ? at.last : at.first);
  }

  Map<String, dynamic> toJson() => {
        'source': source,
        'rows': [
          for (final r in rows) [r.$1, for (final p in r.$2) [p.$1, p.$2]]
        ],
      };

  factory CrossSections.fromJson(Map<String, dynamic> j) => CrossSections(j['source'] as String, [
        for (final r in j['rows'] as List)
          (
            ((r as List)[0] as num).toDouble(),
            [for (final p in r.skip(1)) (((p as List)[0] as num).toDouble(), (p[1] as num).toDouble())]
          )
      ]);
}
