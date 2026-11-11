// PMTiles версії 3 (github.com/protomaps/PMTiles/blob/main/spec/v3/spec.md): читання з файлу чи по мережі
// шматками (HTTP Range) і запис невеликого архіву ділянки. Каталоги й плитки стиснені gzip.
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'i18n.dart';

class PmHeader {
  final int rootOffset, rootLength, metaOffset, metaLength, leafOffset, leafLength, dataOffset, dataLength;
  final int internalCompression, tileCompression, tileType, minZoom, maxZoom;
  final double minLon, minLat, maxLon, maxLat;
  const PmHeader({
    required this.rootOffset,
    required this.rootLength,
    required this.metaOffset,
    required this.metaLength,
    required this.leafOffset,
    required this.leafLength,
    required this.dataOffset,
    required this.dataLength,
    required this.internalCompression,
    required this.tileCompression,
    required this.tileType,
    required this.minZoom,
    required this.maxZoom,
    required this.minLon,
    required this.minLat,
    required this.maxLon,
    required this.maxLat,
  });

  /// Тип плиток: 1 — векторні (MVT), 2 — PNG, 3 — JPEG, 4 — WebP.
  bool get isVector => tileType == 1;
}

class PmTilesException implements Exception {
  final String message;
  const PmTilesException(this.message);
  @override
  String toString() => message;
}

PmHeader parseHeader(Uint8List b) {
  if (b.length < 127 || ascii.decode(b.sublist(0, 7), allowInvalid: true) != 'PMTiles') {
    throw const PmTilesException('не PMTiles');
  }
  if (b[7] != 3) throw PmTilesException(t('версія PMTiles {n}, програма читає 3', {'n': b[7]}));
  final d = ByteData.sublistView(b);
  // Дві 32-бітні половини: у браузерній версії Dart 64-бітних читань немає.
  int u64(int o) => d.getUint32(o, Endian.little) + d.getUint32(o + 4, Endian.little) * 0x100000000;
  double e7(int o) => d.getInt32(o, Endian.little) / 1e7;
  return PmHeader(
    rootOffset: u64(8),
    rootLength: u64(16),
    metaOffset: u64(24),
    metaLength: u64(32),
    leafOffset: u64(40),
    leafLength: u64(48),
    dataOffset: u64(56),
    dataLength: u64(64),
    internalCompression: b[97],
    tileCompression: b[98],
    tileType: b[99],
    minZoom: b[100],
    maxZoom: b[101],
    minLon: e7(102),
    minLat: e7(106),
    maxLon: e7(110),
    maxLat: e7(114),
  );
}

/// Номер плитки в PMTiles: усі плитки менших наближень + номер на кривій Гільберта.
int zxyToTileId(int z, int x, int y) {
  var acc = 0;
  for (var t = 0; t < z; t++) {
    acc += (1 << t) * (1 << t);
  }
  final n = 1 << z;
  var rx = 0, ry = 0, d = 0;
  var xx = x, yy = y;
  for (var s = n ~/ 2; s > 0; s ~/= 2) {
    rx = (xx & s) > 0 ? 1 : 0;
    ry = (yy & s) > 0 ? 1 : 0;
    d += s * s * ((3 * rx) ^ ry);
    // Поворот чверті.
    if (ry == 0) {
      if (rx == 1) {
        xx = s - 1 - xx;
        yy = s - 1 - yy;
      }
      final t = xx;
      xx = yy;
      yy = t;
    }
  }
  return acc + d;
}

class PmEntry {
  final int tileId, offset, length, runLength;
  const PmEntry(this.tileId, this.offset, this.length, this.runLength);
}

class _Varint {
  final Uint8List b;
  int pos = 0;
  _Varint(this.b);
  int next() {
    var v = 0, shift = 0;
    while (true) {
      if (pos >= b.length) throw const PmTilesException('каталог обірвано');
      final c = b[pos++];
      v |= (c & 0x7f) << shift;
      if (c < 0x80) return v;
      shift += 7;
    }
  }
}

