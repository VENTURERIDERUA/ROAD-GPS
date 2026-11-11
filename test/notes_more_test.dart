import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:road_gps/act_docx.dart';
import 'package:road_gps/chainage.dart';
import 'package:road_gps/geometry.dart';
import 'package:road_gps/notes.dart';
import 'package:road_gps/notes_screens.dart' show parseStationInput;
import 'package:road_gps/photo_stamp.dart';

// Вісь 1 км на схід від (1000, 2000); ПК рахується від 0.
final axis = RoadAxis([LineSeg(const Vec(1000, 2000), const Vec(2000, 2000))]);

Note at(String id, double st, double off,
    {NoteKind kind = NoteKind.defect, DateTime? updated, List<String>? photos, List<String>? after}) {
  final p = axis.pointAtStation(st) + axis.rightNormalAt(st) * off;
  return Note(
    id: id,
    created: DateTime(2026, 10, 27, 10),
    kind: kind,
    text: 'позначка $id',
    station: st,
    offset: off,
    lat: 45,
    lon: 26,
    east: p.x,
    north: p.y,
    photos: photos,
    photosAfter: after,
    status: kind == NoteKind.defect ? NoteStatus.open : null,
    author: 'Майстер 1',
    updated: updated,
  );
}

Uint8List jpeg(int w, int h) => img.encodeJpg(img.Image(width: w, height: h)..clear(img.ColorRgb8(200, 200, 200)));

String docText(Uint8List docx) =>
    utf8.decode(ZipDecoder().decodeBytes(docx).findFile('word/document.xml')!.content as List<int>);

