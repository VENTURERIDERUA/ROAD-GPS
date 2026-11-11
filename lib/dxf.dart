// Читання текстового DXF: лінії, дуги, полілінії й підписи по шарах — і всередині вставлених блоків (INSERT).
// Об'єкти Civil 3D не розбираються — лише рахуються, щоб попередити.
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'chainage.dart';
import 'geometry.dart';
import 'i18n.dart';
import 'problems.dart';

/// Файл не прочитався; [problem] каже, що робити.
class DxfException extends FormatException {
  final Problem problem;
  DxfException(this.problem) : super(problem.title);
}

class DxfLayer {
  final String name;
  final List<Segment> segments = [];
  final List<LabelPoint> labels = [];

  /// 3D-грані (ЦММ): 9 чисел на трикутник — x y z трьох вершин; чотирикутна грань — два трикутники.
  final List<double> faces = [];

  /// Точки з відмітками (x y z підряд) — для ЦММ, яку будує програма: точки, вставки блоків (пікети зйомки) і
  /// вершини ліній з відміткою Z ≠ 0.
  final List<double> points3d = [];

  /// Скільки об'єктів якого типу на шарі (LINE, ARC, LWPOLYLINE, ACAD_PROXY_ENTITY…).
  final Map<String, int> counts = {};
  DxfLayer(this.name);

  double get length => segments.fold(0.0, (a, s) => a + s.length);

  /// Об'єкти, схожі на лінії, яких програма не читає: блоки, Civil 3D (proxy), сплайни… — за типом.
  Map<String, int> get unreadableKinds => {
        for (final e in counts.entries)
          if (!_readable.contains(e.key) && !_ignorable.contains(e.key)) e.key: e.value
      };

  int get unreadable => unreadableKinds.values.fold(0, (a, v) => a + v);
}

const _readable = {'LINE', 'ARC', 'LWPOLYLINE', 'POLYLINE', 'TEXT', 'MTEXT', 'INSERT_READ', '3DFACE'};

/// Не лінії — для осі й кромок не потрібні, попереджати про них нема чого.
const _ignorable = {
  'POINT', 'HATCH', 'DIMENSION', 'SOLID', 'LEADER', 'MLEADER', 'MULTILEADER', 'ATTDEF', 'ATTRIB',
  'VIEWPORT', 'WIPEOUT', 'IMAGE', 'OLE2FRAME', 'TOLERANCE', 'CIRCLE', 'TRACE',
};

class DxfDrawing {
  final Map<String, DxfLayer> layers;

  /// Попередження про креслення в цілому.
  final List<Problem> problems;
  DxfDrawing(this.layers, this.problems);
}

class _Ent {
  final String type;
  final List<(int, String)> g = [];
  _Ent(this.type);

  String? s(int code) {
    for (final p in g) {
      if (p.$1 == code) return p.$2;
    }
    return null;
  }

  double d(int code, [double def = 0]) => double.tryParse(s(code)?.trim() ?? '') ?? def;
  String get layer => s(8)?.trim() ?? '0';

  /// Нормаль площини об'єкта з Z < 0 — креслення «дзеркальне» (OCS): X треба взяти з мінусом.
  bool get mirrored => d(230, 1) < 0;
}

