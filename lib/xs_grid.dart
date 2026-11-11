// Масштаби, вісь і її відмітка поперечника — з чисел на аркуші векторного PDF, без торкань: рядок відстаней від осі
// (з «0») дає горизонталь і місце осі; стовпчик відміток сітки чи рядок проєктних відміток таблиці під
// поперечником (наприклад «COTE PROIECT»), звірений з самою лінією профілю, — вертикаль.
import 'dart:math' as math;

import 'geometry.dart';
import 'pdf_vector.dart';
import 'profile.dart';
import 'raster_geo.dart';

/// Число на аркуші: значення й середина в пікселях зображення (Y — униз); [h] — висота символу.
class SheetNumber {
  final double v;
  final Vec c;
  final double h;
  final String text;
  const SheetNumber(this.v, this.c, this.h, this.text);
}

/// Символ з рамкою в пікселях зображення (Y — униз).
typedef SheetChar = (String ch, double left, double top, double right, double bottom);

final _numRe = RegExp(r'^[+-]?\d+(?:[.,]\d+)?$');

/// Числа сторінки з окремих символів: сусідні цифри, крапка, кома, знак — в одне число; символ, надрукований кілька
/// разів на тому самому місці (так креслення роблять жирний шрифт), — один раз. Повернутий текст (уздовж Y) —
/// знизу вгору; не читається так — зверху вниз.
List<SheetNumber> sheetNumbers(List<SheetChar> chars) {
  final cs = <SheetChar>[];
  for (final c in chars) {
    if (!RegExp(r'[0-9.,+\-]').hasMatch(c.$1)) continue;
    final dup = cs.reversed.take(8).any((o) =>
        o.$1 == c.$1 && ((o.$2 + o.$4) - (c.$2 + c.$4)).abs() < (c.$4 - c.$2).abs() * 0.6 + 0.5 &&
        ((o.$3 + o.$5) - (c.$3 + c.$5)).abs() < (c.$5 - c.$3).abs() * 0.6 + 0.5);
    if (!dup) cs.add(c);
  }
  // Сусіди — лише вздовж письма: звичайний текст — по горизонталі, повернутий (рамка цифри ширша, ніж висока) — по
  // вертикалі; проміжок між рамками — менше за пів висоти цифри. Сусідні стовпчики повернутих чисел не злипаються.
  // Рамки бувають самого знака (PDFium): крапка — крихітна внизу, тож її напрям — як у сусідньої цифри.
  final n = cs.length;
  final parent = List<int>.generate(n, (i) => i);
  int find(int i) => parent[i] == i ? i : parent[i] = find(parent[i]);
  Vec mid(SheetChar c) => Vec((c.$2 + c.$4) / 2, (c.$3 + c.$5) / 2);
  double size(SheetChar c) => math.max((c.$4 - c.$2).abs(), (c.$5 - c.$3).abs());
  bool digit(SheetChar c) => c.$1.codeUnitAt(0) >= 0x30 && c.$1.codeUnitAt(0) <= 0x39;
  bool rotated(SheetChar c) => (c.$4 - c.$2).abs() > 1.15 * (c.$5 - c.$3).abs();
  bool linked(SheetChar a, SheetChar b) {
    if (!digit(a) && !digit(b)) return false;
    final d = digit(a) ? a : b, o = identical(d, a) ? b : a;
    final rot = rotated(d);
    if (digit(o) && rotated(o) != rot) return false;
    final dl = math.min(d.$2, d.$4), dr = math.max(d.$2, d.$4), dt = math.min(d.$3, d.$5), db = math.max(d.$3, d.$5);
    final ol = math.min(o.$2, o.$4), or = math.max(o.$2, o.$4), ot = math.min(o.$3, o.$5), ob = math.max(o.$3, o.$5);
    if (rot) {
      final w = dr - dl;
      // Поперек письма — у межах цифри (з запасом), уздовж — близько.
      if (ol < dl - 0.3 * w || or > dr + 0.3 * w) return false;
      if (digit(o) && ((ol + or) / 2 - (dl + dr) / 2).abs() > 0.3 * w) return false;
      return math.max(ot - db, dt - ob) < 0.6 * w;
    }
    final h = db - dt;
    if (ot < dt - 0.3 * h || ob > db + 0.3 * h) return false;
    if (digit(o) && ((ot + ob) / 2 - (dt + db) / 2).abs() > 0.3 * h) return false;
    return math.max(ol - dr, dl - or) < 0.6 * h;
  }

  // Сітка для пошуку сусідів.
  final cell = <(int, int), List<int>>{};
  final g = cs.isEmpty ? 1.0 : math.max(1.0, cs.map(size).reduce(math.max) * 1.5);
  for (var i = 0; i < n; i++) {
    final m = mid(cs[i]);
    (cell[((m.x / g).floor(), (m.y / g).floor())] ??= []).add(i);
  }
  for (var i = 0; i < n; i++) {
    final a = mid(cs[i]);
    final kx = (a.x / g).floor(), ky = (a.y / g).floor();
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        for (final j in cell[(kx + dx, ky + dy)] ?? const <int>[]) {
          if (j > i && linked(cs[i], cs[j])) parent[find(i)] = find(j);
        }
      }
    }
  }
  final groups = <int, List<SheetChar>>{};
  for (var i = 0; i < n; i++) {
    (groups[find(i)] ??= []).add(cs[i]);
  }
  final out = <SheetNumber>[];
  for (final g in groups.values) {
    final xs = g.map((c) => mid(c).x), ys = g.map((c) => mid(c).y);
    final spanX = xs.reduce(math.max) - xs.reduce(math.min), spanY = ys.reduce(math.max) - ys.reduce(math.min);
    final vertical = g.length > 1 && spanY > spanX;
    final ordered = [...g]..sort((a, b) => vertical ? mid(b).y.compareTo(mid(a).y) : mid(a).x.compareTo(mid(b).x));
    var s = ordered.map((c) => c.$1).join();
    if (!_numRe.hasMatch(s)) s = s.split('').reversed.join();
    if (!_numRe.hasMatch(s)) continue;
    final c = Vec((xs.reduce(math.min) + xs.reduce(math.max)) / 2, (ys.reduce(math.min) + ys.reduce(math.max)) / 2);
    final h = g.map((c) => vertical ? (c.$4 - c.$2).abs() : (c.$5 - c.$3).abs()).reduce(math.max);
    out.add(SheetNumber(double.parse(s.replaceAll(',', '.')), c, h, s));
  }
  return out;
}

