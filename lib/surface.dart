// ЦММ проєкту (TIN): трикутники в координатах креслення (X — схід, Y — північ, Z — проєктна відмітка).
// Відмітка в точці — з трикутника, у який точка потрапляє (площина через три вершини). Поза ЦММ — null.
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:xml/xml.dart';

import 'geometry.dart';
import 'i18n.dart';
import 'problems.dart';
import 'profile.dart';

class Surface {
  /// Звідки: «LandXML: Top», «DXF: XS_TIN».
  final String source;

  /// 9 чисел на трикутник: x1 y1 z1 x2 y2 z2 x3 y3 z3.
  final Float64List tri;
  Surface(this.source, this.tri);

  int get count => tri.length ~/ 9;

  late final _Grid _grid = _Grid(tri);

  /// Межі ЦММ у плані: (minX, minY, maxX, maxY).
  (double, double, double, double) get bounds => (_grid.x0, _grid.y0, _grid.x1, _grid.y1);

  /// Проєктна відмітка в точці [p], або null — точка поза ЦММ.
  double? elevationAt(Vec p) {
    for (final i in _grid.at(p.x, p.y)) {
      final k = i * 9;
      final x1 = tri[k], y1 = tri[k + 1], x2 = tri[k + 3], y2 = tri[k + 4], x3 = tri[k + 6], y3 = tri[k + 7];
      final det = (y2 - y3) * (x1 - x3) + (x3 - x2) * (y1 - y3);
      if (det.abs() < 1e-12) continue; // вертикальна грань (бордюр) — у плані без площі
      final a = ((y2 - y3) * (p.x - x3) + (x3 - x2) * (p.y - y3)) / det;
      final b = ((y3 - y1) * (p.x - x3) + (x1 - x3) * (p.y - y3)) / det;
      final c = 1 - a - b;
      const eps = -1e-9;
      if (a < eps || b < eps || c < eps) continue;
      return a * tri[k + 2] + b * tri[k + 5] + c * tri[k + 8];
    }
    return null;
  }

  /// Файл ЦММ у пам'яті програми: 256 байт заголовка (JSON), далі числа трикутників.
  Uint8List encode() {
    final head = utf8.encode(jsonEncode({'format': 1, 'source': source, 'n': count}));
    final out = Uint8List(256 + tri.length * 8);
    out.setAll(0, head.length > 256 ? head.sublist(0, 256) : head);
    for (var i = head.length; i < 256; i++) {
      out[i] = 0x20;
    }
    final bd = ByteData.sublistView(out);
    for (var i = 0; i < tri.length; i++) {
      bd.setFloat64(256 + i * 8, tri[i], Endian.little);
    }
    return out;
  }

  static Surface decode(Uint8List b) {
    final head = jsonDecode(utf8.decode(b.sublist(0, 256)).trim()) as Map<String, dynamic>;
    final n = (head['n'] as num).toInt() * 9;
    final bd = ByteData.sublistView(b);
    final tri = Float64List(n);
    for (var i = 0; i < n; i++) {
      tri[i] = bd.getFloat64(256 + i * 8, Endian.little);
    }
    return Surface(head['source'] as String, tri);
  }
}

/// Рівномірна сітка над ЦММ: у кожній клітинці — трикутники, що в неї заходять.
class _Grid {
  late final double x0, y0, x1, y1, cell;
  late final int nx, ny;
  late final List<List<int>> cells;
  _Grid(Float64List t) {
    var a = double.infinity, b = double.infinity, c = -double.infinity, d = -double.infinity;
    for (var k = 0; k < t.length; k += 3) {
      a = math.min(a, t[k]);
      c = math.max(c, t[k]);
      b = math.min(b, t[k + 1]);
      d = math.max(d, t[k + 1]);
    }
    x0 = a;
    y0 = b;
    x1 = c;
    y1 = d;
    final n = t.length ~/ 9;
    // Близько двох трикутників на клітинку; сторона клітинки — не менше 0.1 м.
    final area = math.max((x1 - x0) * (y1 - y0), 1e-6);
    cell = math.max(0.1, math.sqrt(area / math.max(1, n / 2)));
    nx = math.max(1, ((x1 - x0) / cell).ceil());
    ny = math.max(1, ((y1 - y0) / cell).ceil());
    cells = List.generate(nx * ny, (_) => <int>[]);
    for (var i = 0; i < n; i++) {
      final k = i * 9;
      final ax = math.min(t[k], math.min(t[k + 3], t[k + 6])), bx = math.max(t[k], math.max(t[k + 3], t[k + 6]));
      final ay = math.min(t[k + 1], math.min(t[k + 4], t[k + 7])), by = math.max(t[k + 1], math.max(t[k + 4], t[k + 7]));
      for (var gx = _ix(ax); gx <= _ix(bx); gx++) {
        for (var gy = _iy(ay); gy <= _iy(by); gy++) {
          cells[gy * nx + gx].add(i);
        }
      }
    }
  }

