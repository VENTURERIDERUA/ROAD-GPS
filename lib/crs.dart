// Системи координат креслення і перерахунок у WGS84 (те, що дає GPS).
// Параметри переходів — з бази EPSG (перевірено через PROJ / pyproj), найточніший перехід для країни.
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';
import 'package:proj4dart/proj4dart.dart' as proj4;

import 'geometry.dart';
import 'i18n.dart';

class CoordSystem {
  final String id;
  final String name;

  /// Країна чи група — для списку вибору.
  final String group;

  /// Опис для proj4dart. Повороти towgs84 тут — у записі «position vector»
  /// (протилежний знак до EPSG «coordinate frame»).
  final String proj;

  /// Точність самого перерахунку за офіційними параметрами, м.
  final double accuracyM;

  /// Приблизні межі, де ця система вживається (широта/довгота), — щоб спіймати переплутані X/Y чи не ту систему.
  final double minLat, maxLat, minLon, maxLon;

  /// Калібрування за точками: креслення (x, y) → система [proj]: (a·x − b·y + c, b·x + a·y + d).
  final List<double>? helmert;

  const CoordSystem(this.id, this.name, this.proj, this.accuracyM, this.minLat, this.maxLat, this.minLon, this.maxLon,
      {this.group = '', this.helmert});

  bool contains(LatLng p) =>
      p.latitude >= minLat && p.latitude <= maxLat && p.longitude >= minLon && p.longitude <= maxLon;

  bool get calibrated => helmert != null;
}

/// Stereo 70: перехід EPSG «Pulkovo 1942(58) to WGS 84 (19)», точність 3 м.
/// EPSG дає повороти 0.309 / −0.325 / −0.497 у записі «coordinate frame»; тут — з протилежним
/// знаком. Поширений рядок з epsg.io має знаки як у EPSG і зсуває точку приблизно на 35 м.
const stereo70 = CoordSystem(
  'stereo70',
  'Stereo 70 (Румунія)',
  '+proj=sterea +lat_0=46 +lon_0=25 +k=0.99975 +x_0=500000 +y_0=500000 +ellps=krass '
      '+towgs84=2.329,-147.042,-92.08,-0.309,0.325,0.497,5.69 +units=m +no_defs',
  3.0,
  43.5, 48.4, 20.2, 29.8,
  group: 'Румунія',
);

// УСК-2000 → WGS84: EPSG «UCS-2000 to WGS 84 (2)», зсув 24 / −121 / −76 м, точність 1 м.
const _ucs = '+ellps=krass +towgs84=24,-121,-76,0,0,0,0 +units=m +no_defs';

// СК-42 (Pulkovo 1942) → WGS84 для України й Молдови: EPSG «Pulkovo 1942 to WGS 84 (20)», 3 м.
// EPSG: rx 0, ry −0.35, rz −0.79, s −0.22 у записі «coordinate frame» — тут повороти з протилежним знаком.
const _sk42 = '+ellps=krass +towgs84=23.57,-140.95,-79.8,0,0.35,0.79,-0.22 +units=m +no_defs';

// Межі України з запасом; зона обрізає довготу.
CoordSystem _ua(String id, String name, String proj, double acc, double lon0, double half) =>
    CoordSystem(id, name, proj, acc, 43.5, 53, math.max(21, lon0 - half), math.min(41, lon0 + half), group: 'Україна');

