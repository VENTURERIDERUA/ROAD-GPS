// Лінії векторного PDF (креслення, «надруковане» з AutoCAD / Civil 3D): шляхи сторінки з кольором — щоб торкання
// лінії брало саму лінію креслення, а не пікселі зображення. Лише читання; скан (картинка) ліній не має — порожньо.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'geometry.dart';

/// Лінія сторінки: точки в пунктах від верхнього лівого кута сторінки, як її видно (з урахуванням повороту),
/// Y — униз (як у зображення сторінки); колір обведення 0xRRGGBB; товщина в пунктах.
class PdfStroke {
  final List<Vec> pts;
  final int rgb;
  final double width;
  const PdfStroke(this.pts, this.rgb, this.width);
}

/// Лінії сторінки [page] (з нуля) і її розмір у пунктах, як її видно. Не PDF, шифрований, немає такої сторінки — null.
(List<PdfStroke>, double, double)? pdfPageStrokes(Uint8List bytes, int page) {
  try {
    final doc = _Doc(bytes);
    final pages = doc.pages();
    if (page < 0 || page >= pages.length) return null;
    return doc.strokes(pages[page]);
  } catch (_) {
    return null;
  }
}

/// Лінії в одиницях зображення сторінки: [k] — пікселів на пункт.
List<PdfStroke> scaleStrokes(List<PdfStroke> strokes, double k) =>
    [for (final s in strokes) PdfStroke([for (final p in s.pts) p * k], s.rgb, s.width * k)];

/// Лінії всіх сторінок за один розбір файлу (null — сторінку не прочитано). Не PDF чи шифрований — порожньо.
List<(List<PdfStroke>, double, double)?> pdfAllStrokes(Uint8List bytes) {
  try {
    final doc = _Doc(bytes);
    return [
      for (final p in doc.pages())
        () {
          try {
            return doc.strokes(p);
          } catch (_) {
            return null;
          }
        }()
    ];
  } catch (_) {
    return const [];
  }
}

/// Для `compute`: лінії всіх сторінок ([pdfAllStrokes]).
List<(List<PdfStroke>, double, double)?> pdfAllStrokesOf(Uint8List bytes) => pdfAllStrokes(bytes);

/// Аргумент для `compute`: (байти PDF, сторінка).
(List<PdfStroke>, double, double)? pdfPageStrokesOf((Uint8List, int) a) => pdfPageStrokes(a.$1, a.$2);

/// Сіра чи чорна (сітка, рамки, підписи) — не кольорова.
bool isGrey(int rgb) {
  final r = rgb >> 16, g = (rgb >> 8) & 255, b = rgb & 255;
  return math.max(r, math.max(g, b)) - math.min(r, math.min(g, b)) < 40;
}

/// Лінія креслення від одного торкання: найближчий до [p] (у межах [radius]) відрізок і всі з'єднані з ним кінцями
/// відрізки того самого кольору — далі ліворуч і праворуч, на розгалуженнях — найпрямішим продовженням (вертикальні
/// риски переломів не збивають). Проєктні лінії виділено кольором — кольорова лінія в межах [radius] переважає сіру
/// чи чорну, навіть ближчу. Точки — зліва направо, у тих самих одиницях, що й [strokes]. Нічого поруч — порожньо.
List<Vec> pickVectorLine(List<PdfStroke> strokes, Vec p, {double radius = 12, double join = 1.0}) {
  final segs = _segments(strokes);
  final first = _nearest(segs, p, radius);
  if (first == null) return const [];
  return _chain(segs, first, join);
}

/// Колір лінії, яку бере [pickVectorLine] для того самого торкання; нічого поруч — null.
int? pickVectorRgb(List<PdfStroke> strokes, Vec p, {double radius = 12}) => _nearest(_segments(strokes), p, radius)?.$3;

/// Усі окремі лінії кольору [rgb] на сторінці — кожна зліва направо, як від дотику до неї ([pickVectorLine]).
List<List<Vec>> vectorLinesOfColor(List<PdfStroke> strokes, int rgb, {double join = 1.0}) {
  final segs = _segments(strokes);
  final out = <List<Vec>>[];
  final seen = <String>{};
  for (final s in segs) {
    if (s.$3 != rgb) continue;
    final line = _chain(segs, s, join);
    if (line.length < 2) continue;
    final key = '${line.first.x.toStringAsFixed(1)}:${line.first.y.toStringAsFixed(1)}:${line.last.x.toStringAsFixed(1)}';
    if (seen.add(key)) out.add(line);
  }
  return out;
}

