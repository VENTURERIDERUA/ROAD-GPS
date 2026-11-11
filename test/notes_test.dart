import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_gps/chainage.dart';
import 'package:road_gps/crs.dart';
import 'package:road_gps/geometry.dart';
import 'package:road_gps/notes.dart';

Note note(String id, double st, double off, String text, {List<String>? photos, List<String>? audios, double? acc = 4}) {
  final p = toWgs84(stereo70, const Vec(587800, 328500));
  return Note(
    id: id,
    created: DateTime(2026, 10, 27, 9, 5),
    kind: NoteKind.defect,
    text: text,
    station: st,
    offset: off,
    lat: p.latitude,
    lon: p.longitude,
    east: 587800,
    north: 328500,
    accuracy: acc,
    photos: photos,
    audios: audios,
  );
}

String fileText(Archive a, String name) => utf8.decode(a.findFile(name)!.content as List<int>);

void main() {
  test('позначка зберігається в JSON і читається назад', () {
    final n = note('1', 125.4, -3.2, 'Вибоїна', photos: ['1_a.jpg'], audios: ['1_v.m4a']);
    final back = Note.fromJson(n.toJson());
    expect(back.station, 125.4);
    expect(back.offset, -3.2);
    expect(back.kind, NoteKind.defect);
    expect(back.photos, ['1_a.jpg']);
    expect(back.audios, ['1_v.m4a']);
    // Позначка, збережена до появи голосу, читається без помилки.
    expect(Note.fromJson(note('3', 1, 0, '').toJson()..remove('audios')).audios, isEmpty);
    expect(stampText(DateTime(2026, 10, 7, 9, 5)), '07.10.2026 09:05');
    final ms = DateTime(2026, 10, 27, 14, 32).millisecondsSinceEpoch;
    expect(fileTime('n1_$ms.m4a'), DateTime(2026, 10, 27, 14, 32));
    expect(fileTime('photo.jpg'), isNull);
    expect(Note.fromJson(note('2', 1, 0, '', acc: null).toJson()).accuracy, isNull);
    expect(sideText(-3.2), 'ліворуч');
    expect(sideText(0.01), 'на осі');
  });

  test('книга Excel: правильна будова, спецсимволи екрановано', () {
    final x = buildXlsx('Позначки', ['№', 'Опис'], [
      [const Num(1, 0), const Txt('A & B <тест> "лапки"')],
    ], [5, 30]);
    final a = ZipDecoder().decodeBytes(x);
    expect(a.files.map((f) => f.name),
        containsAll(['[Content_Types].xml', '_rels/.rels', 'xl/workbook.xml', 'xl/worksheets/sheet1.xml', 'xl/styles.xml']));
    final sheet = fileText(a, 'xl/worksheets/sheet1.xml');
    expect(sheet, contains('A &amp; B &lt;тест&gt; &quot;лапки&quot;'));
    expect(sheet, contains('state="frozen"'));
  });

  test('експорт: Excel + фото в ZIP, рядки за ПК, посилання на фото', () async {
    final photos = {
      'n2_1.jpg': Uint8List.fromList([1, 2, 3]),
      'n2_2.jpg': Uint8List.fromList([4, 5]),
      'n2_v.m4a': Uint8List.fromList([7, 7, 7, 7]),
    };
    final notes = [
      note('n2', 350.5, 2.4, 'Тріщина покриття', photos: ['n2_1.jpg', 'n2_2.jpg'], audios: ['n2_v.m4a']),
      note('n1', 25, -6.2, 'Немає бордюру', acc: null),
    ];
    final zip = await exportNotesZip('Тестова вулиця', ChainageStyle.km, 'Stereo 70', notes, (n) async => photos[n]);
    final a = ZipDecoder().decodeBytes(zip);
    expect(a.findFile('фото/n2_1.jpg'), isNotNull);
    expect(a.findFile('фото/n2_2.jpg')!.size, 2);
    expect(a.findFile('аудіо/n2_v.m4a')!.size, 4);
    final xlsx = a.files.firstWhere((f) => f.name.endsWith('.xlsx'));
    final sheet = fileText(ZipDecoder().decodeBytes(xlsx.content as List<int>), 'xl/worksheets/sheet1.xml');
    // Спершу ПК 0+025 (ліворуч, точка на карті), потім 0+350.5 з двома фото.
    expect(sheet.indexOf('км 0+025.0'), lessThan(sheet.indexOf('км 0+350.5')));
    expect(sheet, contains('точка на карті'));
    expect(sheet, contains('<f>HYPERLINK("фото/n2_1.jpg","n2_1.jpg")</f>'));
    expect(sheet, contains('Голос 1'));
    expect(sheet, contains('<f>HYPERLINK("аудіо/n2_v.m4a","n2_v.m4a")</f>'));
    final out = Platform.environment['ROAD_GPS_XLSX_OUT'];
    if (out != null) File(out).writeAsBytesSync(xlsx.content as List<int>);
  });

  test('сховище позначок: файл і фото на диску', () async {
    final tmp = await Directory.systemTemp.createTemp('road_gps_notes');
    try {
      final s = NoteStore(dir: tmp);
      await s.addFile('obj', 'a.jpg', Uint8List.fromList([9, 9]));
      await s.saveAll('obj', [note('1', 10, 1, 'x', photos: ['a.jpg'])]);
      final back = await s.load('obj');
      expect(back.single.text, 'x');
      expect(await s.file('obj', 'a.jpg'), [9, 9]);
      await s.deleteFile('obj', 'a.jpg');
      expect(await s.file('obj', 'a.jpg'), isNull);
      expect(await s.load('other'), isEmpty);
      // Видалення позначки прибирає і її фото та записи.
      await s.addFile('obj', 'b.jpg', Uint8List.fromList([1]));
      await s.addFile('obj', 'b.m4a', Uint8List.fromList([2]));
      final keep = note('3', 20, 0, 'лишається');
      final gone = note('2', 10, 1, 'y', photos: ['b.jpg'], audios: ['b.m4a']);
      await s.saveAll('obj', [keep, gone]);
      await deleteNote(s, 'obj', gone);
      expect((await s.load('obj')).single.id, '3');
      expect(await s.file('obj', 'b.jpg'), isNull);
      expect(await s.file('obj', 'b.m4a'), isNull);
      await s.deleteAll('obj');
      expect(await s.load('obj'), isEmpty);
    } finally {
      await tmp.delete(recursive: true);
    }
  });
}