final coordSystems = <CoordSystem>[
  stereo70,
  // УСК-2000, 3-градусні зони 7–13 (EPSG 6381–6387): X без номера зони, 300 000 на осьовому меридіані.
  for (var z = 7; z <= 13; z++)
    _ua('ucs2000_tm$z', 'УСК-2000, 3° зона $z (осьовий ${21 + (z - 7) * 3}°)',
        '+proj=tmerc +lat_0=0 +lon_0=${21 + (z - 7) * 3} +k=1 +x_0=300000 +y_0=0 $_ucs', 1, 21.0 + (z - 7) * 3, 2.5),
  // УСК-2000, 6-градусні зони 4–7 (EPSG 5562–5565): номер зони — перша цифра X (4 500 000…).
  for (var z = 4; z <= 7; z++)
    _ua('ucs2000_gk$z', 'УСК-2000, 6° зона $z (X з «$z…»)',
        '+proj=tmerc +lat_0=0 +lon_0=${z * 6 - 3} +k=1 +x_0=${z}500000 +y_0=0 $_ucs', 1, z * 6 - 3.0, 4),
  // СК-42 Гаусса — Крюгера, зони 4–7 (EPSG 28404–28407) — старі креслення України й Молдови.
  for (var z = 4; z <= 7; z++)
    CoordSystem('sk42_gk$z', 'СК-42, 6° зона $z (X з «$z…»)',
        '+proj=tmerc +lat_0=0 +lon_0=${z * 6 - 3} +k=1 +x_0=${z}500000 +y_0=0 $_sk42', 3, 43.5, 53,
        math.max(20, z * 6 - 7.0), math.min(41, z * 6 + 1.0),
        group: 'Україна, Молдова'),
  // MOLDREF99 / Moldova TM (EPSG 4026): ETRS89, з WGS84 збігається в межах 1 м.
  const CoordSystem('moldref99', 'MOLDREF99 (Молдова)',
      '+proj=tmerc +lat_0=0 +lon_0=28.4 +k=0.99994 +x_0=200000 +y_0=-5000000 +ellps=GRS80 +units=m +no_defs', 1,
      45.2, 48.7, 26.4, 30.4,
      group: 'Молдова'),
  // HTRS96 / Croatia TM (EPSG 3765).
  const CoordSystem('htrs96', 'HTRS96/TM (Хорватія)',
      '+proj=tmerc +lat_0=0 +lon_0=16.5 +k=0.9999 +x_0=500000 +y_0=0 +ellps=GRS80 +units=m +no_defs', 1,
      42.2, 46.7, 13.2, 19.6,
      group: 'Хорватія'),
  // Балкани й сусіди Румунії (27.10.2026). Переходи — найточніші EPSG для країни, звірено з PROJ.
  // HD72 / EOV (EPSG 23700), «HD72 to WGS 84 (4)», 1 м. Угорці пишуть Y — схід (650 000), X — північ.
  const CoordSystem('eov', 'HD72 / EOV (Угорщина)',
      '+proj=somerc +lat_0=47.1443937222222 +lon_0=19.0485717777778 +k_0=0.99993 +x_0=650000 +y_0=200000 '
          '+ellps=GRS67 +towgs84=52.17,-71.82,-14.9,0,0,0,0 +units=m +no_defs',
      1, 45.6, 48.7, 16.0, 23.0,
      group: 'Угорщина'),
  // SRB_ETRS89 / UTM 34N (EPSG 8682) — нова система Сербії.
  const CoordSystem('srb_utm34', 'SRB_ETRS89 / UTM 34N (Сербія)', '+proj=utm +zone=34 +ellps=GRS80 +units=m +no_defs', 1,
      42.1, 46.3, 18.7, 23.1,
      group: 'Сербія'),
  // Старі креслення колишньої Югославії: MGI 1901 / Балкани, зони 5–8 (EPSG 8677, 8678, 6316, 8679), Бессель;
  // перехід у WGS84 у кожній країні свій.
  for (final (z, lat0, lat1, lon0, lon1) in const [(6, 42.1, 46.3, 18.7, 19.6), (7, 42.1, 46.3, 19.4, 22.6), (8, 42.1, 44.8, 22.4, 23.1)])
    _mgi('srb', 'Сербія', z, _mgiSrb, 1, lat0, lat1, lon0, lon1),
  for (final (z, lon0, lon1) in const [(5, 15.6, 16.6), (6, 16.4, 19.6), (7, 19.4, 19.7)])
    _mgi('bih', 'Боснія і Герцеговина', z, _mgiBih, 1, 42.5, 45.4, lon0, lon1),
  for (final (z, lon0, lon1) in const [(6, 18.4, 19.6), (7, 19.4, 20.4)])
    _mgi('mne', 'Чорногорія', z, _mgiMne, 10, 41.8, 43.6, lon0, lon1),
  for (final (z, lon0, lon1) in const [(7, 20.4, 22.6), (8, 22.4, 23.1)])
    _mgi('mkd', 'Північна Македонія', z, _mgiMkd, 2, 40.8, 42.4, lon0, lon1),
  _mgi('kos', 'Косово', 7, _mgiKos, 1, 41.8, 43.3, 20.0, 21.9),
  // KOSOVAREF01 / Balkans zone 7 (EPSG 9141) — нова система Косова, на ETRS89.
  const CoordSystem('kosovaref', 'KOSOVAREF01 / Балкани зона 7 (Косово)',
      '+proj=tmerc +lat_0=0 +lon_0=21 +k=0.9999 +x_0=7500000 +y_0=0 +ellps=GRS80 +units=m +no_defs', 1,
      41.8, 43.3, 20.0, 21.9,
      group: 'Косово'),
  // ETRS89 / Albania TM 2010 (EPSG 6870) і стара Albanian 1987 / Гаусс — Крюгер зона 4 (EPSG 2462).
  const CoordSystem('alb_tm2010', 'ETRS89 / Albania TM 2010 (Албанія)',
      '+proj=tmerc +lat_0=0 +lon_0=20 +k=1 +x_0=500000 +y_0=0 +ellps=GRS80 +units=m +no_defs', 1,
      39.6, 42.7, 19.2, 21.1,
      group: 'Албанія'),
  const CoordSystem('alb87_gk4', 'Albanian 1987 / Гаусс — Крюгер зона 4 (Албанія)',
      '+proj=tmerc +lat_0=0 +lon_0=21 +k=1 +x_0=4500000 +y_0=0 +ellps=krass '
          '+towgs84=-44.183,-0.58,-38.489,2.3867,2.7072,-3.5196,-8.2703 +units=m +no_defs',
      1, 39.6, 42.7, 19.2, 21.1,
      group: 'Албанія'),
  // BGS2005 / CCS2005 (EPSG 7801). Стару болгарську «1970» EPSG не описує — для неї калібрування.
  const CoordSystem('bgs_ccs2005', 'BGS2005 / CCS2005 (Болгарія)',
      '+proj=lcc +lat_0=42.6678756833333 +lon_0=25.5 +lat_1=42 +lat_2=43.3333333333333 +x_0=500000 '
          '+y_0=4725824.3591 +ellps=GRS80 +units=m +no_defs',
      1, 41.2, 44.3, 22.3, 28.7,
      group: 'Болгарія'),
  // GGRS87 / Greek Grid (EPSG 2100), «GGRS87 to WGS 84 (1)».
  const CoordSystem('ggrs87', 'GGRS87 / Greek Grid (Греція)',
      '+proj=tmerc +lat_0=0 +lon_0=24 +k=0.9996 +x_0=500000 +y_0=0 +ellps=GRS80 '
          '+towgs84=-199.87,74.79,246.62,0,0,0,0 +units=m +no_defs',
      1, 34.8, 41.8, 19.3, 28.3,
      group: 'Греція'),
  // Словенія: D96/TM (EPSG 3794) і стара D48/GK (EPSG 3912, «MGI 1901 to WGS 84 (16)»).
  const CoordSystem('slo_d96', 'D96/TM (Словенія)',
      '+proj=tmerc +lat_0=0 +lon_0=15 +k=0.9999 +x_0=500000 +y_0=-5000000 +ellps=GRS80 +units=m +no_defs', 1,
      45.4, 46.9, 13.3, 16.7,
      group: 'Словенія'),
  const CoordSystem('slo_d48', 'D48/GK (Словенія)',
      '+proj=tmerc +lat_0=0 +lon_0=15 +k=0.9999 +x_0=500000 +y_0=-5000000 +ellps=bessel $_mgiSlo +units=m +no_defs', 1,
      45.4, 46.9, 13.3, 16.7,
      group: 'Словенія'),
  // Хорватія до HTRS96 — HDKS, теж MGI 1901 / Балкани зони 5–6, «MGI 1901 to WGS 84 (4)».
  _mgi('hr', 'Хорватія', 5, _mgiHr, 1, 42.3, 46.6, 13.4, 16.6),
  _mgi('hr', 'Хорватія', 6, _mgiHr, 1, 42.3, 46.6, 16.4, 19.5),
  // UTM на WGS84 (ETRS89 UTM — ті самі цифри з точністю до 1 м).
  for (var z = 33; z <= 37; z++) utmZone(z),
];

