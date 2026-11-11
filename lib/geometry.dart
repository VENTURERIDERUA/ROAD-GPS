// Геометрія осі в плані: відрізки й дуги в координатах креслення (метри),
// збирання осі з окремих шматків, ПК+плюс і зміщення від осі.
import 'dart:math' as math;

class Vec {
  final double x, y;
  const Vec(this.x, this.y);
  Vec operator +(Vec o) => Vec(x + o.x, y + o.y);
  Vec operator -(Vec o) => Vec(x - o.x, y - o.y);
  Vec operator *(double k) => Vec(x * k, y * k);
  double dot(Vec o) => x * o.x + y * o.y;
  double cross(Vec o) => x * o.y - y * o.x;
  double get length => math.sqrt(x * x + y * y);
  double dist(Vec o) => (this - o).length;
  @override
  String toString() => '(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)})';
}

abstract class Segment {
  Vec get start;
  Vec get end;
  double get length;

  /// Точка на відстані [s] від початку шматка (0..length).
  Vec pointAt(double s);

  /// Одиничний напрям руху в точці [s].
  Vec tangentAt(double s);

  /// Відстань від початку шматка до найближчої до [p] точки (0..length).
  double closest(Vec p);

  Segment reversed();

  /// Дзеркально міняє X і Y місцями (коли в файлі спершу північ, потім схід).
  Segment swapXY();

  /// Точки для малювання на карті, приблизно через [step] м.
  List<Vec> densify(double step);

  Map<String, dynamic> toJson();

  static Segment fromJson(Map<String, dynamic> j) {
    final v = (j['v'] as List).map((e) => (e as num).toDouble()).toList();
    return switch (j['t']) {
      'L' => LineSeg(Vec(v[0], v[1]), Vec(v[2], v[3])),
      'A' => ArcSeg(Vec(v[0], v[1]), v[2], v[3], v[4]),
      _ => throw FormatException('Невідомий тип шматка осі: ${j['t']}'),
    };
  }
}

class LineSeg implements Segment {
  @override
  final Vec start, end;
  LineSeg(this.start, this.end);

  @override
  double get length => start.dist(end);

  @override
  Vec pointAt(double s) => start + tangentAt(0) * s;

  @override
  Vec tangentAt(double s) {
    final d = end - start;
    final l = d.length;
    return l == 0 ? const Vec(1, 0) : d * (1 / l);
  }

  @override
  double closest(Vec p) {
    final d = end - start;
    final l2 = d.dot(d);
    if (l2 == 0) return 0;
    final t = ((p - start).dot(d) / l2).clamp(0.0, 1.0);
    return t * math.sqrt(l2);
  }

  @override
  Segment reversed() => LineSeg(end, start);

  @override
  Segment swapXY() => LineSeg(Vec(start.y, start.x), Vec(end.y, end.x));

  @override
  List<Vec> densify(double step) => [start, end];

  @override
  Map<String, dynamic> toJson() => {
        't': 'L',
        'v': [start.x, start.y, end.x, end.y],
      };
}

/// Дуга кола: [startAngle] у радіанах від осі X, [sweep] — зі знаком (+ проти годинникової).
class ArcSeg implements Segment {
  final Vec center;
  final double radius, startAngle, sweep;
  ArcSeg(this.center, this.radius, this.startAngle, this.sweep);

  /// Дуга з полілінії: від [p1] до [p2] з «опуклістю» (bulge) DXF.
  factory ArcSeg.fromBulge(Vec p1, Vec p2, double bulge) {
    final sweep = 4 * math.atan(bulge);
    final chord = p2 - p1;
    final l = chord.length;
    final mid = (p1 + p2) * 0.5;
    final left = Vec(-chord.y / l, chord.x / l);
    final center = mid + left * ((l / 2) / math.tan(sweep / 2));
    final r = center.dist(p1);
    final a0 = math.atan2(p1.y - center.y, p1.x - center.x);
    return ArcSeg(center, r, a0, sweep);
  }

  Vec _at(double a) => center + Vec(math.cos(a), math.sin(a)) * radius;

  @override
  Vec get start => _at(startAngle);
  @override
  Vec get end => _at(startAngle + sweep);
  @override
  double get length => radius * sweep.abs();

  @override
  Vec pointAt(double s) => _at(startAngle + sweep.sign * s / radius);

  @override
  Vec tangentAt(double s) {
    final a = startAngle + sweep.sign * s / radius;
    return sweep >= 0 ? Vec(-math.sin(a), math.cos(a)) : Vec(math.sin(a), -math.cos(a));
  }

