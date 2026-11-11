import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:road_gps/dxf.dart';
import 'package:road_gps/geometry.dart';
import 'package:road_gps/problems.dart';

Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

Uint8List entities(List<Object> pairs) {
  final b = StringBuffer('  0\nSECTION\n  2\nENTITIES\n');
  for (var i = 0; i < pairs.length; i += 2) {
    b.write('${pairs[i]}\n${pairs[i + 1]}\n');
  }
  b.write('  0\nENDSEC\n  0\nEOF\n');
  return bytes(b.toString());
}

Problem problemOf(Uint8List b) {
  try {
    parseDxf(b);
  } on DxfException catch (e) {
    return e.problem;
  }
  fail('очікувалась помилка читання');
}

void main() {
  test('не той файл — пояснення й кроки, як отримати DXF', () {
    expect(problemForFileName('axis.DXF'), isNull);
    final dwg = problemForFileName('axis.dwg')!;
    expect(dwg.severity, Severity.error);
    expect(dwg.fixes.any((f) => f.contains('DXF')), isTrue);
    expect(dwg.fixes.any((f) => f.contains('RECOVER')), isTrue);
    expect(problemForFileName('axis.xml'), isNull);
    for (final n in ['plan.pdf', 'scan.JPG', 'axis.tif', 'vidomist.xlsx', 'vidomist.csv', 'readme']) {
      final p = problemForFileName(n);
      expect(p, isNotNull, reason: n);
      expect(p!.fixes, isNotEmpty, reason: n);
    }
  });

  test('двійковий, порожній, сміття, без креслення, без ліній — кожен зі своєю порадою', () {
    expect(problemOf(Uint8List.fromList(latin1.encode('AutoCAD Binary DXF\r\n\x1a\x00'))), same(binaryDxf));
    expect(problemOf(bytes('')).title, 'Файл не схожий на DXF');
    final junk = problemOf(bytes('hello\nworld\n'));
    expect(junk.title, 'Файл не схожий на DXF');
    expect(junk.detail, contains('рядок 1'));
    expect(problemOf(bytes('  0\nSECTION\n  2\nHEADER\n  0\nENDSEC\n  0\nEOF\n')), same(noEntities));
    expect(problemOf(entities([0, 'TEXT', 8, 'A', 10, 0, 20, 0, 1, 'x'])), same(noLines));
  });

  test('блоки й сплайни на шарі — попередження з порадою, штрихування — ні', () {
    final d = parseDxf(entities([
      0, 'LINE', 8, 'Ax', 10, 0, 20, 0, 11, 100, 21, 0,
      0, 'INSERT', 8, 'Ax', 2, 'TICK', 10, 0, 20, 0,
      0, 'SPLINE', 8, 'Ax',
      0, 'HATCH', 8, 'Ax',
    ]));
    final l = d.layers['Ax']!;
    expect(l.unreadableKinds, {'INSERT': 1, 'SPLINE': 1});
    final p = unreadableOnLayer(l.name, l.unreadableKinds);
    expect(p.detail, contains('блоків: 1'));
    expect(p.detail, contains('сплайнів чи еліпсів: 1'));
    expect(p.fixes.any((f) => f.contains('EXPLODE')), isTrue);
    expect(p.fixes.any((f) => f.contains('SPLINEDIT')), isTrue);
  });

  test('розірвана вісь: видно довжину найдовшого з відкинутих шматків', () {
    final c = buildChain([
      LineSeg(const Vec(0, 0), const Vec(100, 0)),
      LineSeg(const Vec(101, 0), const Vec(181, 0)), // зазор 1 м
      LineSeg(const Vec(50, -5), const Vec(50, 5)), // риска 10 м
    ]);
    expect(c.segments.single.length, 100);
    expect(c.secondLength, closeTo(80, 1e-9));
    expect(axisBroken(100, 190, c.secondLength).detail, contains('80 м'));
  });
}
