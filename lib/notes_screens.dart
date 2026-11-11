// Екрани позначок: створити чи змінити (тип, стан дефекту, текст з шаблонами, ділянка «від ПК до ПК»,
// фото «до / після» зі штампом, голос), список з пошуком і фільтрами, експорт в Excel, акт у Word,
// об'єднання з позначками колеги.
import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'act_docx.dart';
import 'chainage.dart';
import 'crs.dart';
import 'i18n.dart';
import 'notes.dart';
import 'photo_stamp.dart';
import 'problem_card.dart';
import 'problems.dart';
import 'road_object.dart';
import 'send.dart';
import 'settings.dart';
import 'keyboards.dart';

String noteWhere(Note n, ChainageStyle style) => [
      formatStation(n.station, style),
      if (n.toStation != null) '– ${formatStation(n.toStation!, style)}',
      '· ${t('{n} м {side}', {'n': n.offset.abs().toStringAsFixed(1), 'side': sideText(n.offset)})}',
    ].join(' ');

/// «Дефект · відкрито», «Зауваження».
String noteKindText(Note n) => [t(n.kind.label), if (n.status != null) t(n.status!.label).toLowerCase()].join(' · ');

/// Читати ПК, як його пишуть: «0+450», «км 1+250.5», «ПК 12+40» або просто метри «450».
double? parseStationInput(String s) {
  final t = s.trim().replaceAll(',', '.');
  if (t.isEmpty) return null;
  return parseChainageLabel(t)?.$1 ?? double.tryParse(t);
}

class NoteEditScreen extends StatefulWidget {
  final RoadObject object;
  final Note note;
  final bool isNew;

  /// Де людина зараз (ПК) — для кнопки «Кінець ділянки — тут»; null — місце невідоме.
  final double? Function()? hereStation;

  /// Показати дорогу до позначки на екрані об'єкта.
  final void Function(Note)? onGuide;

  const NoteEditScreen(
      {super.key, required this.object, required this.note, this.isNew = false, this.hereStation, this.onGuide});

  @override
  State<NoteEditScreen> createState() => _NoteEditScreenState();
}

class _NoteEditScreenState extends State<NoteEditScreen> {
  late final _text = TextEditingController(text: widget.note.text);
  late final _author = TextEditingController(text: widget.note.author.isNotEmpty ? widget.note.author : settings.author);
  late final _to = TextEditingController(
      text: widget.note.toStation == null ? '' : formatStation(widget.note.toStation!, widget.object.style));
  late NoteKind _kind = widget.note.kind;
  late final _sample = TextEditingController(text: widget.note.sampleNo ?? '');
  late NoteStatus? _status = widget.note.status;
  late DateTime? _fixedAt = widget.note.fixedAt;
  late bool _linear = widget.note.toStation != null;
  late final List<String> _photos = [...widget.note.photos];
  late final List<String> _after = [...widget.note.photosAfter];
  late final List<String> _audios = [...widget.note.audios];
  final _added = <String>[];
  bool _busy = false;

