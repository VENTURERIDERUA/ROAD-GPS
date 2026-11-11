// Карта OpenStreetMap з кешем переглянутих плиток.
// Правила OSM (operations.osmfoundation.org/policies/tiles): завантажувати наперед і «офлайн» — заборонено;
// кешувати переглянуте — треба, за заголовками сервера, а без них — щонайменше 7 днів. Тож тут: лише те,
// що людина переглядала з інтернетом; без зв'язку показуємо збережене, навіть прострочене (сервер не
// навантажується — запиту немає).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

const osmUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// Своє, впізнаване ім'я програми — так вимагають правила OSM.
const osmUserAgent = 'ROAD-GPS/0.4 (io.github.ventureriderua.road_gps; Android)';

/// Скільки плитка вважається свіжою за заголовками відповіді; без них — 7 днів.
Duration freshFor(Map<String, String> headers, {DateTime? now}) {
  final cc = headers['cache-control'] ?? '';
  final m = RegExp(r'max-age=(\d+)').firstMatch(cc);
  if (cc.contains('no-store') || cc.contains('no-cache')) return Duration.zero;
  if (m != null) return Duration(seconds: int.parse(m[1]!));
  final exp = headers['expires'];
  if (exp != null) {
    try {
      final d = HttpDate.parse(exp).difference(now ?? DateTime.now());
      return d.isNegative ? Duration.zero : d;
    } catch (_) {
      // Незрозуміла дата — як без заголовка.
    }
  }
  return const Duration(days: 7);
}

/// Кеш понад [maxBytes] — найстаріші плитки видаляються (запускається раз при старті програми).
Future<void> trimCache(Directory dir, {int maxBytes = 500 * 1024 * 1024}) async {
  if (!await dir.exists()) return;
  final files = <(File, int, DateTime)>[];
  await for (final f in dir.list(recursive: true)) {
    if (f is File && f.path.endsWith('.png')) {
      final s = await f.stat();
      files.add((f, s.size, s.modified));
    }
  }
  var total = files.fold(0, (a, f) => a + f.$2);
  if (total <= maxBytes) return;
  files.sort((a, b) => a.$3.compareTo(b.$3));
  for (final (f, size, _) in files) {
    if (total <= maxBytes) break;
    try {
      await f.delete();
      final meta = File('${f.path}.json');
      if (await meta.exists()) await meta.delete();
      total -= size;
    } catch (_) {
      // Зайнятий файл — спробуємо наступного разу.
    }
  }
}

Directory? _cacheDir;
Future<Directory> osmCacheDir() async =>
    _cacheDir ??= Directory('${(await getApplicationSupportDirectory()).path}/osm_tiles');

/// Плитки OSM з кешем; у браузері (перевірка на комп'ютері) — звичайні мережеві.
TileProvider osmTileProvider() => kIsWeb ? NetworkTileProvider() : _CachedOsmProvider();

class _CachedOsmProvider extends TileProvider {
  _CachedOsmProvider() : super(headers: {'User-Agent': osmUserAgent});
  final _client = http.Client();

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      _OsmTile(coordinates.z, coordinates.x, coordinates.y, _client);

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
}

@immutable
class _OsmTile extends ImageProvider<_OsmTile> {
  final int z, x, y;
  final http.Client client;
  const _OsmTile(this.z, this.x, this.y, this.client);

  @override
  Future<_OsmTile> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_OsmTile key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(_load(decode).then((c) async => ImageInfo(image: (await c.getNextFrame()).image)));

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    Future<ui.Codec> codec(Uint8List b) async => decode(await ui.ImmutableBuffer.fromUint8List(b));
    final dir = await osmCacheDir();
    final file = File('${dir.path}/$z/$x/$y.png');
    final meta = File('${file.path}.json');
    Map<String, dynamic>? m;
    if (await file.exists() && await meta.exists()) {
      try {
        m = jsonDecode(await meta.readAsString()) as Map<String, dynamic>;
        if (DateTime.now().isBefore(DateTime.parse(m['fresh'] as String))) return await codec(await file.readAsBytes());
      } catch (_) {
        m = null;
      }
    }
    try {
      final r = await client.get(Uri.parse('https://tile.openstreetmap.org/$z/$x/$y.png'), headers: {
        'User-Agent': osmUserAgent,
        if (m?['etag'] != null) 'If-None-Match': m!['etag'] as String,
      }).timeout(const Duration(seconds: 15));
      final headers = r.headers;
      if (r.statusCode == 304 && await file.exists()) {
        await _writeMeta(meta, headers, m?['etag'] as String?);
        return await codec(await file.readAsBytes());
      }
      if (r.statusCode == 200) {
        await file.parent.create(recursive: true);
        await file.writeAsBytes(r.bodyBytes);
        await _writeMeta(meta, headers, headers['etag']);
        return await codec(r.bodyBytes);
      }
      throw HttpException('HTTP ${r.statusCode}');
    } catch (e) {
      // Немає зв'язку чи сервер відмовив — показуємо збережене, навіть прострочене.
      if (await file.exists()) return await codec(await file.readAsBytes());
      rethrow;
    }
  }

  Future<void> _writeMeta(File meta, Map<String, String> headers, String? etag) => meta.writeAsString(jsonEncode({
        'fresh': DateTime.now().add(freshFor(headers)).toIso8601String(),
        'etag': ?etag,
      }));

  @override
  bool operator ==(Object other) => other is _OsmTile && other.z == z && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(z, x, y);
}