List<PmEntry> parseDirectory(Uint8List raw) {
  final r = _Varint(raw);
  final n = r.next();
  final ids = List<int>.filled(n, 0), runs = List<int>.filled(n, 0), lens = List<int>.filled(n, 0);
  final offs = List<int>.filled(n, 0);
  var last = 0;
  for (var i = 0; i < n; i++) {
    last += r.next();
    ids[i] = last;
  }
  for (var i = 0; i < n; i++) {
    runs[i] = r.next();
  }
  for (var i = 0; i < n; i++) {
    lens[i] = r.next();
  }
  for (var i = 0; i < n; i++) {
    final v = r.next();
    // 0 — «одразу за попереднім».
    offs[i] = v == 0 && i > 0 ? offs[i - 1] + lens[i - 1] : v - 1;
  }
  return [for (var i = 0; i < n; i++) PmEntry(ids[i], offs[i], lens[i], runs[i])];
}

Uint8List _varints(Iterable<int> vs) {
  final out = BytesBuilder();
  for (var v in vs) {
    while (v >= 0x80) {
      out.addByte((v & 0x7f) | 0x80);
      v >>= 7;
    }
    out.addByte(v);
  }
  return out.toBytes();
}

Uint8List serializeDirectory(List<PmEntry> entries) => _serialize(entries);

Uint8List _serialize(List<PmEntry> entries) {
  final b = BytesBuilder();
  b.add(_varints([entries.length]));
  var last = 0;
  final deltas = <int>[];
  for (final e in entries) {
    deltas.add(e.tileId - last);
    last = e.tileId;
  }
  b.add(_varints(deltas));
  b.add(_varints([for (final e in entries) e.runLength]));
  b.add(_varints([for (final e in entries) e.length]));
  final offs = <int>[];
  for (var i = 0; i < entries.length; i++) {
    final contiguous = i > 0 && entries[i].offset == entries[i - 1].offset + entries[i - 1].length;
    offs.add(contiguous ? 0 : entries[i].offset + 1);
  }
  b.add(_varints(offs));
  return b.toBytes();
}

Uint8List gunzipIfNeeded(Uint8List b, int compression) =>
    compression == 2 ? Uint8List.fromList(const GZipDecoder().decodeBytes(b)) : b;

/// Звідки читати байти: файл на пристрої чи сайт (HTTP Range).
abstract class RangeSource {
  Future<Uint8List> read(int offset, int length);
}

class PmTilesReader {
  final RangeSource src;
  final PmHeader header;
  final Map<int, List<PmEntry>> _dirs = {};
  PmTilesReader._(this.src, this.header);

  static Future<PmTilesReader> open(RangeSource src) async {
    // Перші 16 КБ: заголовок і, зазвичай, кореневий каталог — одним запитом.
    final first = await src.read(0, 16384);
    final h = parseHeader(first);
    final r = PmTilesReader._(src, h);
    if (h.rootOffset + h.rootLength <= first.length) {
      r._dirs[-1] = parseDirectory(gunzipIfNeeded(first.sublist(h.rootOffset, h.rootOffset + h.rootLength), h.internalCompression));
    }
    return r;
  }

  Future<List<PmEntry>> _dir(int key, int offset, int length) async =>
      _dirs[key] ??= parseDirectory(gunzipIfNeeded(await src.read(offset, length), header.internalCompression));

  /// Де лежить плитка: (зсув від початку файлу, довжина) або null, якщо її немає.
  Future<(int, int)?> locate(int z, int x, int y) async {
    final id = zxyToTileId(z, x, y);
    var dir = await _dir(-1, header.rootOffset, header.rootLength);
    for (var depth = 0; depth < 4; depth++) {
      final e = _find(dir, id);
      if (e == null) return null;
      if (e.runLength > 0) return (header.dataOffset + e.offset, e.length);
      dir = await _dir(header.leafOffset + e.offset, header.leafOffset + e.offset, e.length);
    }
    return null;
  }