  // Голосовий запис: запис іде, скільки вже, обмеження — 5 хвилин.
  final _rec = AudioRecorder();
  DateTime? _recStart;
  Timer? _tick;
  static const _maxRec = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    loadSettings().then((s) {
      if (mounted && _author.text.isEmpty && s.author.isNotEmpty) setState(() => _author.text = s.author);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _rec.dispose();
    super.dispose();
  }

  Note get n => widget.note;
  bool get _isDefect => _kind == NoteKind.defect;

  Future<void> _toggleRecord() async {
    if (_recStart != null) return _stopRecord();
    try {
      if (!await _rec.hasPermission()) {
        if (mounted) await showProblemDialog(context, micDenied);
        return;
      }
      final path = kIsWeb ? '' : '${(await getTemporaryDirectory()).path}/rec_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _rec.start(
          const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 22050, numChannels: 1),
          path: path);
      setState(() => _recStart = DateTime.now());
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        if (DateTime.now().difference(_recStart!) >= _maxRec) {
          _stopRecord();
        } else {
          setState(() {});
        }
      });
    } catch (e) {
      if (mounted) await showProblemDialog(context, _micFailed(e));
    }
  }

  Future<void> _stopRecord() async {
    _tick?.cancel();
    setState(() => _recStart = null);
    try {
      final path = await _rec.stop();
      if (path == null) return;
      final bytes = await XFile(path).readAsBytes();
      if (!kIsWeb) await File(path).delete().catchError((_) => File(path));
      final name = '${n.id}_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await noteStore.addFile(widget.object.id, name, bytes);
      setState(() {
        _audios.add(name);
        _added.add(name);
      });
    } catch (e) {
      if (mounted) await showProblemDialog(context, _micFailed(e));
    }
  }

  /// Рядки штампу: де, що, коли й координати — фото зрозуміле й без програми.
  List<String> _stampLines(bool after, DateTime when) {
    final o = widget.object;
    final to = parseStationInput(_to.text);
    return [
      [
        formatStation(n.station, o.style),
        if (_linear && to != null) '– ${formatStation(to, o.style)}',
        '· ${t('{n} м {side}', {'n': n.offset.abs().toStringAsFixed(1), 'side': sideText(n.offset)})} · ${o.name}',
      ].join(' '),
      [
        t(_kind.label),
        if (_isDefect && _status != null) t(_status!.label).toLowerCase(),
        if (_isDefect) after ? t('ПІСЛЯ УСУНЕННЯ') : t('ДО'),
        if (_sample.text.trim().isNotEmpty) t('Проба № {n}', {'n': _sample.text.trim()}),
        if (_author.text.trim().isNotEmpty) _author.text.trim(),
      ].join(' · '),
      '${stampText(when)} · ${n.lat.toStringAsFixed(6)}, ${n.lon.toStringAsFixed(6)} · '
          '${crsName(o.crs)}: E ${n.east.toStringAsFixed(1)}  N ${n.north.toStringAsFixed(1)} · '
          '${n.accuracy == null ? t('точка на карті') : t('GPS ±{n} м', {'n': n.accuracy!.toStringAsFixed(0)})}',
    ];
  }

  /// Кілька фото на позначку: з галереї — вибрати одразу кілька; камера — після кожного знімка відкривається знову,
  /// доки її не закрили («назад»).
  Future<void> _addPhoto(ImageSource source, {bool after = false}) async {
    final picker = ImagePicker();
    try {
      if (source == ImageSource.gallery) {
        final xs = await picker.pickMultiImage(maxWidth: 2048, maxHeight: 2048, imageQuality: 82);
        for (final x in xs) {
          if (!mounted) return;
          await _savePhoto(x, after);
        }
      } else {
        while (mounted) {
          final x = await picker.pickImage(source: source, maxWidth: 2048, maxHeight: 2048, imageQuality: 82);
          if (x == null) break;
          await _savePhoto(x, after);
        }
      }
    } catch (e) {
      if (mounted) {
        await showProblemDialog(
            context,
            Problem(Severity.error, source == ImageSource.camera ? 'Камера недоступна' : 'Фото не вибралося',
                detail: '$e',
                fixes: const [
                  'Дозвольте програмі камеру: Налаштування → Програми → ROAD-GPS → Дозволи → Камера.',
                  'Або зробіть фото звичайною камерою й додайте його кнопкою «З галереї».',
                ]));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _savePhoto(XFile x, bool after) async {
    setState(() => _busy = true);
    final now = DateTime.now();
    var bytes = await x.readAsBytes();
    var stampFailed = false;
    if (settings.stampPhotos) {
      try {
        bytes = await stampPhoto(bytes, _stampLines(after, now));
      } catch (_) {
        stampFailed = true; // фото важливіше за штамп — зберігаємо як є
      }
    }
    // Кілька фото за ту саму мілісекунду (з галереї) — різні назви.
    var name = '${n.id}_${now.millisecondsSinceEpoch}.jpg';
    for (var i = 2; _photos.contains(name) || _after.contains(name); i++) {
      name = '${n.id}_${now.millisecondsSinceEpoch}_$i.jpg';
    }
    await noteStore.addFile(widget.object.id, name, bytes);
    if (!mounted) return;
    setState(() {
      (after ? _after : _photos).add(name);
      _added.add(name);
      _busy = false;
    });
    if (stampFailed) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: T('Штамп на це фото нанести не вдалося — фото збережено без нього.')));
    }
  }

  void _setStatus(NoteStatus s) => setState(() {
        _status = s;
        _fixedAt = s == NoteStatus.fixed ? (_fixedAt ?? DateTime.now()) : null;
      });

  void _setKind(NoteKind k) => setState(() {
        _kind = k;
        if (k == NoteKind.defect) _status ??= NoteStatus.open;
      });

  void _hereAsEnd() {
    final s = widget.hereStation?.call();
    if (s == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: T('Місце зараз невідоме: на екрані об’єкта немає GPS чи вибраної точки. Впишіть ПК кінця.')));
      return;
    }
    setState(() => _to.text = formatStation(s, widget.object.style));
  }

  /// Записати позначку; false — щось не так (уже показано).
  Future<bool> _persist() async {
    if (_recStart != null) await _stopRecord();
    double? to;
    if (_linear) {
      to = parseStationInput(_to.text);
      if (to == null || (to - n.station).abs() < 0.5) {
        if (mounted) {
          await showProblemDialog(
              context,
              Problem(Severity.error, 'Не зрозумів ПК кінця ділянки', detail: '«${_to.text}»',
                  fixes: [
                    t('Впишіть, як на кресленні: {a} — або метри: {b}.', {
                      'a': formatStation(n.station + 50, widget.object.style),
                      'b': (n.station + 50).toStringAsFixed(0),
                    }),
                    'Або підійдіть до кінця ділянки й натисніть «Кінець — тут».',
                    'Позначка в одній точці — вимкніть «Ділянка».',
                  ]));
        }
        return false;
      }
    }
    final all = await noteStore.load(widget.object.id);
    final gone = n.files.toSet().difference({..._photos, ..._after, ..._audios});
    n
      ..text = _text.text.trim()
      ..kind = _kind
      ..status = _isDefect ? (_status ?? NoteStatus.open) : null
      ..fixedAt = _isDefect && _status == NoteStatus.fixed ? _fixedAt : null
      ..toStation = to
      ..author = _author.text.trim()
      ..sampleNo = _sample.text.trim().isEmpty ? null : _sample.text.trim()
      ..updated = DateTime.now();
    n.photos
      ..clear()
      ..addAll(_photos);
    n.photosAfter
      ..clear()
      ..addAll(_after);
    n.audios
      ..clear()
      ..addAll(_audios);
    n.audioText.removeWhere((k, _) => !_audios.contains(k));
    final i = all.indexWhere((x) => x.id == n.id);
    i >= 0 ? all[i] = n : all.add(n);
    await noteStore.saveAll(widget.object.id, all);
    for (final p in gone) {
      await noteStore.deleteFile(widget.object.id, p);
    }
    _added.clear(); // збережене вже не «сироти»
    if (n.author.isNotEmpty && n.author != settings.author) {
      settings.author = n.author;
      await saveSettings();
    }
    return true;
  }

  Future<void> _save() async {
    if (await _persist() && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _guide() async {
    if (await _persist()) widget.onGuide!(n);
  }

  Future<void> _delete() async {
    if (_recStart != null) await _stopRecord();
    if (!mounted || !await confirmDeleteNote(context, n, widget.object.style)) return;
    await deleteNote(noteStore, widget.object.id, n, alsoFiles: [..._photos, ..._after, ..._audios]);
    if (mounted) Navigator.of(context).pop(true);
  }

  /// Прибрати фото чи запис з позначки — з підтвердженням: випадковий дотик не має стирати знімок.
  Future<void> _removeFile(List<String> from, String name, String question) async {
    final ft = fileTime(name);
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(question),
        content: ft == null ? null : Text(t('Зроблено {time}.', {'time': stampText(ft)})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const T('Ні')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const T('Видалити')),
        ],
      ),
    );
    // Файл з диска прибирається при «Зберегти позначку»; вихід без збереження його повертає.
    if (yes == true) setState(() => from.remove(name));
  }

  /// Вихід без збереження — прибрати щойно зроблені фото й записи, щоб не лишались «сиротами».
  Future<void> _discard() async {
    for (final p in _added) {
      await noteStore.deleteFile(widget.object.id, p);
    }
  }

  /// Розпізнаний текст запису — в кінець опису.
  void _useText(String s) {
    final cur = _text.text.trim();
    setState(() => _text.text = cur.isEmpty ? s : '$cur\n$s');
  }

  void _useTemplate(String t) {
    final cur = _text.text.trim();
    setState(() => _text.text = cur.isEmpty ? t : '$cur, ${t[0].toLowerCase()}${t.substring(1)}');
  }

  Future<void> _saveTemplate() async {
    final t = _text.text.trim();
    if (t.isEmpty || t.length > 80) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: T('Шаблон — це короткий текст (до 80 знаків): напишіть його в «Опис» і натисніть ще раз.')));
      return;
    }
    if (settings.templates.contains(t)) return;
    setState(() => settings.templates.add(t));
    await saveSettings();
  }

  Future<void> _removeTemplate(String t) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const T('Прибрати шаблон?'),
        content: Text('«$t»'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const T('Ні')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const T('Прибрати')),
        ],
      ),
    );
    if (yes != true) return;
    setState(() => settings.templates.remove(t));
    await saveSettings();
  }

  Widget _photoBlock(String title, List<String> list, {bool after = false}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty) Text(title, style: Theme.of(context).textTheme.titleSmall),
          if (title.isNotEmpty) const SizedBox(height: 6),
          if (list.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final p in list)
                  _Thumb(objectId: widget.object.id, name: p, onRemove: () => _removeFile(list, p, t('Видалити фото?'))),
              ]),
            ),
          Wrap(spacing: 8, runSpacing: 8, children: [
            // У браузері телефона відкриває камеру; на комп'ютері — вибір файлу.
            FilledButton.tonalIcon(
                onPressed: () => _addPhoto(ImageSource.camera, after: after),
                icon: const Icon(Icons.photo_camera),
                label: const T('Сфотографувати')),
            OutlinedButton.icon(
                onPressed: () => _addPhoto(ImageSource.gallery, after: after),
                icon: const Icon(Icons.photo_library),
                label: const T('З галереї (кілька)')),
          ]),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final o = widget.object;
    final theme = Theme.of(context);
    final templates = [...?noteTemplates[o.work]?[_kind]];
    final to = parseStationInput(_to.text);
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop && result != true) _discard();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.isNew ? t('Нова позначка') : t('Позначка')),
          actions: [
            if (widget.onGuide != null && !widget.isNew)
              IconButton(tooltip: t('Вести до позначки'), icon: const Icon(Icons.navigation_outlined), onPressed: _guide),
            IconButton(tooltip: t('Видалити позначку'), icon: const Icon(Icons.delete_outline), onPressed: _delete),
          ],
        ),
        body: AbsorbPointer(
          absorbing: _busy,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Text(noteWhere(n, o.style), style: theme.textTheme.titleLarge),
            Text(
              [
                n.accuracy == null
                    ? t('точка, вибрана на карті')
                    : t('GPS ±{n} м', {'n': n.accuracy!.toStringAsFixed(0)}),
                t('записано {time}', {'time': stampText(n.created)}),
                if (n.updated != null && n.updated!.difference(n.created).inMinutes >= 1)
                  t('змінено {time}', {'time': stampText(n.updated!)}),
              ].join(' · '),
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final k in o.work.kinds)
                ChoiceChip(label: Text(t(k.label)), selected: _kind == k, onSelected: (_) => _setKind(k)),
            ]),
            // Номер проби — для лабораторії: запропоновано наступний, можна свій чи без номера.
            if (o.work == WorkType.lab || n.sampleNo != null) ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _sample,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: t('№ проби'),
                      hintText: t('без номера'),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                    onPressed: _sample.text.isEmpty ? null : () => setState(_sample.clear),
                    child: const T('Без номера')),
              ]),
            ],
            if (_isDefect) ...[
              const SizedBox(height: 12),
              T('Стан дефекту', style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              SegmentedButton<NoteStatus>(
                segments: [
                  for (final s in NoteStatus.values)
                    ButtonSegment(value: s, label: Text(t(s.label)), icon: Icon(statusIcon(s), color: statusColor(s))),
                ],
                selected: {_status ?? NoteStatus.open},
                onSelectionChanged: (s) => _setStatus(s.first),
              ),
              if (_status == NoteStatus.fixed && _fixedAt != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(t('Усунено {time}', {'time': stampText(_fixedAt!)}), style: const TextStyle(color: Colors.black54)),
                ),
            ],
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const T('Ділянка (від ПК до ПК)'),
              subtitle: Text(_linear
                  ? t('Початок — {pk}', {'pk': formatStation(n.station, o.style)}) +
                      (to != null ? t(', довжина {n} м', {'n': (to - n.station).abs().toStringAsFixed(0)}) : '')
                  : t('Позначка в одній точці')),
              value: _linear,
              onChanged: (v) => setState(() => _linear = v),
            ),
            if (_linear)
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _to,
                    readOnly: true,
                    showCursor: true,
                    onTap: () => showDigitPad(context, _to, label: t('Кінець ділянки'), onChanged: (_) => setState(() {})),
                    decoration: InputDecoration(
                      labelText: t('Кінець ділянки'),
                      hintText: formatStation(n.station + 50, o.style),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: widget.hereStation == null ? null : _hereAsEnd,
                  icon: const Icon(Icons.my_location),
                  label: const T('Кінець — тут'),
                ),
              ]),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              minLines: 3,
              maxLines: 8,
              decoration: InputDecoration(labelText: t('Опис'), border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 0, children: [
              // Готові фрази — мовою інтерфейсу (і в текст позначки йдуть нею ж); свої шаблони — як записані.
              for (final s in templates)
                ActionChip(label: Text(t(s)), visualDensity: VisualDensity.compact, onPressed: () => _useTemplate(t(s))),
              for (final s in settings.templates)
                GestureDetector(
                  onLongPress: () => _removeTemplate(s),
                  child: ActionChip(
                    avatar: const Icon(Icons.bookmark, size: 16),
                    label: Text(s),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _useTemplate(s),
                    tooltip: t('Мій шаблон; довге натискання — прибрати'),
                  ),
                ),
              ActionChip(
                avatar: const Icon(Icons.bookmark_add_outlined, size: 16),
                label: const T('Зберегти як шаблон'),
                visualDensity: VisualDensity.compact,
                onPressed: _saveTemplate,
              ),
            ]),
            const SizedBox(height: 12),
            if (_isDefect) ...[
              _photoBlock(t('Фото до усунення'), _photos),
              const SizedBox(height: 12),
              _photoBlock(t('Фото після усунення'), _after, after: true),
              if (_status == NoteStatus.fixed && _after.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: T('Додайте фото після усунення — воно піде в акт поруч із фото «до».',
                      style: TextStyle(color: Colors.orange.shade900)),
                ),
            ] else
              _photoBlock('', _photos),
            Row(children: [
              Switch(
                value: settings.stampPhotos,
                onChanged: (v) async {
                  setState(() => settings.stampPhotos = v);
                  await saveSettings();
                },
              ),
              const Expanded(child: T('Штамп на нових фото: ПК, дата, координати')),
            ]),
            const SizedBox(height: 8),
            for (final a in _audios)
              _AudioRow(
                objectId: o.id,
                name: a,
                text: widget.note.audioText[a],
                onUseText: () => _useText(widget.note.audioText[a]!),
                onRemove: () => _removeFile(_audios, a, t('Видалити голосовий запис?')),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: _recStart == null
                  ? OutlinedButton.icon(
                      onPressed: _toggleRecord, icon: const Icon(Icons.mic), label: const T('Записати голос'))
                  : FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                      onPressed: _toggleRecord,
                      icon: const Icon(Icons.stop),
                      label: Text('● ${_clock(DateTime.now().difference(_recStart!))} · ${t('Зупинити')}'),
                    ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _author,
              decoration: InputDecoration(
                labelText: t('Хто записав'),
                hintText: t('Ім’я — піде в акт і допоможе при об’єднанні позначок'),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (_busy) const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator())),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: _save, icon: const Icon(Icons.check), label: const T('Зберегти позначку')),
          ]),
        ),
      ),
    );
  }
}

