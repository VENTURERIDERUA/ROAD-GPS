// «Дані об'єкта»: профіль і ширини (відомість CSV чи LandXML), поперечний ухил, PDF поперечників.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'basemaps.dart';
import 'chainage.dart';
import 'crs.dart';
import 'csv_import_screen.dart';
import 'dxf.dart';
import 'i18n.dart';
import 'help_screen.dart';
import 'keyboards.dart';
import 'landxml.dart';
import 'lines.dart';
import 'osm_offline.dart';
import 'pdf_label_screen.dart';
import 'pdf_reader.dart';
import 'pdf_sections.dart';
import 'pmtiles.dart';
import 'problem_card.dart';
import 'problems.dart';
import 'profile.dart';
import 'notes.dart' show WorkType;
import 'raster_import_screen.dart';
import 'road_object.dart';
import 'surface.dart';
import 'vidomist.dart';
import 'xs_drawing_screen.dart';
import 'xs_scan_screen.dart';

class ObjectDataScreen extends StatefulWidget {
  final RoadObject object;
  const ObjectDataScreen({super.key, required this.object});

  @override
  State<ObjectDataScreen> createState() => _ObjectDataScreenState();
}

class _ObjectDataScreenState extends State<ObjectDataScreen> {
  RoadObject get o => widget.object;
  bool _busy = false;
  List<Basemap> _maps = [];

  @override
  void initState() {
    super.initState();
    _reloadMaps();
  }

  Future<void> _reloadMaps() async {
    final m = await basemapStore.list();
    if (mounted) setState(() => _maps = m);
  }

