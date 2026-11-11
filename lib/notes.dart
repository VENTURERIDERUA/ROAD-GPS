// Позначки на трасі: ПК, зміщення, координати, текст і фото — і експорт: Excel + тека фото в одному ZIP.
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'chainage.dart';
import 'geometry.dart';
import 'i18n.dart';

enum NoteKind {
  remark('Зауваження'),
  defect('Дефект'),
  done('Виконано'),
  measure('Замір'),
  sample('Відбір зразка'),
  test('Випробування'),
  other('Інше');

  final String label;
  const NoteKind(this.label);
}

/// Стан дефекту: від виявлення до усунення.
enum NoteStatus {
  open('Відкрито'),
  inWork('В роботі'),
  fixed('Усунено');

  final String label;
  const NoteStatus(this.label);
}

/// Вид робіт на об'єкті: від нього — готові фрази, порядок типів позначок і тип нової позначки.
enum WorkType {
  construction('Нове будівництво'),
  repair('Ремонт'),
  lab('Лабораторія');

  final String label;
  const WorkType(this.label);

  /// Типи позначок у порядку вибору; перший — тип нової позначки.
  List<NoteKind> get kinds => switch (this) {
        repair => const [NoteKind.defect, NoteKind.done, NoteKind.measure, NoteKind.remark, NoteKind.other],
        construction => const [NoteKind.remark, NoteKind.done, NoteKind.defect, NoteKind.measure, NoteKind.other],
        lab => const [NoteKind.sample, NoteKind.test, NoteKind.measure, NoteKind.remark, NoteKind.other],
      };
}

/// Готові фрази для опису за видом робіт — торкання дописує фразу в текст.
const noteTemplates = <WorkType, Map<NoteKind, List<String>>>{
  WorkType.construction: {
    NoteKind.remark: [
      'Перевірити', 'Уточнити в проєкті', 'Узгодити з технаглядом', 'Потрібна виконавча зйомка',
      'Повідомити проєктувальника', 'Сфотографувати після',
    ],
    NoteKind.done: [
      'Виконано згідно з проєктом', 'Прийнято технаглядом', 'Влаштовано земляне полотно', 'Влаштовано шар основи',
      'Влаштовано нижній шар покриття', 'Влаштовано верхній шар покриття', 'Встановлено бордюр',
      'Влаштовано водовідвід', 'Укріплено укоси', 'Нанесено розмітку', 'Встановлено знак', 'Встановлено огородження',
    ],
    NoteKind.defect: [
      'Відмітка не відповідає проєкту', 'Ширина не відповідає проєкту', 'Товщина шару менша за проєктну',
      'Недостатнє ущільнення', 'Нерівність покриття', 'Порушено поперечний ухил', 'Застій води',
      'Пошкоджено бордюр', 'Розмив укосу', 'Не прибрано матеріали чи сміття',
    ],
    NoteKind.measure: [
      'Відмітка', 'Ширина проїзної частини', 'Товщина шару', 'Поперечний ухил', 'Поздовжній ухил',
      'Просвіт під рейкою 3 м', 'Коефіцієнт ущільнення',
    ],
    NoteKind.other: [],
  },
  WorkType.repair: {
    NoteKind.defect: [
      'Вибоїна', 'Сітка тріщин', 'Поздовжня тріщина', 'Поперечна тріщина', 'Колійність', 'Просідання',
      'Відшарування покриття', 'Вибивання', 'Застій води', 'Пошкоджено бордюр', 'Пошкоджено огородження',
      'Немає розмітки', 'Знак відсутній', 'Засмічено водовідвід', 'Розмив узбіччя',
    ],
    NoteKind.done: [
      'Ямковий ремонт', 'Заливка тріщин', 'Фрезерування', 'Укладено покриття', 'Відновлено узбіччя',
      'Очищено водовідвід', 'Нанесено розмітку', 'Встановлено знак', 'Відремонтовано огородження', 'Прийнято',
    ],
    NoteKind.measure: [
      'Площа ремонту', 'Довжина', 'Ширина', 'Глибина вибоїни', 'Глибина колії', 'Товщина шару',
    ],
    NoteKind.remark: [
      'Перевірити', 'Включити до відомості обсягів', 'Потрібне обмеження руху', 'Повідомити замовника',
      'Сфотографувати після',
    ],
    NoteKind.other: [],
  },
  // Лабораторія: зразки й випробування на дорозі — місце (ПК, зміщення, координати), дата й час — у позначці й на фото.
  WorkType.lab: {
    NoteKind.sample: [
      'Відбір керна з покриття', 'Відбір проби асфальтобетонної суміші з-під укладальника',
      'Відбір проби асфальтобетонної суміші з кузова', 'Відбір проби щебеню', 'Відбір проби піщано-гравійної суміші',
      'Відбір проби піску', 'Відбір проби ґрунту', 'Відбір проби бетонної суміші', 'Виготовлено зразки-куби бетону',
      'Відбір проби бітуму', 'Відбір проби бітумної емульсії', 'Зразок передано до лабораторії',
    ],
    NoteKind.test: [
      'Щільність і вологість ґрунту (ріжуче кільце)', 'Коефіцієнт ущільнення', 'Модуль пружності штампом',
      'Динамічний штамп (модуль деформації)', 'Прогин (балка Бенкельмана)', 'Рівність рейкою 3 м',
      'Шорсткість (піщана пляма)', 'Міцність бетону склерометром', 'Зчеплення шарів', 'Товщина шару за керном',
      'Температура суміші при укладанні', 'Температура повітря й основи',
    ],
    NoteKind.measure: [
      'Товщина шару', 'Температура суміші', 'Температура повітря', 'Вологість', 'Просвіт під рейкою 3 м',
      'Поперечний ухил', 'Глибина колії',
    ],
    NoteKind.remark: [
      'Відповідає нормам', 'Не відповідає нормам — повідомити технагляд', 'Повторити випробування',
      'Результат — після лабораторних випробувань', 'Сфотографувати після',
    ],
    NoteKind.other: [],
  },
};