String _clock(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

const micDenied = Problem(Severity.error, 'Програмі не дозволено мікрофон',
    fixes: [
      'Налаштування → Програми → ROAD-GPS → Дозволи → Мікрофон → «Дозволити під час використання».',
      'Або продиктуйте текст у поле «Опис» — мікрофоном на клавіатурі.',
    ]);

Problem _micFailed(Object e) => Problem(Severity.error, 'Голосовий запис не вдався', detail: '$e',
    fixes: const [
      'Перевірте, що мікрофон не зайнятий іншою програмою (дзвінок, диктофон).',
      'Або продиктуйте текст у поле «Опис» — мікрофоном на клавіатурі.',
    ]);

/// Голосовий запис позначки: прослухати / зупинити, прибрати.
class _AudioRow extends StatefulWidget {
  final String objectId, name;

  /// Розпізнаний текст (Whisper на комп'ютері); null — ще не розпізнано.
  final String? text;
  final VoidCallback onRemove, onUseText;
  const _AudioRow(
      {required this.objectId, required this.name, this.text, required this.onUseText, required this.onRemove});

  @override
  State<_AudioRow> createState() => _AudioRowState();
}

class _AudioRowState extends State<_AudioRow> {
  final _player = AudioPlayer();
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.stop();
      setState(() => _playing = false);
      return;
    }
    final b = await noteStore.file(widget.objectId, widget.name);
    if (b == null) return;
    try {
      await _player.play(BytesSource(b, mimeType: 'audio/mp4'));
      setState(() => _playing = true);
    } catch (e) {
      if (mounted) {
        await showProblemDialog(context, Problem(Severity.error, 'Запис не відтворюється', detail: '$e',
            fixes: const ['Перевірте гучність і спробуйте ще раз; в експорті запис лишиться файлом .m4a.']));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 6),
        child: ListTile(
          dense: true,
          leading: IconButton(
            tooltip: _playing ? t('Зупинити') : t('Прослухати'),
            icon: Icon(_playing ? Icons.stop_circle : Icons.play_circle, size: 32),
            onPressed: _toggle,
          ),
          title: const T('Голосова нотатка'),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(fileTime(widget.name) == null
                ? widget.name
                : t('записано {time}', {'time': stampText(fileTime(widget.name)!)})),
            if (widget.text != null) ...[
              const SizedBox(height: 4),
              Text('«${widget.text}»', style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.black87)),
              TextButton.icon(
                style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                onPressed: widget.onUseText,
                icon: const Icon(Icons.subdirectory_arrow_left, size: 16),
                label: const T('Додати в опис'),
              ),
            ],
          ]),
          trailing: IconButton(tooltip: t('Видалити запис'), icon: const Icon(Icons.delete_outline), onPressed: widget.onRemove),
        ),
      );
}