  Future<void> _removeMap(Basemap m) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t('Видалити підкладку «{name}»?', {'name': m.name})),
        content: const T('Вона зникне з пристрою для всіх об’єктів. Ваш файл на комп’ютері не зміниться.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const T('Ні')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const T('Видалити')),
        ],
      ),
    );
    if (yes != true) return;
    await basemapStore.remove(m);
    if (o.basemap == m.id) {
      o.basemap = 'osm';
      await _save();
    }
    await _reloadMaps();
  }

  /// Підкладка не перетинається з віссю — питаємо, чи справді додати.
  Future<bool> _confirmOverlap(Basemap m) async {
    final pts = [for (final p in o.roadAxis.densify(50)) toWgs84(o.crs, p)];
    final lat = pts.map((p) => p.latitude), lon = pts.map((p) => p.longitude);
    if (m.overlaps(lat.reduce(math.min), lon.reduce(math.min), lat.reduce(math.max), lon.reduce(math.max))) return true;
    if (!mounted) return false;
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: const SingleChildScrollView(
          child: ProblemCard(Problem(Severity.warning, 'Підкладка не перетинається з віссю цього об’єкта',
              fixes: [
                'Можливо, це підкладка іншої ділянки — тоді все гаразд, вона знадобиться там.',
                'Якщо вона мала лягти сюди — перевірте систему координат знімка й файлу прив’язки.',
              ])),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const T('Скасувати')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const T('Додати все одно')),
        ],
      ),
    );
    return go == true;
  }

  /// Межі ділянки об'єкта з запасом — для вирізання карти.
  (double, double, double, double) _areaBounds() {
    final pts = [for (final p in o.roadAxis.densify(50)) toWgs84(o.crs, p)];
    return bufferedBounds([for (final p in pts) (p.latitude, p.longitude)], 1000);
  }

  Future<void> _addBasemapBytes(Basemap m, Uint8List bytes) async {
    if (kIsWeb) {
      basemapStore.keepInMemory(m.id, bytes);
    } else {
      await File(await basemapStore.pathOf(m)).writeAsBytes(bytes);
    }
    await basemapStore.add(m);
    o.basemap = m.id;
    await _save();
    await _reloadMaps();
  }

  /// Вирізає карту ділянки зі свіжої збірки Protomaps (дані OpenStreetMap) — як `pmtiles extract`.
  Future<void> _downloadOsm() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const T('Карта OSM для ділянки без інтернету'),
        content: const T('Програма візьме зі щоденної збірки Protomaps (дані OpenStreetMap) лише ділянку '
            'цього об’єкта з запасом 1 км, наближення до 15 (вулиці, будинки, назви). Потрібен інтернет '
            'зараз — далі карта працює без нього. Зазвичай це кілька мегабайт.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const T('Скасувати')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const T('Завантажити')),
        ],
      ),
    );
    if (go != true || !mounted) return;
    final progress = ValueNotifier<double>(0);
    var cancel = false;
    final client = http.Client();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const T('Завантажую карту ділянки…'),
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (_, v, _) => LinearProgressIndicator(value: v == 0 ? null : v),
        ),
        actions: [TextButton(onPressed: () => cancel = true, child: const T('Скасувати'))],
      ),
    );
    Problem? problem;
    try {
      final url = await latestProtomapsBuild(client);
      final b = _areaBounds();
      final bytes = await extractArea(HttpRangeSource(url, client), b,
          onProgress: (d, t) => progress.value = t == 0 ? 0 : d / t, cancelled: () => cancel);
      final id = 'p${DateTime.now().microsecondsSinceEpoch}';
      final date = url.split('/').last.replaceAll('.pmtiles', '');
      final m = describePmtiles(parseHeader(bytes), id, 'OSM ${o.name} ($date)');
      await _addBasemapBytes(m, bytes);
    } on PmTilesException catch (e) {
      if (e.message != 'скасовано') problem = _osmProblem('$e');
    } on BasemapException catch (e) {
      problem = e.problem;
    } catch (e) {
      problem = _osmProblem('$e');
    } finally {
      client.close();
      if (mounted) Navigator.of(context).pop();
    }
    if (problem != null && mounted) await showProblemDialog(context, problem);
  }

  Problem _osmProblem(String detail) => Problem(Severity.error, 'Карту ділянки не вдалося завантажити',
      detail: detail,
      fixes: const [
        'Перевірте інтернет (мобільні дані чи Wi-Fi) і спробуйте ще раз.',
        'Або виріжте ділянку на комп’ютері (кнопка «Команда для ПК») і додайте файл .pmtiles.',
      ]);

  Future<void> _addPmtiles() async {
    final f = await FilePicker.pickFile(dialogTitle: t('Файл PMTiles'));
    if (f == null || !mounted) return;
    if (!f.name.toLowerCase().endsWith('.pmtiles')) {
      await showProblemDialog(context, problemForFileName(f.name) ?? notPmtilesFile);
      return;
    }
    setState(() => _busy = true);
    try {
      final bytes = await f.readAsBytes();
      final m = describePmtiles(parseHeader(bytes), 'p${DateTime.now().microsecondsSinceEpoch}',
          f.name.replaceAll(RegExp(r'\.pmtiles$', caseSensitive: false), ''));
      if (!await _confirmOverlap(m)) return;
      await _addBasemapBytes(m, bytes);
    } on BasemapException catch (e) {
      if (mounted) await showProblemDialog(context, e.problem);
    } on PmTilesException catch (e) {
      if (mounted) {
        await showProblemDialog(context, Problem(Severity.error, 'Це не PMTiles, який програма читає', detail: '$e',
            fixes: const ['Потрібен PMTiles версії 3 — такий робить `pmtiles extract` і Protomaps.']));
      }
    } catch (e) {
      if (mounted) {
        await showProblemDialog(context, Problem(Severity.error, 'Файл PMTiles не відкрився', detail: '$e',
            fixes: const ['Перевірте, що файл цілий (перекопіюйте його) і що на пристрої досить місця.']));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Команда для комп'ютера: вирізати цю ж ділянку офіційним інструментом pmtiles.
  Future<void> _showPcCommand() async {
    final (s, w, n, e) = _areaBounds();
    String f(double v) => v.toStringAsFixed(5);
    final cmd = t('pmtiles extract https://build.protomaps.com/РРРРММДД.pmtiles ділянка.pmtiles '
        '--bbox={bbox} --maxzoom=15', {'bbox': '${f(w)},${f(s)},${f(e)},${f(n)}'});
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const T('Вирізати карту на комп’ютері'),
        content: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const T('1. Завантажте pmtiles для Windows: github.com/protomaps/go-pmtiles/releases (файл pmtiles.exe).'),
            const T('2. Дату збірки (РРРРММДД) візьміть на maps.protomaps.com/builds — найсвіжішу.'),
            const T('3. Виконайте в командному рядку:'),
            const SizedBox(height: 6),
            SelectableText(cmd, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            const SizedBox(height: 6),
            const T('4. Перенесіть ділянка.pmtiles на пристрій і додайте кнопкою «Додати PMTiles».'),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: cmd)),
            child: const T('Скопіювати команду'),
          ),
          TextButton(onPressed: () => Navigator.pop(c), child: const T('Закрити')),
        ],
      ),
    );
  }

  Future<void> _addMbtiles() async {
    if (kIsWeb) {
      await showProblemDialog(context, const Problem(Severity.info, 'MBTiles у браузері не відкриваються',
          fixes: ['Це перевірочна версія на комп’ютері; на планшеті MBTiles працюють.']));
      return;
    }
    final f = await FilePicker.pickFile(dialogTitle: t('Файл MBTiles'));
    if (f == null || !mounted) return;
    if (!f.name.toLowerCase().endsWith('.mbtiles')) {
      await showProblemDialog(context, problemForFileName(f.name) ?? notMbtilesFile);
      return;
    }
    setState(() => _busy = true);
    final id = 'm${DateTime.now().microsecondsSinceEpoch}';
    final file = File('${(await basemapStore.folder()).path}/$id.mbtiles');
    try {
      // Великий файл — копіюємо потоком, не через пам’ять.
      final sink = file.openWrite();
      await sink.addStream(f.readAsByteStream());
      await sink.close();
      final m = await describeMbtiles(file.path, id, f.name.replaceAll(RegExp(r'\.mbtiles$', caseSensitive: false), ''));
      if (!await _confirmOverlap(m)) {
        await file.delete();
        return;
      }
      await basemapStore.add(m);
      o.basemap = m.id;
      await _save();
      await _reloadMaps();
    } on BasemapException catch (e) {
      if (await file.exists()) await file.delete();
      if (mounted) await showProblemDialog(context, e.problem);
    } catch (e) {
      if (await file.exists()) await file.delete();
      if (mounted) {
        await showProblemDialog(context, Problem(Severity.error, 'MBTiles не додався', detail: '$e',
            fixes: const ['Перевірте, що на пристрої досить місця, і спробуйте ще раз.']));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addImage() async {
    final files = await FilePicker.pickFiles(dialogTitle: t('Знімок (JPG/PNG) разом з файлом прив’язки'));
    if (files.isEmpty || !mounted) return;
    String ext(PlatformFile f) => f.name.contains('.') ? f.name.split('.').last.toLowerCase() : '';
    final img = files.where((f) => const {'jpg', 'jpeg', 'png'}.contains(ext(f))).firstOrNull;
    final world = files.where((f) => const {'jgw', 'pgw', 'jpgw', 'pngw', 'wld', 'tfw'}.contains(ext(f))).firstOrNull;
    final tif = files.where((f) => const {'tif', 'tiff'}.contains(ext(f))).firstOrNull;
    if (img == null || world == null) {
      await showProblemDialog(context, tif != null ? geoTiffProblem : imageNeedsWorldFile);
      return;
    }
    setState(() => _busy = true);
    try {
      final bytes = await img.readAsBytes();
      final w = parseWorldFile(utf8.decode(await world.readAsBytes(), allowMalformed: true));
      final size = imageSize(bytes);
      if (size == null) throw const BasemapException(notPngJpeg);
      final (width, height) = size;
      final id = 'i${DateTime.now().microsecondsSinceEpoch}';
      final e = ext(img) == 'jpeg' ? 'jpg' : ext(img);
      final m = describeImage(id, img.name.replaceAll(RegExp(r'\.[^.]+$'), ''), e, w, width, height, o.crs);
      if (!await _confirmOverlap(m)) return;
      if (kIsWeb) {
        basemapStore.keepInMemory(id, bytes);
      } else {
        await File(await basemapStore.pathOf(m)).writeAsBytes(bytes);
      }
      await basemapStore.add(m);
      o.basemap = m.id;
      await _save();
      await _reloadMaps();
    } on BasemapException catch (e) {
      if (mounted) await showProblemDialog(context, e.problem);
    } catch (e) {
      if (mounted) {
        await showProblemDialog(context, Problem(Severity.error, 'Знімок не додався', detail: '$e',
            fixes: const ['Перевірте, що це звичайний JPG чи PNG і що він відкривається на комп’ютері.']));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    await objectStore.save(o);
    if (mounted) setState(() {});
  }

  /// Вибір файлу з перевіркою розширення; null — скасовано або не той файл (людині показано чому).
  Future<(String, Uint8List)?> _pick(List<String> exts, Problem wrong) async {
    final f = await FilePicker.pickFile(dialogTitle: t('Виберіть файл ({ext})', {'ext': exts.join(', ')}));
    if (f == null || !mounted) return null;
    final ext = f.name.contains('.') ? f.name.split('.').last.toLowerCase() : '';
    if (!exts.contains(ext)) {
      await showProblemDialog(context, wrong);
      return null;
    }
    try {
      return (f.name, await f.readAsBytes());
    } catch (e) {
      if (mounted) {
        await showProblemDialog(context, Problem(Severity.error, t('Не вдалося відкрити «{name}»', {'name': f.name}), detail: '$e',
            fixes: const ['Збережіть файл у пам’ять пристрою (Завантаження) і виберіть ще раз.']));
      }
      return null;
    }
  }

  /// Креслення (DXF) для ЦММ і поперечників: є збережене креслення об'єкта — спершу воно, без пошуку
  /// файлу; інакше — вибір файлу (вибрали те саме креслення, з якого створено об'єкт, — запам'ятовується).
  /// DWG програма не читає: об'єкт, створений з DWG давнішою версією, свого креслення не пропонує, а вибраний
  /// DWG — картка «збережіть як DXF».
  Future<(String, Uint8List)?> _pickDrawing(Problem wrong) async {
    final ownDwg = o.sourceFile.toLowerCase().endsWith('.dwg');
    if (!ownDwg && await objectStore.hasDrawing(o.id)) {
      if (!mounted) return null;
      final own = await showDialog<bool>(
        context: context,
        builder: (c) => SimpleDialog(
          title: const T('Яке креслення?'),
          children: [
            SimpleDialogOption(
                onPressed: () => Navigator.pop(c, true),
                child: ListTile(
                    leading: const Icon(Icons.architecture),
                    title: Text(t('Креслення об\'єкта: {f}', {'f': o.sourceFile})))),
            SimpleDialogOption(
                onPressed: () => Navigator.pop(c, false),
                child: const ListTile(leading: Icon(Icons.folder_open), title: T('Інший файл…'))),
          ],
        ),
      );
      if (own == null) return null;
      if (own) {
        final bytes = await objectStore.loadDrawing(o.id);
        if (bytes != null) return (o.sourceFile, bytes);
      }
    }
    final picked = await _pick(['dxf', 'dwg'], wrong);
    if (picked != null && picked.$1.toLowerCase().endsWith('.dwg')) {
      if (mounted) await showProblemDialog(context, problemForFileName(picked.$1)!);
      return null;
    }
    if (picked != null && picked.$1 == o.sourceFile && !await objectStore.hasDrawing(o.id)) {
      await objectStore.saveDrawing(o.id, picked.$2);
    }
    return picked;
  }

  /// Призначення шару ліній плану й попередження — коли програма визначила неправильно чи треба мережа.
  Future<void> _editLayer(String layer) async {
    final first = o.lines.firstWhere((l) => l.layer == layer);
    var role = first.role;
    final alert = TextEditingController(text: first.alert == null ? '' : _num(first.alert!));
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          scrollable: true,
          title: Text(t('Шар «{l}»', {'l': layer})),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            DropdownButton<LineRole>(
              isExpanded: true,
              value: role,
              items: [
                for (final r in LineRole.values)
                  DropdownMenuItem(
                      value: r,
                      child: Row(children: [
                        Container(width: 24, height: 4, color: r.color),
                        const SizedBox(width: 8),
                        Expanded(child: Text(t(r.label))),
                      ])),
              ],
              onChanged: (r) => set(() {
                role = r!;
                if (r.utility && alert.text.trim().isEmpty) alert.text = '2';
              }),
            ),
            TextField(
              controller: alert,
              keyboardType: numberKeyboard,
              decoration: InputDecoration(labelText: t('Попереджати ближче ніж, м')),
            ),
            const SizedBox(height: 6),
            const T('Порожньо — без попередження. З попередженням: вібрація й напис, коли ви за GPS підходите до '
                'лінії ближче (у будь-якому напрямку — і там, де мережа перетинає дорогу).',
                style: TextStyle(color: Colors.black54)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const T('Скасувати')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const T('Зберегти')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final a = double.tryParse(alert.text.trim().replaceAll(',', '.'));
    o.lines = [for (final l in o.lines) l.layer == layer ? l.withRole(role, a != null && a > 0 ? a : null) : l];
    await _save();
  }

  static String _num(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  Future<void> _addCsv() async {
    final picked = await _pick(['csv', 'txt'], const Problem(Severity.error, 'Потрібна відомість у форматі CSV',
        fixes: ['Excel: «Файл → Зберегти як» → «CSV UTF-8 (розділювач — кома)» або «CSV (розділювач — крапка з комою)».',
          'Колонки: ПК (наприклад 0+025.00 або метри), проєктна відмітка, за бажанням — ширина чи напівширина.']));
    if (picked == null || !mounted) return;
    CsvTable table;
    try {
      table = parseCsv(picked.$2);
    } on VidomistException catch (e) {
      await showProblemDialog(context, e.problem);
      return;
    }
    if (!mounted) return;
    final ax = o.roadAxis;
    final r = await Navigator.of(context).push<VidomistResult>(MaterialPageRoute(
        builder: (_) => CsvImportScreen(table: table, fileName: picked.$1, axisStart: ax.startStation, axisEnd: ax.endStation)));
    if (r == null) return;
    if (r.profile != null) o.profile = r.profile;
    if (r.widths != null) o.widths = r.widths;
    await _save();
  }

  /// ЦММ проєкту з LandXML: кілька поверхонь — вибір (проєктні — першими).
  Future<void> _addSurfaceLandXml() async {
    final picked = await _pick(['xml', 'landxml'], noSurface);
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    List<Surface> all;
    try {
      all = await compute(parseLandXmlSurfaces, picked.$2);
    } on SurfaceException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        await showProblemDialog(context, e.problem);
      }
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    all.sort((a, b) => designScore(b.source).compareTo(designScore(a.source)));
    final s = all.length == 1 ? all.single : await _chooseSurface(all.map((x) => (x.source, x)).toList());
    if (s != null) await _takeSurface(s);
  }

  /// ЦММ з 3D-граней креслення (DXF): шар з гранями — вибір, якщо їх кілька.
  Future<void> _addSurfaceDrawing() async {
    final picked = await _pickDrawing(noSurface);
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final d = await compute(parseDxf, picked.$2);
      final layers = [for (final l in d.layers.values) if (l.faces.isNotEmpty) l]
        ..sort((a, b) => designScore(b.name).compareTo(designScore(a.name)));
      if (!mounted) return;
      if (layers.isEmpty) {
        await showProblemDialog(context, noSurface);
        return;
      }
      setState(() => _busy = false);
      final options = [
        for (final l in layers) ('DXF: ${l.name}', Surface('DXF: ${l.name}', Float64List.fromList(l.faces))),
        if (layers.length > 1)
          (t('Усі шари з гранями'), Surface('DXF: ${layers.map((l) => l.name).join(', ')}',
              Float64List.fromList([for (final l in layers) ...l.faces]))),
      ];
      final s = options.length == 1 ? options.single.$2 : await _chooseSurface(options);
      if (s != null) await _takeSurface(s);
    } on DxfException catch (e) {
      if (mounted) await showProblemDialog(context, e.problem);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Surface?> _chooseSurface(List<(String, Surface)> options) => showDialog<Surface>(
        context: context,
        builder: (c) => SimpleDialog(
          title: const T('Яка поверхня — проєкт?'),
          children: [
            for (final (name, s) in options)
              ListTile(
                title: Text(name),
                subtitle: Text([
                  t('трикутників: {n}', {'n': s.count}),
                  if (designScore(name) < 0) t('схоже на землю, а не проєкт'),
                ].join(' · ')),
                onTap: () => Navigator.pop(c, s),
              ),
          ],
        ),
      );

  /// ЦММ проєкту з поперечників об'єкта — програма з'єднує сусідні поперечники трикутниками.
  Future<void> _surfaceFromSections() async {
    final cs = o.crossSections;
    if (cs == null) return;
    await _takeSurface(surfaceFromSections(cs, o.roadAxis, t('з поперечників ({src})', {'src': cs.source})),
        ground: false);
  }

  /// ЦММ з точок креслення (пікети зйомки, точки, вершини 3D-ліній) — тріангуляція Делоне в програмі.
  Future<void> _surfaceFromPoints() async {
    final picked = await _pickDrawing(const Problem(Severity.error, 'Потрібне креслення з точками з відмітками (DXF)',
        fixes: ['Топозйомка: пікети (точки чи блоки на висоті), 3D-полілінії бровок, кромок, укосів.']));
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final d = await compute(parseDxf, picked.$2);
      final layers = [for (final l in d.layers.values) if (l.points3d.isNotEmpty) l]
        ..sort((a, b) => b.points3d.length.compareTo(a.points3d.length));
      if (!mounted) return;
      setState(() => _busy = false);
      if (layers.isEmpty) {
        await showProblemDialog(context, const Problem(Severity.error, 'У кресленні немає точок з відмітками',
            detail: 'Точки, блоки й лінії лежать на висоті 0 — відміток у кресленні немає.',
            fixes: ['Потрібна топозйомка з відмітками (Z) або поверхня: «З LandXML», «З 3D-граней».']));
        return;
      }
      final chosen = await _choosePointLayers(layers);
      if (chosen == null || chosen.isEmpty || !mounted) return;
      setState(() => _busy = true);
      final pts = [for (final l in chosen) ...l.points3d];
      final tri = await compute(_tin, pts);
      if (!mounted) return;
      setState(() => _busy = false);
      if (tri.isEmpty) {
        await showProblemDialog(context, const Problem(Severity.error, 'Трикутників не вийшло',
            fixes: ['Точок замало або вони далі 60 м одна від одної — виберіть шари з пікетами зйомки.']));
        return;
      }
      await _takeSurface(Surface(t('з точок креслення ({f}: {l})', {'f': picked.$1, 'l': chosen.map((l) => l.name).join(', ')}), tri));
    } on DxfException catch (e) {
      if (mounted) await showProblemDialog(context, e.problem);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Які шари з точками брати: за замовчуванням — усі.
  Future<List<DxfLayer>?> _choosePointLayers(List<DxfLayer> layers) {
    final on = {for (final l in layers) l.name};
    return showDialog<List<DxfLayer>>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const T('Точки з яких шарів брати?'),
          content: SizedBox(
            width: 420,
            child: ListView(shrinkWrap: true, children: [
              for (final l in layers)
                CheckboxListTile(
                  value: on.contains(l.name),
                  title: Text(l.name),
                  subtitle: Text(t('точок: {n}', {'n': l.points3d.length ~/ 3})),
                  onChanged: (v) => set(() => v == true ? on.add(l.name) : on.remove(l.name)),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const T('Скасувати')),
            FilledButton(
                onPressed: () => Navigator.pop(c, [for (final l in layers) if (on.contains(l.name)) l]),
                child: const T('Побудувати')),
          ],
        ),
      ),
    );
  }

  /// Перевірити, що ЦММ лежить на осі об'єкта, вибрати — проєкт це чи земля, — і зберегти.
  /// [ground] — уже відомо (з поперечників — проєкт); null — питаємо, підказка — за назвою.
  Future<void> _takeSurface(Surface s, {bool? ground}) async {
    final ax = o.roadAxis;
    var inside = 0, total = 0;
    for (var st = ax.startStation; st <= ax.endStation; st += math.max(1, ax.length / 200)) {
      total++;
      if (s.elevationAt(ax.pointAtStation(st)) != null) inside++;
    }
    final problems = [
      if (inside == 0)
        Problem(Severity.error, 'ЦММ не накриває вісь об’єкта',
            detail: t('Жодна з {n} перевірених точок осі не потрапила на поверхню.', {'n': total}),
            fixes: const [
              'Перевірте, що ЦММ цієї ділянки й у тій самій системі координат, що й вісь.',
              'У LandXML точки записано «північ схід» — програма це враховує; у DXF X — схід, Y — північ.',
            ])
      else if (inside < total)
        Problem(Severity.info, t('ЦММ накриває {p} % осі', {'p': (100 * inside / total).round()})),
    ];
    var isGround = ground ?? designScore(s.source) < 0;
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(t('ЦММ: трикутників {n}', {'n': s.count})),
          content: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.source, style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 8),
              if (ground == null)
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(value: false, label: Text(t('Проєкт'))),
                    ButtonSegment(value: true, label: Text(t('Земля (зйомка)'))),
                  ],
                  selected: {isGround},
                  onSelectionChanged: (v) => set(() => isGround = v.first),
                ),
              const SizedBox(height: 6),
              Text(isGround
                  ? t('Земля — окремим рядком «Відмітка землі»; проєктна відмітка — з поперечників.')
                  : t('Проєкт — відмітка в точці з ЦММ, поза нею — з поперечників.')),
              for (final p in problems) ProblemCard(p),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const T('Скасувати')),
            if (inside > 0) FilledButton(onPressed: () => Navigator.pop(c, true), child: const T('Додати')),
          ],
        ),
      ),
    );
    if (go != true) return;
    await objectStore.saveSurface(o.id, s.encode());
    o
      ..surfaceSource = s.source
      ..surfaceTriangles = s.count
      ..surfaceGround = isGround;
    await _save();
  }

  /// Обвести поперечники на сторінках PDF поперечників об'єкта — відмітки зі скану (додаються до наявних).
  Future<void> _traceSections() async {
    final s = o.sections;
    final bytes = await objectStore.loadPdf(o.id);
    if (!mounted || s == null) return;
    if (bytes == null) {
      await showProblemDialog(context, const Problem(Severity.error, 'PDF поперечників не знайдено в пам’яті',
          fixes: ['Додайте його ще раз: «Дані об’єкта» → «Додати PDF».']));
      return;
    }
    final cs = await Navigator.of(context).push<CrossSections>(MaterialPageRoute(
        builder: (_) =>
            XsScanScreen(pdf: bytes, sections: s, style: o.style, profile: o.profile, existing: o.crossSections)));
    if (cs == null) return;
    o.crossSections = cs;
    await _save();
  }

  /// Поперечники, намальовані в DXF (аркуш поперечників). Замінюють наявні.
  Future<void> _addSectionsDrawing() async {
    final picked = await _pickDrawing(const Problem(Severity.error, 'Потрібне креслення поперечників (DXF)',
        fixes: [
          'Біля кожного поперечника в кресленні — підпис з ПК, вертикаль осі й лінія проєкту.',
          'PDF чи скан — поки ні; є таблиця «ПК, зміщення, відмітка» — «З таблиці (CSV)».',
        ]));
    if (picked == null || !mounted) return;
    final cs = await Navigator.of(context).push<CrossSections>(MaterialPageRoute(
        builder: (_) => XsDrawingScreen(dxf: picked.$2, fileName: picked.$1, style: o.style, profile: o.profile)));
    if (cs == null) return;
    o.crossSections = cs;
    await _save();
  }

  /// Поперечники з таблиці: рядок = точка (ПК, зміщення від осі, відмітка). Замінюють наявні.
  Future<void> _addSectionsCsv() async {
    final picked = await _pick(['csv', 'txt'], const Problem(Severity.error, 'Потрібна таблиця поперечників у форматі CSV',
        fixes: [
          'Excel: «Файл → Зберегти як» → «CSV UTF-8 (розділювач — кома)» або «CSV (розділювач — крапка з комою)».',
          'Колонки: ПК (наприклад 0+025.00 або метри), зміщення від осі (ліворуч — з мінусом), проєктна відмітка; '
              'одна точка поперечника в рядку.',
        ]));
    if (picked == null || !mounted) return;
    CsvTable table;
    try {
      table = parseCsv(picked.$2);
    } on VidomistException catch (e) {
      await showProblemDialog(context, e.problem);
      return;
    }
    if (!mounted) return;
    final ax = o.roadAxis;
    final cs = await Navigator.of(context).push<CrossSections>(MaterialPageRoute(
        builder: (_) =>
            CsvSectionsScreen(table: table, fileName: picked.$1, axisStart: ax.startStation, axisEnd: ax.endStation)));
    if (cs == null) return;
    o.crossSections = cs;
    await _save();
  }

  Future<void> _addLandXml() async {
    final picked = await _pick(['xml', 'landxml'], const Problem(Severity.error, 'Потрібен файл LandXML (.xml)',
        fixes: ['Civil 3D: «Вивід → Експорт у LandXML», позначте вісь і її профіль.']));
    if (picked == null || !mounted) return;
    List<LxAlignment> axes;
    try {
      axes = parseLandXml(picked.$2);
    } on LandXmlException catch (e) {
      await showProblemDialog(context, e.problem);
      return;
    }
    if (!mounted) return;
    final withProfile = axes.where((a) => a.profiles.isNotEmpty || a.sections != null).toList();
    if (withProfile.isEmpty) {
      await showProblemDialog(context, const Problem(Severity.error, 'У LandXML немає ні поздовжнього профілю, ні поперечників',
          fixes: ['Civil 3D: під час експорту в LandXML позначте не лише вісь, а й її профіль (Profile) і поперечники (Cross Sections).']));
      return;
    }
    // Профіль якої осі: тієї, що найближча до осі об'єкта.
    final ax = o.roadAxis;
    LxAlignment best = withProfile.first;
    var bestOff = double.infinity;
    for (final a in withProfile) {
      final off = ax.locate(a.segs.first.start).offset.abs();
      if (off < bestOff) {
        bestOff = off;
        best = a;
      }
    }
    final at = ax.locate(best.segs.first.start);
    final problems = [
      ...best.problems,
      if (at.offset.abs() > 1 || (at.station - best.staStart).abs() > 1)
        Problem(Severity.warning, 'Вісь у LandXML не збігається з віссю об’єкта',
            detail: t('Початок осі «{name}» ({a}) лежить на {b} об’єкта, за {off} м від осі.', {
              'name': best.name,
              'a': formatStation(best.staStart, o.style),
              'b': formatStation(at.station, o.style),
              'off': at.offset.abs().toStringAsFixed(1),
            }),
            fixes: const [
              'Перевірте, що це LandXML саме цієї дороги й ділянки.',
              'Перевірте ПК початку осі об’єкта — він має збігатися з пікетажем Civil 3D.',
            ]),
    ];
    if (!mounted) return;
    final profile = best.profiles.firstOrNull;
    if (problems.isNotEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(t('Вісь «{name}»', {'name': best.name})),
          content: SingleChildScrollView(child: Column(children: [for (final p in problems) ProblemCard(p)])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const T('Скасувати')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const T('Додати все одно')),
          ],
        ),
      );
      if (go != true) return;
    }
    if (profile != null) o.profile = profile;
    if (best.sections != null) o.crossSections = best.sections;
    await _save();
  }

  /// Профіль зі скану чи PDF аркуша поздовжнього профілю (етап 7): масштаб за підписами й обведення лінії.
  Future<void> _addProfileScan() async {
    final picked = await _pick(['pdf', 'jpg', 'jpeg', 'png'], const Problem(Severity.error, 'Потрібен скан чи PDF поздовжнього профілю',
        fixes: ['Виберіть аркуш профілю: PDF, JPG або PNG.']));
    if (picked == null || !mounted) return;
    final p = await Navigator.of(context).push<Profile>(MaterialPageRoute(
        builder: (_) => RasterImportScreen(fileName: picked.$1, bytes: picked.$2, mode: RasterMode.profile, object: o)));
    if (p == null) return;
    o.profile = p;
    await _save();
  }

  Future<void> _addPdf() async {
    final picked = await _pick(['pdf'], const Problem(Severity.error, 'Потрібен PDF з поперечниками',
        fixes: ['Виберіть PDF-аркуші поперечних профілів, де кожен підписаний «PK 0+025.00» чи «ПК 12+34».']));
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    try {
      var s = await indexPdf(picked.$2, picked.$1);
      if (!mounted) return;
      if (s.labels.isEmpty) {
        // Скан без тексту: ПК сторінок вписує людина.
        final go = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const T('У PDF не знайдено підписів ПК'),
            content: const T('Схоже, це скан: підписи в ньому — картинка. Розмітьте сторінки вручну: гортаєте й вписуєте ПК '
                'кожного поперечника (або першого й крок — решту програма заповнить).'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const T('Скасувати')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const T('Розмітити сторінки')),
            ],
          ),
        );
        if (go != true || !mounted) return;
        final manual = await Navigator.of(context).push<PdfSections>(MaterialPageRoute(
            builder: (_) => PdfLabelScreen(bytes: picked.$2, fileName: picked.$1, style: o.style)));
        if (manual == null || !mounted) return;
        s = manual;
      }
      final ax = o.roadAxis;
      final inside = s.labels.where((l) => l.station >= ax.startStation - 1 && l.station <= ax.endStation + 1).length;
      if (inside == 0) {
        await showProblemDialog(context, Problem(Severity.error, 'ПК у PDF не збігаються з віссю',
            detail: t('Знайдено {n} підписів, але жоден не в межах осі ({a} – {b}).', {
              'n': s.labels.length,
              'a': formatStation(ax.startStation, o.style),
              'b': formatStation(ax.endStation, o.style),
            }),
            fixes: const ['Перевірте, що PDF від цієї ділянки, і ПК початку осі об’єкта.']));
        return;
      }
      await objectStore.savePdf(o.id, picked.$2);
      o.sections = s;
      await _save();
    } catch (e) {
      if (mounted) {
        await showProblemDialog(context, Problem(Severity.error, 'PDF не відкрився', detail: '$e',
            fixes: const ['Перевірте, що PDF відкривається на комп’ютері й не захищений паролем.']));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Шари ліній плану: що це за лінія й чи попереджати біля неї; торкання — змінити.
  Widget _layersCard(ThemeData theme) {
    final layers = <String, List<RoadLine>>{};
    for (final l in o.lines) {
      (layers[l.layer] ??= []).add(l);
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t('Лінії плану'), style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          const T('Що це за лінія — видно на карті й на схемі поперечника. Програма визначає за назвою шару; '
              'неправильно — торкніться шару й змініть. Прив’язка — лише до осі, лінії — для огляду.'),
          for (final MapEntry(key: name, value: ls) in layers.entries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(width: 28, height: 5, color: ls.first.role.color),
              title: Text(name),
              subtitle: Text([
                t(ls.first.role.label),
                t('ліній: {n}', {'n': ls.length}),
                if (ls.first.alert != null) t('попередження за {m} м', {'m': _num(ls.first.alert!)}),
              ].join(' · ')),
              trailing: const Icon(Icons.edit),
              onTap: () => _editLayer(name),
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ax = o.roadAxis;
    final theme = Theme.of(context);
    Widget section(String title, String status, List<Widget> buttons) => Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(status),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 4, children: buttons),
            ]),
          ),
        );
    return Scaffold(
      appBar: AppBar(title: Text(t('Дані: {name}', {'name': o.name})), actions: [
        IconButton(
          icon: const Icon(Icons.help_outline),
          tooltip: t('Довідка: що вміє програма, формати файлів з прикладами'),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HelpScreen())),
        ),
      ]),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(padding: const EdgeInsets.all(12), children: [
          Text(t('Вісь: {a} – {b}, {len} м · {crs} · {file}', {
            'a': formatStation(ax.startStation, o.style),
            'b': formatStation(ax.endStation, o.style),
            'len': ax.length.toStringAsFixed(1),
            'crs': crsName(o.crs),
            'file': o.sourceFile,
          })),
          const SizedBox(height: 8),
          section(
            t('Вид робіт'),
            t('Від нього — готові фрази в позначках і тип нової позначки (ремонт — «Дефект», нове будівництво — '
                '«Зауваження», лабораторія — «Відбір зразка»).'),
            [
              // Окремими кнопками, а не одним рядком: три назви з великим шрифтом у рядок телефона не вміщаються.
              for (final w in WorkType.values)
                ChoiceChip(
                  label: Text(t(w.label)),
                  selected: o.work == w,
                  onSelected: (_) {
                    o.work = w;
                    _save();
                  },
                ),
            ],
          ),
          if (o.lines.isNotEmpty) _layersCard(theme),
          section(
            t('Поздовжній профіль (проєктна відмітка осі)'),
            o.profile == null
                ? t('Немає.')
                : t('{src}: точок {n}, {a} – {b}.', {
                    'src': o.profile!.source,
                    'n': o.profile!.pvis.length,
                    'a': formatStation(o.profile!.startStation, o.style),
                    'b': formatStation(o.profile!.endStation, o.style),
                  }),
            [
              OutlinedButton.icon(onPressed: _addCsv, icon: const Icon(Icons.table_chart), label: const T('З відомості (CSV)')),
              OutlinedButton.icon(onPressed: _addLandXml, icon: const Icon(Icons.timeline), label: const T('З LandXML')),
              OutlinedButton.icon(onPressed: _addProfileScan, icon: const Icon(Icons.gesture), label: const T('Зі скану (PDF, JPG)')),
              if (o.profile != null)
                TextButton(onPressed: () { o.profile = null; _save(); }, child: const T('Прибрати')),
            ],
          ),
          section(
            t('ЦММ (поверхня)'),
            o.surfaceSource == null
                ? t('Немає. ЦММ проєкту дає відмітку в будь-якій точці — першою, до поперечників; ЦММ землі (зйомки) — '
                    'рядком «Відмітка землі». Програма може побудувати її сама — з поперечників чи з точок креслення.')
                : t('{kind}: {src}, трикутників {n}.', {
                    'kind': o.surfaceGround ? t('Земля') : t('Проєкт'),
                    'src': o.surfaceSource!,
                    'n': o.surfaceTriangles,
                  }),
            [
              OutlinedButton.icon(
                  onPressed: o.crossSections == null ? null : _surfaceFromSections,
                  icon: const Icon(Icons.auto_awesome),
                  label: const T('Побудувати з поперечників')),
              OutlinedButton.icon(
                  onPressed: _surfaceFromPoints,
                  icon: const Icon(Icons.scatter_plot),
                  label: const T('Побудувати з точок креслення (DXF)')),
              OutlinedButton.icon(
                  onPressed: _addSurfaceLandXml, icon: const Icon(Icons.terrain), label: const T('З LandXML')),
              OutlinedButton.icon(
                  onPressed: _addSurfaceDrawing,
                  icon: const Icon(Icons.change_history),
                  label: const T('З 3D-граней (DXF)')),
              if (o.surfaceSource != null)
                TextButton(
                    onPressed: () async {
                      await objectStore.saveSurface(o.id, null);
                      o
                        ..surfaceSource = null
                        ..surfaceTriangles = 0
                        ..surfaceGround = false;
                      await _save();
                    },
                    child: const T('Прибрати')),
            ],
          ),
          section(
            t('Поперечники з відмітками'),
            o.crossSections == null
                ? t('Немає (з креслення поперечників, таблиці CSV чи LandXML). Без них відмітка в точці, де ви стоїте, — '
                    'прочерк; на осі — з профілю.')
                : t('{src}: поперечників {n}, {a} – {b}. Відмітка — по поперечнику там, де він є (між сусідніми '
                    'не далі 50 м — за обома).', {
                    'src': o.crossSections!.source,
                    'n': o.crossSections!.rows.length,
                    'a': formatStation(o.crossSections!.startStation, o.style),
                    'b': formatStation(o.crossSections!.endStation, o.style),
                  }),
            [
              OutlinedButton.icon(
                  onPressed: _addSectionsDrawing,
                  icon: const Icon(Icons.architecture),
                  label: const T('З креслення (DXF)')),
              OutlinedButton.icon(
                  onPressed: _addSectionsCsv, icon: const Icon(Icons.table_chart), label: const T('З таблиці (CSV)')),
              OutlinedButton.icon(onPressed: _addLandXml, icon: const Icon(Icons.timeline), label: const T('З LandXML')),
              if (o.crossSections != null)
                TextButton(onPressed: () { o.crossSections = null; _save(); }, child: const T('Прибрати')),
            ],
          ),
          section(
            t('PDF поперечників'),
            o.sections == null
                ? t('Немає.')
                : t('{file}: сторінок {p}, підписаних поперечників {n}.', {
                    'file': o.sections!.fileName,
                    'p': o.sections!.pageCount,
                    'n': o.sections!.labels.length,
                  }),
            [
              OutlinedButton.icon(onPressed: _addPdf, icon: const Icon(Icons.picture_as_pdf), label: const T('Додати PDF')),
              if (o.sections != null)
                OutlinedButton.icon(
                    onPressed: _traceSections, icon: const Icon(Icons.gesture), label: const T('Обвести поперечники (відмітки)')),
              if (o.sections != null)
                TextButton(
                    onPressed: () async {
                      o.sections = null;
                      await objectStore.savePdf(o.id, null);
                      await _save();
                    },
                    child: const T('Прибрати')),
            ],
          ),
          section(
            t('Підкладки (спільні для всіх об’єктів)'),
            t('Карта OSM без інтернету — вирізана з Protomaps для ділянки об’єкта; ортофото чи інша карта — '
                'PMTiles, MBTiles (будь-якого розміру) або знімок JPG/PNG з файлом прив’язки '
                '(.jgw / .pgw) у системі координат об’єкта. Вибір підкладки — кнопка шарів на екрані об’єкта.'),
            [
              for (final m in _maps)
                InputChip(
                  label: Text(m.name),
                  avatar: Icon(
                      switch (m.kind) {
                        BasemapKind.mbtiles => Icons.grid_on,
                        BasemapKind.pmtiles => Icons.map,
                        BasemapKind.image => Icons.image,
                      },
                      size: 18),
                  selected: o.basemap == m.id,
                  onPressed: () async {
                    o.basemap = m.id;
                    await _save();
                  },
                  onDeleted: () => _removeMap(m),
                ),
              FilledButton.tonalIcon(
                  onPressed: _downloadOsm, icon: const Icon(Icons.download), label: const T('OSM без інтернету (Protomaps)')),
              OutlinedButton.icon(onPressed: _addPmtiles, icon: const Icon(Icons.map), label: const T('Додати PMTiles')),
              TextButton(onPressed: _showPcCommand, child: const T('Команда для ПК')),
              OutlinedButton.icon(onPressed: _addMbtiles, icon: const Icon(Icons.grid_on), label: const T('Додати MBTiles')),
              OutlinedButton.icon(
                  onPressed: _addImage, icon: const Icon(Icons.image), label: const T('Додати знімок + прив’язку')),
            ],
          ),
          if (_busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
        ]),
      ),
    );
  }
}

/// Тріангуляція в окремому потоці.
Float64List _tin(List<double> pts) => triangulate(pts);