class Note {
  final String id;
  final DateTime created;
  NoteKind kind;
  String text;

  /// Де: ПК (м), зміщення від осі (м, «+» праворуч), WGS84 і координати креслення (E, N).
  final double station, offset, lat, lon, east, north;

  /// Точність GPS, м; null — точку вибрано на карті.
  final double? accuracy;

  /// Імена файлів фото й голосових записів у теці позначок об'єкта; photosAfter — фото після усунення.
  final List<String> photos;
  final List<String> photosAfter;
  final List<String> audios;

  /// Текст голосових записів (файл → текст) — розпізнає Whisper на комп'ютері.
  final Map<String, String> audioText;

  /// Стан дефекту (для інших типів — null) і коли усунено.
  NoteStatus? status;
  DateTime? fixedAt;

  /// Позначка-ділянка: кінцевий ПК (null — позначка в точці).
  double? toStation;

  /// Хто записав (ім'я з налаштувань) і коли востаннє змінено — для об'єднання позначок кількох людей.
  String author;
  DateTime? updated;

  /// Номер проби (лабораторія): програма пропонує наступний ([nextSampleNo]), людина може вписати свій чи
  /// відмовитись (null — без номера).
  String? sampleNo;

  Note({
    required this.id,
    required this.created,
    required this.kind,
    required this.text,
    required this.station,
    required this.offset,
    required this.lat,
    required this.lon,
    required this.east,
    required this.north,
    this.accuracy,
    List<String>? photos,
    List<String>? photosAfter,
    List<String>? audios,
    Map<String, String>? audioText,
    this.status,
    this.fixedAt,
    this.toStation,
    this.author = '',
    this.updated,
    this.sampleNo,
  })  : photos = photos ?? [],
        photosAfter = photosAfter ?? [],
        audios = audios ?? [],
        audioText = audioText ?? {};