DxfDrawing parseDxf(Uint8List bytes) {
  const binSentinel = 'AutoCAD Binary DXF';
  if (bytes.length > binSentinel.length &&
      latin1.decode(bytes.sublist(0, binSentinel.length)) == binSentinel) {
    throw DxfException(binaryDxf);
  }
  String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    text = latin1.decode(bytes); // старі DXF у кодуванні Windows; числа читаються однаково
  }
  final lines = const LineSplitter().convert(text);

  // Пари «код — значення» з розділів ENTITIES (креслення) і BLOCKS (вміст блоків).
  final ents = <_Ent>[];
  final blocks = <String, _Block>{};
  String? section;
  var sawEntities = false;
  _Block? block;
  _Ent? cur;
  void close() {
    final e = cur;
    cur = null;
    if (e == null) return;
    if (section == 'ENTITIES') {
      ents.add(e);
    } else if (e.type == 'BLOCK') {
      block = _Block(Vec(e.d(10), e.d(20)));
      blocks[e.s(2)?.trim() ?? ''] = block!;
    } else if (e.type == 'ENDBLK') {
      block = null;
    } else {
      block?.ents.add(e);
    }
  }

  for (var i = 0; i + 1 < lines.length; i += 2) {
    final code = int.tryParse(lines[i].trim());
    if (code == null) {
      throw DxfException(notDxf(t('рядок {n} — «{s}» замість числового коду', {'n': i + 1, 's': _short(lines[i])})));
    }
    final val = lines[i + 1];
    if (section == null) {
      if (code == 2) {
        section = val.trim();
        if (section == 'ENTITIES') sawEntities = true;
      }
      continue;
    }
    if (code == 0) {
      close();
      if (val.trim() == 'ENDSEC') {
        section = null;
        continue;
      }
      if (section == 'ENTITIES' || section == 'BLOCKS') cur = _Ent(val.trim());
    } else {
      cur?.g.add((code, val));
    }
  }
  close();
  if (!sawEntities) throw DxfException(lines.isEmpty ? notDxf(t('файл порожній')) : noEntities);

  final layers = <String, DxfLayer>{};
  final problems = <Problem>[];
  DxfLayer layerOf(String name) => layers[name] ??= DxfLayer(name);

  /// Об'єкти [list] у координатах креслення через [xf]; [inherit] — шар вставки для об'єктів на шарі «0» блоку.
  void read(List<_Ent> list, _Xf xf, String? inherit, int depth) {
    for (var i = 0; i < list.length; i++) {
      final e = list[i];
      if (e.type == 'VERTEX' || e.type == 'SEQEND') continue; // розбираються разом з POLYLINE
      final name = inherit != null && e.layer == '0' ? inherit : e.layer;
      final layer = layerOf(name);
      // Вставка блоку, який знайдено, — читається, тож не попереджаємо про неї як про «блок».
      final b = e.type == 'INSERT' && depth < 8 ? blocks[e.s(2)?.trim()] : null;
      final kind = b == null ? e.type : 'INSERT_READ';
      layer.counts[kind] = (layer.counts[kind] ?? 0) + 1;
      switch (e.type) {
        case 'LINE':
          layer.segments.add(xf.seg(LineSeg(Vec(e.d(10), e.d(20)), Vec(e.d(11), e.d(21)))));
          _z(layer, xf, e.d(10), e.d(20), e.d(30));
          _z(layer, xf, e.d(11), e.d(21), e.d(31));
        case 'POINT':
          _z(layer, xf, e.d(10), e.d(20), e.d(30));
        case 'ARC':
          layer.segments.addAll(xf.any(_arc(e)));
        case 'LWPOLYLINE':
          final segs = _lwpolyline(e);
          for (final s in segs) {
            layer.segments.addAll(xf.any(s));
          }
          // Полілінія на висоті (код 38) — горизонталь чи лінія з однією відміткою.
          for (final s in segs) {
            _z(layer, xf, s.start.x, s.start.y, e.d(38));
          }
        case 'POLYLINE':
          final verts = <_Ent>[];
          while (i + 1 < list.length && list[i + 1].type == 'VERTEX') {
            verts.add(list[++i]);
          }
          if (e.d(70).toInt() & 64 != 0) {
            _polyface(verts, xf, layer.faces);
          } else {
            for (final s in _polyline(e, verts)) {
              layer.segments.addAll(xf.any(s));
            }
            for (final v in verts) {
              if (v.d(70).toInt() & 16 == 0) _z(layer, xf, v.d(10), v.d(20), v.d(30));
            }
          }
        case '3DFACE':
          List<double> c(int k) {
            final p = xf.apply(Vec(e.d(10 + k), e.d(20 + k)));
            return [p.x, p.y, e.d(30 + k)];
          }
          final a = c(0), b = c(1), cc = c(2), d = c(3);
          layer.faces.addAll([...a, ...b, ...cc]);
          if ((d[0] - cc[0]).abs() + (d[1] - cc[1]).abs() + (d[2] - cc[2]).abs() > 1e-9) {
            layer.faces.addAll([...a, ...cc, ...d]);
          }
        case 'TEXT':
          layer.labels.add(LabelPoint(e.s(1) ?? '', xf.apply(_maybeMirror(e, Vec(e.d(10), e.d(20))))));
        case 'MTEXT':
          final raw = [for (final p in e.g) if (p.$1 == 3 || p.$1 == 1) p.$2].join();
          layer.labels.add(LabelPoint(_plainMtext(raw), xf.apply(Vec(e.d(10), e.d(20)))));
        case 'INSERT' when b != null:
          // Пікет зйомки — блок-значок, вставлений на висоті точки.
          if (depth == 0) _z(layer, xf, e.d(10), e.d(20), e.d(30));
          read(b.ents, _insert(e, b.base).then(xf), name, depth + 1);
      }
    }
  }

  read(ents, _Xf.identity, null, 0);
  if (layers.values.any((l) => (l.counts['ACAD_PROXY_ENTITY'] ?? 0) > 0)) problems.add(proxyInDrawing);
  // Креслення лише з 3D-гранями (ЦММ) — теж креслення: його беруть як поверхню, не як вісь.
  if (layers.values.every((l) => l.segments.isEmpty && l.faces.isEmpty)) throw DxfException(noLines);
  return DxfDrawing(layers, problems);
}

