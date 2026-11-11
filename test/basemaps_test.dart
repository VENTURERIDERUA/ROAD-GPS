import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:road_gps/basemaps.dart';
import 'package:road_gps/crs.dart';
import 'package:road_gps/geometry.dart';
import 'package:road_gps/osm_cache.dart';

void main() {
  test('розмір знімка із заголовка: PNG і JPEG; інше — null', () {
    // JPEG: SOI, APP0 (довжина 16), SOF0: довжина 17, точність 8, висота 2, ширина 3.
    final jpg = Uint8List.fromList([
      0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, ...List.filled(14, 0), //
      0xFF, 0xC0, 0x00, 0x11, 0x08, 0x00, 0x02, 0x00, 0x03, ...List.filled(12, 0),
    ]);
    expect(imageSize(jpg), (3, 2));
    expect(imageSize(Uint8List.fromList([1, 2, 3, 4, 5])), isNull);
  });

  test('кеш OSM: свіжість за заголовками, без них — 7 днів', () {
    expect(freshFor({'cache-control': 'max-age=86400'}), const Duration(days: 1));
    expect(freshFor({'cache-control': 'no-store'}), Duration.zero);
    expect(freshFor({}), const Duration(days: 7));
    final now = DateTime.utc(2026, 10, 26, 12);
    expect(freshFor({'expires': HttpDate.format(now.add(const Duration(hours: 5)))}, now: now),
        const Duration(hours: 5));
  });

  test('MBTiles: рядок TMS, межі з metadata, межі плитки', () {
    expect(tmsRow(0, 0), 0);
    expect(tmsRow(3, 0), 7);
    expect(tmsRow(3, 7), 0);
    expect(parseBounds('26.1,44.4,26.2,44.5'), (44.4, 26.1, 44.5, 26.2));
    expect(parseBounds('1,2,3'), isNull);
    final b = tileBounds(0, 0, 0);
    expect(b.$1, closeTo(-85.0511, 1e-4));
    expect(b.$4, closeTo(180, 1e-9));
  });

  test('файл прив\u2019язки: кути знімка — по краях пікселів', () {
    final w = parseWorldFile('0.5\n0\n0\n-0.5\n100.25\n199.75\n');
    final c = imageCorners(w, 4, 2);
    expect(c[0].dist(const Vec(100, 200)), lessThan(1e-9)); // лівий верхній
    expect(c[1].dist(const Vec(100, 199)), lessThan(1e-9)); // лівий нижній
    expect(c[2].dist(const Vec(102, 199)), lessThan(1e-9)); // правий нижній
    expect(() => parseWorldFile('1\n2\n'), throwsA(isA<BasemapException>()));
  });

  test('знімок: завеликий і поза країною — зрозумілі помилки з порадами', () {
    final w = parseWorldFile('0.25\n0\n0\n-0.25\n587672.6\n328795.1\n');
    expect(() => describeImage('a', 'a', 'png', w, 10000, 10000, stereo70),
        throwsA(isA<BasemapException>().having((e) => e.problem.fixes.first, 'порада', contains('MBTiles'))));
    final far = parseWorldFile('1\n0\n0\n-1\n100\n100\n');
    expect(() => describeImage('a', 'a', 'png', far, 10, 10, stereo70), throwsA(isA<BasemapException>()));
  });
}
