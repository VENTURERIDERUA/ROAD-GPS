// Етап 7: невекторні оригінали. Прив'язка скану за точками (пікселі → координати креслення),
// «прилипання» обведення до лінії потрібного кольору, масштаб поздовжнього профілю.
// Тут лише розрахунки — без екранів, щоб усе перевірялось тестами.
import 'dart:math' as math;
import 'dart:typed_data';

import 'geometry.dart';
import 'profile.dart';

/// Точка зображення в пікселях (неперервно: піксель i займає [i, i+1), його центр — i + 0.5)
/// → координати (X схід, Y північ): X = a·x + b·y + c, Y = d·x + e·y + f.
class Affine {
  final double a, b, c, d, e, f;
  const Affine(this.a, this.b, this.c, this.d, this.e, this.f);

  Vec apply(Vec px) => Vec(a * px.x + b * px.y + c, d * px.x + e * px.y + f);

  Vec invert(Vec w) {
    final det = a * e - b * d;
    final x = w.x - c, y = w.y - f;
    return Vec((e * x - b * y) / det, (-d * x + a * y) / det);
  }

  /// Файл прив'язки (.pgw / .jgw): A, D, B, E, C, F; у world file C, F — центр лівого верхнього пікселя.
  List<double> get worldFile => [a, d, b, e, c + 0.5 * a + 0.5 * b, f + 0.5 * d + 0.5 * e];

  /// Розмір пікселя на місцевості, м (середній по двох осях).
  double get pixelSize => (math.sqrt(a * a + d * d) + math.sqrt(b * b + e * e)) / 2;
}

class ImageFit {
  final Affine affine;

  /// Похибка кожної точки, м; порожньо, коли точок рівно стільки, скільки треба (перевірити нічим).
  final List<double> residuals;
  const ImageFit(this.affine, this.residuals);

  double get rms =>
      residuals.isEmpty ? 0 : math.sqrt(residuals.fold(0.0, (s, r) => s + r * r) / residuals.length);
}

/// Прив'язати зображення: 2 точки — зсув, поворот і масштаб (скан без перекосу);
/// 3 і більше — афінне перетворення (враховує перекіс і різний масштаб по осях), найменші квадрати.
ImageFit fitImage(List<(Vec px, Vec world)> pairs) {
  if (pairs.length < 2) throw ArgumentError('потрібно щонайменше 2 точки');
  final Affine aff;
  if (pairs.length == 2) {
    // Рядки зображення йдуть униз, північ — угору: перевертаємо рядок, далі — подібність.
    final p = [for (final x in pairs) Vec(x.$1.x, -x.$1.y)], q = [for (final x in pairs) x.$2];
    final dp = p[1] - p[0], dq = q[1] - q[0];
    final den = dp.x * dp.x + dp.y * dp.y;
    if (den < 1e-9) throw ArgumentError('точки на зображенні збігаються');
    final sa = (dp.x * dq.x + dp.y * dq.y) / den, sb = (dp.x * dq.y - dp.y * dq.x) / den;
    // (col, −row) → (sa·col + sb·row, sb·col − sa·row) + зсув
    final c = q[0].x - (sa * p[0].x - sb * p[0].y), f = q[0].y - (sb * p[0].x + sa * p[0].y);
    aff = Affine(sa, sb, c, sb, -sa, f);
  } else {
    // Нормальні рівняння 3×3 окремо для X і Y; точки центруємо — так стійкіше з великими координатами.
    final n = pairs.length;
    final mx = pairs.fold(0.0, (s, x) => s + x.$1.x) / n, my = pairs.fold(0.0, (s, x) => s + x.$1.y) / n;
    final wx = pairs.fold(0.0, (s, x) => s + x.$2.x) / n, wy = pairs.fold(0.0, (s, x) => s + x.$2.y) / n;
    var sxx = 0.0, sxy = 0.0, syy = 0.0, sxX = 0.0, syX = 0.0, sxY = 0.0, syY = 0.0;
    for (final (px, w) in pairs) {
      final x = px.x - mx, y = px.y - my, X = w.x - wx, Y = w.y - wy;
      sxx += x * x;
      sxy += x * y;
      syy += y * y;
      sxX += x * X;
      syX += y * X;
      sxY += x * Y;
      syY += y * Y;
    }
    final det = sxx * syy - sxy * sxy;
    if (det.abs() < 1e-9 * (sxx * syy + 1)) throw ArgumentError('точки на зображенні лежать на одній прямій');
    final a = (sxX * syy - syX * sxy) / det, b = (syX * sxx - sxX * sxy) / det;
    final d = (sxY * syy - syY * sxy) / det, e = (syY * sxx - sxY * sxy) / det;
    aff = Affine(a, b, wx - a * mx - b * my, d, e, wy - d * mx - e * my);
  }
  final residuals = pairs.length <= 3 ? <double>[] : [for (final (px, w) in pairs) aff.apply(px).dist(w)];
  return ImageFit(aff, residuals);
}