  int _ix(double x) => ((x - x0) / cell).floor().clamp(0, nx - 1);
  int _iy(double y) => ((y - y0) / cell).floor().clamp(0, ny - 1);

  List<int> at(double x, double y) =>
      x < x0 || x > x1 || y < y0 || y > y1 ? const [] : cells[_iy(y) * nx + _ix(x)];
}

class SurfaceException implements Exception {
  final Problem problem;
  const SurfaceException(this.problem);
}

// Поверхня проєкту (верх), а не земля: Civil 3D пише Top / FG / Finished Grade, румунською — Proiect.
final _design = RegExp(r'top|finish|design|(^|[^a-z])fg([^a-z]|$)|proiect|проєкт|проект|верх', caseSensitive: false);
final _ground = RegExp(r'(^|[^a-z])eg([^a-z]|$)|exist|ground|teren|natural|земл|існу|сущ|topo', caseSensitive: false);

/// Чи схожа назва поверхні на проєктну (1), на землю (−1), чи невідомо (0) — щоб запропонувати правильну.
int designScore(String name) => _design.hasMatch(name) ? 1 : (_ground.hasMatch(name) ? -1 : 0);

/// Поверхні (TIN) з LandXML: точки «північ схід відмітка» → X = схід, Y = північ; невидимі грані (i="1") — пропущено.
List<Surface> parseLandXmlSurfaces(Uint8List bytes) {
  XmlDocument doc;
  try {
    doc = XmlDocument.parse(utf8.decode(bytes, allowMalformed: true));
  } on XmlException {
    throw const SurfaceException(noSurface);
  }
  final unit = doc.findAllElements('Metric').firstOrNull?.getAttribute('linearUnit') ??
      (doc.findAllElements('Imperial').isNotEmpty ? 'foot' : 'meter');
  if (unit != 'meter') {
    throw SurfaceException(Problem(Severity.error, t('Одиниці LandXML — «{u}», а не метри', {'u': unit}),
        fixes: const ['Експортуйте LandXML з метричними одиницями (налаштування креслення Civil 3D → Units: Meters).']));
  }
  final out = <Surface>[];
  for (final s in doc.findAllElements('Surface')) {
    final pts = <String, (double, double, double)>{};
    for (final p in s.findAllElements('P')) {
      final v = p.innerText.trim().split(RegExp(r'\s+')).map(double.tryParse).toList();
      final id = p.getAttribute('id');
      if (id == null || v.length < 3 || v.take(3).any((x) => x == null)) continue;
      pts[id] = (v[1]!, v[0]!, v[2]!);
    }
    final tri = <double>[];
    for (final f in s.findAllElements('F')) {
      if (f.getAttribute('i') == '1') continue;
      final ids = f.innerText.trim().split(RegExp(r'\s+'));
      if (ids.length < 3) continue;
      final a = pts[ids[0]], b = pts[ids[1]], c = pts[ids[2]];
      if (a == null || b == null || c == null) continue;
      tri.addAll([a.$1, a.$2, a.$3, b.$1, b.$2, b.$3, c.$1, c.$2, c.$3]);
    }
    if (tri.isNotEmpty) {
      out.add(Surface('LandXML: ${s.getAttribute('name') ?? t('поверхня {n}', {'n': out.length + 1})}', Float64List.fromList(tri)));
    }
  }
  if (out.isEmpty) throw const SurfaceException(noSurface);
  return out;
}