class _Thumb extends StatelessWidget {
  final String objectId, name;
  final VoidCallback onRemove;
  const _Thumb({required this.objectId, required this.name, required this.onRemove});

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
        future: noteStore.file(objectId, name),
        builder: (context, s) => Column(mainAxisSize: MainAxisSize.min, children: [
          Stack(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 96,
                height: 96,
                child: s.data == null
                    ? const ColoredBox(color: Color(0xFFE0E0E0))
                    : GestureDetector(
                        onTap: () => showDialog<void>(
                            context: context,
                            builder: (c) => Dialog(child: InteractiveViewer(child: Image.memory(s.data!)))),
                        child: Image.memory(s.data!, fit: BoxFit.cover, cacheWidth: 192),
                      ),
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              child: IconButton.filledTonal(
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                tooltip: t('Видалити фото'),
                icon: const Icon(Icons.delete_outline),
                onPressed: onRemove,
              ),
            ),
          ]),
          if (fileTime(name) != null)
            Text(stampText(fileTime(name)!), style: const TextStyle(fontSize: 11, color: Colors.black54)),
        ]),
      );
}

enum _Order { station, newest }

class NotesListScreen extends StatefulWidget {
  final RoadObject object;
  final double? Function()? hereStation;
  final void Function(Note)? onGuide;
  const NotesListScreen({super.key, required this.object, this.hereStation, this.onGuide});

