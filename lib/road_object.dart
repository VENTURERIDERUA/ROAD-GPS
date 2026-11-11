// Об'єкт (дорога, ділянка): вісь, система координат, ПК початку — і їх збереження в телефоні.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'chainage.dart';
import 'crs.dart';
import 'geometry.dart';
import 'lines.dart';
import 'notes.dart';
import 'pdf_sections.dart';
import 'profile.dart';

class RoadObject {
  final String id;
  String name;
  final String sourceFile;
  final String axisLayer;
  final String crsId;
  double startStation;
  ChainageStyle style;

  /// Вісь у координатах системи [crsId]: X — схід, Y — північ, напрям — за зростанням пікетажу.
  final List<Segment> axis;

  /// Кромки, бровки, межі відводу… — у тих самих координатах, що й вісь.
  List<RoadLine> lines;

  /// Поздовжній профіль (відмітка осі) і ширини проїзної частини — з відомості чи LandXML.
  Profile? profile;
  Widths? widths;

  /// Поперечники з відмітками (LandXML) — відмітка будь-де на поперечнику; null — немає.
  CrossSections? crossSections;

  /// ЦММ проєкту: звідки й скільки трикутників (null — немає). Самі трикутники — окремим файлом
  /// ([ObjectStore.loadSurface]).
  String? surfaceSource;
  int surfaceTriangles;

  /// ЦММ — земля (зйомка), а не проєкт: тоді вона дає «землю тут», а не проєктну відмітку.
  bool surfaceGround;

  /// PDF поперечників: підписи ПК і сторінки. Сам PDF — окремим файлом поруч ([ObjectStore.loadPdf]).
  PdfSections? sections;

  /// Підкладка: «none», «osm» або id власної ([basemapStore]).
  String basemap;

  /// Нове будівництво чи ремонт — від цього готові фрази й тип нової позначки.
  WorkType work;
  final DateTime created;

  RoadObject({
    required this.id,
    required this.name,
    required this.sourceFile,
    required this.axisLayer,
    required this.crsId,
    required this.startStation,
    required this.style,
    required this.axis,
    this.lines = const [],
    this.profile,
    this.widths,
    this.crossSections,
    this.surfaceSource,
    this.surfaceTriangles = 0,
    this.surfaceGround = false,
    this.sections,
    this.basemap = 'osm',
    this.work = WorkType.construction,
    required this.created,
  });

  CoordSystem get crs => coordSystemById(crsId);
  RoadAxis get roadAxis => RoadAxis(axis, startStation: startStation);

  Map<String, dynamic> toJson() => {
        'format': 1,
        'id': id,
        'name': name,
        'sourceFile': sourceFile,
        'axisLayer': axisLayer,
        'crs': crsId,
        'startStation': startStation,
        'style': style.name,
        'created': created.toIso8601String(),
        'axis': [for (final s in axis) s.toJson()],
        'lines': [for (final l in lines) l.toJson()],
        if (profile != null) 'profile': profile!.toJson(),
        if (widths != null) 'widths': widths!.toJson(),
        if (crossSections != null) 'crossSections': crossSections!.toJson(),
        if (surfaceSource != null)
          'surface': {'source': surfaceSource, 'triangles': surfaceTriangles, if (surfaceGround) 'ground': true},
        if (sections != null) 'sections': sections!.toJson(),
        'basemap': basemap,
        'work': work.name,
      };

  factory RoadObject.fromJson(Map<String, dynamic> j) => RoadObject(
        id: j['id'] as String,
        name: j['name'] as String,
        sourceFile: j['sourceFile'] as String? ?? '',
        axisLayer: j['axisLayer'] as String? ?? '',
        crsId: j['crs'] as String,
        startStation: (j['startStation'] as num).toDouble(),
        style: ChainageStyle.values.byName(j['style'] as String),
        created: DateTime.parse(j['created'] as String),
        axis: [for (final s in j['axis'] as List) Segment.fromJson(s as Map<String, dynamic>)],
        lines: [
          for (final l in j['lines'] as List? ?? const []) RoadLine.fromJson(l as Map<String, dynamic>)
        ],
        profile: j['profile'] == null ? null : Profile.fromJson(j['profile'] as Map<String, dynamic>),
        widths: j['widths'] == null ? null : Widths.fromJson(j['widths'] as Map<String, dynamic>),
        crossSections:
            j['crossSections'] == null ? null : CrossSections.fromJson(j['crossSections'] as Map<String, dynamic>),
        surfaceSource: (j['surface'] as Map<String, dynamic>?)?['source'] as String?,
        surfaceTriangles: ((j['surface'] as Map<String, dynamic>?)?['triangles'] as num?)?.toInt() ?? 0,
        surfaceGround: (j['surface'] as Map<String, dynamic>?)?['ground'] == true,
        sections: j['sections'] == null ? null : PdfSections.fromJson(j['sections'] as Map<String, dynamic>),
        basemap: j['basemap'] as String? ?? 'osm',
        work: WorkType.values.where((w) => w.name == j['work']).firstOrNull ?? WorkType.construction,
      );
}