void main() {
  test('стан, фото «після», ділянка й автор зберігаються і читаються', () {
    final n = at('a', 100, 2, after: ['a_1.jpg'])
      ..status = NoteStatus.fixed
      ..fixedAt = DateTime(2026, 10, 28, 12)
      ..toStation = 160;
    final b = Note.fromJson(jsonDecode(jsonEncode(n.toJson())) as Map<String, dynamic>);
    expect(b.status, NoteStatus.fixed);
    expect(b.fixedAt, DateTime(2026, 10, 28, 12));
    expect(b.photosAfter, ['a_1.jpg']);
    expect(b.toStation, 160);
    expect(b.length, 60);
    expect(b.author, 'Майстер 1');
    expect(b.files, ['a_1.jpg']);
  });

  test('лабораторія: нова позначка — «Відбір зразка», є фрази для зразків і випробувань; зберігається й читається', () {
    expect(WorkType.lab.kinds.first, NoteKind.sample);
    expect(WorkType.lab.kinds, contains(NoteKind.test));
    expect(noteTemplates[WorkType.lab]![NoteKind.sample], contains('Відбір керна з покриття'));
    expect(noteTemplates[WorkType.lab]![NoteKind.test], contains('Коефіцієнт ущільнення'));
    // Інші види робіт лабораторних типів не показують.
    expect(WorkType.repair.kinds, isNot(contains(NoteKind.sample)));
    final n = at('s', 250, -1.5, kind: NoteKind.sample);
    final b = Note.fromJson(jsonDecode(jsonEncode(n.toJson())) as Map<String, dynamic>);
    expect(b.kind, NoteKind.sample);
    expect(b.station, 250);
    expect(b.created, DateTime(2026, 10, 27, 10));
  });

  test('номер проби: наступний сам («7» → «8», «К-12» → «К-13», «П/09» → «П/10»), свій чи без номера', () async {
    Note numbered(String id, String? no, int minute) =>
        Note.fromJson((at(id, 100, 0, kind: NoteKind.sample).toJson()
          ..['created'] = DateTime(2026, 11, 5, 10, minute).toIso8601String()
          ..['sample'] = no));
    expect(nextSampleNo([]), '1');
    expect(nextSampleNo([numbered('a', '7', 1)]), '8');
    expect(nextSampleNo([numbered('a', '7', 1), numbered('b', 'К-12', 2)]), 'К-13');
    expect(nextSampleNo([numbered('a', 'П/09', 1)]), 'П/10');
    // Без номера — не рахується: далі за останнім пронумерованим.
    expect(nextSampleNo([numbered('a', '3', 1), numbered('b', null, 2)]), '4');
    final b = Note.fromJson(jsonDecode(jsonEncode(numbered('a', 'К-12', 1).toJson())) as Map<String, dynamic>);
    expect(b.sampleNo, 'К-12');
    expect(numbered('c', null, 3).toJson().containsKey('sample'), isFalse);
    // В Excel — колонка «№ проби», коли хоч одна позначка з номером.
    final zip = await exportNotesZip('Тест', ChainageStyle.km, 'Stereo 70', [b, numbered('c', null, 3)], (_) async => null);
    final xlsx = ZipDecoder().decodeBytes(zip).files.firstWhere((f) => f.name.endsWith('.xlsx'));
    final sheet = utf8.decode(ZipDecoder().decodeBytes(xlsx.content as List<int>).findFile('xl/worksheets/sheet1.xml')!.content as List<int>);
    expect(sheet, contains('№ проби'));
    expect(sheet, contains('К-12'));
  });

  test('ПК, як його пишуть: «0+450», «ПК 4+50», «км 1+250.5», метри', () {
    expect(parseStationInput('0+450'), 450);
    expect(parseStationInput('ПК 4+50'), 450);
    expect(parseStationInput('км 1+250,5'), 1250.5);
    expect(parseStationInput(' 320 '), 320);
    expect(parseStationInput('десь тут'), isNull);
  });

  test('експорт: нові колонки, фото «після» в теці фото, позначки для програми', () async {
    final n = at('a', 100, 2, photos: ['a_1.jpg'], after: ['a_2.jpg'])..toStation = 150;
    final files = {'a_1.jpg': Uint8List.fromList([1]), 'a_2.jpg': Uint8List.fromList([2])};
    final zip = await exportNotesZip('Тест', ChainageStyle.km, 'Stereo 70', [n], (f) async => files[f]);
    final a = ZipDecoder().decodeBytes(zip);
    expect(a.findFile('фото/a_2.jpg'), isNotNull);
    final xlsx = a.files.firstWhere((f) => f.name.endsWith('.xlsx'));
    final sheet = utf8.decode(ZipDecoder().decodeBytes(xlsx.content as List<int>).findFile('xl/worksheets/sheet1.xml')!.content as List<int>);
    for (final s in ['До ПК', 'Довжина, м', 'Стан', 'Відкрито', 'Хто записав', 'Майстер 1', 'Фото після 1', 'км 0+150.0']) {
      expect(sheet, contains(s));
    }
    final pack = readNotesZip(zip)!;
    expect(pack.object, 'Тест');
    expect(pack.notes.single.toStation, 150);
    expect(pack.files.keys, containsAll(['a_1.jpg', 'a_2.jpg']));
  });

  test('текст голосу (Whisper на комп’ютері): колонка «Голос — текст» і назад у програму', () async {
    final n = at('a', 100, 2)
      ..audios.addAll(['a_1.m4a', 'a_2.m4a'])
      ..audioText.addAll({'a_1.m4a': 'Вибоїна біля зупинки', 'a_2.m4a': 'Глибина п’ять сантиметрів'});
    final m = at('b', 200, 1);
    final zip = await exportNotesZip('Тест', ChainageStyle.km, 'Stereo 70', [n, m], (f) async => Uint8List(1));
    final a = ZipDecoder().decodeBytes(zip);
    final xlsx = a.files.firstWhere((f) => f.name.endsWith('.xlsx'));
    final sheet = utf8.decode(ZipDecoder().decodeBytes(xlsx.content as List<int>).findFile('xl/worksheets/sheet1.xml')!.content as List<int>);
    expect(sheet, contains('Голос — текст'));
    expect(sheet, contains('Вибоїна біля зупинки\nГлибина п’ять сантиметрів'));
    expect(readNotesZip(zip)!.notes.first.audioText['a_2.m4a'], 'Глибина п’ять сантиметрів');
    // Без розпізнаного тексту колонки немає.
    final plain = await exportNotesZip('Тест', ChainageStyle.km, 'Stereo 70', [m], (f) async => null);
    final px = ZipDecoder().decodeBytes(plain).files.firstWhere((f) => f.name.endsWith('.xlsx'));
    expect(utf8.decode(ZipDecoder().decodeBytes(px.content as List<int>).findFile('xl/worksheets/sheet1.xml')!.content as List<int>),
        isNot(contains('Голос — текст')));
  });

  test('об’єднання: нові додаються, новіша редакція заміняє, ПК — за координатами на своїй осі', () {
    final mine = [at('a', 100, 2, updated: DateTime(2026, 10, 27, 11)), at('b', 300, -3)];
    final theirs = [
      at('a', 100, 2, updated: DateTime(2026, 10, 27, 15))..text = 'уточнено колегою', // новіша
      at('b', 300, -3), // та сама
      at('c', 500, 1), // нова
      at('d', 500, 400), // далеко від осі — мабуть, інший об'єкт
    ];
    // У колеги початок пікетажу був інший — ПК у його позначці «з'їхав» на 1000 м.
    theirs[2] = theirs[2].copyAt(1500, 1);
    final r = mergeNotes(mine, theirs, axis);
    expect((r.added, r.updated, r.same, r.far), (2, 1, 1, 1));
    expect(r.notes.firstWhere((n) => n.id == 'a').text, 'уточнено колегою');
    expect(r.notes.firstWhere((n) => n.id == 'c').station, closeTo(500, 1e-6));
    expect(r.notes.firstWhere((n) => n.id == 'c').offset, closeTo(1, 1e-6));
    expect(r.taken.map((n) => n.id), ['a', 'c', 'd']);
  });

  test('акт огляду: шапка, таблиця, фото «до / після», підписи', () async {
    final ms = DateTime(2026, 10, 27, 10, 5).millisecondsSinceEpoch;
    final before = 'a_$ms.jpg', after = 'a_${ms + 60000}.jpg';
    final notes = [
      at('a', 100, 2, photos: [before], after: [after])
        ..status = NoteStatus.fixed
        ..fixedAt = DateTime(2026, 10, 28),
      at('b', 300, -3, kind: NoteKind.remark)..toStation = 420,
    ];
    final files = {before: jpeg(400, 300), after: jpeg(300, 400)};
    final docx = await buildInspectionDocx(
        objectName: 'Тестова вулиця', style: ChainageStyle.km, crsName: 'Stereo 70', notes: notes,
        file: (f) async => files[f], date: DateTime(2026, 10, 29));
    final a = ZipDecoder().decodeBytes(docx);
    expect(a.files.where((f) => f.name.startsWith('word/media/')).length, 2);
    final d = docText(docx);
    for (final s in ['АКТ ОГЛЯДУ', 'Тестова вулиця', '29.10.2026', 'км 0+100.0', 'км 0+300.0 – км 0+420.0 (120 м)',
        'дефектів 1: усунено 1', 'Фото до', 'Фото після усунення', 'усунено 28.10.2026', 'Майстер 1', 'w:drawing']) {
      expect(d, contains(s));
    }
    // Висота фото — за пропорцією: 400×300 → 8 × 6 см.
    expect(d, contains('cx="2880000" cy="2160000"'));
    final out = Platform.environment['ROAD_GPS_DOCX_OUT'];
    if (out != null) File(out).writeAsBytesSync(docx);
  });

  testWidgets('штамп: розмір фото той самий, унизу — темна смуга з текстом', (tester) async {
    await tester.runAsync(() async {
      final src = jpeg(800, 600);
      final out = await stampPhoto(src, ['км 0+338.2 · 1.3 м ліворуч', '27.10.2026 09:34 · 44.451234, 26.103456']);
      final m = img.decodeJpg(out)!;
      expect((m.width, m.height), (800, 600));
      expect(m.getPixel(400, 590).r, lessThan(150)); // смуга
      expect(m.getPixel(400, 100).r, greaterThan(180)); // знімок не зачеплено
    });
  });
}