// MGI 1901 → WGS84 за країнами (EPSG), повороти — у записі «position vector».
const _mgiSrb = '+towgs84=577.84843,165.45019,390.43652,4.93131,-0.96052,-13.05072,7.86546'; // (15)
const _mgiBih = '+towgs84=489.88,183.912,533.711,5.76545,4.69994,-12.58211,1.00646'; // (13)
const _mgiMne = '+towgs84=695.5,-216.6,491.1,0,0,0,0'; // (6), лише 10 м — точнішого EPSG не має
const _mgiMkd = '+towgs84=521.748,229.489,590.921,4.029,4.488,-15.521,-9.78'; // (10), 2 м
const _mgiKos = '+towgs84=628.54052,192.2538,498.43507,-13.79189,-0.81467,41.21533,-17.40368'; // (14)
const _mgiSlo = '+towgs84=476.08,125.947,417.81,4.610862,2.388137,-11.942335,9.896638'; // (16)
const _mgiHr = '+towgs84=551.7,162.9,467.9,6.04,1.96,-11.38,-4.82'; // (4)

/// MGI 1901 / Балкани, зона [z]: осьовий меридіан 3·z°, X з «z5…».
CoordSystem _mgi(String country, String group, int z, String towgs84, double acc, double lat0, double lat1,
        double lon0, double lon1) =>
    CoordSystem('mgi_${country}_b$z', 'MGI 1901, Балкани зона $z ($group)',
        '+proj=tmerc +lat_0=0 +lon_0=${z * 3} +k=0.9999 +x_0=${z}500000 +y_0=0 +ellps=bessel $towgs84 +units=m +no_defs',
        acc, lat0, lat1, lon0, lon1,
        group: group);