  /// Усі файли позначки.
  Iterable<String> get files => [...photos, ...photosAfter, ...audios];

  /// Довжина ділянки, м (0 — точка).
  double get length => toStation == null ? 0 : (toStation! - station).abs();

  Note copyAt(double station, double offset) => Note(
        id: id, created: created, kind: kind, text: text, station: station, offset: offset, lat: lat, lon: lon,
        east: east, north: north, accuracy: accuracy, photos: [...photos], photosAfter: [...photosAfter],
        audios: [...audios], audioText: {...audioText}, status: status, fixedAt: fixedAt,
        toStation: toStation == null ? null : toStation! + station - this.station, author: author, updated: updated,
        sampleNo: sampleNo,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'created': created.toIso8601String(),
        'kind': kind.name,
        'text': text,
        'at': [station, offset, lat, lon, east, north],
        'accuracy': ?accuracy,
        'photos': photos,
        'photosAfter': photosAfter,
        'audios': audios,
        if (audioText.isNotEmpty) 'audioText': audioText,
        'status': ?status?.name,
        'fixedAt': ?fixedAt?.toIso8601String(),
        'toStation': ?toStation,
        'author': author,
        'updated': ?updated?.toIso8601String(),
        'sample': ?sampleNo,
      };

  factory Note.fromJson(Map<String, dynamic> j) {
    final a = [for (final v in j['at'] as List) (v as num).toDouble()];
    return Note(
      id: j['id'] as String,
      created: DateTime.parse(j['created'] as String),
      kind: NoteKind.values.byName(j['kind'] as String),
      text: j['text'] as String? ?? '',
      station: a[0],
      offset: a[1],
      lat: a[2],
      lon: a[3],
      east: a[4],
      north: a[5],
      accuracy: (j['accuracy'] as num?)?.toDouble(),
      photos: [for (final p in j['photos'] as List? ?? const []) p as String],
      photosAfter: [for (final p in j['photosAfter'] as List? ?? const []) p as String],
      audios: [for (final p in j['audios'] as List? ?? const []) p as String],
      audioText: {
        for (final e in (j['audioText'] as Map<String, dynamic>? ?? const {}).entries) e.key: e.value as String
      },
      status: j['status'] == null ? null : NoteStatus.values.byName(j['status'] as String),
      fixedAt: j['fixedAt'] == null ? null : DateTime.parse(j['fixedAt'] as String),
      toStation: (j['toStation'] as num?)?.toDouble(),
      author: j['author'] as String? ?? '',
      updated: j['updated'] == null ? null : DateTime.parse(j['updated'] as String),
      sampleNo: j['sample'] as String?,
    );
  }
}

/// Наступний номер проби об'єкта: за останньою пронумерованою позначкою — число в кінці на одиницю більше, решта
/// як була («7» → «8», «К-12» → «К-13», «П/09» → «П/10»); номерів ще немає — «1».
String nextSampleNo(List<Note> notes) {
  final withNo = [for (final n in notes) if (n.sampleNo != null && n.sampleNo!.trim().isNotEmpty) n]
    ..sort((a, b) => a.created.compareTo(b.created));
  if (withNo.isEmpty) return '1';
  final last = withNo.last.sampleNo!.trim();
  final m = RegExp(r'^(.*?)(\d+)$').firstMatch(last);
  if (m == null) return '$last-2';
  final digits = m[2]!;
  final next = (int.parse(digits) + 1).toString().padLeft(digits.length, '0');
  return '${m[1]}$next';
}

String sideText(double offset) =>
    offset.abs() < 0.05 ? t('на осі') : (offset > 0 ? t('праворуч') : t('ліворуч'));