List<(Vec, Vec, int)> _segments(List<PdfStroke> strokes) => [
      for (final s in strokes)
        for (var i = 1; i < s.pts.length; i++)
          if (s.pts[i - 1].dist(s.pts[i]) > 1e-6) (s.pts[i - 1], s.pts[i], s.rgb)
    ];

(Vec, Vec, int)? _nearest(List<(Vec, Vec, int)> segs, Vec p, double radius) {
  double distTo((Vec, Vec, int) s) {
    final d = s.$2 - s.$1;
    final t = ((p - s.$1).dot(d) / d.dot(d)).clamp(0.0, 1.0);
    return (s.$1 + d * t - p).length;
  }

  // Кольорова лінія в межах [radius] — найближча з кольорових, навіть коли сіра ближча; кольорової немає — сіра.
  (Vec, Vec, int)? first, firstGrey;
  var best = radius, bestGrey = radius;
  for (final s in segs) {
    final d = distTo(s);
    if (isGrey(s.$3)) {
      if (d < bestGrey) {
        bestGrey = d;
        firstGrey = s;
      }
    } else if (d < best) {
      best = d;
      first = s;
    }
  }
  return first ?? firstGrey;
}

/// Лінія від відрізка [first]: з'єднані кінцями відрізки того самого кольору — ліворуч і праворуч.
List<Vec> _chain(List<(Vec, Vec, int)> segs, (Vec, Vec, int) first, double join) {
  final rgb = first.$3;
  // Кінці відрізків того самого кольору — у сітці з кроком [join].
  final same = [for (final s in segs) if (s.$3 == rgb) s];
  final grid = <(int, int), List<int>>{};
  (int, int) cell(Vec v) => ((v.x / join).floor(), (v.y / join).floor());
  for (var i = 0; i < same.length; i++) {
    for (final v in [same[i].$1, same[i].$2]) {
      (grid[cell(v)] ??= []).add(i);
    }
  }
  final used = <int>{same.indexOf(first)};

  // Від кінця [end] (прийшли з напрямом [dir]) — далі в бік [side] (+1 праворуч, −1 ліворуч).
  List<Vec> extend(Vec end, Vec dir, int side) {
    final out = <Vec>[];
    for (var guard = 0; guard < 100000; guard++) {
      final c = cell(end);
      int? next;
      Vec? far;
      var bestCos = -2.0;
      for (var dx = -1; dx <= 1; dx++) {
        for (var dy = -1; dy <= 1; dy++) {
          for (final i in grid[(c.$1 + dx, c.$2 + dy)] ?? const <int>[]) {
            if (used.contains(i)) continue;
            final s = same[i];
            final Vec o;
            if (s.$1.dist(end) <= join) {
              o = s.$2;
            } else if (s.$2.dist(end) <= join) {
              o = s.$1;
            } else {
              continue;
            }
            final step = o - end;
            // Лише туди, куди йдемо (вертикаль уступу — можна), не назад.
            if (step.x * side < -join) continue;
            final cos = step.dot(dir) / (step.length * dir.length + 1e-12);
            if (cos > bestCos) {
              bestCos = cos;
              next = i;
              far = o;
            }
          }
        }
      }
      if (next == null) break;
      used.add(next);
      dir = far! - end;
      end = far;
      out.add(end);
    }
    return out;
  }

  final a = first.$1.x <= first.$2.x ? first.$1 : first.$2, b = first.$1.x <= first.$2.x ? first.$2 : first.$1;
  final right = extend(b, b - a, 1), left = extend(a, a - b, -1);
  final line = [...left.reversed, a, b, ...right];
  // Пішла назад (лінія замкнена чи петля) — лише частина, що йде зліва направо.
  final out = <Vec>[line.first];
  for (final v in line.skip(1)) {
    if (v.x >= out.last.x - join) out.add(v);
  }
  return out;
}

// ---------- Розбір PDF ----------

class _Ref {
  final int n;
  const _Ref(this.n);
}

class _Name {
  final String s;
  const _Name(this.s);
}

class _Op {
  final String s;
  const _Op(this.s);
}

