import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:road_gps/crs.dart';
import 'package:road_gps/geometry.dart';

void main() {
  // Еталон — pyproj 3.8 / PROJ 9.8, EPSG:3844 → EPSG:4326, перехід «Pulkovo 1942(58) to WGS 84 (19)».
  const ref = [
    (Vec(598594.53, 688414.31), 47.68748566, 26.31175318), // північ Румунії, точка 1
    (Vec(584416.33, 692863.67), 47.72947503, 26.12377007), // північ Румунії, точка 2
    (Vec(598521.397, 688466.624), 47.68796707, 26.31079083), // реперна точка DEx01
    (Vec(583000.0, 326000.0), 44.42896619, 26.04094274), // біля Бухареста
  ];

  test('Stereo 70 → WGS84 збігається з PROJ до 1 см', () {
    for (final (p, lat, lon) in ref) {
      final r = toWgs84(stereo70, p);
      // 1e-7° ≈ 1 см
      expect(r.latitude, closeTo(lat, 1e-7), reason: '$p');
      expect(r.longitude, closeTo(lon, 1e-7), reason: '$p');
    }
  });

  test('WGS84 → Stereo 70 і назад — без втрат', () {
    for (final (p, lat, lon) in ref) {
      final back = fromWgs84(stereo70, LatLng(lat, lon));
      expect(back.dist(p), lessThan(0.02), reason: '$p');
    }
  });

  test('переплутані X і Y — розпізнаються лише коли «як є» виходить за межі країни', () {
    final segs = [LineSeg(const Vec(598594.53, 688414.31), const Vec(584416.33, 692863.67))];
    expect(checkPlacement(stereo70, segs), Placement.ok);
    // Точка з переставленими X/Y теж у Румунії (біля Ясс) — сама програма цього не помітить,
    // тому вісь завжди показується на карті для підтвердження.
    expect(checkPlacement(stereo70, [segs.single.swapXY()]), Placement.ok);
    // Дельта Дунаю (схід 850 км): переставлені X/Y дають точку поза Румунією.
    final delta = [LineSeg(const Vec(450000, 850000), const Vec(450100, 850100))];
    expect(checkPlacement(stereo70, delta), Placement.swapped);
    expect(checkPlacement(stereo70, [LineSeg(const Vec(0, 0), const Vec(10, 10))]),
        Placement.outside);
  });

  // Еталон — pyproj 3.8 / PROJ 9.8, найточніший перехід EPSG для країни (WGS84 → система).
  const others = [
    ('ucs2000_tm10', 50.4501, 30.5234, 337290.892, 5591157.510), // Київ, EPSG:6384
    ('ucs2000_tm8', 49.8397, 24.0297, 302256.748, 5523140.306), // Львів, EPSG:6382
    ('ucs2000_tm12', 49.9935, 36.2304, 316632.966, 5540253.499), // Харків, EPSG:6386
    ('ucs2000_gk5', 46.4825, 30.7233, 5786011.713, 5156575.629), // Одеса, EPSG:5563
    ('sk42_gk5', 46.4825, 30.7233, 5786015.582, 5156580.060), // Одеса, EPSG:28405, перехід (20)
    ('sk42_gk6', 49.9935, 36.2304, 6731736.226, 5545238.446), // Харків, EPSG:28406
    ('moldref99', 47.0105, 28.8638, 235265.718, 208206.208), // Кишинів, EPSG:4026
    ('htrs96', 43.5081, 16.4402, 495164.705, 4818688.440), // Спліт, EPSG:3765
    ('utm34', 45.815, 15.9819, 110157.944, 5085750.551), // Загреб, EPSG:32634
    ('utm35', 44.4268, 26.1025, 428561.493, 4919670.032), // Бухарест, EPSG:32635
    ('utm36', 50.4501, 30.5234, 324182.209, 5591607.607), // Київ, EPSG:32636
    // Балкани й сусіди Румунії — той самий перехід EPSG, що в crs.dart (MGI 1901 — свій для кожної країни).
    ('eov', 47.5, 19.04, 649439.112, 239562.881), // Будапешт
    ('srb_utm34', 44.81, 20.46, 457299.309, 4961985.976), // Белград
    ('mgi_srb_b6', 45.2, 19.2, 6594678.798, 5006875.853),
    ('mgi_srb_b7', 44.81, 20.46, 7457718.213, 4962967.606), // Белград
    ('mgi_srb_b8', 43.9, 22.6, 8387996.689, 4862659.084),
    ('mgi_bih_b5', 44.82, 15.87, 5569177.403, 4964327.331), // Біхач
    ('mgi_bih_b6', 43.86, 18.41, 6533363.893, 4857366.224), // Сараєво
    ('mgi_bih_b7', 44.5, 19.55, 7385126.881, 4929401.024),
    ('mgi_mne_b6', 42.42, 18.77, 6563789.182, 4697605.618), // Котор
    ('mgi_mne_b7', 42.85, 19.75, 7398286.509, 4745823.316),
    ('mgi_mkd_b7', 42.0, 21.43, 7536063.275, 4650754.187), // Скоп’є
    ('mgi_mkd_b8', 41.6, 22.7, 8392104.401, 4607044.255),
    ('kosovaref', 42.66, 21.17, 7513936.758, 4724490.995), // Приштина
    ('mgi_kos_b7', 42.66, 21.17, 7512769.857, 4724153.619), // Приштина
    ('alb_tm2010', 41.33, 19.82, 484931.449, 4577237.765), // Тирана
    ('alb87_gk4', 41.33, 19.82, 4401347.121, 4578025.181), // Тирана
    ('bgs_ccs2005', 42.7, 23.32, 321410.142, 4731695.480), // Софія
    ('ggrs87', 37.98, 23.73, 476138.586, 4203342.440), // Афіни
    ('slo_d96', 46.06, 14.51, 462087.840, 102361.500), // Любляна
    ('slo_d48', 46.06, 14.51, 462458.763, 101875.202), // Любляна
    ('mgi_hr_b5', 45.81, 15.98, 5576537.091, 5074443.232), // Загреб
    ('mgi_hr_b6', 42.65, 18.09, 6507786.540, 4722873.033), // Дубровник
  ];

  test('УСК-2000, СК-42, MOLDREF99, HTRS96, UTM, Балкани — збігаються з PROJ до 5 см', () {
    for (final (id, lat, lon, e, n) in others) {
      final c = coordSystemById(id);
      expect(c.id, id);
      final p = fromWgs84(c, LatLng(lat, lon));
      expect(p.dist(Vec(e, n)), lessThan(0.05), reason: '$id: ${p.x} ${p.y}');
      final back = toWgs84(c, Vec(e, n));
      expect(back.latitude, closeTo(lat, 1e-6), reason: id);
      expect(back.longitude, closeTo(lon, 1e-6), reason: id);
      expect(c.contains(back), isTrue, reason: '$id: межі системи');
    }
  });

  test('підбір системи: київські координати УСК-2000 лягають в Україну, а не в Румунію', () {
    final segs = [LineSeg(const Vec(337290.9, 5591157.5), const Vec(337800, 5591900))];
    final s = suggestCoordSystems(segs);
    expect(s.map((x) => x.$1.id), contains('ucs2000_tm10'));
    expect(s.map((x) => x.$1.id), isNot(contains('stereo70')));
    // Переставлені X/Y теж знаходяться.
    final swapped = suggestCoordSystems([segs.single.swapXY()]);
    expect(swapped.firstWhere((x) => x.$1.id == 'ucs2000_tm10').$2, Placement.swapped);
  });

  test('калібрування за точками: умовні координати → WGS84, похибка й збереження в id', () {
    // Справжні точки — у Stereo 70 біля Бухареста; «креслення» — ті самі, зсунуті й повернуті на 30°.
    final real = [const Vec(583000, 326000), const Vec(583900, 326400), const Vec(583300, 327100), const Vec(584200, 327300)];
    final rot = 30 * 3.141592653589793 / 180;
    Vec local(Vec p) {
      final x = p.x - 583000, y = p.y - 326000;
      return Vec(1000 + x * cosOf(rot) + y * sinOf(rot), 2000 - x * sinOf(rot) + y * cosOf(rot));
    }

    final pairs = [for (final p in real) (local(p), toWgs84(stereo70, p))];
    final cal = fitCalibration(pairs);
    expect(cal.rms, lessThan(0.05));
    expect(cal.scale, closeTo(1, 0.01)); // UTM і Stereo 70 мають трохи різний масштаб
    for (final p in real) {
      final a = toWgs84(stereo70, p), b = toWgs84(cal.system, local(p));
      expect(const Distance().as(LengthUnit.Meter, a, b), lessThan(0.1));
    }
    // Система відтворюється з id (так її зберігає об'єкт).
    final again = coordSystemById(cal.system.id);
    expect(fromWgs84(again, pairs[2].$2).dist(pairs[2].$1), lessThan(0.05));
    // Помилка в одній точці видно в похибці.
    final bad = [...pairs.take(3), (pairs[3].$1 + const Vec(15, 0), pairs[3].$2)];
    expect(fitCalibration(bad).residuals.reduce((a, b) => a > b ? a : b), greaterThan(5));
  });
}

double cosOf(double a) => cos(a);
double sinOf(double a) => sin(a);