/// UTM, північна півкуля, зона [z] (WGS84; ETRS89 — те саме в межах 1 м).
CoordSystem utmZone(int z) => CoordSystem('utm$z', 'UTM ${z}N (WGS84 / ETRS89)',
    '+proj=utm +zone=$z +datum=WGS84 +units=m +no_defs', 1, 0, 84, z * 6 - 186.0 - 3, z * 6 - 180.0 + 3,
    group: 'Будь-яка країна');

/// Назва системи мовою інтерфейсу. [CoordSystem.name] складено один раз українською, а мову
/// можна змінити будь-коли — тож номери зон беремо з id і перекладаємо тут, при показі.
String crsName(CoordSystem c) {
  final p = c.id.split(':');
  if (p.first == 'calib') {
    return t('Калібрування за {n} точками ({base})',
        {'n': p[2], 'base': crsName(coordSystemById(p[1])).split(' (').first});
  }
  final mgi = RegExp(r'^mgi_[a-z]+_b(\d)$').firstMatch(c.id);
  if (mgi != null) return t('MGI 1901, Балкани зона {z} ({country})', {'z': mgi[1], 'country': t(c.group)});
  final m = RegExp(r'^(ucs2000_tm|ucs2000_gk|sk42_gk)(\d+)$').firstMatch(c.id);
  if (m != null) {
    final z = int.parse(m[2]!);
    return switch (m[1]) {
      'ucs2000_tm' => t('УСК-2000, 3° зона {z} (осьовий {m}°)', {'z': z, 'm': 21 + (z - 7) * 3}),
      'ucs2000_gk' => t('УСК-2000, 6° зона {z} (X з «{z}…»)', {'z': z}),
      _ => t('СК-42, 6° зона {z} (X з «{z}…»)', {'z': z}),
    };
  }
  return t(c.name);
}

/// Країна чи група системи мовою інтерфейсу.
String crsGroup(CoordSystem c) => t(c.group);

CoordSystem coordSystemById(String id) {
  if (id.startsWith('calib:')) return _calibFromId(id);
  final utm = RegExp(r'^utm(\d{1,2})$').firstMatch(id);
  if (utm != null) return utmZone(int.parse(utm[1]!));
  return coordSystems.firstWhere((c) => c.id == id, orElse: () => stereo70);
}

final _cache = <String, proj4.Projection>{};
final _wgs84 = proj4.Projection.get('EPSG:4326')!;
proj4.Projection _projOf(CoordSystem c) => _cache[c.proj] ??= proj4.Projection.parse(c.proj);

/// Точка креслення (X — схід, Y — північ) → широта/довгота WGS84.
LatLng toWgs84(CoordSystem c, Vec p) {
  final h = c.helmert;
  final q = h == null ? p : Vec(h[0] * p.x - h[1] * p.y + h[2], h[1] * p.x + h[0] * p.y + h[3]);
  final r = _projOf(c).transform(_wgs84, proj4.Point(x: q.x, y: q.y));
  return LatLng(r.y, r.x);
}

/// Широта/довгота WGS84 → точка креслення (X — схід, Y — північ).
Vec fromWgs84(CoordSystem c, LatLng p) {
  final r = _wgs84.transform(_projOf(c), proj4.Point(x: p.longitude, y: p.latitude));
  final h = c.helmert;
  if (h == null) return Vec(r.x, r.y);
  final det = h[0] * h[0] + h[1] * h[1];
  final dx = r.x - h[2], dy = r.y - h[3];
  return Vec((h[0] * dx + h[1] * dy) / det, (-h[1] * dx + h[0] * dy) / det);
}

/// Чи потрапляє вісь у країну системи: як є, з переставленими X/Y, чи ніяк.
/// Перестановку видно не завжди: для Stereo 70 часто обидва варіанти в межах Румунії,
/// тож остаточно — лише по карті.
enum Placement { ok, swapped, outside }