class _Stream {
  final Map<String, Object?> dict;
  final Uint8List raw;
  const _Stream(this.dict, this.raw);
}

bool _ws(int c) => c == 0 || c == 9 || c == 10 || c == 12 || c == 13 || c == 32;
bool _delim(int c) => c == 0x28 || c == 0x29 || c == 0x3C || c == 0x3E || c == 0x5B || c == 0x5D || c == 0x7B ||
    c == 0x7D || c == 0x2F || c == 0x25;

/// Читання об'єктів PDF з байтів: числа, імена, рядки, масиви, словники, посилання «n g R», оператори.
class _Lex {
  final Uint8List b;
  int pos;
  _Lex(this.b, this.pos);

  bool get end {
    _skip();
    return pos >= b.length;
  }

  void _skip() {
    while (pos < b.length) {
      final c = b[pos];
      if (_ws(c)) {
        pos++;
      } else if (c == 0x25) {
        while (pos < b.length && b[pos] != 10 && b[pos] != 13) {
          pos++;
        }
      } else {
        break;
      }
    }
  }

  String _word() {
    final s = pos;
    while (pos < b.length && !_ws(b[pos]) && !_delim(b[pos])) {
      pos++;
    }
    return String.fromCharCodes(b, s, pos);
  }

  Object? value() {
    _skip();
    if (pos >= b.length) return null;
    final c = b[pos];
    if (c == 0x2F) {
      pos++;
      return _Name(_word().replaceAllMapped(
          RegExp(r'#([0-9A-Fa-f]{2})'), (m) => String.fromCharCode(int.parse(m[1]!, radix: 16))));
    }
    if (c == 0x28) return _literal();
    if (c == 0x3C) {
      if (pos + 1 < b.length && b[pos + 1] == 0x3C) {
        pos += 2;
        return _dict();
      }
      final e = b.indexOf(0x3E, pos);
      pos = e < 0 ? b.length : e + 1;
      return '';
    }
    if (c == 0x5B) {
      pos++;
      final out = <Object?>[];
      while (true) {
        _skip();
        if (pos >= b.length) break;
        if (b[pos] == 0x5D) {
          pos++;
          break;
        }
        out.add(value());
      }
      return out;
    }
    if (c == 0x5D || c == 0x3E || c == 0x7B || c == 0x7D || c == 0x29) {
      pos++;
      return _Op(String.fromCharCode(c));
    }
    final w = _word();
    if (w.isEmpty) {
      pos++;
      return null;
    }
    final n = num.tryParse(w);
    if (n != null) {
      // «n g R» — посилання на об'єкт.
      if (n is int) {
        final save = pos;
        _skip();
        final g = _word();
        if (int.tryParse(g) != null) {
          _skip();
          if (pos < b.length && b[pos] == 0x52 && (pos + 1 >= b.length || _ws(b[pos + 1]) || _delim(b[pos + 1]))) {
            pos++;
            return _Ref(n);
          }
        }
        pos = save;
      }
      return n;
    }
    if (w.startsWith('.') || w.startsWith('-') || w.startsWith('+')) {
      final m = double.tryParse(w.replaceFirst(RegExp(r'^\+'), '').replaceFirst(RegExp(r'^-\.'), '-0.'));
      if (m != null) return m;
    }
    return switch (w) { 'true' => true, 'false' => false, 'null' => null, _ => _Op(w) };
  }

  String _literal() {
    pos++;
    var depth = 1;
    final out = StringBuffer();
    while (pos < b.length && depth > 0) {
      final c = b[pos++];
      if (c == 0x5C && pos < b.length) {
        out.writeCharCode(b[pos++]);
      } else if (c == 0x28) {
        depth++;
        out.writeCharCode(c);
      } else if (c == 0x29) {
        depth--;
        if (depth > 0) out.writeCharCode(c);
      } else {
        out.writeCharCode(c);
      }
    }
    return out.toString();
  }

  Map<String, Object?> _dict() {
    final out = <String, Object?>{};
    while (true) {
      _skip();
      if (pos >= b.length) break;
      if (b[pos] == 0x3E) {
        pos += 2;
        break;
      }
      final k = value();
      if (k is! _Name) continue;
      out[k.s] = value();
    }
    return out;
  }
}