/// Що знайдено на аркуші для одного поперечника: де вісь, пікселів на метр по горизонталі й вертикалі, відмітка
/// осі (на лінії профілю) і звідки взято вертикаль.
class SectionGrid {
  final double xAxis, pxPerMH, pxPerMV, zAxis;
  final String how;
  const SectionGrid(this.xAxis, this.pxPerMH, this.pxPerMV, this.zAxis, this.how);
}

/// Масштаби й вісь поперечника за числами навколо лінії профілю [line] (у пікселях, зліва направо). [grid] — лінії
/// аркуша (векторний PDF): число біля лінії сітки чи риски бере її місце, а не середину напису (напис стоїть трохи
/// зсунуто — це сантиметри відмітки). Не вийшло — null.
SectionGrid? fitSectionGrid(List<SheetNumber> nums, List<Vec> line, {List<List<Vec>> grid = const []}) {
  if (line.length < 2 || nums.isEmpty) return null;
  final x0 = line.first.x, x1 = line.last.x;
  final ys = line.map((p) => p.y);
  final top = ys.reduce(math.min), bottom = ys.reduce(math.max);
  final w = x1 - x0;
  if (w <= 0) return null;
  // Горизонтальні й вертикальні відрізки ліній аркуша — для прив'язки чисел.
  final hor = <(double, double, double)>[], ver = <(double, double, double)>[]; // (рівень, від, до)
  for (final l in grid) {
    for (var i = 1; i < l.length; i++) {
      final a = l[i - 1], b = l[i];
      if ((a.y - b.y).abs() < 0.3 && (a.x - b.x).abs() > 1) hor.add(((a.y + b.y) / 2, math.min(a.x, b.x), math.max(a.x, b.x)));
      if ((a.x - b.x).abs() < 0.3 && (a.y - b.y).abs() > 1) ver.add(((a.x + b.x) / 2, math.min(a.y, b.y), math.max(a.y, b.y)));
    }
  }
  // Лінія сітки біля числа: горизонталь на рівні числа, що починається поруч з ним (відмітки); вертикаль чи риска
  // над / під числом (відстані). Немає — середина напису.
  double snapY(SheetNumber n) {
    double? best;
    for (final (y, a, b) in hor) {
      if ((y - n.c.y).abs() > 0.8 * n.h) continue;
      if (n.c.x < a - 3 * n.h || n.c.x > b + 3 * n.h) continue;
      if (best == null || (y - n.c.y).abs() < (best - n.c.y).abs()) best = y;
    }
    return best ?? n.c.y;
  }

  double snapX(SheetNumber n) {
    double? best;
    for (final (x, a, b) in ver) {
      if ((x - n.c.x).abs() > 0.8 * n.h) continue;
      if (n.c.y < a - 3 * n.h || n.c.y > b + 3 * n.h) continue;
      if (best == null || (x - n.c.x).abs() < (best - n.c.x).abs()) best = x;
    }
    return best ?? n.c.x;
  }

  double? yAt(double x) {
    for (var i = 1; i < line.length; i++) {
      final a = line[i - 1], b = line[i];
      if (x >= a.x && x <= b.x) return b.x - a.x < 1e-9 ? a.y : a.y + (b.y - a.y) * (x - a.x) / (b.x - a.x);
    }
    return null;
  }

  // Рядки чисел: однаковий Y (у межах половини висоти символу) і в межах ширини поперечника.
  List<List<SheetNumber>> rows(bool Function(SheetNumber) keep) {
    final pool = [for (final n in nums) if (keep(n)) n]..sort((a, b) => a.c.y.compareTo(b.c.y));
    final out = <List<SheetNumber>>[];
    for (final n in pool) {
      if (out.isNotEmpty && (out.last.first.c.y - n.c.y).abs() < 0.6 * n.h) {
        out.last.add(n);
      } else {
        out.add([n]);
      }
    }
    return [for (final r in out) if (r.length >= 3) r];
  }

  bool within(SheetNumber n) => n.c.x > x0 - 0.15 * w && n.c.x < x1 + 0.15 * w;

  // Горизонталь: рядок з нулем; |значення| пропорційне відстані від нуля по X. Тісні підписи таблиці відведено від
  // своїх точок виносками — вони не збігаються; масштаб — той, з яким збігається найбільше підписів (щонайменше два).
  (double, double, List<SheetNumber>, double)? horizontal; // (вісь, пікс./м, рядок, X нуля)
  var bestRow = double.infinity;
  for (final r in rows((n) => within(n) && (n.c.y > bottom || n.c.y < top))) {
    final zero = r.where((n) => n.v == 0).toList();
    if (zero.length != 1) continue;
    final xa = snapX(zero.single);
    final pts = [for (final n in r) if (n.v != 0) ((snapX(n) - xa).abs(), n.v.abs())];
    bool fits(double k, (double, double) p) => (k * p.$1 - p.$2).abs() <= 0.01 * p.$2 + 0.03;
    List<(double, double)> best = const [];
    for (final c in pts) {
      if (c.$1 < 1) continue;
      final inl = [for (final p in pts) if (fits(c.$2 / c.$1, p)) p];
      if (inl.length > best.length) best = inl;
    }
    if (best.length < 2) continue;
    var sdv = 0.0, sdd = 0.0;
    for (final (d, v) in best) {
      sdv += d * v;
      sdd += d * d;
    }
    final k = sdv / sdd; // метрів на піксель
    if (k <= 0) continue;
    // Найближчий до лінії рядок.
    final dist = math.min((r.first.c.y - bottom).abs(), (r.first.c.y - top).abs());
    if (dist < bestRow) {
      bestRow = dist;
      horizontal = (xa, 1 / k, r, zero.single.c.x);
    }
  }
  if (horizontal == null) return null;
  final (xAxis, pxPerMH, distRow, zeroX) = horizontal;
  final yAxis = yAt(xAxis);
  if (yAxis == null) return null;

  // Пряма z = a + b·y найменшими квадратами; похибка — найбільше відхилення.
  (double, double, double)? fit(List<(double, double)> p) {
    if (p.length < 3) return null;
    final my = p.map((e) => e.$1).reduce((a, b) => a + b) / p.length;
    final mz = p.map((e) => e.$2).reduce((a, b) => a + b) / p.length;
    var syy = 0.0, syz = 0.0;
    for (final (y, z) in p) {
      syy += (y - my) * (y - my);
      syz += (y - my) * (z - mz);
    }
    if (syy < 1e-9) return null;
    final b = syz / syy, a = mz - b * my;
    final err = p.map((e) => (a + b * e.$1 - e.$2).abs()).reduce(math.max);
    return (a, b, err);
  }

  // Вертикаль (а): стовпчик відміток сітки біля поперечника — значення лінійно від Y.
  final h = bottom - top;
  final cols = <List<SheetNumber>>[];
  final colPool = [
    for (final n in nums)
      if (n.c.y > top - 1.5 * h - 20 && n.c.y < bottom + 1.5 * h + 20 && (n.c.x < x0 + 0.05 * w || n.c.x > x1 - 0.05 * w) &&
          (n.c.x - (n.c.x < x0 + 0.05 * w ? x0 : x1)).abs() < 0.25 * w)
        n
  ]..sort((a, b) => a.c.x.compareTo(b.c.x));
  for (final n in colPool) {
    if (cols.isNotEmpty && (cols.last.first.c.x - n.c.x).abs() < 1.0 * n.h) {
      cols.last.add(n);
    } else {
      cols.add([n]);
    }
  }
  for (final c in cols) {
    final f = fit([for (final n in c) (snapY(n), n.v)]);
    if (f == null) continue;
    final (a, b, err) = f;
    final range = c.map((n) => n.v).reduce(math.max) - c.map((n) => n.v).reduce(math.min);
    if (b >= 0 || range <= 0 || err > 0.01 * range + 0.005) continue;
    return SectionGrid(xAxis, pxPerMH, -1 / b, a + b * yAxis, 'стовпчик відміток');
  }
  // Вертикаль (б): рядок відміток таблиці під поперечником («проєктні відмітки»), звірений з лінією профілю. Місце
  // кожної відмітки — з відстані в тому самому стовпчику таблиці (підпис може бути відведений виноскою), немає —
  // за підписом.
  double? trueX(SheetNumber n) {
    for (final d in distRow) {
      if ((d.c.x - n.c.x).abs() > 0.6 * n.h) continue;
      final signed = d.v < 0 || d.c.x >= zeroX ? d.v : -d.v;
      return xAxis + signed * pxPerMH;
    }
    return null;
  }

  // Вертикаль на кресленнях — та сама, що горизонталь, або крупніша в «круглу» кількість разів. Рядок підходить,
  // коли з такою вертикаллю щонайменше три його відмітки лягають на лінію (до 2 см; дві — коли одна з них на осі,
  // а лінія тягнеться лише в один бік від осі): симетричний поперечник має лише
  // два різні рівні — вільна пряма через них підійшла б до будь-якого рядка. Відмітка в стовпчику осі (відстань 0)
  // мусить лягти на лінію: інакше це рядок іншої лінії (землі, низу шару одягу).
  const ratios = [1.0, 2.0, 5.0, 10.0, 2.5, 4.0, 20.0];
  // Лише таблиця цього поперечника: між лінією й рядком відстаней (нижче — таблиця наступного).
  final distY = distRow.map((n) => n.c.y).reduce(math.max) + distRow.first.h;
  final byRow = [...rows((n) => within(n) && n.v.abs() > 1 && n.c.y > bottom && n.c.y < distY && !distRow.contains(n))]
    ..sort((p, q) => p.first.c.y.compareTo(q.first.c.y));
  for (final r in byRow) {
    final pts = [
      for (final n in r)
        if (yAt(trueX(n) ?? snapX(n)) case final y?) (y, n.v)
    ];
    final atAxis = [for (final n in r) if ((n.c.x - zeroX).abs() < 0.6 * n.h) n.v];
    if (pts.length < 3) continue;
    for (final k in ratios) {
      final b = -1 / (pxPerMH * k);
      // Зсув — за тією точкою, з якою збігається найбільше інших.
      var bestIn = <(double, double)>[];
      for (final c in pts) {
        final a = c.$2 - b * c.$1;
        final inl = [for (final p in pts) if ((a + b * p.$1 - p.$2).abs() <= 0.02) p];
        if (inl.length > bestIn.length) bestIn = inl;
      }
      final a = bestIn.map((p) => p.$2 - b * p.$1).reduce((x, y) => x + y) / bestIn.length;
      final axisFits = atAxis.isNotEmpty && (a + b * yAxis - atAxis.first).abs() <= 0.02;
      if (atAxis.isNotEmpty && !axisFits) continue;
      final levels = {for (final p in bestIn) (p.$1 * 4).round()}.length;
      if (bestIn.length < (axisFits && levels >= 2 ? 2 : 3) || bestIn.length * 2 < pts.length) continue;
      return SectionGrid(xAxis, pxPerMH, pxPerMH * k, a + b * yAxis, 'рядок проєктних відміток');
    }
  }
  return null;
}