const noSurface = Problem(Severity.error, 'У файлі немає поверхні (ЦММ)',
    fixes: [
      'Civil 3D: «Вивід → Експорт у LandXML» — позначте поверхню проєкту (наприклад коридору «Top»).',
      'Або креслення з 3D-гранями: Civil 3D — «Витягнути об’єкти з поверхні» (3D Faces), збережіть як DXF.',
    ]);

// ---------- Програма будує ЦММ сама ----------

/// Тріангуляція Делоне точок [xyz] (x y z підряд) — алгоритм «опуклої оболонки, що росте» (як у бібліотеці
/// Delaunator): точки за віддаленістю від центру, кожна з'єднується з видимою частиною оболонки, далі — перевертання
/// ребер, доки трикутники не стануть «правильними». Трикутники з ребром, довшим за [maxEdge], відкидаються: на
/// кривій трасі опукла оболонка інакше перекине трикутники через поворот, де зйомки немає.
Float64List triangulate(List<double> xyz, {double maxEdge = 60}) {
  final n = xyz.length ~/ 3;
  if (n < 3) return Float64List(0);
  // Координати від центру — великі числа (600 000 у Stereo 70) з'їдають точність перевірок «по який бік».
  var mx = 0.0, my = 0.0;
  for (var i = 0; i < n; i++) {
    mx += xyz[3 * i] / n;
    my += xyz[3 * i + 1] / n;
  }
  final x = Float64List(n), y = Float64List(n);
  for (var i = 0; i < n; i++) {
    x[i] = xyz[3 * i] - mx;
    y[i] = xyz[3 * i + 1] - my;
  }
  final d = _Delaunay(x, y);
  final out = <double>[];
  final t = d.triangles;
  double len2(int a, int b) => (x[a] - x[b]) * (x[a] - x[b]) + (y[a] - y[b]) * (y[a] - y[b]);
  final m2 = maxEdge * maxEdge;
  for (var k = 0; k < d.len; k += 3) {
    final a = t[k], b = t[k + 1], c = t[k + 2];
    if (len2(a, b) > m2 || len2(b, c) > m2 || len2(c, a) > m2) continue;
    for (final i in [a, b, c]) {
      out.addAll([xyz[3 * i], xyz[3 * i + 1], xyz[3 * i + 2]]);
    }
  }
  return Float64List.fromList(out);
}

class _Delaunay {
  final Float64List x, y;
  late final Uint32List triangles;
  late final Int32List halfedges;
  int len = 0;
  late final Uint32List _prev, _next, _tri;
  late final Int32List _hash;
  late final int _hashSize;
  double _cx = 0, _cy = 0;
  int _start = 0;
  final _stack = Uint32List(512);

  _Delaunay(this.x, this.y) {
    final n = x.length;
    final maxT = math.max(2 * n - 5, 0);
    triangles = Uint32List(maxT * 3);
    halfedges = Int32List(maxT * 3);
    _hashSize = math.sqrt(n).ceil();
    _prev = Uint32List(n);
    _next = Uint32List(n);
    _tri = Uint32List(n);
    _hash = Int32List(_hashSize)..fillRange(0, _hashSize, -1);
    _run();
  }

  static double _d2(double ax, double ay, double bx, double by) => (ax - bx) * (ax - bx) + (ay - by) * (ay - by);

  /// Чи r праворуч від напряму p → q.
  static bool _orient(double px, double py, double qx, double qy, double rx, double ry) =>
      (qy - py) * (rx - qx) - (qx - px) * (ry - qy) < 0;

  static bool _inCircle(double ax, double ay, double bx, double by, double cx, double cy, double px, double py) {
    final dx = ax - px, dy = ay - py, ex = bx - px, ey = by - py, fx = cx - px, fy = cy - py;
    final ap = dx * dx + dy * dy, bp = ex * ex + ey * ey, cp = fx * fx + fy * fy;
    return dx * (ey * cp - bp * fy) - dy * (ex * cp - bp * fx) + ap * (ex * fy - ey * fx) < 0;
  }