/// Документ: таблиця об'єктів (пошуком «n g obj» по файлу — стійко до зламаних і дописаних xref) і об'єкти в
/// потоках об'єктів (PDF 1.5+).
class _Doc {
  final Uint8List b;
  final _offsets = <int, int>{};
  final _inStream = <int, (int, int)>{}; // об'єкт → (потік об'єктів, зміщення в ньому)
  final _cache = <int, Object?>{};
  final _streams = <int, Uint8List>{};

  _Doc(this.b) {
    if (b.length < 8 || String.fromCharCodes(b, 0, 5) != '%PDF-') throw const FormatException('not a PDF');
    _scan();
    for (final e in _offsets.entries.toList()) {
      final head = String.fromCharCodes(b, e.value, math.min(b.length, e.value + 400));
      if (!head.contains('/ObjStm')) continue;
      final s = get(e.key);
      if (s is! _Stream) continue;
      final data = _decode(s);
      if (data == null) continue;
      _streams[e.key] = data;
      final first = _num(s.dict['First']).toInt(), n = _num(s.dict['N']).toInt();
      final lx = _Lex(data, 0);
      for (var k = 0; k < n; k++) {
        final num = lx.value(), off = lx.value();
        if (num is int && off is int && !_offsets.containsKey(num)) _inStream[num] = (e.key, first + off);
      }
    }
    if (_offsets.values.any((o) => String.fromCharCodes(b, o, math.min(b.length, o + 300)).contains('/Encrypt'))) {
      throw const FormatException('encrypted');
    }
  }

  void _scan() {
    for (var i = 1; i + 3 <= b.length; i++) {
      if (b[i] != 0x6F || b[i + 1] != 0x62 || b[i + 2] != 0x6A) continue; // «obj»
      if (!_ws(b[i - 1]) || (i + 3 < b.length && !_ws(b[i + 3]) && !_delim(b[i + 3]))) continue;
      var j = i - 1;
      while (j > 0 && _ws(b[j])) {
        j--;
      }
      final ge = j + 1;
      while (j >= 0 && b[j] >= 0x30 && b[j] <= 0x39) {
        j--;
      }
      if (j + 1 == ge) continue;
      while (j > 0 && _ws(b[j])) {
        j--;
      }
      final ne = j + 1;
      while (j >= 0 && b[j] >= 0x30 && b[j] <= 0x39) {
        j--;
      }
      if (j + 1 == ne) continue;
      final n = int.parse(String.fromCharCodes(b, j + 1, ne));
      _offsets[n] = j + 1; // пізніше визначення (дописане) — головне
    }
  }

  Object? get(int n) {
    if (_cache.containsKey(n)) return _cache[n];
    _cache[n] = null; // від циклів
    Object? v;
    final off = _offsets[n];
    if (off != null) {
      final lx = _Lex(b, off);
      lx.value();
      lx.value();
      lx.value(); // «n g obj»
      v = lx.value();
      if (v is Map<String, Object?>) {
        lx._skip();
        if (lx.pos + 6 <= b.length && String.fromCharCodes(b, lx.pos, lx.pos + 6) == 'stream') {
          var s = lx.pos + 6;
          if (s < b.length && b[s] == 13) s++;
          if (s < b.length && b[s] == 10) s++;
          final len = resolve(v['Length']);
          var e = len is int ? s + len : -1;
          if (e < 0 || e > b.length || !_endstreamAt(e)) e = _find('endstream', s);
          v = _Stream(v, Uint8List.sublistView(b, s, math.max(s, e)));
        }
      }
    } else if (_inStream[n] case (final sn, final at)) {
      final data = _streams[sn];
      if (data != null) v = _Lex(data, at).value();
    }
    _cache[n] = v;
    return v;
  }

  bool _endstreamAt(int e) {
    var i = e;
    while (i < b.length && _ws(b[i])) {
      i++;
    }
    return i + 9 <= b.length && String.fromCharCodes(b, i, i + 9) == 'endstream';
  }

  int _find(String s, int from) {
    final cs = s.codeUnits;
    for (var i = from; i + cs.length <= b.length; i++) {
      var ok = true;
      for (var k = 0; k < cs.length && ok; k++) {
        ok = b[i + k] == cs[k];
      }
      if (ok) {
        var e = i;
        while (e > from && _ws(b[e - 1])) {
          e--;
        }
        return e;
      }
    }
    return b.length;
  }