/// «27.10.2026 14:05» — як дату й час показує екран.
String stampText(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.day)}.${two(t.month)}.${t.year} ${two(t.hour)}:${two(t.minute)}';
}

/// Коли зроблено фото чи запис: програма дає файлам імена «<позначка>_<мілісекунди>.jpg / .m4a».
DateTime? fileTime(String name) {
  final m = RegExp(r'_(\d{12,14})\.\w+$').firstMatch(name);
  return m == null ? null : DateTime.fromMillisecondsSinceEpoch(int.parse(m.group(1)!));
}

/// Видалити позначку разом з її фото й записами.
Future<void> deleteNote(NoteStore store, String objectId, Note n, {Iterable<String> alsoFiles = const []}) async {
  final all = await store.load(objectId)..removeWhere((x) => x.id == n.id);
  await store.saveAll(objectId, all);
  for (final p in {...n.files, ...alsoFiles}) {
    await store.deleteFile(objectId, p);
  }
}

/// Позначки об'єкта — JSON-файл і тека фото в пам'яті програми; у браузері — у пам'яті сторінки.
class NoteStore {
  final Directory? dir;
  NoteStore({this.dir});

  final Map<String, List<Note>> _web = {};
  final Map<String, Uint8List> _webPhotos = {};
  bool get _memory => kIsWeb && dir == null;

  Future<Directory> _folder(String objectId) async {
    final base = dir ?? Directory('${(await getApplicationDocumentsDirectory()).path}/notes');
    final d = Directory('${base.path}/$objectId');
    await d.create(recursive: true);
    return d;
  }

  Future<List<Note>> load(String objectId) async {
    if (_memory) return [...?_web[objectId]];
    final f = File('${(await _folder(objectId)).path}/notes.json');
    if (!await f.exists()) return [];
    return [for (final j in jsonDecode(await f.readAsString()) as List) Note.fromJson(j as Map<String, dynamic>)];
  }

  Future<void> saveAll(String objectId, List<Note> notes) async {
    if (_memory) {
      _web[objectId] = [...notes];
      return;
    }
    final d = await _folder(objectId);
    final tmp = File('${d.path}/notes.json.tmp');
    await tmp.writeAsString(jsonEncode([for (final n in notes) n.toJson()]));
    await tmp.rename('${d.path}/notes.json');
  }

  /// Файл позначки (фото чи голосовий запис).
  Future<String> addFile(String objectId, String name, Uint8List bytes) async {
    if (_memory) {
      _webPhotos['$objectId/$name'] = bytes;
      return name;
    }
    await File('${(await _folder(objectId)).path}/$name').writeAsBytes(bytes);
    return name;
  }

  Future<Uint8List?> file(String objectId, String name) async {
    if (_memory) return _webPhotos['$objectId/$name'];
    final f = File('${(await _folder(objectId)).path}/$name');
    return await f.exists() ? f.readAsBytes() : null;
  }

  /// Усі позначки й фото об'єкта (коли видаляють сам об'єкт).
  Future<void> deleteAll(String objectId) async {
    if (_memory) {
      _web.remove(objectId);
      _webPhotos.removeWhere((k, _) => k.startsWith('$objectId/'));
      return;
    }
    final d = await _folder(objectId);
    if (await d.exists()) await d.delete(recursive: true);
  }

  Future<void> deleteFile(String objectId, String name) async {
    if (_memory) {
      _webPhotos.remove('$objectId/$name');
      return;
    }
    final f = File('${(await _folder(objectId)).path}/$name');
    if (await f.exists()) await f.delete();
  }
}

final noteStore = NoteStore();

// ---------- Excel (.xlsx) без сторонніх бібліотек: це ZIP з кількома XML ----------

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

String _col(int i) {
  var n = i + 1, s = '';
  while (n > 0) {
    final r = (n - 1) % 26;
    s = String.fromCharCode(65 + r) + s;
    n = (n - 1) ~/ 26;
  }
  return s;
}