/// Блок: базова точка й об'єкти всередині (у його власних координатах).
class _Block {
  final Vec base;
  final List<_Ent> ents = [];
  _Block(this.base);
}

/// Перетворення вставки: точка блоку → креслення. Базова точка блоку лягає в точку вставки; масштаби X/Y,
/// поворот; вставка з нормаллю Z < 0 — дзеркальна, як інші об'єкти (OCS).
_Xf _insert(_Ent e, Vec base) {
  final sx = e.d(41, 1), sy = e.d(42, 1), r = e.d(50) * math.pi / 180;
  final c = math.cos(r), s = math.sin(r);
  final ins = Vec(e.d(10), e.d(20));
  final a = c * sx, b = -s * sy, d = s * sx, f = c * sy;
  final m = _Xf(a, b, ins.x - (a * base.x + b * base.y), d, f, ins.y - (d * base.x + f * base.y));
  return e.mirrored ? m.then(const _Xf(-1, 0, 0, 0, 1, 0)) : m;
}

/// Афінне перетворення площини: (x, y) → (a·x + b·y + c, d·x + e·y + f).
class _Xf {
  final double a, b, c, d, e, f;
  const _Xf(this.a, this.b, this.c, this.d, this.e, this.f);
  static const identity = _Xf(1, 0, 0, 0, 1, 0);

  Vec apply(Vec p) => Vec(a * p.x + b * p.y + c, d * p.x + e * p.y + f);

  /// Спершу це перетворення, потім [o].
  _Xf then(_Xf o) => _Xf(o.a * a + o.b * d, o.a * b + o.b * e, o.a * c + o.b * f + o.c, o.d * a + o.e * d,
      o.d * b + o.e * e, o.d * c + o.e * f + o.f);

  Segment seg(LineSeg s) => identical(this, identity) ? s : LineSeg(apply(s.start), apply(s.end));

  Iterable<Segment> any(Segment s) => s is ArcSeg ? arc(s) : [seg(s as LineSeg)];

  /// Дуга лишається дугою при повороті й однаковому масштабі (і дзеркалі); при різних масштабах X/Y
  /// стає еліпсом — тоді ламана через кожні ~2°.
  Iterable<Segment> arc(ArcSeg s) {
    if (identical(this, identity)) return [s];
    final k1 = a * a + d * d, k2 = b * b + e * e;
    if ((k1 - k2).abs() <= 1e-9 * k1 && (a * b + d * e).abs() <= 1e-9 * k1) {
      final c0 = apply(s.center), p0 = apply(s.start);
      final mirror = a * e - b * d < 0;
      return [ArcSeg(c0, s.radius * math.sqrt(k1), math.atan2(p0.y - c0.y, p0.x - c0.x), mirror ? -s.sweep : s.sweep)];
    }
    final n = math.max(2, (s.sweep.abs() / (2 * math.pi / 180)).ceil());
    final pts = [for (var k = 0; k <= n; k++) apply(s.pointAt(s.length * k / n))];
    return [for (var k = 0; k < n; k++) LineSeg(pts[k], pts[k + 1])];
  }
}

String _short(String s) => s.length > 30 ? '${s.substring(0, 30)}…' : s.trim();

Vec _maybeMirror(_Ent e, Vec p) => e.mirrored ? Vec(-p.x, p.y) : p;