/// Поперечник, знайдений сам: ПК, точки (зміщення від осі, відмітка) і відмітка осі.
typedef FoundSection = (double station, List<(double, double)> points, double zAxis);

/// Поперечники сторінки: лінії кольору [rgb], для яких з чисел аркуша знайшлися масштаби, вісь і відмітка
/// ([fitSectionGrid]). Кілька ліній одного поперечника (шари одягу, лінія двома штрихами) — одна: верхня, з найбільшою
/// відміткою осі. ПК — з підписів ([assignStations]).
List<(List<Vec> line, SectionGrid grid, double? station)> pageSections(
    List<PdfStroke> strokes, List<SheetNumber> nums, int rgb, List<(double, Vec)> labels) {
  final grid = [for (final s in strokes) s.pts];
  final secs = <(List<Vec>, SectionGrid, double)>[]; // лінія, масштаби, Y осі на лінії
  for (final line in vectorLinesOfColor(strokes, rgb)) {
    if (line.last.x - line.first.x < 20) continue;
    final g = fitSectionGrid(nums, line, grid: grid);
    if (g == null) continue;
    final y = zOnLine([for (final p in line) (p.x, p.y)], g.xAxis);
    if (y == null) continue;
    final same = secs.indexWhere((s) => (s.$2.xAxis - g.xAxis).abs() < 3 && (s.$3 - y).abs() < 25);
    if (same < 0) {
      secs.add((line, g, y));
    } else if (g.zAxis > secs[same].$2.zAxis) {
      secs[same] = (line, g, y);
    }
  }
  final st = assignStations([for (final (l, _, y) in secs) (l.first.x, l.last.x, y)], labels);
  return [for (var i = 0; i < secs.length; i++) (secs[i].$1, secs[i].$2, st[i])];
}

