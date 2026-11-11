// Власні підкладки: MBTiles (ортофото чи будь-яка растрова карта, нарізана на ПК) і знімок JPG/PNG
// з файлом прив'язки (.jgw / .pgw / .tfw). Зберігаються в пам'яті програми, спільні для всіх об'єктів.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'crs.dart';
import 'geometry.dart';
import 'i18n.dart';
import 'pmtiles.dart';
import 'problems.dart';

enum BasemapKind { mbtiles, image, pmtiles }

class Basemap {
  final String id;
  final String name;
  final BasemapKind kind;

  /// Ім'я файлу в теці підкладок.
  final String file;

  /// Межі (широта/довгота).
  final double south, west, north, east;

  /// MBTiles / PMTiles: діапазон наближень і формат плиток («mvt» — векторні, як у Protomaps).
  final int minZoom, maxZoom;
  final String format;

  /// Знімок: кути (лівий верхній, лівий нижній, правий нижній) — WGS84.
  final List<LatLng> corners;

  Basemap({
    required this.id,
    required this.name,
    required this.kind,
    required this.file,
    required this.south,
    required this.west,
    required this.north,
    required this.east,
    this.minZoom = 0,
    this.maxZoom = 22,
    this.format = 'png',
    this.corners = const [],
  });

  bool overlaps(double s, double w, double n, double e) => !(n < south || s > north || e < west || w > east);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'file': file,
        'bounds': [south, west, north, east],
        'zoom': [minZoom, maxZoom],
        'format': format,
        'corners': [for (final c in corners) [c.latitude, c.longitude]],
      };

  factory Basemap.fromJson(Map<String, dynamic> j) {
    final b = [for (final v in j['bounds'] as List) (v as num).toDouble()];
    final z = j['zoom'] as List;
    return Basemap(
      id: j['id'] as String,
      name: j['name'] as String,
      kind: BasemapKind.values.byName(j['kind'] as String),
      file: j['file'] as String,
      south: b[0],
      west: b[1],
      north: b[2],
      east: b[3],
      minZoom: (z[0] as num).toInt(),
      maxZoom: (z[1] as num).toInt(),
      format: j['format'] as String? ?? 'png',
      corners: [
        for (final c in j['corners'] as List? ?? const [])
          LatLng(((c as List)[0] as num).toDouble(), (c[1] as num).toDouble())
      ],
    );
  }
}

class BasemapException implements Exception {
  final Problem problem;
  const BasemapException(this.problem);
}

// ---------- MBTiles ----------

/// Рядок плитки в MBTiles (схема TMS: рахунок знизу) для плитки XYZ (рахунок згори).
int tmsRow(int z, int y) => (1 << z) - 1 - y;

/// «захід,південь,схід,північ» з metadata → (південь, захід, північ, схід).
(double, double, double, double)? parseBounds(String? s) {
  if (s == null) return null;
  final v = [for (final t in s.split(',')) double.tryParse(t.trim())];
  if (v.length != 4 || v.any((x) => x == null)) return null;
  return (v[1]!, v[0]!, v[3]!, v[2]!);
}

/// Межі плитки XYZ: (південь, захід, північ, схід).
(double, double, double, double) tileBounds(int z, int x, int y) {
  final n = 1 << z;
  double lat(int yy) => math.atan(_sinh(math.pi * (1 - 2 * yy / n))) * 180 / math.pi;
  return (lat(y + 1), x / n * 360 - 180, lat(y), (x + 1) / n * 360 - 180);
}

double _sinh(double v) => (math.exp(v) - math.exp(-v)) / 2;

const _notMbtiles = Problem(Severity.error, 'Це не MBTiles з растровими плитками',
    fixes: [
      'QGIS: «Обробка → Інструменти → Растрові інструменти → Створити XYZ-плитки (MBTiles)» з ортофото.',
      'Або GDAL: gdal_translate -of MBTILES ортофото.tif ортофото.mbtiles, потім gdaladdo -r average ортофото.mbtiles 2 4 8 16.',
    ]);