// ---------- Пікселі й «прилипання» до лінії ----------

/// Зображення в пам'яті: RGBA, рядок за рядком.
class Raster {
  final int width, height;
  final Uint8List rgba;
  const Raster(this.width, this.height, this.rgba);

  int rgb(int x, int y) {
    final i = (y * width + x) * 4;
    return (rgba[i] << 16) | (rgba[i + 1] << 8) | rgba[i + 2];
  }

  bool inside(int x, int y) => x >= 0 && y >= 0 && x < width && y < height;
}

double colorDist(int a, int b) {
  final dr = ((a >> 16) & 255) - ((b >> 16) & 255);
  final dg = ((a >> 8) & 255) - ((b >> 8) & 255);
  final db = (a & 255) - (b & 255);
  return math.sqrt((dr * dr + dg * dg + db * db).toDouble());
}

/// Найближча до [p] середина лінії кольору [rgb] у колі [radius]; null — такої лінії поруч немає.
Vec? snapToLine(Raster r, Vec p, int rgb, {double radius = 8, double tol = 70}) {
  final cx = p.x.floor(), cy = p.y.floor(), ri = radius.ceil();
  var sx = 0.0, sy = 0.0, n = 0;
  for (var y = cy - ri; y <= cy + ri; y++) {
    for (var x = cx - ri; x <= cx + ri; x++) {
      // Центр пікселя — x + 0.5.
      final dx = x + 0.5 - p.x, dy = y + 0.5 - p.y;
      if (!r.inside(x, y) || dx * dx + dy * dy > radius * radius) continue;
      if (colorDist(r.rgb(x, y), rgb) > tol) continue;
      sx += x + 0.5;
      sy += y + 0.5;
      n++;
    }
  }
  return n == 0 ? null : Vec(sx / n, sy / n);
}

/// Обведення: між сусідніми торканнями — точки кожні [step] пікселів, кожна «прилипає» до лінії.
/// Де лінії поруч немає (розрив, напис) — лишається пряма між торканнями.
List<Vec> traceLine(Raster r, List<Vec> taps, int rgb, {double step = 3, double radius = 8, double tol = 70}) {
  if (taps.isEmpty) return const [];
  final out = <Vec>[snapToLine(r, taps.first, rgb, radius: radius, tol: tol) ?? taps.first];
  for (var i = 1; i < taps.length; i++) {
    final a = taps[i - 1], b = taps[i];
    final n = math.max(1, (a.dist(b) / step).ceil());
    for (var k = 1; k <= n; k++) {
      final q = a + (b - a) * (k / n);
      out.add(snapToLine(r, q, rgb, radius: radius, tol: tol) ?? q);
    }
  }
  return simplify(out, 0.7);
}

/// Спрощення ламаної (Дуглас — Пекер): прибирає точки, що відхиляються менше за [tol].
List<Vec> simplify(List<Vec> pts, double tol) {
  if (pts.length < 3) return [...pts];
  final keep = List<bool>.filled(pts.length, false)
    ..[0] = true
    ..[pts.length - 1] = true;
  final stack = <(int, int)>[(0, pts.length - 1)];
  while (stack.isNotEmpty) {
    final (i, j) = stack.removeLast();
    final a = pts[i], ab = pts[j] - a;
    final len = ab.length;
    var far = -1.0, at = -1;
    for (var k = i + 1; k < j; k++) {
      final ap = pts[k] - a;
      final d = len < 1e-9 ? ap.length : (ab.x * ap.y - ab.y * ap.x).abs() / len;
      if (d > far) {
        far = d;
        at = k;
      }
    }
    if (far > tol) {
      keep[at] = true;
      stack
        ..add((i, at))
        ..add((at, j));
    }
  }
  return [for (var k = 0; k < pts.length; k++) if (keep[k]) pts[k]];
}