/// Клітинка: текст, число або посилання (формула HYPERLINK — відкриває фото з теки поруч).
sealed class Cell {
  const Cell();
}

class Txt extends Cell {
  final String v;
  const Txt(this.v);
}

class Num extends Cell {
  final double v;
  final int digits;
  const Num(this.v, [this.digits = 2]);
}

class Link extends Cell {
  final String target, label;
  const Link(this.target, this.label);
}

/// Книга з одним аркушем: заголовок жирним і закріплений, ширини колонок.
Uint8List buildXlsx(String sheetName, List<String> header, List<List<Cell?>> rows, List<double> widths) {
  final sheet = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">')
    ..write('<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>')
    ..write('<cols>');
  for (var i = 0; i < widths.length; i++) {
    sheet.write('<col min="${i + 1}" max="${i + 1}" width="${widths[i]}" customWidth="1"/>');
  }
  sheet.write('</cols><sheetData>');
  void row(int r, List<Cell?> cells, {bool head = false}) {
    sheet.write('<row r="$r">');
    for (var c = 0; c < cells.length; c++) {
      final ref = '${_col(c)}$r';
      final style = head ? ' s="1"' : '';
      switch (cells[c]) {
        case Txt(:final v):
          sheet.write('<c r="$ref" t="inlineStr"$style><is><t xml:space="preserve">${_esc(v)}</t></is></c>');
        case Num(:final v, :final digits):
          // 0 знаків — загальний формат, 2 — «0.00», більше — «0.0000000» (широта й довгота).
          final s = digits == 0 ? '' : ' s="${digits == 2 ? 2 : 3}"';
          sheet.write('<c r="$ref"$s><v>$v</v></c>');
        case Link(:final target, :final label):
          sheet.write('<c r="$ref" t="str" s="4"><f>HYPERLINK("${_esc(target.replaceAll('"', ''))}","${_esc(label.replaceAll('"', ''))}")</f>'
              '<v>${_esc(label)}</v></c>');
        case null:
          break;
      }
    }
    sheet.write('</row>');
  }

  row(1, [for (final h in header) Txt(h)], head: true);
  for (var i = 0; i < rows.length; i++) {
    row(i + 2, rows[i]);
  }
  sheet.write('</sheetData></worksheet>');

  const styles = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<numFmts count="2"><numFmt numFmtId="164" formatCode="0.00"/><numFmt numFmtId="165" formatCode="0.0000000"/></numFmts>'
      '<fonts count="3"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font>'
      '<font><u/><sz val="11"/><color rgb="FF0563C1"/><name val="Calibri"/></font></fonts>'
      '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>'
      '<borders count="1"><border/></borders><cellStyleXfs count="1"><xf/></cellStyleXfs>'
      '<cellXfs count="5"><xf/><xf fontId="1" applyFont="1"/><xf numFmtId="164" applyNumberFormat="1"/>'
      '<xf numFmtId="165" applyNumberFormat="1"/><xf fontId="2" applyFont="1"/></cellXfs></styleSheet>';
  final files = <String, String>{
    '[Content_Types].xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '</Types>',
    '_rels/.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>',
    'xl/workbook.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets><sheet name="${_esc(sheetName)}" sheetId="1" r:id="rId1"/></sheets></workbook>',
    'xl/_rels/workbook.xml.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '</Relationships>',
    'xl/worksheets/sheet1.xml': sheet.toString(),
    'xl/styles.xml': styles,
  };
  final a = Archive();
  for (final e in files.entries) {
    final b = utf8.encode(e.value);
    a.addFile(ArchiveFile(e.key, b.length, b));
  }
  return Uint8List.fromList(ZipEncoder().encode(a));
}

/// Імена листа й файлу без символів, які не люблять Excel і Windows.
String safeName(String s) => s.replaceAll(RegExp(r'[\\/:*?"<>|\[\]]'), '_').trim();

