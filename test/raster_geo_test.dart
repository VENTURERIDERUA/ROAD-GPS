import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:road_gps/geometry.dart';
import 'package:road_gps/profile.dart';
import 'package:road_gps/raster_geo.dart';

/// Білий аркуш з сірою сіткою, червоною дугою (вісь) і зеленою прямою (кромка); трохи шуму скану.
Raster sheet() {
  const w = 400, h = 300;
  final b = Uint8List(w * h * 4);
  final rnd = math.Random(1);
  void put(int x, int y, int r, int g, int bl) {
    if (x < 0 || y < 0 || x >= w || y >= h) return;
    final i = (y * w + x) * 4;
    b[i] = r;
    b[i + 1] = g;
    b[i + 2] = bl;
    b[i + 3] = 255;
  }

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final n = rnd.nextInt(12);
      put(x, y, 243 + n, 243 + n, 243 + n);
      if (x % 50 == 0 || y % 50 == 0) put(x, y, 180, 180, 180);
    }
  }
  // Червона дуга радіуса 200 з центром (200, 400): товщина 3 пікселі.
  for (var a = 200.0; a <= 340; a += 0.05) {
    final t = a * math.pi / 180;
    for (var k = -1; k <= 1; k++) {
      put((200 + (200 + k) * math.cos(t)).round(), (400 + (200 + k) * math.sin(t)).round(), 210, 30, 30);
    }
  }
  // Зелена пряма y = 260.
  for (var x = 20; x < 380; x++) {
    for (var k = -1; k <= 1; k++) {
      put(x, 260 + k, 30, 160, 60);
    }
  }
  return Raster(w, h, b);
}