  /// Стиснена плитка (як лежить в архіві) або null.
  Future<Uint8List?> tile(int z, int x, int y) async {
    final at = await locate(z, x, y);
    return at == null ? null : src.read(at.$1, at.$2);
  }

  static PmEntry? _find(List<PmEntry> dir, int id) {
    var lo = 0, hi = dir.length - 1;
    while (lo <= hi) {
      final m = (lo + hi) >> 1;
      if (dir[m].tileId < id) {
        lo = m + 1;
      } else if (dir[m].tileId > id) {
        hi = m - 1;
      } else {
        return dir[m];
      }
    }
    // Найбільший tileId < id: або каталог-лист (runLength 0), або серія однакових плиток.
    if (hi >= 0) {
      final e = dir[hi];
      if (e.runLength == 0) return e;
      if (id - e.tileId < e.runLength) return e;
    }
    return null;
  }
}

/// Невеликий архів ділянки: усі плитки — в одному кореневому каталозі. [tiles] — стиснені gzip, як в оригіналі.
Uint8List writePmTiles(Map<int, Uint8List> tiles, PmHeader like,
    {required double minLon, required double minLat, required double maxLon, required double maxLat, required String meta}) {
  final ids = tiles.keys.toList()..sort();
  final data = BytesBuilder();
  final entries = <PmEntry>[];
  for (final id in ids) {
    entries.add(PmEntry(id, data.length, tiles[id]!.length, 1));
    data.add(tiles[id]!);
  }
  final root = Uint8List.fromList(const GZipEncoder().encodeBytes(_serialize(entries)));
  final metaBytes = Uint8List.fromList(const GZipEncoder().encodeBytes(utf8.encode(meta)));
  final rootOff = 127, metaOff = rootOff + root.length, dataOff = metaOff + metaBytes.length;
  final h = ByteData(127);
  for (var i = 0; i < 7; i++) {
    h.setUint8(i, 'PMTiles'.codeUnitAt(i));
  }
  h.setUint8(7, 3);
  void u64(int o, int v) {
    h.setUint32(o, v % 0x100000000, Endian.little);
    h.setUint32(o + 4, v ~/ 0x100000000, Endian.little);
  }
  u64(8, rootOff);
  u64(16, root.length);
  u64(24, metaOff);
  u64(32, metaBytes.length);
  u64(40, dataOff); // каталогів-листів немає
  u64(48, 0);
  u64(56, dataOff);
  u64(64, data.length);
  u64(72, ids.length);
  u64(80, ids.length);
  u64(88, ids.length);
  h.setUint8(96, 1); // впорядковано
  h.setUint8(97, 2); // каталоги — gzip
  h.setUint8(98, like.tileCompression);
  h.setUint8(99, like.tileType);
  final zooms = [for (final id in ids) _zoomOf(id)];
  h.setUint8(100, zooms.reduce(math.min));
  h.setUint8(101, zooms.reduce(math.max));
  void e7(int o, double v) => h.setInt32(o, (v * 1e7).round(), Endian.little);
  e7(102, minLon);
  e7(106, minLat);
  e7(110, maxLon);
  e7(114, maxLat);
  h.setUint8(118, zooms.reduce(math.max));
  e7(119, (minLon + maxLon) / 2);
  e7(123, (minLat + maxLat) / 2);
  return (BytesBuilder()
        ..add(h.buffer.asUint8List())
        ..add(root)
        ..add(metaBytes)
        ..add(data.toBytes()))
      .toBytes();
}

int _zoomOf(int tileId) {
  var acc = 0;
  for (var z = 0;; z++) {
    final n = (1 << z) * (1 << z);
    if (tileId < acc + n) return z;
    acc += n;
  }
}