/// Позначки для програми в експортному ZIP.
const notesJsonName = 'позначки.road-gps.json';

/// Експорт: «позначки.xlsx», тека «фото» і тека «аудіо» — в одному ZIP. Розпакуйте й відкрийте xlsx: посилання
/// ведуть на фото й записи.
Future<Uint8List> exportNotesZip(String objectName, ChainageStyle style, String crsName, List<Note> notes,
    Future<Uint8List?> Function(String name) file) async {
  final sorted = [...notes]..sort((a, b) => a.station.compareTo(b.station));
  final maxPhotos = sorted.fold(0, (m, n) => n.photos.length > m ? n.photos.length : m);
  final maxAfter = sorted.fold(0, (m, n) => n.photosAfter.length > m ? n.photosAfter.length : m);
  final maxAudios = sorted.fold(0, (m, n) => n.audios.length > m ? n.audios.length : m);
  final voiceText = sorted.any((n) => n.audioText.isNotEmpty);
  final samples = sorted.any((n) => n.sampleNo != null);
  String two(int v) => v.toString().padLeft(2, '0');
  String time(DateTime t) => '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  final header = [
    t('№'), t('ПК'), t('ПК, м'), t('Зміщення, м'), t('Сторона'), t('До ПК'), t('Довжина, м'), t('Тип'), //
    if (samples) t('№ проби'),
    t('Стан'),
    t('Усунено'), t('Опис'), t('Дата й час'), t('Хто записав'), t('Точність GPS, м'), t('Широта'), t('Довгота'),
    'E ($crsName)', 'N ($crsName)',
    for (var i = 0; i < maxPhotos; i++) t('Фото {n}', {'n': i + 1}),
    for (var i = 0; i < maxAfter; i++) t('Фото після {n}', {'n': i + 1}),
    for (var i = 0; i < maxAudios; i++) t('Голос {n}', {'n': i + 1}),
    if (voiceText) t('Голос — текст'),
  ];
  final rows = <List<Cell?>>[
    for (var i = 0; i < sorted.length; i++)
      [
        Num(i + 1.0, 0),
        Txt(formatStation(sorted[i].station, style)),
        Num(sorted[i].station),
        Num(sorted[i].offset),
        Txt(sideText(sorted[i].offset)),
        sorted[i].toStation == null ? null : Txt(formatStation(sorted[i].toStation!, style)),
        sorted[i].toStation == null ? null : Num(sorted[i].length, 0),
        Txt(t(sorted[i].kind.label)),
        if (samples) sorted[i].sampleNo == null ? null : Txt(sorted[i].sampleNo!),
        sorted[i].status == null ? null : Txt(t(sorted[i].status!.label)),
        sorted[i].fixedAt == null ? null : Txt(time(sorted[i].fixedAt!)),
        Txt(sorted[i].text),
        Txt(time(sorted[i].created)),
        Txt(sorted[i].author),
        sorted[i].accuracy == null ? Txt(t('точка на карті')) : Num(sorted[i].accuracy!, 0),
        Num(sorted[i].lat, 7),
        Num(sorted[i].lon, 7),
        Num(sorted[i].east),
        Num(sorted[i].north),
        for (final p in sorted[i].photos) Link('фото/$p', p),
        for (var k = sorted[i].photos.length; k < maxPhotos; k++) null,
        for (final p in sorted[i].photosAfter) Link('фото/$p', p),
        for (var k = sorted[i].photosAfter.length; k < maxAfter; k++) null,
        for (final a in sorted[i].audios) Link('аудіо/$a', a),
        if (voiceText) ...[
          for (var k = sorted[i].audios.length; k < maxAudios; k++) null,
          Txt([for (final a in sorted[i].audios) ?sorted[i].audioText[a]].join('\n')),
        ],
      ],
  ];
  final widths = <double>[
    5, 14, 10, 13, 10, 14, 12, 12, if (samples) 10, 11, 17, 50, 17, 16, 16, 12, 12, 22, 22, //
    for (var i = 0; i < maxPhotos + maxAfter + maxAudios; i++) 22,
    if (voiceText) 60,
  ];
  final xlsx = buildXlsx(t('Позначки'), header, rows, widths);
  final zip = Archive()..addFile(ArchiveFile('${safeName(objectName)} — позначки.xlsx', xlsx.length, xlsx));
  // Для програми: ці ж позначки, щоб інший пристрій міг додати їх до своїх («Об'єднати»).
  final json = utf8.encode(jsonEncode({
    'object': objectName,
    'crs': crsName,
    'notes': [for (final n in sorted) n.toJson()],
  }));
  zip.addFile(ArchiveFile(notesJsonName, json.length, json));
  for (final n in sorted) {
    for (final p in [...n.photos, ...n.photosAfter]) {
      final b = await file(p);
      if (b != null) zip.addFile(ArchiveFile('фото/$p', b.length, b));
    }
    for (final a in n.audios) {
      final b = await file(a);
      if (b != null) zip.addFile(ArchiveFile('аудіо/$a', b.length, b));
    }
  }
  return Uint8List.fromList(ZipEncoder().encode(zip));
}