/// ПК поперечників сторінки ([secs] — ліва й права межа по X та рівень осі по Y): у стовпчику аркуша поперечники й
/// підписи ПК — у тому самому порядку згори вниз, тож однакова їх кількість — пара за порядком, байдуже, чи підпис
/// над поперечником, чи під його таблицею. Інакше — найближчий підпис над чи під поперечником у межах його ширини.
List<double?> assignStations(List<(double x0, double x1, double y)> secs, List<(double, Vec)> labels) {
  final out = List<double?>.filled(secs.length, null);
  bool inside((double, double, double) s, Vec c) => c.x > s.$1 - 0.25 * (s.$2 - s.$1) && c.x < s.$2 + 0.25 * (s.$2 - s.$1);
  final done = <int>{};
  for (var i = 0; i < secs.length; i++) {
    if (done.contains(i)) continue;
    // Стовпчик: поперечники, що перекриваються по X з цим.
    final col = [
      for (var j = 0; j < secs.length; j++)
        if (secs[j].$1 < secs[i].$2 && secs[j].$2 > secs[i].$1) j
    ]..sort((a, b) => secs[a].$3.compareTo(secs[b].$3));
    done.addAll(col);
    final mine = [for (final l in labels) if (col.any((j) => inside(secs[j], l.$2))) l]..sort((a, b) => a.$2.y.compareTo(b.$2.y));
    if (mine.length == col.length) {
      for (var k = 0; k < col.length; k++) {
        out[col[k]] = mine[k].$1;
      }
      continue;
    }
    for (final j in col) {
      double? best;
      var bestD = double.infinity;
      for (final (st, c) in mine) {
        if (!inside(secs[j], c)) continue;
        final d = (c.y - secs[j].$3).abs();
        if (d < bestD) {
          bestD = d;
          best = st;
        }
      }
      out[j] = best;
    }
  }
  return out;
}

