import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_gps/osm_offline.dart';
import 'package:road_gps/pmtiles.dart';

Uint8List gz(String s) => Uint8List.fromList(const GZipEncoder().encodeBytes(utf8.encode(s)));

const like = PmHeader(
  rootOffset: 0, rootLength: 0, metaOffset: 0, metaLength: 0, leafOffset: 0, leafLength: 0, dataOffset: 0, //
  dataLength: 0, internalCompression: 2, tileCompression: 2, tileType: 1, minZoom: 0, maxZoom: 15,
  minLon: 0, minLat: 0, maxLon: 0, maxLat: 0,
);

void main() {
  test('номер плитки PMTiles (крива Гільберта) — як у специфікації', () {
    expect(zxyToTileId(0, 0, 0), 0);
    expect(zxyToTileId(1, 0, 0), 1);
    expect(zxyToTileId(1, 0, 1), 2);
    expect(zxyToTileId(1, 1, 1), 3);
    expect(zxyToTileId(1, 1, 0), 4);
    expect(zxyToTileId(2, 0, 0), 5);
    // Усі номери наближення 3 — різні й ідуть підряд після 0..20.
    final ids = {for (var x = 0; x < 8; x++) for (var y = 0; y < 8; y++) zxyToTileId(3, x, y)};
    expect(ids.length, 64);
    expect(ids.reduce((a, b) => a < b ? a : b), 21);
  });

  test('каталог: запис і читання назад, «одразу за попереднім»', () {
    const e = [PmEntry(5, 0, 10, 1), PmEntry(6, 10, 20, 1), PmEntry(9, 100, 7, 3)];
    final back = parseDirectory(serializeDirectory(e));
    expect([for (final x in back) (x.tileId, x.offset, x.length, x.runLength)],
        [(5, 0, 10, 1), (6, 10, 20, 1), (9, 100, 7, 3)]);
  });

  test('архів ділянки: записали — прочитали ті самі плитки; чужої немає', () async {
    final tiles = {zxyToTileId(0, 0, 0): gz('z0'), zxyToTileId(15, 18760, 11800): gz('z15')};
    final file = writePmTiles(tiles, like, minLon: 26.1, minLat: 44.4, maxLon: 26.2, maxLat: 44.5, meta: '{}');
    final r = await PmTilesReader.open(MemoryRangeSource(file));
    expect(r.header.isVector, isTrue);
    expect(r.header.minZoom, 0);
    expect(r.header.maxZoom, 15);
    expect(r.header.minLon, closeTo(26.1, 1e-7));
    expect(utf8.decode(gunzipIfNeeded((await r.tile(15, 18760, 11800))!, 2)), 'z15');
    expect(await r.tile(15, 18761, 11800), isNull);
    expect(() => parseHeader(Uint8List(200)), throwsA(isA<PmTilesException>()));
  });

  test('плитки для ділянки й запас навколо осі', () {
    final t = tilesForBounds(44.447, 26.100, 44.454, 26.107, 0, 15);
    expect(t.where((x) => x.$1 == 0).length, 1);
    expect(t.where((x) => x.$1 == 15).length, inInclusiveRange(1, 4));
    final b = bufferedBounds(const [(44.45, 26.10)], 1000);
    expect(b.$3 - b.$1, closeTo(2000 / 111320, 1e-9));
  });
}