Segment _arc(_Ent e) {
  final r = e.d(40);
  final a0 = e.d(50) * math.pi / 180, a1 = e.d(51) * math.pi / 180;
  var sweep = (a1 - a0) % (2 * math.pi);
  if (sweep == 0) sweep = 2 * math.pi;
  final c = Vec(e.d(10), e.d(20));
  if (e.mirrored) {
    // Точка під кутом a в дзеркальній площині = під кутом π − a у звичайній, напрям — навпаки.
    return ArcSeg(Vec(-c.x, c.y), r, math.pi - a0, -sweep);
  }
  return ArcSeg(c, r, a0, sweep);
}

List<Segment> _fromVertices(List<Vec> pts, List<double> bulges, bool closed) {
  final out = <Segment>[];
  final n = pts.length;
  final count = closed ? n : n - 1;
  for (var k = 0; k < count; k++) {
    final a = pts[k], b = pts[(k + 1) % n];
    if (a.dist(b) < 1e-9) continue;
    final bulge = bulges[k];
    out.add(bulge.abs() < 1e-12 ? LineSeg(a, b) : ArcSeg.fromBulge(a, b, bulge));
  }
  return out;
}

List<Segment> _lwpolyline(_Ent e) {
  final pts = <Vec>[];
  final bulges = <double>[];
  double? x;
  for (final p in e.g) {
    final v = double.tryParse(p.$2.trim()) ?? 0;
    switch (p.$1) {
      case 10:
        x = v;
      case 20:
        pts.add(Vec(x ?? 0, v));
        bulges.add(0);
      case 42:
        if (bulges.isNotEmpty) bulges[bulges.length - 1] = v;
    }
  }
  final closed = (e.d(70).toInt() & 1) == 1;
  if (e.mirrored) {
    return _fromVertices(
        [for (final p in pts) Vec(-p.x, p.y)], [for (final b in bulges) -b], closed);
  }
  return _fromVertices(pts, bulges, closed);
}

List<Segment> _polyline(_Ent e, List<_Ent> verts) {
  final flags = e.d(70).toInt();
  if (flags & (16 | 64) != 0) return const []; // сітки й багатогранники — не лінії
  final is3d = flags & 8 != 0;
  final pts = <Vec>[];
  final bulges = <double>[];
  for (final v in verts) {
    if (v.d(70).toInt() & 16 != 0) continue; // керуючі точки сплайна
    pts.add(Vec(v.d(10), v.d(20)));
    bulges.add(is3d ? 0 : v.d(42));
  }
  final closed = flags & 1 == 1;
  if (!is3d && e.mirrored) {
    return _fromVertices(
        [for (final p in pts) Vec(-p.x, p.y)], [for (final b in bulges) -b], closed);
  }
  return _fromVertices(pts, bulges, closed);
}

/// Точка з відміткою — у [DxfLayer.points3d], якщо відмітка є (Z ≠ 0: «нуль» у кресленнях означає «без висоти»).
void _z(DxfLayer layer, _Xf xf, double x, double y, double z) {
  if (z.abs() < 1e-6) return;
  final p = xf.apply(Vec(x, y));
  layer.points3d.addAll([p.x, p.y, z]);
}

/// Сітка-багатогранник (POLYLINE з прапорцем 64): спершу вершини (VERTEX з прапорцями 64+128), далі грані
/// (VERTEX з прапорцем 128 без 64; номери вершин у 71–74, від одиниці, мінус — невидиме ребро).
void _polyface(List<_Ent> verts, _Xf xf, List<double> out) {
  final pts = <List<double>>[];
  for (final v in verts) {
    final f = v.d(70).toInt();
    if (f & 64 != 0) {
      final p = xf.apply(Vec(v.d(10), v.d(20)));
      pts.add([p.x, p.y, v.d(30)]);
    } else if (f & 128 != 0) {
      final ids = [for (final c in [71, 72, 73, 74]) v.d(c).toInt().abs()].where((n) => n > 0).toList();
      if (ids.length < 3 || ids.any((n) => n > pts.length)) continue;
      out.addAll([...pts[ids[0] - 1], ...pts[ids[1] - 1], ...pts[ids[2] - 1]]);
      if (ids.length == 4) out.addAll([...pts[ids[0] - 1], ...pts[ids[2] - 1], ...pts[ids[3] - 1]]);
    }
  }
}

String _plainMtext(String s) => s
    .replaceAll(RegExp(r'\\[Pp]'), ' ')
    .replaceAll(RegExp(r'\\[A-Za-z][^;\\]*;'), '')
    .replaceAll(RegExp(r'[{}]'), '')
    .trim();