/// Для `compute`: (лінії, числа, колір, підписи ПК) → [sectionsOnPage].
List<FoundSection> sectionsOnPageOf((List<PdfStroke>, List<SheetNumber>, int, List<(double, Vec)>) a) =>
    sectionsOnPage(a.$1, a.$2, a.$3, a.$4);

/// Усі поперечники сторінки векторного PDF за один раз: лінії кольору [rgb] (того, якої торкнулися на одному
/// поперечнику) → масштаби, вісь і відмітка з чисел аркуша → ПК з підпису. Без масштабу чи ПК — без цього поперечника.
List<FoundSection> sectionsOnPage(List<PdfStroke> strokes, List<SheetNumber> nums, int rgb, List<(double, Vec)> labels) {
  final out = <double, FoundSection>{};
  for (final (line, g, st) in pageSections(strokes, nums, rgb, labels)) {
    if (st == null) continue;
    final y = zOnLine([for (final p in line) (p.x, p.y)], g.xAxis)!;
    final pts = sectionFromTrace(line, Vec(g.xAxis, y), g.zAxis, g.pxPerMH, g.pxPerMV);
    if (pts.length >= 2) out[st] = (st, pts, g.zAxis);
  }
  return out.values.toList()..sort((a, b) => a.$1.compareTo(b.$1));
}