  @override
  double closest(Vec p) {
    final v = p - center;
    if (v.length == 0) return 0;
    final ang = math.atan2(v.y, v.x);
    const twoPi = 2 * math.pi;
    final d = sweep >= 0 ? (ang - startAngle) % twoPi : (startAngle - ang) % twoPi;
    if (d <= sweep.abs()) return d * radius;
    // Поза дугою — найближчий з кінців.
    return p.dist(start) <= p.dist(end) ? 0 : length;
  }

  @override
  Segment reversed() => ArcSeg(center, radius, startAngle + sweep, -sweep);

  @override
  Segment swapXY() =>
      ArcSeg(Vec(center.y, center.x), radius, math.pi / 2 - startAngle, -sweep);

  @override
  List<Vec> densify(double step) {
    final n = math.max(2, (length / step).ceil());
    return [for (var i = 0; i <= n; i++) pointAt(length * i / n)];
  }

  @override
  Map<String, dynamic> toJson() => {
        't': 'A',
        'v': [center.x, center.y, radius, startAngle, sweep],
      };
}

/// Результат збирання осі з окремих шматків.
class ChainResult {
  final List<Segment> segments;
  final int usedPieces;
  final int ignoredPieces;
  final double ignoredLength;

  /// Вузли, де сходиться більше двох шматків (розгалуження) — у вибраній частині.
  final int branchNodes;
  final bool closed;

  /// Довжина найдовшої з решти частин, м: велика — вісь розірвана, мала — це риски чи обривки.
  final double secondLength;
  ChainResult(this.segments, this.usedPieces, this.ignoredPieces, this.ignoredLength,
      this.branchNodes, this.closed, [this.secondLength = 0]);
}

/// Збирає найдовший нерозривний ланцюжок з відрізків і дуг (кінці збігаються в межах [tol] м).
/// Решта (позначки пікетів, окремі шматки) — пропускається й рахується.
/// Шматки й вузли (кінці, що збігаються в межах допуску), з переліком шматків у кожному вузлі.
class _Graph {
  final usable = <Segment>[];
  final ends = <(int, int)>[];
  final adj = <int, List<int>>{};

  _Graph(List<Segment> pieces, double tol) {
    final nodes = <Vec>[];
    final grid = <String, List<int>>{};
    int nodeOf(Vec p) {
      final ix = (p.x / tol).floor(), iy = (p.y / tol).floor();
      for (var dx = -1; dx <= 1; dx++) {
        for (var dy = -1; dy <= 1; dy++) {
          for (final n in grid['${ix + dx}:${iy + dy}'] ?? const <int>[]) {
            if (nodes[n].dist(p) <= tol) return n;
          }
        }
      }
      nodes.add(p);
      (grid['$ix:$iy'] ??= []).add(nodes.length - 1);
      return nodes.length - 1;
    }

    for (final s in pieces) {
      if (s.length < 1e-6) continue;
      final a = nodeOf(s.start), b = nodeOf(s.end);
      if (a == b) continue; // замкнене коло з одного шматка
      usable.add(s);
      ends.add((a, b));
    }
    for (var i = 0; i < usable.length; i++) {
      (adj[ends[i].$1] ??= []).add(i);
      (adj[ends[i].$2] ??= []).add(i);
    }
  }

  /// Іде від вузла [from] невикористаними шматками, розвертаючи кожен за напрямом руху.
  List<Segment> walk(int from, Set<int> used) {
    final out = <Segment>[];
    var cur = from;
    while (true) {
      final next = adj[cur]!.where((j) => !used.contains(j)).firstOrNull;
      if (next == null) break;
      used.add(next);
      if (ends[next].$1 == cur) {
        out.add(usable[next]);
        cur = ends[next].$2;
      } else {
        out.add(usable[next].reversed());
        cur = ends[next].$1;
      }
    }
    return out;
  }
}

/// Усі лінії шару як окремі нерозривні ланцюжки (ліва й права кромка, кілька поліліній…).
/// Розгалуження розбиваються на кілька ланцюжків — для перетинів і карти цього досить.
List<List<Segment>> chainAll(List<Segment> pieces, {double tol = 0.05}) {
  final g = _Graph(pieces, tol);
  final used = <int>{};
  final out = <List<Segment>>[];
  int unusedDegree(int n) => g.adj[n]!.where((j) => !used.contains(j)).length;
  for (var i = 0; i < g.usable.length; i++) {
    if (used.contains(i)) continue;
    // Починаємо з вільного кінця, якщо він є, — тоді ланцюжок не розірветься посередині.
    var start = g.ends[i].$1;
    final seen = <int>{start};
    final stack = [start];
    while (stack.isNotEmpty) {
      final n = stack.removeLast();
      if (unusedDegree(n) == 1) {
        start = n;
        break;
      }
      for (final j in g.adj[n]!) {
        if (used.contains(j)) continue;
        for (final m in [g.ends[j].$1, g.ends[j].$2]) {
          if (seen.add(m)) stack.add(m);
        }
      }
    }
    out.add(g.walk(start, used));
  }
  return out;
}