/// Читає опис MBTiles: межі, наближення, формат. [factory] — для тестів на комп'ютері.
Future<Basemap> describeMbtiles(String path, String id, String name, {DatabaseFactory? factory}) async {
  final f = factory ?? databaseFactory;
  Database db;
  try {
    db = await f.openDatabase(path, options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
  } catch (_) {
    throw const BasemapException(_notMbtiles);
  }
  try {
    final tables = {for (final r in await db.rawQuery("SELECT name FROM sqlite_master")) r['name']};
    if (!tables.contains('tiles') || !tables.contains('metadata')) throw const BasemapException(_notMbtiles);
    final meta = {
      for (final r in await db.rawQuery('SELECT name, value FROM metadata')) '${r['name']}': '${r['value']}'
    };
    final format = (meta['format'] ?? 'png').toLowerCase();
    if (format == 'pbf' || format == 'mvt') {
      throw const BasemapException(Problem(Severity.error, 'Це векторні MBTiles — програма показує лише растрові',
          fixes: ['Наріжте растрові плитки (PNG чи JPG) з ортофото чи карти в QGIS: «Створити XYZ-плитки (MBTiles)».']));
    }
    final zr = (await db.rawQuery('SELECT MIN(zoom_level) AS a, MAX(zoom_level) AS b FROM tiles')).first;
    if (zr['a'] == null) {
      throw const BasemapException(Problem(Severity.error, 'У MBTiles немає жодної плитки',
          fixes: ['Перевірте діапазон наближень під час нарізки (наприклад 14–20).']));
    }
    var b = parseBounds(meta['bounds']);
    if (b == null) {
      // Меж у metadata немає — рахуємо за плитками найбільшого наближення.
      final z = (zr['b'] as num).toInt();
      final r = (await db.rawQuery(
              'SELECT MIN(tile_column) a, MAX(tile_column) b, MIN(tile_row) c, MAX(tile_row) d FROM tiles WHERE zoom_level = ?',
              [z]))
          .first;
      final sw = tileBounds(z, (r['a'] as num).toInt(), tmsRow(z, (r['c'] as num).toInt()));
      final ne = tileBounds(z, (r['b'] as num).toInt(), tmsRow(z, (r['d'] as num).toInt()));
      b = (sw.$1, sw.$2, ne.$3, ne.$4);
    }
    return Basemap(
      id: id,
      name: meta['name']?.isNotEmpty == true ? meta['name']! : name,
      kind: BasemapKind.mbtiles,
      file: '$id.mbtiles',
      south: b.$1,
      west: b.$2,
      north: b.$3,
      east: b.$4,
      minZoom: (zr['a'] as num).toInt(),
      maxZoom: (zr['b'] as num).toInt(),
      format: format,
    );
  } on BasemapException {
    rethrow;
  } catch (_) {
    // Файл «відкривається» будь-який — помилка вилазить лише на першому запиті.
    throw const BasemapException(_notMbtiles);
  } finally {
    await db.close();
  }
}

/// Плитка XYZ з MBTiles або null.
Future<Uint8List?> readMbTile(Database db, int z, int x, int y) async {
  final r = await db.rawQuery('SELECT tile_data FROM tiles WHERE zoom_level = ? AND tile_column = ? AND tile_row = ?',
      [z, x, tmsRow(z, y)]);
  return r.isEmpty ? null : r.first['tile_data'] as Uint8List;
}

const notMbtilesFile = Problem(Severity.error, 'Потрібен файл .mbtiles',
    fixes: [
      'Ортофото (GeoTIFF) наріжте в MBTiles: QGIS «Створити XYZ-плитки (MBTiles)» або gdal_translate -of MBTILES.',
    ]);

const notPmtilesFile = Problem(Severity.error, 'Потрібен файл .pmtiles',
    fixes: ['Виріжте ділянку командою pmtiles extract (кнопка «Команда для ПК») або завантажте карту ділянки кнопкою «OSM без інтернету».']);

const geoTiffProblem = Problem(Severity.error, 'GeoTIFF програма напряму не показує',
    detail: 'Ортофото з дрона зазвичай — гігабайти; без нарізки на плитки воно не вміститься в пам’ять планшета.',
    fixes: [
      'QGIS: «Обробка → Інструменти → Растрові інструменти → Створити XYZ-плитки (MBTiles)», наближення 14–21, потім «Додати MBTiles».',
      'Або GDAL: gdal_translate -of MBTILES орто.tif орто.mbtiles, потім gdaladdo -r average орто.mbtiles 2 4 8 16 32.',
      'Невеликий знімок: QGIS «Растр → Перетворення → Перетворити» у JPEG з параметром WORLDFILE=YES — і «Додати знімок + прив’язку».',
    ]);

const notPngJpeg = Problem(Severity.error, 'Знімок не схожий на PNG чи JPEG',
    fixes: ['Збережіть знімок як PNG або JPEG (QGIS: «Растр → Перетворення → Перетворити»).']);

const imageNeedsWorldFile = Problem(Severity.error, 'Потрібні два файли: знімок і файл прив’язки',
    detail: 'Файл прив’язки (.jgw для JPG, .pgw для PNG) каже, де знімок лежить у координатах.',
    fixes: [
      'Виберіть обидва файли разом (довгий дотик — вибрати кілька).',
      'Немає файлу прив’язки — експортуйте знімок з QGIS з параметром WORLDFILE=YES у системі координат об’єкта.',
    ]);

// ---------- PMTiles ----------

/// Опис архіву PMTiles за заголовком: межі, наближення, вид плиток.
Basemap describePmtiles(PmHeader h, String id, String name) {
  final format = switch (h.tileType) { 1 => 'mvt', 2 => 'png', 3 => 'jpg', 4 => 'webp', _ => '' };
  if (format.isEmpty) {
    throw const BasemapException(Problem(Severity.error, 'Невідомий вид плиток у PMTiles',
        fixes: ['Підходять векторні плитки (як у Protomaps) або растрові PNG / JPEG / WebP.']));
  }
  if (h.tileCompression != 1 && h.tileCompression != 2) {
    throw const BasemapException(Problem(Severity.error, 'Плитки в PMTiles стиснені способом, якого програма не знає',
        fixes: ['Вирізайте ділянку з Protomaps (там gzip) або зберігайте PMTiles без стиснення плиток.']));
  }
  return Basemap(
    id: id,
    name: name,
    kind: BasemapKind.pmtiles,
    file: '$id.pmtiles',
    south: h.minLat,
    west: h.minLon,
    north: h.maxLat,
    east: h.maxLon,
    minZoom: h.minZoom,
    maxZoom: h.maxZoom,
    format: format,
  );
}

// ---------- Знімок з файлом прив'язки ----------

/// Файл прив'язки (world file): 6 чисел — A, D, B, E, C, F; X = A·стовпчик + B·рядок + C, Y = D·стовпчик + E·рядок + F
/// (для центру пікселя).
List<double> parseWorldFile(String text) {
  final v = [for (final l in const LineSplitter().convert(text)) if (l.trim().isNotEmpty) double.tryParse(l.trim().replaceAll(',', '.'))];
  if (v.length < 6 || v.take(6).any((x) => x == null)) {
    throw const BasemapException(Problem(Severity.error, 'Файл прив’язки не читається',
        detail: 'Очікується 6 чисел, по одному в рядку.',
        fixes: ['Створіть його заново під час експорту знімка (QGIS: параметр WORLDFILE=YES).']));
  }
  return [for (final x in v.take(6)) x!];
}

/// Кути знімка в координатах креслення: лівий верхній, лівий нижній, правий нижній (краї пікселів).
List<Vec> imageCorners(List<double> w, int width, int height) {
  final a = w[0], d = w[1], b = w[2], e = w[3], c = w[4], f = w[5];
  Vec at(double col, double row) => Vec(a * col + b * row + c, d * col + e * row + f);
  return [at(-0.5, -0.5), at(-0.5, height - 0.5), at(width - 0.5, height - 0.5)];
}

/// Ширина й висота PNG чи JPEG із заголовка файлу (без розпаковки знімка), або null.
(int, int)? imageSize(Uint8List b) {
  final d = ByteData.sublistView(b);
  // PNG: підпис і блок IHDR — ширина й висота в байтах 16–23.
  if (b.length > 24 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
    return (d.getUint32(16), d.getUint32(20));
  }
  // JPEG: шукаємо маркер кадру SOF0…SOF15 (крім DHT/JPG/DAC), там висота й ширина.
  if (b.length > 4 && b[0] == 0xFF && b[1] == 0xD8) {
    var i = 2;
    while (i + 9 < b.length) {
      if (b[i] != 0xFF) return null;
      final m = b[i + 1];
      final len = d.getUint16(i + 2);
      if (m >= 0xC0 && m <= 0xCF && m != 0xC4 && m != 0xC8 && m != 0xCC) {
        return (d.getUint16(i + 7), d.getUint16(i + 5));
      }
      i += 2 + len;
    }
  }
  return null;
}

/// Найбільший знімок, який розумно тримати в пам'яті пристрою (пікселів).
const maxImagePixels = 40 * 1000 * 1000;

Basemap describeImage(String id, String name, String ext, List<double> world, int width, int height, CoordSystem crs) {
  if (width * height > maxImagePixels) {
    throw BasemapException(Problem(Severity.error,
        t('Знімок завеликий для пристрою: {n} млн пікселів', {'n': (width * height / 1e6).toStringAsFixed(0)}),
        detail: 'Без нарізки на плитки такий знімок не вміститься в пам’ять планшета.',
        fixes: [
          'Наріжте його в MBTiles: QGIS «Створити XYZ-плитки (MBTiles)» або gdal_translate -of MBTILES.',
          t('Або експортуйте менший (з більшим пікселем) — до {n} млн пікселів.', {'n': maxImagePixels ~/ 1000000}),
        ]));
  }
  final cv = imageCorners(world, width, height);
  final c = [for (final p in cv) toWgs84(crs, p)];
  final all = [...c, toWgs84(crs, cv[2] - cv[1] + cv[0])]; // + правий верхній — для меж
  final out = Basemap(
    id: id,
    name: name,
    kind: BasemapKind.image,
    file: '$id.$ext',
    south: all.map((p) => p.latitude).reduce(math.min),
    west: all.map((p) => p.longitude).reduce(math.min),
    north: all.map((p) => p.latitude).reduce(math.max),
    east: all.map((p) => p.longitude).reduce(math.max),
    corners: c,
  );
  if (!crs.contains(LatLng((out.south + out.north) / 2, (out.west + out.east) / 2))) {
    throw BasemapException(Problem(Severity.error, t('Знімок не потрапляє в межі країни системи «{name}»', {'name': crsName(crs)}),
        fixes: const [
          'Перевірте, що файл прив’язки зроблено в тій самій системі координат, що й вісь об’єкта.',
          'Знімок у WGS84 / UTM чи іншій системі — перепроєктуйте його в QGIS у систему об’єкта.',
        ]));
  }
  return out;
}

// ---------- Сховище ----------

class BasemapStore {
  final Directory? dir;
  BasemapStore({this.dir});

  final List<Basemap> _web = [];
  final Map<String, Uint8List> _webBytes = {};
  bool get _memory => kIsWeb && dir == null;

  Future<Directory> folder() async {
    final d = dir ?? Directory('${(await getApplicationDocumentsDirectory()).path}/basemaps');
    await d.create(recursive: true);
    return d;
  }

  Future<File> _index() async => File('${(await folder()).path}/index.json');

  Future<List<Basemap>> list() async {
    if (_memory) return [..._web];
    final f = await _index();
    if (!await f.exists()) return [];
    try {
      return [for (final j in jsonDecode(await f.readAsString()) as List) Basemap.fromJson(j as Map<String, dynamic>)];
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(List<Basemap> all) async {
    final f = await _index();
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode([for (final b in all) b.toJson()]));
    await tmp.rename(f.path);
  }

  Future<void> add(Basemap b) async {
    if (_memory) {
      _web.add(b);
      return;
    }
    await _save([...await list(), b]);
  }

  Future<void> remove(Basemap b) async {
    if (_memory) {
      _web.removeWhere((x) => x.id == b.id);
      _webBytes.remove(b.id);
      return;
    }
    await _save([for (final x in await list()) if (x.id != b.id) x]);
    final f = File('${(await folder()).path}/${b.file}');
    if (await f.exists()) await f.delete();
  }

  Future<String> pathOf(Basemap b) async => '${(await folder()).path}/${b.file}';

  /// У браузері файлів немає — знімок тримаємо в пам'яті.
  void keepInMemory(String id, Uint8List bytes) => _webBytes[id] = bytes;
  Uint8List? memoryBytes(String id) => _webBytes[id];
}

final basemapStore = BasemapStore();
