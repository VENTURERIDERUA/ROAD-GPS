// OSM без інтернету через Protomaps: щоденна збірка карти з даних OpenStreetMap у форматі PMTiles.
// Програма вирізає з неї лише ділянку об'єкта (як `pmtiles extract`) і показує векторно, без мережі.
// Ліцензія даних — ODbL: на карті підпис «© OpenStreetMap, Protomaps».
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:vector_map_tiles/vector_map_tiles.dart';

import 'i18n.dart';
import 'osm_cache.dart';
import 'pmtiles.dart';

const protomapsBuilds = 'https://build-metadata.protomaps.dev/builds.json';
const protomapsBase = 'https://build.protomaps.com/';

class HttpRangeSource implements RangeSource {
  final String url;
  final http.Client client;
  HttpRangeSource(this.url, this.client);

  @override
  Future<Uint8List> read(int offset, int length) async {
    final r = await client.get(Uri.parse(url), headers: {
      'Range': 'bytes=$offset-${offset + length - 1}',
      'User-Agent': osmUserAgent,
    }).timeout(const Duration(seconds: 60));
    if (r.statusCode != 206 && r.statusCode != 200) throw PmTilesException(t('сайт відповів {code}', {'code': r.statusCode}));
    return r.bodyBytes;
  }
}

class FileRangeSource implements RangeSource {
  final RandomAccessFile f;
  FileRangeSource(this.f);

  @override
  Future<Uint8List> read(int offset, int length) async {
    final len = await f.length();
    if (offset >= len) return Uint8List(0);
    await f.setPosition(offset);
    return f.read(math.min(length, len - offset));
  }
}

class MemoryRangeSource implements RangeSource {
  final Uint8List b;
  MemoryRangeSource(this.b);

  @override
  Future<Uint8List> read(int offset, int length) async =>
      offset >= b.length ? Uint8List(0) : Uint8List.sublistView(b, offset, math.min(b.length, offset + length));
}

/// Найсвіжіша збірка Protomaps: адреса файлу.
Future<String> latestProtomapsBuild(http.Client client) async {
  final r = await client.get(Uri.parse(protomapsBuilds), headers: {'User-Agent': osmUserAgent})
      .timeout(const Duration(seconds: 30));
  if (r.statusCode != 200) throw PmTilesException(t('список збірок недоступний ({code})', {'code': r.statusCode}));
  final list = jsonDecode(r.body) as List;
  final keys = [for (final e in list) (e as Map)['key'] as String]..sort();
  return '$protomapsBase${keys.last}';
}

