import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:pdfrx/pdfrx.dart';

import 'chainage.dart';
import 'crs.dart';
import 'geometry.dart';
import 'help_screen.dart';
import 'import_screen.dart';
import 'landxml_import_screen.dart';
import 'nearest_axis.dart';
import 'notes.dart';
import 'osm_cache.dart';
import 'problem_card.dart';
import 'problems.dart';
import 'road_object.dart';
import 'raster_import_screen.dart';
import 'road_screen.dart';
import 'i18n.dart';
import 'settings.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();
  // Кеш плиток OSM не росте безмежно: зайве понад 500 МБ — найстаріше геть.
  if (!kIsWeb) osmCacheDir().then(trimCache);
  // Мова — з налаштувань пристрою; поки читаються, показуємо українською.
  loadSettings();
  runApp(const RoadGpsApp());
}

class RoadGpsApp extends StatelessWidget {
  const RoadGpsApp({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Lang>(
        valueListenable: lang,
        // Ключ з мовою: після перемикання вся програма перемальовується новою мовою.
        builder: (context, l, _) => MaterialApp(
          key: ValueKey(l),
          title: 'ROAD-GPS',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(colorSchemeSeed: const Color(0xFFE65100), useMaterial3: true),
          home: const HomeScreen(),
          // Арабська — справа наліво: меню, кнопки й рядки дзеркаляться.
          builder: (context, child) =>
              Directionality(textDirection: l.rtl ? TextDirection.rtl : TextDirection.ltr, child: child!),
        ),
      );
}

/// Список об'єктів у телефоні й додавання нового з DXF.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<RoadObject>? _objects;

  /// Де зараз пристрій — щоб поставити нагору об'єкт, біля якого стоїмо.
  LatLng? _here;

  @override
  void initState() {
    super.initState();
    _reload();
    _locate();
  }

  Future<void> _locate() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 30)),
      );
      if (mounted) setState(() => _here = LatLng(p.latitude, p.longitude));
    } catch (_) {
      // Без GPS список просто не сортується за відстанню.
    }
  }

  /// Відстань від пристрою до осі об'єкта, м, і де саме на осі.
  (double, StationResult)? _near(RoadObject o) {
    final here = _here;
    if (here == null) return null;
    final ax = o.roadAxis;
    final r = ax.locate(fromWgs84(o.crs, here));
    return (distanceToAxis(ax, r), r);
  }

  Future<void> _reload() async {
    final list = await objectStore.loadAll();
    if (mounted) setState(() => _objects = list);
  }

  Future<void> _add() async {
    final f = await FilePicker.pickFile(dialogTitle: t('Креслення DXF, LandXML або скан плану (JPG, PNG, PDF)'));
    if (f == null || !mounted) return;
    final name = f.name;
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    // Скан чи PDF без координат — етап 7: прив'язка за точками й обведення.
    final raster = const {'jpg', 'jpeg', 'png', 'pdf'}.contains(ext);
    final wrong = raster ? null : problemForFileName(name);
    if (wrong != null) {
      await showProblemDialog(context, wrong);
      return;
    }
    Uint8List bytes;
    try {
      bytes = await f.readAsBytes();
    } catch (e) {
      if (mounted) {
        await showProblemDialog(
            context,
            Problem(Severity.error, t('Не вдалося відкрити «{name}»', {'name': name}),
                detail: '$e',
                fixes: const [
                  'Якщо файл у хмарі чи пошті — спершу збережіть його в пам’ять пристрою (Завантаження).',
                  'Спробуйте вибрати файл ще раз.',
                ]));
      }
      return;
    }
    if (!mounted) return;
    final isXml = name.toLowerCase().endsWith('.xml') || name.toLowerCase().endsWith('.landxml');
    final o = await Navigator.of(context).push<RoadObject>(
      MaterialPageRoute(
          builder: (_) => raster
              ? RasterImportScreen(fileName: name, bytes: bytes, mode: RasterMode.plan)
              : isXml
                  ? LandXmlImportScreen(fileName: name, bytes: bytes)
                  : ImportScreen(fileName: name, bytes: bytes)),
    );
    await _reload();
    if (o != null && mounted) _open(o);
  }

  /// Екран траси; інші об'єкти — щоб переходити на ближчу вісь (примикання, з'їзди).
  void _open(RoadObject o) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => RoadHost(objects: _objects ?? [o], start: o)));

  Future<void> _delete(RoadObject o) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const T('Видалити об\'єкт?'),
        content: Text(t(
            '«{name}» зникне з цього пристрою разом з його позначками й фото — спершу експортуйте '
            'їх, якщо потрібні. Файл DXF, з якого зроблено об’єкт, не зміниться.',
            {'name': o.name})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const T('Ні')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const T('Видалити')),
        ],
      ),
    );
    if (yes == true) {
      await objectStore.delete(o.id);
      await noteStore.deleteAll(o.id);
      await _reload();
    }
  }

  /// Найближчий за GPS об'єкт — нагорі; без GPS — як були (новіші вище).
  List<(RoadObject, (double, StationResult)?)> _sorted(List<RoadObject> list) {
    final out = [for (final o in list) (o, _near(o))];
    if (_here != null) out.sort((a, b) => a.$2!.$1.compareTo(b.$2!.$1));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final list = _objects;
    return Scaffold(
      appBar: AppBar(title: const T('ROAD-GPS — об\'єкти'), actions: [
        IconButton(
          icon: const Icon(Icons.help_outline),
          tooltip: t('Довідка: що вміє програма, формати файлів з прикладами'),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HelpScreen())),
        ),
        PopupMenuButton<Lang>(
          tooltip: 'Мова / Language / Langue / Sprache / Język / Dil / Язык / Idioma / اللغة / 语言',
          initialValue: lang.value,
          onSelected: (l) async {
            lang.value = l;
            await saveSettings();
          },
          itemBuilder: (_) => [for (final l in Lang.values) PopupMenuItem(value: l, child: Text(l.label))],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [const Icon(Icons.translate), const SizedBox(width: 4), Text(lang.value.short)]),
          ),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const T('Додати (DXF, LandXML, скан)'),
      ),
      body: list == null
          ? const Center(child: CircularProgressIndicator())
          : list.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: T('Об\'єктів ще немає.\nНатисніть «Додати» і виберіть креслення DXF чи LandXML з віссю дороги.',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 16)),
                  ),
                )
              : ListView(children: [
                  if (objectStore.broken > 0)
                    Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: ProblemCard(brokenSaved(objectStore.broken))),
                  for (final (o, near) in _sorted(list))
                    ListTile(
                      leading: Icon(Icons.add_road,
                          color: near != null && near.$1 < 500 ? Theme.of(context).colorScheme.primary : null),
                      title: Text(o.name),
                      subtitle: Text([
                        if (near != null)
                          near.$1 < 500
                              ? t('Ви тут: {pk}', {'pk': formatStation(near.$2.station, o.style)})
                              : t('{n} км звідси', {'n': (near.$1 / 1000).toStringAsFixed(1)}),
                        t(o.work.label),
                        '${t('{n} км', {'n': (o.roadAxis.length / 1000).toStringAsFixed(2)})} · ${crsName(o.crs)}',
                        if (o.lines.isNotEmpty) t('ліній: {n}', {'n': o.lines.length}),
                        o.sourceFile,
                      ].join(' · ')),
                      onTap: () => _open(o),
                      trailing: IconButton(
                        tooltip: t('Видалити'),
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _delete(o),
                      ),
                    ),
                ]),
    );
  }
}
