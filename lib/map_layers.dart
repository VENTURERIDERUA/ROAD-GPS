// Шари-підкладки для карти: OSM з кешем, MBTiles з пам'яті пристрою, знімок з файлом прив'язки.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:sqflite/sqflite.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' show ThemeReader;

import 'basemaps.dart';
import 'osm_cache.dart';
import 'osm_offline.dart';
import 'pmtiles.dart';

/// Що під віссю: нічого, OSM, або власна підкладка з [basemapStore] (за id).
const bgNone = 'none', bgOsm = 'osm';

Widget osmLayer(VoidCallback? onFailed) => TileLayer(
      urlTemplate: osmUrl,
      userAgentPackageName: 'io.github.ventureriderua.road_gps',
      tileProvider: osmTileProvider(),
      maxNativeZoom: 19,
      errorTileCallback: (_, _, _) => onFailed?.call(),
    );

/// Шар для власної підкладки; для MBTiles база відкривається тут і закривається з [dispose].
class BasemapLayer {
  final Basemap map;
  final Database? _db;
  final PmTilesReader? _pm;
  final RandomAccessFile? _file;
  BasemapLayer._(this.map, this._db, [this._pm, this._file]);

  static Future<BasemapLayer> open(Basemap m) async {
    if (m.kind == BasemapKind.mbtiles && !kIsWeb) {
      final db = await openDatabase(await basemapStore.pathOf(m), readOnly: true, singleInstance: false);
      return BasemapLayer._(m, db);
    }
    if (m.kind == BasemapKind.pmtiles) {
      final mem = basemapStore.memoryBytes(m.id);
      if (mem != null) return BasemapLayer._(m, null, await PmTilesReader.open(MemoryRangeSource(mem)));
      final f = await File(await basemapStore.pathOf(m)).open();
      return BasemapLayer._(m, null, await PmTilesReader.open(FileRangeSource(f)), f);
    }
    return BasemapLayer._(m, null);
  }

  Future<void> dispose() async {
    await _db?.close();
    await _file?.close();
  }

  Widget build() {
    final m = map;
    final pm = _pm;
    if (pm != null) {
      final layer = m.format == 'mvt'
          ? VectorTileLayer(
              tileProviders: TileProviders({'protomaps': PmVectorProvider(pm)}),
              theme: _theme,
              maximumZoom: 22,
            )
          : TileLayer(
              tileProvider: _PmRasterProvider(pm),
              minNativeZoom: m.minZoom,
              maxNativeZoom: m.maxZoom,
            );
      return Stack(children: [
        layer,
        const Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: EdgeInsets.all(4),
            child: Text('© OpenStreetMap, Protomaps', style: TextStyle(fontSize: 10, color: Color(0x8A000000))),
          ),
        ),
      ]);
    }
    if (m.kind == BasemapKind.mbtiles) {
      return TileLayer(
        tileProvider: _MbTilesProvider(_db),
        minNativeZoom: m.minZoom,
        maxNativeZoom: m.maxZoom,
        // Поза межами знімка плиток немає — не питати базу даремно.
        tileBounds: LatLngBounds.unsafe(north: m.north, south: m.south, east: m.east, west: m.west),
      );
    }
    final bytes = basemapStore.memoryBytes(m.id);
    return FutureBuilder<String>(
      future: bytes != null ? Future.value('') : basemapStore.pathOf(m),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final ImageProvider img = bytes != null ? MemoryImage(bytes) : FileImage(File(snap.data!));
        return OverlayImageLayer(overlayImages: [
          RotatedOverlayImage(
            topLeftCorner: m.corners[0],
            bottomLeftCorner: m.corners[1],
            bottomRightCorner: m.corners[2],
            imageProvider: img,
          ),
        ]);
      },
    );
  }
}

final _theme = ThemeReader().read(protomapsStyle());

class _PmRasterProvider extends TileProvider {
  final PmTilesReader reader;
  _PmRasterProvider(this.reader);

  @override
  ImageProvider getImage(TileCoordinates c, TileLayer options) => _PmTile(reader, c.z, c.x, c.y);
}

@immutable
class _PmTile extends ImageProvider<_PmTile> {
  final PmTilesReader reader;
  final int z, x, y;
  const _PmTile(this.reader, this.z, this.x, this.y);

  @override
  Future<_PmTile> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_PmTile key, ImageDecoderCallback decode) => OneFrameImageStreamCompleter(() async {
        final raw = await reader.tile(z, x, y);
        final bytes = raw == null ? TileProvider.transparentImage : gunzipIfNeeded(raw, reader.header.tileCompression);
        final codec = await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
        return ImageInfo(image: (await codec.getNextFrame()).image);
      }());

  @override
  bool operator ==(Object other) => other is _PmTile && other.reader == reader && other.z == z && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(reader, z, x, y);
}

class _MbTilesProvider extends TileProvider {
  final Database? db;
  _MbTilesProvider(this.db);

  @override
  ImageProvider getImage(TileCoordinates c, TileLayer options) => _MbTile(db, c.z, c.x, c.y);
}

@immutable
class _MbTile extends ImageProvider<_MbTile> {
  final Database? db;
  final int z, x, y;
  const _MbTile(this.db, this.z, this.x, this.y);

  @override
  Future<_MbTile> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_MbTile key, ImageDecoderCallback decode) => OneFrameImageStreamCompleter(() async {
        final bytes = (db == null ? null : await readMbTile(db!, z, x, y)) ?? TileProvider.transparentImage;
        final codec = await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
        return ImageInfo(image: (await codec.getNextFrame()).image);
      }());

  @override
  bool operator ==(Object other) => other is _MbTile && other.db == db && other.z == z && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(db, z, x, y);
}