  @override
  State<NotesListScreen> createState() => _NotesListScreenState();
}

class _NotesListScreenState extends State<NotesListScreen> {
  List<Note>? _notes;
  bool _busy = false;
  final _search = TextEditingController();
  final _kinds = <NoteKind>{};
  bool _openOnly = false;
  _Order _order = _Order.station;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final l = await noteStore.load(widget.object.id);
    if (mounted) setState(() => _notes = l);
  }

  bool get _filtering => _search.text.trim().isNotEmpty || _kinds.isNotEmpty || _openOnly;

  /// Позначки, що підходять під пошук і фільтри, у вибраному порядку.
  List<Note> get _shown {
    final o = widget.object;
    final q = _search.text.trim().toLowerCase();
    final l = [
      for (final n in _notes ?? const <Note>[])
        if ((_kinds.isEmpty || _kinds.contains(n.kind)) &&
            (!_openOnly || (n.kind == NoteKind.defect && n.status != NoteStatus.fixed)) &&
            (q.isEmpty ||
                '${n.text} ${n.author} ${noteWhere(n, o.style)} ${noteKindText(n)} ${stampText(n.created)}'
                    .toLowerCase()
                    .contains(q)))
          n,
    ];
    return l
      ..sort((a, b) =>
          _order == _Order.station ? a.station.compareTo(b.station) : b.created.compareTo(a.created));
  }

  /// Надіслати файл; [smaller] — той самий зі зменшеними фото (якщо для пошти завеликий).
  Future<void> _share(Uint8List bytes, String name, String mime, String text, Future<Uint8List> Function() smaller) =>
      sendFile(context,
          bytes: bytes, name: name, mime: mime, subject: '${widget.object.name}: $text', text: text, smaller: smaller);

  /// Фото — зменшені для пошти, решта файлів — як є.
  Future<Uint8List?> _smallFile(String name) async {
    final b = await noteStore.file(widget.object.id, name);
    return b != null && name.toLowerCase().endsWith('.jpg') ? shrinkPhoto(b) : b;
  }

  String get _today {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<bool> _haveNotes(List<Note> notes) async {
    if (notes.isNotEmpty) return true;
    await showProblemDialog(
        context,
        _filtering
            ? const Problem(Severity.info, 'За цими фільтрами позначок немає',
                fixes: ['Зніміть фільтри чи очистьте пошук — експортується те, що показано в списку.'])
            : const Problem(Severity.info, 'Позначок ще немає',
                fixes: ['На екрані об’єкта натисніть «Позначка тут» — у потрібному місці або торкнувшись карти.']));
    return false;
  }

  Future<void> _run(Future<void> Function() job, String failTitle) async {
    setState(() => _busy = true);
    try {
      await job();
    } catch (e) {
      if (mounted) {
        await showProblemDialog(context, Problem(Severity.error, failTitle, detail: '$e',
            fixes: const ['Перевірте вільне місце на пристрої й спробуйте ще раз.']));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportExcel() async {
    final o = widget.object;
    final notes = _shown;
    if (!await _haveNotes(notes)) return;
    await _run(() async {
      final zip = await exportNotesZip(o.name, o.style, crsName(o.crs), notes, (p) => noteStore.file(o.id, p));
      if (!mounted) return;
      await _share(
          zip,
          '${safeName(o.name)} позначки $_today.zip',
          'application/zip',
          t('Позначки ({n}) — розпакуйте ZIP і відкрийте .xlsx; посилання в колонках «Фото» і «Голос» '
              'відкривають файли з тек «фото» і «аудіо». Колега з ROAD-GPS може додати цей ZIP до своїх позначок.',
              {'n': notes.length}),
          () => exportNotesZip(o.name, o.style, crsName(o.crs), notes, _smallFile));
    }, 'Експорт не вдався');
  }

  Future<void> _exportAct() async {
    final o = widget.object;
    final notes = _shown..sort((a, b) => a.station.compareTo(b.station));
    if (!await _haveNotes(notes)) return;
    await _run(() async {
      final docx = await buildInspectionDocx(
          objectName: o.name, style: o.style, crsName: crsName(o.crs), notes: notes, file: (p) => noteStore.file(o.id, p));
      if (!mounted) return;
      await _share(docx, '${safeName(o.name)} акт огляду $_today.docx',
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          t('Акт огляду ({n} позначок). Відкрийте у Word, перевірте й підпишіть; PDF — «Зберегти як PDF».',
              {'n': notes.length}),
          () => buildInspectionDocx(
              objectName: o.name, style: o.style, crsName: crsName(o.crs), notes: notes, file: _smallFile));
    }, 'Акт не склався');
  }

  /// Додати позначки колеги з його експортного ZIP.
  Future<void> _merge() async {
    final o = widget.object;
    final f = await FilePicker.pickFile(dialogTitle: t('ZIP з позначками колеги'));
    if (f == null || !mounted) return;
    NotesPack? pack;
    try {
      pack = readNotesZip(await f.readAsBytes());
    } catch (e) {
      pack = null;
    }
    if (!mounted) return;
    if (pack == null) {
      await showProblemDialog(
          context,
          Problem(Severity.error, 'У файлі немає позначок ROAD-GPS', detail: f.name,
              fixes: [
                t('Потрібен ZIP, який колега зробив у ROAD-GPS кнопкою «Експорт → Excel + фото» (усередині є файл '
                    '«{f}»).', {'f': notesJsonName}),
                'Якщо колега має стару версію програми — хай оновить її й зробить експорт ще раз.',
              ]));
      return;
    }
    final mine = await noteStore.load(o.id);
    final r = mergeNotes(mine, pack.notes, o.roadAxis);
    if (!mounted) return;
    final warn = [
      if (pack.object.isNotEmpty && pack.object != o.name)
        t('Позначки зроблено в об’єкті «{a}», а відкрито «{b}».', {'a': pack.object, 'b': o.name}),
      if (r.far > 0) t('{n} позначок лежать далі 300 м від осі чи за її кінцями — можливо, це інший об’єкт.', {'n': r.far}),
    ];
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const T('Додати позначки колеги?'),
        content: Text([
          t('Нових: {a}, новіших за ваші: {b}, однакових: {c}.', {'a': r.added, 'b': r.updated, 'c': r.same}),
          t('ПК і зміщення буде перераховано за координатами на осі цього об’єкта.'),
          ...warn,
        ].join('\n\n')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const T('Скасувати')),
          FilledButton(
              onPressed: r.added + r.updated == 0 ? null : () => Navigator.pop(c, true), child: const T('Додати')),
        ],
      ),
    );
    if (yes != true) return;
    await _run(() async {
      var missing = 0;
      for (final n in r.taken) {
        for (final name in n.files) {
          final b = pack!.files[name];
          b == null ? missing++ : await noteStore.addFile(o.id, name, b);
        }
      }
      await noteStore.saveAll(o.id, r.notes);
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${t('Додано {a}, оновлено {b}', {'a': r.added, 'b': r.updated})}'
                '${missing > 0 ? t('; {n} фото чи записів у ZIP не було', {'n': missing}) : ''}.')));
      }
    }, 'Об’єднати не вдалося');
  }

  /// За скільки метрів до неусуненої позначки вібрувати (на екрані об'єкта, за GPS).
  Future<void> _chooseNear() async {
    final v = await showDialog<int>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const T('Вібрація біля позначки'),
        children: [
          for (final m in const [0, 10, 20, 50, 100])
            ListTile(
              leading: Icon(settings.nearNote == m ? Icons.radio_button_checked : Icons.radio_button_unchecked),
              title: Text(m == 0 ? t('Не вібрувати') : t('ближче за {m} м', {'m': m})),
              onTap: () => Navigator.pop(c, m),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: T('Лише неусунені позначки й лише за GPS, коли відкрито екран об’єкта. Один раз на підхід — '
                'знову, коли відійдете вдвічі далі.',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
          ),
        ],
      ),
    );
    if (v == null) return;
    setState(() => settings.nearNote = v);
    await saveSettings();
  }

  Future<void> _open(Note n) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => NoteEditScreen(
            object: widget.object, note: n, hereStation: widget.hereStation, onGuide: widget.onGuide)));
    if (changed == true) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.object;
    final all = _notes;
    final l = _shown;
    return Scaffold(
      appBar: AppBar(
        title: Text(t('Позначки: {name}', {'name': o.name})),
        actions: [
          IconButton(
            tooltip: t('Вібрація біля позначки'),
            icon: Icon(settings.nearNote > 0 ? Icons.vibration : Icons.mobile_off),
            onPressed: _chooseNear,
          ),
          PopupMenuButton<String>(
            tooltip: t('Експорт і об’єднання'),
            icon: const Icon(Icons.ios_share),
            enabled: !_busy,
            onSelected: (v) => switch (v) {
              'xlsx' => _exportExcel(),
              'act' => _exportAct(),
              _ => _merge(),
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'xlsx',
                child: ListTile(
                  leading: const Icon(Icons.table_chart_outlined),
                  title: const T('Excel + фото й голос (ZIP)'),
                  subtitle: Text(_filtering ? t('лише показані в списку ({n})', {'n': l.length}) : t('усі позначки')),
                ),
              ),
              PopupMenuItem(
                value: 'act',
                child: ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const T('Акт огляду (Word)'),
                  subtitle: Text(
                      _filtering ? t('лише показані в списку ({n})', {'n': l.length}) : t('з фотофіксацією «до / після»')),
                ),
              ),
              const PopupMenuItem(
                value: 'merge',
                child: ListTile(
                  leading: Icon(Icons.merge_type),
                  title: T('Додати позначки колеги…'),
                  subtitle: T('з його ZIP-експорту'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: all == null || _busy
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: t('Пошук: текст, ПК, ім’я, дата'),
                    isDense: true,
                    border: const OutlineInputBorder(),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear), onPressed: () => setState(() => _search.clear())),
                  ),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(children: [
                  FilterChip(
                    label: const T('Неусунені дефекти'),
                    selected: _openOnly,
                    onSelected: (v) => setState(() => _openOnly = v),
                  ),
                  const SizedBox(width: 6),
                  for (final k in o.work.kinds) ...[
                    FilterChip(
                      label: Text(t(k.label)),
                      selected: _kinds.contains(k),
                      onSelected: (v) => setState(() => v ? _kinds.add(k) : _kinds.remove(k)),
                    ),
                    const SizedBox(width: 6),
                  ],
                  const SizedBox(width: 6),
                  SegmentedButton<_Order>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: _Order.station, label: T('За ПК')),
                      ButtonSegment(value: _Order.newest, label: T('Нові')),
                    ],
                    selected: {_order},
                    onSelectionChanged: (s) => setState(() => _order = s.first),
                  ),
                ]),
              ),
              if (_filtering)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(t('Показано {a} з {b}', {'a': l.length, 'b': all.length}), style: const TextStyle(color: Colors.black54)),
                  ),
                ),
              Expanded(
                child: all.isEmpty
                    ? const Center(
                        child: Padding(
                        padding: EdgeInsets.all(24),
                        child: T('Позначок ще немає.\nНа екрані об’єкта — кнопка «Позначка тут».',
                            textAlign: TextAlign.center, style: TextStyle(fontSize: 16)),
                      ))
                    : ListView(children: [
                        for (final n in l)
                          ListTile(
                            leading: Icon(n.status == null ? Icons.place : statusIcon(n.status!), color: noteColor(n)),
                            title: Text(noteWhere(n, o.style)),
                            subtitle: Text([
                              stampText(n.created),
                              noteKindText(n),
                              if (n.sampleNo != null) t('Проба № {n}', {'n': n.sampleNo!}),
                              if (n.toStation != null) t('{n} м', {'n': n.length.toStringAsFixed(0)}),
                              if (n.text.isNotEmpty) n.text,
                              if (n.photos.isNotEmpty) t('фото: {n}', {'n': n.photos.length}),
                              if (n.photosAfter.isNotEmpty) t('після: {n}', {'n': n.photosAfter.length}),
                              if (n.audios.isNotEmpty) t('голос: {n}', {'n': n.audios.length}),
                              if (n.author.isNotEmpty) n.author,
                            ].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              if (widget.onGuide != null)
                                IconButton(
                                  tooltip: t('Вести до позначки'),
                                  icon: const Icon(Icons.navigation_outlined),
                                  onPressed: () => widget.onGuide!(n),
                                ),
                              IconButton(
                                tooltip: t('Видалити позначку'),
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () async {
                                  if (!await confirmDeleteNote(context, n, o.style)) return;
                                  await deleteNote(noteStore, o.id, n);
                                  await _reload();
                                },
                              ),
                            ]),
                            onTap: () => _open(n),
                          ),
                      ]),
              ),
            ]),
    );
  }
}