  /// Центр описаного кола відносно (ax, ay).
  static (double, double) _circ(double ax, double ay, double bx, double by, double cx, double cy) {
    final dx = bx - ax, dy = by - ay, ex = cx - ax, ey = cy - ay;
    final bl = dx * dx + dy * dy, cl = ex * ex + ey * ey, d = 0.5 / (dx * ey - dy * ex);
    return ((ey * bl - dy * cl) * d, (dx * cl - ex * bl) * d);
  }

  int _key(double px, double py) {
    final dx = px - _cx, dy = py - _cy;
    final p = dx / (dx.abs() + dy.abs());
    final a = (dy > 0 ? 3 - p : 1 + p) / 4; // «псевдокут» 0..1
    return (a * _hashSize).floor() % _hashSize;
  }

  void _link(int a, int b) {
    halfedges[a] = b;
    if (b != -1) halfedges[b] = a;
  }

  int _add(int i0, int i1, int i2, int a, int b, int c) {
    final t = len;
    triangles[t] = i0;
    triangles[t + 1] = i1;
    triangles[t + 2] = i2;
    _link(t, a);
    _link(t + 1, b);
    _link(t + 2, c);
    len += 3;
    return t;
  }

  void _run() {
    final n = x.length;
    var minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
    for (var i = 0; i < n; i++) {
      minX = math.min(minX, x[i]);
      minY = math.min(minY, y[i]);
      maxX = math.max(maxX, x[i]);
      maxY = math.max(maxY, y[i]);
    }
    final cx = (minX + maxX) / 2, cy = (minY + maxY) / 2;
    var i0 = 0, i1 = 0, i2 = 0;
    var best = double.infinity;
    for (var i = 0; i < n; i++) {
      final d = _d2(cx, cy, x[i], y[i]);
      if (d < best) {
        i0 = i;
        best = d;
      }
    }
    best = double.infinity;
    for (var i = 0; i < n; i++) {
      if (i == i0) continue;
      final d = _d2(x[i0], y[i0], x[i], y[i]);
      if (d < best && d > 0) {
        i1 = i;
        best = d;
      }
    }
    var minR = double.infinity;
    for (var i = 0; i < n; i++) {
      if (i == i0 || i == i1) continue;
      final c = _circ(x[i0], y[i0], x[i1], y[i1], x[i], y[i]);
      final r = c.$1 * c.$1 + c.$2 * c.$2;
      if (r < minR) {
        i2 = i;
        minR = r;
      }
    }
    if (minR == double.infinity) return; // усі точки на одній прямій — трикутників немає
    if (_orient(x[i0], y[i0], x[i1], y[i1], x[i2], y[i2])) {
      final t = i1;
      i1 = i2;
      i2 = t;
    }
    final c = _circ(x[i0], y[i0], x[i1], y[i1], x[i2], y[i2]);
    _cx = x[i0] + c.$1;
    _cy = y[i0] + c.$2;
    final dists = Float64List(n);
    for (var i = 0; i < n; i++) {
      dists[i] = _d2(x[i], y[i], _cx, _cy);
    }
    final ids = List<int>.generate(n, (i) => i)..sort((a, b) => dists[a].compareTo(dists[b]));

    _start = i0;
    _next[i0] = _prev[i2] = i1;
    _next[i1] = _prev[i0] = i2;
    _next[i2] = _prev[i1] = i0;
    _tri[i0] = 0;
    _tri[i1] = 1;
    _tri[i2] = 2;
    _hash[_key(x[i0], y[i0])] = i0;
    _hash[_key(x[i1], y[i1])] = i1;
    _hash[_key(x[i2], y[i2])] = i2;
    _add(i0, i1, i2, -1, -1, -1);

    var xp = 0.0, yp = 0.0;
    for (var k = 0; k < ids.length; k++) {
      final i = ids[k];
      final px = x[i], py = y[i];
      if (k > 0 && (px - xp).abs() <= 1e-9 && (py - yp).abs() <= 1e-9) continue; // повтор точки
      xp = px;
      yp = py;
      if (i == i0 || i == i1 || i == i2) continue;
      // Видиме ребро оболонки — через хеш за кутом.
      var start = 0;
      for (var j = 0, key = _key(px, py); j < _hashSize; j++) {
        start = _hash[(key + j) % _hashSize];
        if (start != -1 && start != _next[start]) break;
      }
      start = _prev[start];
      var e = start;
      var q = _next[e];
      while (!_orient(px, py, x[e], y[e], x[q], y[q])) {
        e = q;
        if (e == start) {
          e = -1;
          break;
        }
        q = _next[e];
      }
      if (e == -1) continue; // майже повтор точки
      var t = _add(e, i, _next[e], -1, -1, _tri[e]);
      _tri[i] = _legalize(t + 2);
      _tri[e] = t;
      var nn = _next[e];
      q = _next[nn];
      while (_orient(px, py, x[nn], y[nn], x[q], y[q])) {
        t = _add(nn, i, q, _tri[i], -1, _tri[nn]);
        _tri[i] = _legalize(t + 2);
        _next[nn] = nn; // прибрано з оболонки
        nn = q;
        q = _next[nn];
      }
      if (e == start) {
        q = _prev[e];
        while (_orient(px, py, x[q], y[q], x[e], y[e])) {
          t = _add(q, i, e, -1, _tri[e], _tri[q]);
          _legalize(t + 2);
          _tri[q] = t;
          _next[e] = e;
          e = q;
          q = _prev[e];
        }
      }
      _start = _prev[i] = e;
      _next[e] = _prev[nn] = i;
      _next[i] = nn;
      _hash[_key(px, py)] = i;
      _hash[_key(x[e], y[e])] = e;
    }
  }