/// Об'єкти лежать у пам'яті програми на телефоні, кожен — окремим JSON-файлом.
/// У браузері (перевірка на комп'ютері) — лише до закриття сторінки.
class ObjectStore {
  /// Тека для тестів; у програмі — тека даних програми на пристрої.
  final Directory? dir;
  ObjectStore({this.dir});

  final Map<String, RoadObject> _web = {};

  /// Скільки збережених файлів не прочиталось під час останнього [loadAll].
  int broken = 0;
  bool get _memory => kIsWeb && dir == null;

  Future<Directory> _dir() async {
    final d = dir ?? Directory('${(await getApplicationDocumentsDirectory()).path}/objects');
    await d.create(recursive: true);
    return d;
  }

  Future<List<RoadObject>> loadAll() async {
    if (_memory) return _web.values.toList();
    final out = <RoadObject>[];
    broken = 0;
    await for (final f in (await _dir()).list()) {
      if (f is! File || !f.path.endsWith('.json')) continue;
      try {
        out.add(RoadObject.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>));
      } catch (_) {
        // Пошкоджений файл не має блокувати решту об'єктів — лише рахуємо, щоб попередити.
        broken++;
      }
    }
    out.sort((a, b) => b.created.compareTo(a.created));
    return out;
  }

  Future<void> save(RoadObject o) async {
    if (_memory) {
      _web[o.id] = o;
      return;
    }
    final dir = await _dir();
    final tmp = File('${dir.path}/${o.id}.tmp');
    await tmp.writeAsString(jsonEncode(o.toJson()));
    await tmp.rename('${dir.path}/${o.id}.json');
  }

  Future<void> delete(String id) async {
    if (_memory) {
      _web.remove(id);
      return;
    }
    final f = File('${(await _dir()).path}/$id.json');
    if (await f.exists()) await f.delete();
    await savePdf(id, null);
    await saveSurface(id, null);
    await saveDrawing(id, null);
  }

  final Map<String, Uint8List> _webDrawing = {};

  /// Креслення, з якого створено об'єкт (DXF як є; null — прибрати): з нього ж — ЦММ і поперечники без
  /// повторного пошуку файлу.
  Future<void> saveDrawing(String id, Uint8List? bytes) async {
    if (_memory) {
      bytes == null ? _webDrawing.remove(id) : _webDrawing[id] = bytes;
      return;
    }
    final f = File('${(await _dir()).path}/$id.drawing');
    if (bytes == null) {
      if (await f.exists()) await f.delete();
      return;
    }
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(bytes);
    await tmp.rename(f.path);
  }

  Future<bool> hasDrawing(String id) async =>
      _memory ? _webDrawing.containsKey(id) : File('${(await _dir()).path}/$id.drawing').exists();

  Future<Uint8List?> loadDrawing(String id) async {
    if (_memory) return _webDrawing[id];
    final f = File('${(await _dir()).path}/$id.drawing');
    return await f.exists() ? f.readAsBytes() : null;
  }

  final Map<String, Uint8List> _webSurface = {};

  /// ЦММ об'єкта ([Surface.encode]; null — прибрати).
  Future<void> saveSurface(String id, Uint8List? bytes) async {
    if (_memory) {
      bytes == null ? _webSurface.remove(id) : _webSurface[id] = bytes;
      return;
    }
    final f = File('${(await _dir()).path}/$id.tin');
    if (bytes == null) {
      if (await f.exists()) await f.delete();
      return;
    }
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(bytes);
    await tmp.rename(f.path);
  }

  Future<Uint8List?> loadSurface(String id) async {
    if (_memory) return _webSurface[id];
    final f = File('${(await _dir()).path}/$id.tin');
    return await f.exists() ? f.readAsBytes() : null;
  }

  final Map<String, Uint8List> _webPdf = {};

  /// PDF поперечників об'єкта (null — прибрати).
  Future<void> savePdf(String id, Uint8List? bytes) async {
    if (_memory) {
      bytes == null ? _webPdf.remove(id) : _webPdf[id] = bytes;
      return;
    }
    final f = File('${(await _dir()).path}/$id.pdf');
    if (bytes == null) {
      if (await f.exists()) await f.delete();
      return;
    }
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(bytes);
    await tmp.rename(f.path);
  }

  Future<Uint8List?> loadPdf(String id) async {
    if (_memory) return _webPdf[id];
    final f = File('${(await _dir()).path}/$id.pdf');
    return await f.exists() ? f.readAsBytes() : null;
  }
}

final objectStore = ObjectStore();