ChainResult buildChain(List<Segment> pieces, {double tol = 0.05}) {
  final g = _Graph(pieces, tol);
  final usable = g.usable, ends = g.ends, adj = g.adj;

  // Компоненти зв'язності; беремо найдовшу.
  final comp = List<int>.filled(usable.length, -1);
  final compLen = <double>[];
  for (var i = 0; i < usable.length; i++) {
    if (comp[i] >= 0) continue;
    final id = compLen.length;
    var len = 0.0;
    final stack = [i];
    comp[i] = id;
    while (stack.isNotEmpty) {
      final k = stack.removeLast();
      len += usable[k].length;
      for (final n in [ends[k].$1, ends[k].$2]) {
        for (final j in adj[n]!) {
          if (comp[j] < 0) {
            comp[j] = id;
            stack.add(j);
          }
        }
      }
    }
    compLen.add(len);
  }
  if (compLen.isEmpty) return ChainResult(const [], 0, 0, 0, 0, false);
  var best = 0;
  for (var c = 1; c < compLen.length; c++) {
    if (compLen[c] > compLen[best]) best = c;
  }
  var second = 0.0;
  for (var c = 0; c < compLen.length; c++) {
    if (c != best && compLen[c] > second) second = compLen[c];
  }

  final mine = [for (var i = 0; i < usable.length; i++) if (comp[i] == best) i];
  final nodeSet = {for (final i in mine) ...[ends[i].$1, ends[i].$2]};
  final freeEnds = nodeSet.where((n) => adj[n]!.length == 1).toList();
  final branchNodes = nodeSet.where((n) => adj[n]!.length > 2).length;
  final closed = freeEnds.isEmpty;

  // Обхід від вільного кінця; кожен шматок розвертаємо за напрямом руху.
  final used = <int>{};
  final out = g.walk(closed ? ends[mine.first].$1 : freeEnds.first, used);

  final ignored = usable.length - used.length;
  var ignoredLen = 0.0;
  for (var i = 0; i < usable.length; i++) {
    if (!used.contains(i)) ignoredLen += usable[i].length;
  }
  return ChainResult(out, used.length, ignored, ignoredLen, branchNodes, closed, second);
}

/// Де точка відносно осі.
class StationResult {
  /// Проєктний пікетаж, м (ПК 125+43.2 = 12543.2).
  final double station;

  /// Зміщення від осі, м: «+» — праворуч за ходом пікетажу, «−» — ліворуч.
  final double offset;

  /// Точка перед початком або за кінцем осі.
  final bool beyond;
  StationResult(this.station, this.offset, this.beyond);
}

class RoadAxis {
  final List<Segment> segs;
  final List<double> _cum;
  final double length;

  /// ПК початку осі, м.
  final double startStation;

  RoadAxis._(this.segs, this._cum, this.length, this.startStation);

  factory RoadAxis(List<Segment> segs, {double startStation = 0}) {
    final cum = <double>[];
    var acc = 0.0;
    for (final s in segs) {
      cum.add(acc);
      acc += s.length;
    }
    return RoadAxis._(List.unmodifiable(segs), cum, acc, startStation);
  }

  double get endStation => startStation + length;

  StationResult locate(Vec p) {
    var bestI = 0;
    var bestS = 0.0;
    var bestD = double.infinity;
    for (var i = 0; i < segs.length; i++) {
      final s = segs[i].closest(p);
      final d = segs[i].pointAt(s).dist(p);
      if (d < bestD) {
        bestD = d;
        bestI = i;
        bestS = s;
      }
    }
    final seg = segs[bestI];
    // Перед початком осі: продовжуємо першу дотичну.
    if (bestI == 0 && bestS <= 1e-9) {
      final t = seg.tangentAt(0);
      final along = (p - seg.start).dot(t);
      if (along < 0) {
        return StationResult(startStation + along, -t.cross(p - seg.start), true);
      }
    }
    // За кінцем осі: продовжуємо останню дотичну.
    if (bestI == segs.length - 1 && bestS >= seg.length - 1e-9) {
      final t = seg.tangentAt(seg.length);
      final along = (p - seg.end).dot(t);
      if (along > 0) {
        return StationResult(endStation + along, -t.cross(p - seg.end), true);
      }
    }
    final q = seg.pointAt(bestS);
    final t = seg.tangentAt(bestS);
    return StationResult(startStation + _cum[bestI] + bestS, -t.cross(p - q), false);
  }