  Object? resolve(Object? v) => v is _Ref ? get(v.n) : v;

  Map<String, Object?>? dict(Object? v) {
    final r = resolve(v);
    return r is Map<String, Object?> ? r : (r is _Stream ? r.dict : null);
  }

  static num _num(Object? v) => v is num ? v : 0;

  /// Розпакований вміст потоку; фільтр, якого програма не знає, — null.
  Uint8List? _decode(_Stream s) {
    final f = resolve(s.dict['Filter']);
    final filters = [for (final x in f is List ? f : [f]) if (resolve(x) case _Name n) n.s];
    var data = s.raw;
    final parms = resolve(s.dict['DecodeParms']);
    for (var i = 0; i < filters.length; i++) {
      switch (filters[i]) {
        case 'FlateDecode' || 'Fl':
          try {
            data = Uint8List.fromList(const ZLibDecoder().decodeBytes(data));
          } catch (_) {
            data = Uint8List.fromList(Inflate(data).getBytes());
          }
          final p = dict(parms is List ? (i < parms.length ? parms[i] : null) : parms);
          final pred = _num(p?['Predictor']).toInt();
          if (pred >= 10) data = _png(data, math.max(1, _num(p?['Columns']).toInt()) * math.max(1, _num(p?['Colors']).toInt()));
        default:
          return null;
      }
    }
    return data;
  }

  /// Передбачення PNG (рядки з байтом типу на початку) — у потоках xref і об'єктів.
  static Uint8List _png(Uint8List d, int cols) {
    final rowLen = cols + 1, rows = d.length ~/ rowLen;
    final out = Uint8List(rows * cols);
    for (var r = 0; r < rows; r++) {
      final t = d[r * rowLen];
      for (var c = 0; c < cols; c++) {
        final x = d[r * rowLen + 1 + c];
        final left = c > 0 ? out[r * cols + c - 1] : 0, up = r > 0 ? out[(r - 1) * cols + c] : 0;
        final ul = r > 0 && c > 0 ? out[(r - 1) * cols + c - 1] : 0;
        out[r * cols + c] = switch (t) {
          1 => x + left,
          2 => x + up,
          3 => x + ((left + up) >> 1),
          4 => x + _paeth(left, up, ul),
          _ => x,
        } & 255;
      }
    }
    return out;
  }

  static int _paeth(int a, int b, int c) {
    final p = a + b - c, pa = (p - a).abs(), pb = (p - b).abs(), pc = (p - c).abs();
    return pa <= pb && pa <= pc ? a : (pb <= pc ? b : c);
  }

  /// Сторінки по порядку: (словник сторінки, успадковані ресурси, рамка, поворот).
  List<(Map<String, Object?>, Map<String, Object?>?, List<double>, int)> pages() {
    Map<String, Object?>? root;
    // Корінь — з останнього trailer чи потоку xref; немає — перший каталог.
    for (final e in _offsets.entries) {
      final o = get(e.key);
      final d = o is _Stream ? o.dict : null;
      if (d != null && resolve(d['Type']) is _Name && (resolve(d['Type']) as _Name).s == 'XRef') root = dict(d['Root']);
    }
    final t = _lastTrailer();
    if (t != null) root = dict(t['Root']) ?? root;
    if (root == null) {
      for (final n in [..._offsets.keys, ..._inStream.keys]) {
        final d = dict(get(n));
        final t = d == null ? null : resolve(d['Type']);
        if (t is _Name && t.s == 'Catalog') {
          root = d;
          break;
        }
      }
    }
    final out = <(Map<String, Object?>, Map<String, Object?>?, List<double>, int)>[];
    void walk(Map<String, Object?> node, Map<String, Object?>? res, List<double>? box, int rot, int depth) {
      if (depth > 50) return;
      res = dict(node['Resources']) ?? res;
      final mb = resolve(node['CropBox']) ?? resolve(node['MediaBox']);
      if (mb is List && mb.length == 4) box = [for (final x in mb) _num(resolve(x)).toDouble()];
      if (resolve(node['Rotate']) is num) rot = (resolve(node['Rotate']) as num).toInt();
      final kids = resolve(node['Kids']);
      if (kids is List) {
        for (final k in kids) {
          final d = dict(k);
          if (d != null) walk(d, res, box, rot, depth + 1);
        }
      } else {
        out.add((node, res, box ?? const [0, 0, 612, 792], ((rot % 360) + 360) % 360));
      }
    }

    final p = dict(root?['Pages']);
    if (p != null) walk(p, null, null, 0, 0);
    return out;
  }