/// Плитки XYZ, що покривають прямокутник, для наближень [minZ]..[maxZ].
List<(int, int, int)> tilesForBounds(double s, double w, double n, double e, int minZ, int maxZ) {
  int tx(double lon, int z) => ((lon + 180) / 360 * (1 << z)).floor().clamp(0, (1 << z) - 1);
  int ty(double lat, int z) {
    final r = lat * math.pi / 180;
    return ((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * (1 << z)).floor().clamp(0, (1 << z) - 1);
  }

  return [
    for (var z = minZ; z <= maxZ; z++)
      for (var x = tx(w, z); x <= tx(e, z); x++)
        for (var y = ty(n, z); y <= ty(s, z); y++) (z, x, y)
  ];
}

/// Прямокутник навколо точок з запасом [bufferM] метрів: (південь, захід, північ, схід).
(double, double, double, double) bufferedBounds(List<(double lat, double lon)> pts, double bufferM) {
  var s = 90.0, w = 180.0, n = -90.0, e = -180.0;
  for (final (lat, lon) in pts) {
    s = math.min(s, lat);
    n = math.max(n, lat);
    w = math.min(w, lon);
    e = math.max(e, lon);
  }
  final dLat = bufferM / 111320;
  final dLon = bufferM / (111320 * math.cos((s + n) / 2 * math.pi / 180));
  return (s - dLat, w - dLon, n + dLat, e + dLon);
}

/// Вирізає ділянку з архіву [src] — як `pmtiles extract --bbox`. Сусідні плитки читаються одним запитом.
Future<Uint8List> extractArea(RangeSource src, (double, double, double, double) bounds,
    {int maxZoom = 15, void Function(int done, int total)? onProgress, bool Function()? cancelled}) async {
  final reader = await PmTilesReader.open(src);
  final h = reader.header;
  final (s, w, n, e) = bounds;
  final want = tilesForBounds(s, w, n, e, h.minZoom, math.min(maxZoom, h.maxZoom));
  final found = <(int id, int off, int len)>[];
  for (var i = 0; i < want.length; i++) {
    if (cancelled?.call() == true) throw const PmTilesException('скасовано');
    final (z, x, y) = want[i];
    final at = await reader.locate(z, x, y);
    if (at != null) found.add((zxyToTileId(z, x, y), at.$1, at.$2));
    onProgress?.call(i ~/ 2, want.length);
  }
  found.sort((a, b) => a.$2.compareTo(b.$2));
  // Групи: проміжок до 64 КБ і група до 4 МБ — менше запитів до сайту.
  final groups = <List<(int, int, int)>>[];
  for (final t in found) {
    final g = groups.isEmpty ? null : groups.last;
    if (g != null && t.$2 - (g.last.$2 + g.last.$3) <= 65536 && t.$2 + t.$3 - g.first.$2 <= 4 << 20) {
      g.add(t);
    } else {
      groups.add([t]);
    }
  }
  final tiles = <int, Uint8List>{};
  var done = 0;
  for (final g in groups) {
    if (cancelled?.call() == true) throw const PmTilesException('скасовано');
    final start = g.first.$2;
    final bytes = await src.read(start, g.last.$2 + g.last.$3 - start);
    for (final (id, off, len) in g) {
      tiles[id] = Uint8List.fromList(Uint8List.sublistView(bytes, off - start, off - start + len));
    }
    done += g.length;
    onProgress?.call(want.length ~/ 2 + done * want.length ~/ (2 * math.max(1, found.length)), want.length);
  }
  if (tiles.isEmpty) throw const PmTilesException('для цієї ділянки в архіві немає плиток');
  return writePmTiles(tiles, h,
      minLon: w,
      minLat: s,
      maxLon: e,
      maxLat: n,
      meta: jsonEncode({'attribution': '© OpenStreetMap contributors, Protomaps', 'source': 'Protomaps basemap'}));
}

/// Векторні плитки з PMTiles для vector_map_tiles (джерело в стилі — «protomaps»).
class PmVectorProvider extends VectorTileProvider {
  final PmTilesReader reader;
  PmVectorProvider(this.reader);

  @override
  Future<Uint8List> provide(TileIdentity tile) async {
    final b = await reader.tile(tile.z, tile.x, tile.y);
    // Немає плитки (поза ділянкою) — порожня: тло без об'єктів, а не помилка.
    return b == null ? Uint8List(0) : gunzipIfNeeded(b, reader.header.tileCompression);
  }

  @override
  int get maximumZoom => reader.header.maxZoom;

  @override
  int get minimumZoom => reader.header.minZoom;

  @override
  TileOffset get tileOffset => TileOffset.DEFAULT;
}

/// Спокійний світлий стиль для схеми Protomaps v4 — щоб червона вісь і лінії проєкту були помітні.
Map<String, dynamic> protomapsStyle() {
  const src = 'protomaps';
  Map<String, dynamic> fill(String id, String layer, String color, [List? filter, double opacity = 1]) => {
        'id': id,
        'type': 'fill',
        'source': src,
        'source-layer': layer,
        'filter': ?filter,
        'paint': {'fill-color': color, 'fill-opacity': opacity},
      };
  Map<String, dynamic> line(String id, String layer, String color, List stops, [List? filter, List? dash, int minzoom = 0]) => {
        'id': id,
        'type': 'line',
        'source': src,
        'source-layer': layer,
        'minzoom': minzoom,
        'filter': ?filter,
        'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {
          'line-color': color,
          'line-width': {'stops': stops},
          'line-dasharray': ?dash,
        },
      };
  Map<String, dynamic> label(String id, String layer, List stops, String color, [List? filter, bool alongLine = false, int minzoom = 0]) => {
        'id': id,
        'type': 'symbol',
        'source': src,
        'source-layer': layer,
        'minzoom': minzoom,
        'filter': ?filter,
        'layout': {
          'text-field': '{name}',
          'text-size': {'stops': stops},
          if (alongLine) 'symbol-placement': 'line',
        },
        'paint': {'text-color': color, 'text-halo-color': '#ffffff', 'text-halo-width': 1.5},
      };
  return {
    'version': 8,
    'name': 'ROAD-GPS Protomaps light',
    'sources': {
      src: {'type': 'vector'}
    },
    'layers': [
      {'id': 'background', 'type': 'background', 'paint': {'background-color': '#e8e6e1'}},
      fill('earth', 'earth', '#f2f0eb'),
      fill('farmland', 'landcover', '#eef0d5', ['in', 'kind', 'farmland', 'grassland']),
      fill('forest', 'landcover', '#d4e4c4', ['in', 'kind', 'forest', 'scrub']),
      fill('landuse-green', 'landuse', '#d8e8c8',
          ['in', 'kind', 'park', 'forest', 'wood', 'grass', 'garden', 'meadow', 'nature_reserve', 'cemetery']),
      fill('landuse-farm', 'landuse', '#eef0d5', ['in', 'kind', 'farmland', 'orchard', 'vineyard']),
      fill('landuse-built', 'landuse', '#e6e2da', ['in', 'kind', 'residential', 'industrial', 'commercial', 'retail', 'railway']),
      fill('water', 'water', '#aad3df', ['==', r'$type', 'Polygon']),
      line('waterway', 'water', '#aad3df', [[10, 0.5], [16, 3]], ['==', r'$type', 'LineString']),
      fill('buildings', 'buildings', '#d9d0c9', null, 0.9),
      line('rail', 'roads', '#9a9a9a', [[10, 0.5], [16, 2]], ['==', 'kind', 'rail'], [3, 2]),
      line('rail-transit', 'transit', '#9a9a9a', [[10, 0.5], [16, 2]], ['==', 'kind', 'rail'], [3, 2]),
      line('path', 'roads', '#c8b8a8', [[14, 0.5], [18, 2]], ['==', 'kind', 'path'], [2, 1], 14),
      line('road-minor', 'roads', '#ffffff', [[12, 0.5], [16, 4], [19, 12]], ['in', 'kind', 'minor_road', 'other'], null, 12),
      line('road-major', 'roads', '#fde9a8', [[8, 0.8], [14, 4], [18, 14]], ['==', 'kind', 'major_road']),
      line('road-highway', 'roads', '#f6b26b', [[6, 1], [14, 5], [18, 16]], ['==', 'kind', 'highway']),
      line('boundary', 'boundaries', '#9e8fa6', [[4, 0.5], [12, 1.5]], null, [4, 2]),
      label('road-label', 'roads', [[14, 10], [18, 13]], '#555555', ['in', 'kind', 'major_road', 'minor_road', 'highway'], true, 14),
      label('water-label', 'water', [[12, 10], [16, 12]], '#4a7f9a', ['==', r'$type', 'Polygon'], false, 12),
      label('place-small', 'places', [[11, 10], [16, 13]], '#444444', ['in', 'kind', 'neighbourhood', 'macrohood'], false, 12),
      label('place-locality', 'places', [[8, 11], [14, 16]], '#222222', ['==', 'kind', 'locality']),
    ],
  };
}