  /// Точка осі на проєктному пікетажі [station] (у межах осі).
  Vec pointAtStation(double station) {
    final a = (station - startStation).clamp(0.0, length);
    var i = 0;
    while (i < segs.length - 1 && _cum[i + 1] <= a) {
      i++;
    }
    return segs[i].pointAt(a - _cum[i]);
  }

  /// Перпендикуляр до осі в точці [station]: одиничний вектор праворуч.
  Vec rightNormalAt(double station) {
    final a = (station - startStation).clamp(0.0, length);
    var i = 0;
    while (i < segs.length - 1 && _cum[i + 1] <= a) {
      i++;
    }
    final t = segs[i].tangentAt(a - _cum[i]);
    return Vec(t.y, -t.x);
  }

  List<Vec> densify(double step) {
    final out = <Vec>[];
    for (final s in segs) {
      final pts = s.densify(step);
      out.addAll(out.isEmpty ? pts : pts.skip(1));
    }
    return out;
  }
}

/// Де пряма «точка [p] + t·[n]» ([n] — одиничний) перетинає шматок: значення t, м.
List<double> crossLine(Segment s, Vec p, Vec n) {
  switch (s) {
    case LineSeg():
      final d = s.end - s.start;
      final den = n.cross(d);
      if (den.abs() < 1e-12) return const []; // паралельно
      final ap = s.start - p;
      final t = ap.cross(d) / den;
      final u = ap.cross(n) / den;
      // Кінець лінії, що не дотягнув до поперечника на кілька сантиметрів, — теж перетин.
      final eps = 0.05 / d.length;
      return u >= -eps && u <= 1 + eps ? [t] : const [];
    case ArcSeg():
      final f = p - s.center;
      final b = f.dot(n);
      final disc = b * b - (f.dot(f) - s.radius * s.radius);
      if (disc < 0) return const [];
      final out = <double>[];
      const twoPi = 2 * math.pi;
      for (final t in {-b - math.sqrt(disc), -b + math.sqrt(disc)}) {
        final q = p + n * t - s.center;
        final ang = math.atan2(q.y, q.x);
        final d = s.sweep >= 0 ? (ang - s.startAngle) % twoPi : (s.startAngle - ang) % twoPi;
        if (d <= s.sweep.abs() + 1e-9) out.add(t);
      }
      return out;
    default:
      return const [];
  }
}

/// Прямокутник, що вміщає лінію, — щоб не перевіряти далекі лінії шматок за шматком.
class Box {
  final double minX, minY, maxX, maxY;
  const Box(this.minX, this.minY, this.maxX, this.maxY);

  factory Box.of(List<Segment> segs) {
    var x0 = double.infinity, y0 = double.infinity, x1 = -double.infinity, y1 = -double.infinity;
    for (final s in segs) {
      for (final p in s.densify(5)) {
        x0 = math.min(x0, p.x);
        y0 = math.min(y0, p.y);
        x1 = math.max(x1, p.x);
        y1 = math.max(y1, p.y);
      }
    }
    return Box(x0, y0, x1, y1);
  }

  /// Чи може лінія бути ближче за [r] м до точки [p].
  bool near(Vec p, double r) =>
      p.x >= minX - r && p.x <= maxX + r && p.y >= minY - r && p.y <= maxY + r;
}

/// Точка перетину двох відрізків (не на самих кінцях) або null.
Vec? _crossPoint(LineSeg a, LineSeg b) {
  final r = a.end - a.start, s = b.end - b.start;
  final den = r.cross(s);
  if (den.abs() < 1e-12) return null;
  final q = b.start - a.start;
  final t = q.cross(s) / den, u = q.cross(r) / den;
  const e = 1e-9;
  return t > e && t < 1 - e && u > e && u < 1 - e ? a.start + r * t : null;
}

/// Зрізає петлі, коли лінія перехльостує сама себе на короткому відрізку (до [maxLoop] м) — так буває з
/// кромками, побудованими зсувом від осі на гострому повороті. Лишається чистий кут у точці перетину.
/// Дуги не чіпаються.
List<Segment> removeLoops(List<Segment> segs, {double maxLoop = 50}) {
  final out = [...segs];
  var i = 0;
  while (i < out.length) {
    var cut = false;
    final a = out[i];
    if (a is LineSeg) {
      var along = 0.0;
      for (var j = i + 2; j < out.length && along <= maxLoop; j++) {
        along += out[j - 1].length;
        final b = out[j];
        if (b is! LineSeg) continue;
        final x = _crossPoint(a, b);
        if (x == null) continue;
        out.replaceRange(i, j + 1, [LineSeg(a.start, x), LineSeg(x, b.end)]);
        cut = true;
        break;
      }
    }
    if (!cut) i++;
  }
  return out;
}