  int _legalize(int start) {
    var a = start;
    var i = 0;
    var ar = 0;
    while (true) {
      final b = halfedges[a];
      final a0 = a - a % 3;
      ar = a0 + (a + 2) % 3;
      if (b == -1) {
        if (i == 0) break;
        a = _stack[--i];
        continue;
      }
      final b0 = b - b % 3;
      final al = a0 + (a + 1) % 3;
      final bl = b0 + (b + 2) % 3;
      final p0 = triangles[ar], pr = triangles[a], pl = triangles[al], p1 = triangles[bl];
      if (_inCircle(x[p0], y[p0], x[pr], y[pr], x[pl], y[pl], x[p1], y[p1])) {
        triangles[a] = p1;
        triangles[b] = p0;
        final hbl = halfedges[bl];
        if (hbl == -1) {
          var e = _start;
          do {
            if (_tri[e] == bl) {
              _tri[e] = a;
              break;
            }
            e = _prev[e];
          } while (e != _start);
        }
        _link(a, hbl);
        _link(b, halfedges[ar]);
        _link(ar, bl);
        final br = b0 + (b + 1) % 3;
        if (i < _stack.length) _stack[i++] = br;
      } else {
        if (i == 0) break;
        a = _stack[--i];
      }
    }
    return ar;
  }
}

/// ЦММ проєкту з поперечників: точки кожного поперечника — у план (ПК і зміщення від осі), сусідні поперечники
/// з'єднуються смугами по два трикутники. Однакова кількість точок — точка з точкою (кромка з кромкою); різна —
/// за однаковими зміщеннями ([CrossSections.lineAt] посередині між ними).
Surface surfaceFromSections(CrossSections cs, RoadAxis axis, String source) {
  final tri = <double>[];
  List<double> at(double st, (double, double) p) {
    final q = axis.pointAtStation(st) + axis.rightNormalAt(st) * p.$1;
    return [q.x, q.y, p.$2];
  }

  for (var i = 0; i + 1 < cs.rows.length; i++) {
    var a = cs.rows[i].$2, c = cs.rows[i + 1].$2;
    final sa = cs.rows[i].$1, sc = cs.rows[i + 1].$1;
    if (a.length != c.length) {
      // Різна будова — обидва поперечники на спільних зміщеннях (так само, як інтерполяція між ними).
      (a, c) = CrossSections.align(a, c);
    }
    for (var k = 0; k + 1 < a.length; k++) {
      final a0 = at(sa, a[k]), a1 = at(sa, a[k + 1]), c0 = at(sc, c[k]), c1 = at(sc, c[k + 1]);
      tri.addAll([...a0, ...a1, ...c1, ...a0, ...c1, ...c0]);
    }
  }
  return Surface(source, Float64List.fromList(tri));
}