void main() {
  // Справжнє перетворення: піксель 0.5 м, поворот 12°, легкий перекіс; початок — Stereo 70.
  const truth = Affine(0.489, 0.104, 583000, 0.102, -0.511, 326500);

  test('прив’язка за 3+ точками відновлює перетворення, похибки видно з 4-ї точки', () {
    final px = [const Vec(10, 20), const Vec(380, 30), const Vec(200, 280), const Vec(50, 250), const Vec(330, 200)];
    final fit = fitImage([for (final p in px) (p, truth.apply(p))]);
    for (final p in px) {
      expect(fit.affine.apply(p).dist(truth.apply(p)), lessThan(1e-6));
    }
    expect(fit.rms, lessThan(1e-6));
    expect(fit.affine.invert(truth.apply(const Vec(123, 45))).dist(const Vec(123, 45)), lessThan(1e-6));
    // Хибна точка (не той хрест сітки) — видно саме її.
    final bad = [for (final (i, p) in px.indexed) (p, truth.apply(p) + (i == 3 ? const Vec(20, 0) : const Vec(0, 0)))];
    final r = fitImage(bad).residuals;
    expect(r.indexOf(r.reduce(math.max)), 3);
    // Три точки на одній прямій — помилка.
    expect(() => fitImage([for (final p in [const Vec(0, 0), const Vec(10, 10), const Vec(20, 20)]) (p, truth.apply(p))]),
        throwsArgumentError);
  });

  test('прив’язка за 2 точками: поворот і масштаб без перекосу, рядки зображення — униз', () {
    // Скан без перекосу: піксель 0.25 м, поворот 30°.
    final s = 0.25, t = 30 * math.pi / 180;
    Vec world(Vec p) => Vec(500000 + s * (p.x * math.cos(t) + p.y * math.sin(t)),
        300000 + s * (p.x * math.sin(t) - p.y * math.cos(t)));
    final fit = fitImage([(const Vec(10, 10), world(const Vec(10, 10))), (const Vec(390, 290), world(const Vec(390, 290)))]);
    expect(fit.affine.apply(const Vec(200, 50)).dist(world(const Vec(200, 50))), lessThan(1e-6));
    expect(fit.affine.pixelSize, closeTo(0.25, 1e-9));
    expect(fit.residuals, isEmpty);
    // Файл прив'язки: A, D, B, E, C, F.
    final wf = fit.affine.worldFile;
    expect(wf[0], closeTo(s * math.cos(t), 1e-9));
    expect(wf[3], closeTo(-s * math.cos(t), 1e-9));
    // C, F — центр лівого верхнього пікселя (0.5, 0.5).
    expect(Vec(wf[4], wf[5]).dist(world(const Vec(0.5, 0.5))), lessThan(1e-6));
  });

  test('обведення прилипає до середини червоної лінії й не плутає її з сіткою чи зеленою', () {
    final r = sheet();
    // Палець — на 3–4 пікселі повз лінію.
    // Дуга при 220°: (46.8, 271.4); торкання — поруч, біля сірої лінії сітки x = 50.
    final c = pickNearestColor(r, const Vec(50, 268));
    expect(colorDist(c, 0xD21E1E), lessThan(40));
    final taps = [
      for (final a in [205.0, 225, 245, 265, 285, 305, 325, 335])
        Vec(200 + 204 * math.cos(a * math.pi / 180), 400 + 204 * math.sin(a * math.pi / 180)),
    ];
    final line = traceLine(r, taps, c);
    expect(line.length, greaterThan(10));
    for (final p in line) {
      final rad = p.dist(const Vec(200, 400));
      if (p.y < 300) expect(rad, closeTo(200, 1.5), reason: '$p');
    }
    // Біля зеленої лінії червоної немає — прилипання не спрацьовує.
    expect(snapToLine(r, const Vec(100, 262), c), isNull);
    expect(snapToLine(r, const Vec(100, 262), pickNearestColor(r, const Vec(100, 262)))!.y, closeTo(260.5, 0.6));
  });

  test('лінія від одного торкання: сама йде лінією в обидва боки, через уступ і напис, до кінця лінії', () {
    const w = 400, h = 200;
    final b = Uint8List(w * h * 4)..fillRange(0, w * h * 4, 255);
    void dot(int x, int y, int rgb) {
      if (x < 0 || y < 0 || x >= w || y >= h) return;
      final i = (y * w + x) * 4;
      b[i] = rgb >> 16;
      b[i + 1] = (rgb >> 8) & 255;
      b[i + 2] = rgb & 255;
    }

    // Товщина 3 пікселі: червона лінія проєкту з уступом бордюру; поруч — чорна лінія землі.
    void seg(Vec a, Vec c, int rgb) {
      final n = (c - a).length.ceil() * 2;
      for (var k = 0; k <= n; k++) {
        final p = a + (c - a) * (k / n);
        for (var d = -1; d <= 1; d++) {
          dot(p.x.floor(), p.y.floor() + d, rgb);
          dot(p.x.floor() + d, p.y.floor(), rgb);
        }
      }
    }

    const red = 0xD21E1E;
    seg(const Vec(20, 100), const Vec(150, 100), red);
    seg(const Vec(150, 100), const Vec(150, 120), red); // уступ 20 пікселів
    seg(const Vec(150, 120), const Vec(300, 140), red);
    seg(const Vec(0, 110), const Vec(400, 112), 0x000000);
    // «Напис» поверх лінії — білий розрив 20 пікселів.
    for (var x = 200; x < 220; x++) {
      for (var y = 120; y < 145; y++) {
        dot(x, y, 0xFFFFFF);
      }
    }
    final r = Raster(w, h, b);
    final c = pickNearestColor(r, const Vec(60, 103));
    final line = followAcross(r, const Vec(60, 103), c);
    expect(line.first.x, lessThan(25));
    expect(line.last.x, greaterThan(295));
    double yAt(double x) => zOnLine([for (final p in line) (p.x, p.y)], x)!;
    expect(yAt(100), closeTo(100.5, 1));
    expect(yAt(250), closeTo(120 + 100 / 150 * 20 + 0.5, 1.5));
    expect(yAt(210), closeTo(120 + 60 / 150 * 20 + 0.5, 1.5)); // під «написом» — прямо
    // Чорна лінія землі поруч не підхоплюється.
    for (final p in line) {
      expect((p.y - (110 + p.x / 200)).abs(), greaterThan(2), reason: '$p');
    }
    // Торкання далеко від лінії цього кольору — порожньо.
    expect(followAcross(r, const Vec(60, 60), c), isEmpty);
  });

  test('обведена вісь стає відрізками в координатах креслення', () {
    final segs = toSegments([const Vec(0, 0), const Vec(100, 0), const Vec(100, 100)], truth);
    expect(segs.length, 2);
    expect(segs.first.length, closeTo(100 * math.sqrt(0.489 * 0.489 + 0.102 * 0.102), 1e-9));
  });

  test('поперечник з уступами бордюрів: обидва кінці уступу, симетрично ліворуч і праворуч', () {
    // Як у типовому кресленні: з краю — вниз до бордюру, уступ униз, до осі вгору, від осі вниз, уступ угору.
    // 10 пікселів на метр, вертикаль у 10 разів крупніша; вісь — x 100, відмітка 82.78.
    const line = [
      Vec(0, 0), Vec(50, 6), Vec(50, 21), Vec(100, 8), Vec(150, 21), Vec(150, 6), Vec(200, 0),
    ];
    final s = sectionFromTrace(line, const Vec(100, 8), 82.78, 10, 100);
    expect(s.length, 7);
    expect(s[1].$1, s[2].$1); // уступ ліворуч — дві точки на одному зміщенні
    expect(s[4].$1, s[5].$1); // і праворуч
    for (final o in [1.0, 3.0, 4.9, 5.2, 7.0, 9.0]) {
      expect(zOnLine(s, -o)!, closeTo(zOnLine(s, o)!, 1e-9), reason: '±$o м');
    }
    // Перед бордюром (уступ на 5 м) — низ, нижче за вісь; за бордюром — верх, вище.
    expect(zOnLine(s, 4.99)!, closeTo(82.65, 0.002));
    expect(zOnLine(s, -4.99)!, closeTo(82.65, 0.002));
    expect(zOnLine(s, 5.2)!, greaterThan(82.78));
  });

  test('профіль з масштабу: два ПК по горизонталі, дві відмітки по вертикалі', () {
    // 1 піксель = 2 м по горизонталі; 10 пікселів = 1 м по вертикалі; рядки — униз.
    const s = ProfileScale((100, 0), (600, 1000), (400, 80), (100, 110));
    expect(s.valid, isTrue);
    final p = profileFromTrace([const Vec(100, 400), const Vec(350, 300), const Vec(600, 350), const Vec(350.1, 300)], s, 'скан');
    expect(p.pvis.length, 3); // повтор біля ПК 500 прибрано
    expect(p.elevationAt(250), closeTo(85, 1e-9));
    expect(p.elevationAt(500), closeTo(90, 1e-9));
    expect(p.elevationAt(1000), closeTo(85, 1e-9));
  });
}