Placement checkPlacement(CoordSystem c, List<Segment> segs) {
  final probe = [segs.first.start, segs.last.end];
  bool inside(Vec p) {
    try {
      return c.contains(toWgs84(c, p));
    } catch (_) {
      return false; // проєкція не рахується для таких чисел — точно не ця система
    }
  }

  if (probe.every(inside)) return Placement.ok;
  if (probe.every((p) => inside(Vec(p.y, p.x)))) return Placement.swapped;
  return Placement.outside;
}

/// Системи, у яких вісь лягає в межі їхньої країни (як є чи з переставленими X/Y).
/// Кілька варіантів — звична річ (сусідні зони мають однакові числа): остаточно вирішує карта.
List<(CoordSystem, Placement)> suggestCoordSystems(List<Segment> segs) => [
      for (final c in coordSystems)
        if (!c.id.startsWith('utm'))
          if (checkPlacement(c, segs) case final p when p != Placement.outside) (c, p),
    ];

// ---------- Калібрування за точками ----------

/// Підібране калібрування: система, похибка на кожній точці (м), масштаб і поворот креслення.
class Calibration {
  final CoordSystem system;
  final List<double> residuals;
  final double scale, rotationDeg;
  const Calibration(this.system, this.residuals, this.scale, this.rotationDeg);

  /// Середньоквадратична похибка, м (з двох точок — 0: перевірити нічим).
  double get rms => residuals.isEmpty
      ? 0
      : math.sqrt(residuals.fold(0.0, (a, r) => a + r * r) / residuals.length);
}

/// Прив'язати креслення в невідомій (місцевій, умовній) системі за точками «креслення ↔ місцевість»:
/// зсув, поворот і масштаб у UTM найближчої зони. Потрібно ≥ 2 точки; з 3 і більше видно похибку.
Calibration fitCalibration(List<(Vec, LatLng)> pairs) {
  if (pairs.length < 2) throw ArgumentError('потрібно щонайменше 2 точки');
  final lon = pairs.fold(0.0, (a, p) => a + p.$2.longitude) / pairs.length;
  final base = utmZone(((lon + 180) / 6).floor() + 1);
  final src = [for (final p in pairs) p.$1];
  final dst = [for (final p in pairs) fromWgs84(base, p.$2)];
  final n = pairs.length;
  final sx = src.fold(0.0, (a, p) => a + p.x) / n, sy = src.fold(0.0, (a, p) => a + p.y) / n;
  final dx = dst.fold(0.0, (a, p) => a + p.x) / n, dy = dst.fold(0.0, (a, p) => a + p.y) / n;
  var num1 = 0.0, num2 = 0.0, den = 0.0;
  for (var i = 0; i < n; i++) {
    final x = src[i].x - sx, y = src[i].y - sy, X = dst[i].x - dx, Y = dst[i].y - dy;
    num1 += x * X + y * Y;
    num2 += x * Y - y * X;
    den += x * x + y * y;
  }
  if (den < 1e-6) throw ArgumentError('точки креслення збігаються');
  final a = num1 / den, b = num2 / den;
  final c = dx - a * sx + b * sy, d = dy - b * sx - a * sy;
  final h = [a, b, c, d];
  final residuals = n < 3
      ? <double>[]
      : [
          for (var i = 0; i < n; i++)
            Vec(a * src[i].x - b * src[i].y + c - dst[i].x, b * src[i].x + a * src[i].y + d - dst[i].y).length,
        ];
  final rms = residuals.isEmpty ? 0.0 : math.sqrt(residuals.fold(0.0, (s, r) => s + r * r) / n);
  return Calibration(
    _calibSystem(base, h, n, rms),
    residuals,
    math.sqrt(a * a + b * b),
    math.atan2(b, a) * 180 / math.pi,
  );
}

CoordSystem _calibSystem(CoordSystem base, List<double> h, int points, double rms) => CoordSystem(
      'calib:${base.id}:$points:${rms.toStringAsFixed(2)}:${h.join(',')}',
      'Калібрування за $points точками (${base.name.split(' (').first})',
      base.proj,
      // Точність: похибка на точках плюс самих точок (GPS телефона ~3 м); з двох точок перевірити нічим.
      points < 3 ? 5 : math.max(1, rms + 1),
      -90, 90, -180, 180,
      group: 'Калібрування',
      helmert: h,
    );

CoordSystem _calibFromId(String id) {
  final p = id.split(':');
  final h = [for (final v in p[4].split(',')) double.parse(v)];
  return _calibSystem(coordSystemById(p[1]), h, int.parse(p[2]), double.parse(p[3]));
}