/// Ламана в пікселях → відрізки в координатах креслення (як вісь із DXF).
List<Segment> toSegments(List<Vec> px, Affine aff) {
  final w = [for (final p in px) aff.apply(p)];
  return [for (var i = 1; i < w.length; i++) if (w[i].dist(w[i - 1]) > 1e-6) LineSeg(w[i - 1], w[i])];
}

// ---------- Поздовжній профіль ----------

/// Масштаб профілю: по горизонталі — два ПК, по вертикалі — дві відмітки (з підписів сітки).
class ProfileScale {
  final (double px, double station) h1, h2;
  final (double py, double z) v1, v2;
  const ProfileScale(this.h1, this.h2, this.v1, this.v2);

  double station(double px) => h1.$2 + (px - h1.$1) * (h2.$2 - h1.$2) / (h2.$1 - h1.$1);
  double z(double py) => v1.$2 + (py - v1.$1) * (v2.$2 - v1.$2) / (v2.$1 - v1.$1);

  bool get valid => (h2.$1 - h1.$1).abs() > 1 && (v2.$1 - v1.$1).abs() > 1 && h1.$2 != h2.$2 && v1.$2 != v2.$2;
}

/// Обведена лінія проєкту → профіль (ламана: переломи без вертикальних кривих).
/// Точки впорядковано за ПК; повтори ближче 0.5 м прибрано.
/// [anchors] — опорні точки, де відомі і ПК, і відмітка: (ПК, на скільки відмітка точки більша за ту, що дає
/// масштаб). Між ними поправка лінійна за ПК, за крайніми — як у крайньої: скан, що «пливе» (перекіс, нерівний
/// друк), вирівнюється по точках, які людина знає. Дві точки масштабу дають нульову поправку — нічого не змінюється.
Profile profileFromTrace(List<Vec> px, ProfileScale s, String source, {List<(double, double)> anchors = const []}) {
  final fix = [...anchors]..sort((a, b) => a.$1.compareTo(b.$1));
  double delta(double st) {
    if (fix.isEmpty) return 0;
    if (st <= fix.first.$1) return fix.first.$2;
    if (st >= fix.last.$1) return fix.last.$2;
    final i = fix.lastIndexWhere((f) => f.$1 <= st);
    final a = fix[i], b = fix[i + 1];
    return b.$1 - a.$1 < 1e-9 ? a.$2 : a.$2 + (b.$2 - a.$2) * (st - a.$1) / (b.$1 - a.$1);
  }

  final pts = [
    for (final p in px) (s.station(p.x), s.z(p.y) + delta(s.station(p.x)))
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  final pvis = <Pvi>[];
  for (final (st, z) in pts) {
    if (pvis.isNotEmpty && st - pvis.last.station < 0.5) continue;
    pvis.add(Pvi(st, z));
  }
  return Profile(source, pvis);
}

// ---------- Поперечник зі скану ----------

/// Пунктів PDF (1/72 дюйма) в одному метрі паперу.
const pointsPerMetre = 72 / 0.0254;

/// Обведена лінія проєкту поперечника → (зміщення, відмітка). [axis] — де вісь перетинає лінію проєкту (на
/// зображенні), там відмітка [zAxis]; [pxPerMH], [pxPerMV] — пікселів на метр місцевості по горизонталі й
/// вертикалі (з масштабу аркуша). Зображення — вниз, тож вище на аркуші — більша відмітка. Точки — у порядку лінії
/// зліва направо, без повернень назад; ближчі за 5 см по горизонталі — одна точка, крім уступу (бордюр): там обидва
/// кінці вертикалі, і лінія йде далі від того кінця, де продовжується на кресленні. Сортування за зміщенням губило
/// один кінець уступу — ліворуч лишався верх бордюру, праворуч низ.
List<(double, double)> sectionFromTrace(List<Vec> px, Vec axis, double zAxis, double pxPerMH, double pxPerMV) {
  var pts = [for (final p in px) ((p.x - axis.x) / pxPerMH, zAxis - (p.y - axis.y) / pxPerMV)];
  if (pts.length > 1 && pts.first.$1 > pts.last.$1) pts = pts.reversed.toList();
  final out = <(double, double)>[];
  for (final p in pts) {
    if (out.isEmpty) {
      out.add(p);
      continue;
    }
    final last = out.last;
    if (p.$1 < last.$1 - 0.05) continue; // назад
    if (p.$1 - last.$1 >= 0.05) {
      out.add(p);
      continue;
    }
    if ((p.$2 - last.$2).abs() < 0.01) continue;
    // Уступ: другий кінець вертикалі — на тому самому зміщенні; довша вертикаль — лише її кінці.
    final step = out.length >= 2 && (last.$1 - out[out.length - 2].$1).abs() < 1e-9;
    if (step) {
      out[out.length - 1] = (last.$1, p.$2);
    } else {
      out.add((last.$1, p.$2));
    }
  }
  return out;
}

/// Масштаб з напису на аркуші: «S 1:100- Vertical scale», «Scara orizontala 1:200», «Масштаб вертикальний 1:100».
/// [vertical] — вертикальний чи горизонтальний; null — напису немає.
double? sheetScale(String text, {required bool vertical}) {
  final word = vertical ? r'vertic\w*|вертик\w*' : r'horiz\w*|oriz\w*|горизонт\w*';
  final after =
      RegExp(r'1\s*:\s*(\d+)[^\n]{0,25}?' '(?:$word)', caseSensitive: false, unicode: true).firstMatch(text);
  final before =
      RegExp('(?:$word)' r'[^\n\d]{0,25}1\s*:\s*(\d+)', caseSensitive: false, unicode: true).firstMatch(text);
  final m = after ?? before;
  return m == null ? null : double.tryParse(m[1]!);
}

/// Обведення лінії, що йде зліва направо (поперечник): у кожному стовпчику через [step] пікселів — відрізок
/// пікселів кольору [rgb], найближчий до прямої між сусідніми торканнями (у межах [radius]); немає — точка на
/// прямій. Окремі «викиди» (сусідні лінії, штрихування, написи) прибирає медіана з п'яти сусідніх точок.
List<Vec> traceAcross(Raster r, List<Vec> taps, int rgb, {double step = 2, int radius = 6, double tol = 60}) {
  if (taps.length < 2) return [...taps];
  final t = [...taps]..sort((a, b) => a.x.compareTo(b.x));
  final raw = <Vec>[];
  for (var i = 0; i + 1 < t.length; i++) {
    final a = t[i], b = t[i + 1];
    for (var x = a.x; x < b.x || (i + 2 == t.length && x <= b.x); x += step) {
      final ye = b.x - a.x < 1e-9 ? a.y : a.y + (b.y - a.y) * (x - a.x) / (b.x - a.x);
      final xi = x.floor();
      double? best;
      var run = <int>[];
      void close() {
        if (run.isEmpty) return;
        final c = (run.first + run.last) / 2 + 0.5;
        if (best == null || (c - ye).abs() < (best! - ye).abs()) best = c;
        run = [];
      }

      for (var y = (ye - radius).floor(); y <= (ye + radius).ceil(); y++) {
        if (r.inside(xi, y) && colorDist(r.rgb(xi, y), rgb) <= tol) {
          run.add(y);
        } else {
          close();
        }
      }
      close();
      raw.add(Vec(x, best ?? ye));
    }
  }
  final med = [
    for (var k = 0; k < raw.length; k++)
      Vec(raw[k].x, ([for (var j = math.max(0, k - 2); j <= math.min(raw.length - 1, k + 2); j++) raw[j].y]..sort())[
          (math.min(raw.length - 1, k + 2) - math.max(0, k - 2)) ~/ 2])
  ];
  return simplify(med, 1.0);
}

/// Лінія від одного торкання (поперечник, профіль — лінія йде зліва направо): з місця торкання програма сама йде
/// лінією кольору [rgb] праворуч і ліворуч, стовпчик за стовпчиком через [step] пікселів. У кожному стовпчику —
/// відрізок цього кольору, найближчий до місця, куди лінія веде за напрямом останніх кроків. Розрив (напис поверх
/// лінії, пунктир, уступ бордюру) — пошук ширшає з кожним кроком; довший за [gap] пікселів — там лінія скінчилась.
/// Поруч з торканням лінії цього кольору немає — порожньо.
List<Vec> followAcross(Raster r, Vec tap, int rgb, {double step = 2, double tol = 60, double gap = 40, int reach = 6}) {
  // Відрізок кольору в стовпчику x, найближчий до [ye] у межах [w]: (його середина, верх, низ).
  (double, int, int)? runNear(int x, double ye, double w) {
    (double, int, int)? best;
    var bestD = double.infinity;
    int? top;
    void close(int y) {
      final t = top;
      if (t == null) return;
      final d = ye < t ? t - ye : (ye > y ? ye - y : 0.0);
      if (d <= w && d < bestD) {
        bestD = d;
        best = ((t + y) / 2 + 0.5, t, y);
      }
      top = null;
    }

    for (var y = (ye - w).floor(); y <= (ye + w).ceil(); y++) {
      if (r.inside(x, y) && colorDist(r.rgb(x, y), rgb) <= tol) {
        top ??= y;
      } else {
        close(y - 1);
      }
    }
    close((ye + w).ceil());
    return best;
  }

  final first = runNear(tap.x.floor(), tap.y, reach.toDouble());
  if (first == null) return const [];
  final start = Vec(tap.x, first.$1);

  List<Vec> walk(int dir) {
    final pts = <Vec>[start];
    var missed = 0.0;
    for (var x = tap.x + dir * step; x >= 0 && x < r.width; x += dir * step) {
      // Куди веде лінія: напрям за останніми точками (до 5).
      final last = pts.last, back = pts[math.max(0, pts.length - 6)];
      final slope = (last.x - back.x).abs() < 1e-9 ? 0.0 : (last.y - back.y) / (last.x - back.x);
      final ye = last.y + slope * (x - last.x);
      final w = math.min(60.0, reach + (slope * step).abs() * 2 + missed * 1.5);
      final run = runNear(x.floor(), ye, w);
      if (run == null) {
        missed += step;
        if (missed > gap) break;
        continue;
      }
      missed = 0;
      // Довгий відрізок (уступ, крута ділянка) — точка там, куди веде лінія, а не посередині уступу.
      final y = run.$3 - run.$2 > 3 * reach ? ye.clamp(run.$2 + 0.5, run.$3 + 0.5) : run.$1;
      pts.add(Vec(x, y));
    }
    return pts;
  }

  final raw = [...walk(-1).reversed, ...walk(1).skip(1)];
  final med = [
    for (var k = 0; k < raw.length; k++)
      Vec(raw[k].x, ([for (var j = math.max(0, k - 2); j <= math.min(raw.length - 1, k + 2); j++) raw[j].y]..sort())[
          (math.min(raw.length - 1, k + 2) - math.max(0, k - 2)) ~/ 2])
  ];
  return simplify(med, 1.0);
}

/// Лінія від першого торкання ([followAcross]), поправлена наступними: між крайніми торканнями — через торкання
/// ([traceAcross]), поза ними — як пройшла сама. Одне торкання — лише [followAcross].
List<Vec> traceFromTaps(Raster r, List<Vec> taps, int rgb) {
  if (taps.isEmpty) return const [];
  final auto = followAcross(r, taps.first, rgb);
  if (taps.length == 1) return auto;
  final forced = traceAcross(r, taps, rgb);
  final a = forced.first.x, b = forced.last.x;
  return [...auto.where((p) => p.x < a), ...forced, ...auto.where((p) => p.x > b)];
}

/// Колір лінії саме там, де торкнулись: найближчий до [p] піксель, що помітно відрізняється від паперу. Поруч кілька
/// ліній (червона лінія проєкту над чорним покриттям) — береться та, у яку влучили, а не найконтрастніша; бліда
/// сітка й світлий шум скану не беруться зовсім.
int pickNearestColor(Raster r, Vec p, {int radius = 6}) {
  final cx = p.x.floor(), cy = p.y.floor();
  var best = r.inside(cx, cy) ? r.rgb(cx, cy) : 0, bestD = double.infinity;
  for (var y = cy - radius; y <= cy + radius; y++) {
    for (var x = cx - radius; x <= cx + radius; x++) {
      if (!r.inside(x, y)) continue;
      final c = r.rgb(x, y);
      if (colorDist(c, 0xFFFFFF) < 150) continue; // папір, бліда сітка, світлий шум скану
      // Проєктні лінії виділено кольором: сірий чи чорний піксель «далі» втричі — поруч з кольоровою лінією
      // береться вона, а не сітка чи лінія землі.
      final grey = math.max(c >> 16, math.max((c >> 8) & 255, c & 255)) -
              math.min(c >> 16, math.min((c >> 8) & 255, c & 255)) <
          40;
      final d = ((x + 0.5 - p.x) * (x + 0.5 - p.x) + (y + 0.5 - p.y) * (y + 0.5 - p.y)) * (grey ? 9 : 1);
      if (d < bestD) {
        bestD = d;
        best = c;
      }
    }
  }
  return best;
}