  Map<String, Object?>? _lastTrailer() {
    final cs = 'trailer'.codeUnits;
    for (var i = b.length - cs.length; i >= 0; i--) {
      var ok = true;
      for (var k = 0; k < cs.length && ok; k++) {
        ok = b[i + k] == cs[k];
      }
      if (ok) {
        final v = _Lex(b, i + cs.length).value();
        return v is Map<String, Object?> ? v : null;
      }
    }
    return null;
  }

  /// Лінії сторінки в пунктах, як її видно (поворот і рамка враховані), Y — униз.
  (List<PdfStroke>, double, double) strokes((Map<String, Object?>, Map<String, Object?>?, List<double>, int) page) {
    final (node, res, box, rot) = page;
    final x0 = math.min(box[0], box[2]), y0 = math.min(box[1], box[3]);
    final w0 = (box[2] - box[0]).abs(), h0 = (box[3] - box[1]).abs();
    final raw = <PdfStroke>[];
    final c = resolve(node['Contents']);
    final parts = <Uint8List>[];
    for (final x in c is List ? c : [c]) {
      final s = resolve(x);
      if (s is _Stream) {
        final d = _decode(s);
        if (d != null) parts.add(d);
      }
    }
    final all = BytesBuilder(copy: false);
    for (final p in parts) {
      all.add(p);
      all.addByte(10);
    }
    _run(all.takeBytes(), res, const [1, 0, 0, 1, 0, 0], raw, 0);
    Vec disp(Vec v) {
      final qx = v.x - x0, qy = v.y - y0;
      return switch (rot) {
        90 => Vec(qy, qx),
        180 => Vec(w0 - qx, qy),
        270 => Vec(h0 - qy, w0 - qx),
        _ => Vec(qx, h0 - qy),
      };
    }

    final rotated = rot == 90 || rot == 270;
    return (
      [for (final s in raw) PdfStroke([for (final v in s.pts) disp(v)], s.rgb, s.width)],
      rotated ? h0 : w0,
      rotated ? w0 : h0,
    );
  }