Future<bool> confirmDeleteNote(BuildContext context, Note n, ChainageStyle style) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const T('Видалити позначку?'),
        content: Text(t('{where}, записано {time}.\nЇї фото й голосові записи теж зникнуть з пристрою.',
            {'where': noteWhere(n, style), 'time': stampText(n.created)})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const T('Ні')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const T('Видалити')),
        ],
      ),
    ) ==
    true;

Color kindColor(NoteKind k) => switch (k) {
      NoteKind.defect => const Color(0xFFD32F2F),
      NoteKind.remark => const Color(0xFFEF6C00),
      NoteKind.done => const Color(0xFF2E7D32),
      NoteKind.measure => const Color(0xFF1565C0),
      NoteKind.sample => const Color(0xFF6A1B9A),
      NoteKind.test => const Color(0xFF00838F),
      NoteKind.other => const Color(0xFF616161),
    };

Color statusColor(NoteStatus s) => switch (s) {
      NoteStatus.open => const Color(0xFFD32F2F),
      NoteStatus.inWork => const Color(0xFFF9A825),
      NoteStatus.fixed => const Color(0xFF2E7D32),
    };

IconData statusIcon(NoteStatus s) => switch (s) {
      NoteStatus.open => Icons.report,
      NoteStatus.inWork => Icons.construction,
      NoteStatus.fixed => Icons.check_circle,
    };

/// Колір позначки на карті й у списку: дефект — за станом, решта — за типом.
Color noteColor(Note n) => n.status != null ? statusColor(n.status!) : kindColor(n.kind);