// ---------- Об'єднання позначок кількох людей ----------

/// Що лежить в експортному ZIP: назва об'єкта, позначки й їхні файли.
class NotesPack {
  final String object;
  final List<Note> notes;
  final Map<String, Uint8List> files;
  const NotesPack(this.object, this.notes, this.files);
}

/// Прочитати експортний ZIP іншого пристрою; null — у ZIP немає позначок для програми.
NotesPack? readNotesZip(Uint8List bytes) {
  final a = ZipDecoder().decodeBytes(bytes);
  final j = a.findFile(notesJsonName);
  if (j == null) return null;
  final data = jsonDecode(utf8.decode(j.content as List<int>)) as Map<String, dynamic>;
  final files = <String, Uint8List>{
    for (final f in a.files)
      if (f.isFile && (f.name.startsWith('фото/') || f.name.startsWith('аудіо/')))
        f.name.substring(f.name.indexOf('/') + 1): Uint8List.fromList(f.content as List<int>),
  };
  return NotesPack(
    data['object'] as String? ?? '',
    [for (final n in data['notes'] as List) Note.fromJson(n as Map<String, dynamic>)],
    files,
  );
}

class MergeResult {
  final List<Note> notes;

  /// Нові й оновлені позначки — їхні файли треба скопіювати.
  final List<Note> taken;
  final int added, updated, same, far;
  const MergeResult(this.notes, this.taken, this.added, this.updated, this.same, this.far);
}

/// Додати позначки іншої людини до своїх. ПК і зміщення перераховуються за координатами на цій осі
/// (у колеги початок пікетажу міг бути заданий інакше). Та сама позначка (той самий номер) — лишається
/// новіша редакція. far — скільки позначок далі 300 м від осі чи за її кінцями (мабуть, інший об'єкт).
MergeResult mergeNotes(List<Note> mine, List<Note> theirs, RoadAxis axis) {
  final out = [...mine];
  final taken = <Note>[];
  var added = 0, updated = 0, same = 0, far = 0;
  for (final t in theirs) {
    final r = axis.locate(Vec(t.east, t.north));
    if (r.beyond || r.offset.abs() > 300) far++;
    final n = t.copyAt(r.station, r.offset);
    final i = out.indexWhere((m) => m.id == t.id);
    if (i < 0) {
      out.add(n);
      taken.add(n);
      added++;
    } else if ((t.updated ?? t.created).isAfter(out[i].updated ?? out[i].created)) {
      out[i] = n;
      taken.add(n);
      updated++;
    } else {
      same++;
    }
  }
  return MergeResult(out, taken, added, updated, same, far);
}