  /// Виконання вмісту сторінки чи форми: лише те, що потрібно для ліній (шляхи, перетворення, колір обведення).
  void _run(Uint8List content, Map<String, Object?>? res, List<double> ctm0, List<PdfStroke> out, int depth) {
    if (depth > 12) return;
    var ctm = ctm0;
    var rgb = 0, lw = 1.0;
    final stack = <(List<double>, int, double)>[];
    final ops = <Object?>[];
    final path = <List<Vec>>[];
    Vec? cur;
    Vec tr(double x, double y) => Vec(ctm[0] * x + ctm[2] * y + ctm[4], ctm[1] * x + ctm[3] * y + ctm[5]);
    double n(int i) => ops.length > i && ops[i] is num ? (ops[i] as num).toDouble() : 0;
    int gray(double g) => _rgb(g, g, g);
    final lx = _Lex(content, 0);
    while (!lx.end) {
      final v = lx.value();
      if (v is! _Op) {
        ops.add(v);
        continue;
      }
      switch (v.s) {
        case 'q':
          stack.add((ctm, rgb, lw));
        case 'Q':
          if (stack.isNotEmpty) (ctm, rgb, lw) = stack.removeLast();
        case 'cm':
          final m = [for (var i = 0; i < 6; i++) n(i)];
          ctm = [
            m[0] * ctm[0] + m[1] * ctm[2], m[0] * ctm[1] + m[1] * ctm[3],
            m[2] * ctm[0] + m[3] * ctm[2], m[2] * ctm[1] + m[3] * ctm[3],
            m[4] * ctm[0] + m[5] * ctm[2] + ctm[4], m[4] * ctm[1] + m[5] * ctm[3] + ctm[5],
          ];
        case 'w':
          lw = n(0);
        case 'm':
          cur = tr(n(0), n(1));
          path.add([cur]);
        case 'l':
          cur = tr(n(0), n(1));
          if (path.isEmpty) path.add([]);
          path.last.add(cur);
        case 'c' || 'v' || 'y':
          final p0 = cur ?? tr(0, 0);
          final (p1, p2, p3) = switch (v.s) {
            'c' => (tr(n(0), n(1)), tr(n(2), n(3)), tr(n(4), n(5))),
            'v' => (p0, tr(n(0), n(1)), tr(n(2), n(3))),
            _ => (tr(n(0), n(1)), tr(n(2), n(3)), tr(n(2), n(3))),
          };
          if (path.isEmpty) path.add([p0]);
          for (var k = 1; k <= 8; k++) {
            final t = k / 8, u = 1 - t;
            path.last.add(p0 * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t * t * t));
          }
          cur = p3;
        case 'h':
          if (path.isNotEmpty && path.last.length > 1) path.last.add(path.last.first);
        case 're':
          final x = n(0), y = n(1), w = n(2), h = n(3);
          path.add([tr(x, y), tr(x + w, y), tr(x + w, y + h), tr(x, y + h), tr(x, y)]);
        case 'S' || 's' || 'B' || 'B*' || 'b' || 'b*':
          if (v.s == 's' || v.s == 'b' || v.s == 'b*') {
            for (final p in path) {
              if (p.length > 1) p.add(p.first);
            }
          }
          final scale = math.sqrt((ctm[0] * ctm[3] - ctm[1] * ctm[2]).abs());
          for (final p in path) {
            if (p.length > 1) out.add(PdfStroke(p, rgb, lw * scale));
          }
          path.clear();
        case 'f' || 'F' || 'f*' || 'n':
          path.clear();
        case 'RG':
          rgb = _rgb(n(0), n(1), n(2));
        case 'G':
          rgb = gray(n(0));
        case 'K':
          rgb = _cmyk(n(0), n(1), n(2), n(3));
        case 'SC' || 'SCN':
          final cs = [for (final o in ops) if (o is num) o.toDouble()];
          rgb = switch (cs.length) {
            1 => gray(cs[0]),
            3 => _rgb(cs[0], cs[1], cs[2]),
            4 => _cmyk(cs[0], cs[1], cs[2], cs[3]),
            _ => rgb,
          };
        case 'Do':
          final name = ops.isNotEmpty && ops.last is _Name ? (ops.last as _Name).s : null;
          final xo = dict(res?['XObject']);
          final f = name == null ? null : resolve(xo?[name]);
          final sub = f is _Stream ? resolve(f.dict['Subtype']) : null;
          if (f is _Stream && sub is _Name && sub.s == 'Form') {
            final m = resolve(f.dict['Matrix']);
            final mm = m is List && m.length == 6 ? [for (final x in m) _num(resolve(x)).toDouble()] : [1.0, 0, 0, 1, 0, 0];
            final fc = [
              mm[0] * ctm[0] + mm[1] * ctm[2], mm[0] * ctm[1] + mm[1] * ctm[3],
              mm[2] * ctm[0] + mm[3] * ctm[2], mm[2] * ctm[1] + mm[3] * ctm[3],
              mm[4] * ctm[0] + mm[5] * ctm[2] + ctm[4], mm[4] * ctm[1] + mm[5] * ctm[3] + ctm[5],
            ];
            final d = _decode(f);
            if (d != null) _run(d, dict(f.dict['Resources']) ?? res, fc, out, depth + 1);
          }
        case 'BI':
          // Вбудована картинка: пропустити дані до «EI».
          final e = _findIn(content, 'EI', lx.pos);
          lx.pos = e;
      }
      ops.clear();
    }
  }

  static int _findIn(Uint8List d, String s, int from) {
    for (var i = from; i + 2 < d.length; i++) {
      if (d[i] == s.codeUnitAt(0) && d[i + 1] == s.codeUnitAt(1) && _ws(d[i - 1]) && (_ws(d[i + 2]) || _delim(d[i + 2]))) {
        return i + 2;
      }
    }
    return d.length;
  }

  static int _rgb(double r, double g, double b) {
    int c(double v) => (v.clamp(0.0, 1.0) * 255).round();
    return (c(r) << 16) | (c(g) << 8) | c(b);
  }

  static int _cmyk(double c, double m, double y, double k) => _rgb((1 - c) * (1 - k), (1 - m) * (1 - k), (1 - y) * (1 - k));
}
