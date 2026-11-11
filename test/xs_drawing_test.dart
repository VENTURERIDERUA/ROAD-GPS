// Поперечники з креслення: синтетичне креслення з відомими відмітками.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:road_gps/dxf.dart';
import 'package:road_gps/profile.dart';
import 'package:road_gps/xs_drawing.dart';

Uint8List dxf(List<Object> pairs) {
  final b = StringBuffer('  0\r\nSECTION\r\n  2\r\nENTITIES\r\n');
  for (var i = 0; i < pairs.length; i += 2) {
    b.write('${pairs[i].toString().padLeft(3)}\r\n${pairs[i + 1]}\r\n');
  }
  b.write('  0\r\nENDSEC\r\n  0\r\nEOF\r\n');
  return Uint8List.fromList(utf8.encode(b.toString()));
}

void main() {
  test('два поперечники: підпис з Z, без Z — з профілю; вертикаль перебільшено вдвічі', () {
    // Поперечник 1 — біля (0, 0): вісь x=10, лінія проєкту з кромками на ±3.5 (−7 см), підпис з Z=100.
    // Поперечник 2 — біля (0, 50): підпис без Z, відмітку осі дасть профіль (101 на ПК 0+50).
    final d = parseDxf(dxf([
      0, 'LWPOLYLINE', 8, 'XS_DESIGN', 90, 3, 10, 6.5, 20, 9.86, 10, 10, 20, 10, 10, 13.5, 20, 9.86,
      0, 'LINE', 8, 'XS_AXIS', 10, 10, 20, 8, 11, 10, 21, 12,
      0, 'TEXT', 8, 'XS_TEXT', 10, 4, 20, 7, 1, 'PK 0+025.00  Z=100.00',
      // Другий намальовано справа наліво — теж має прочитатись.
      0, 'LWPOLYLINE', 8, 'XS_DESIGN', 90, 2, 10, 13, 20, 60, 10, 7, 20, 60.1,
      0, 'LINE', 8, 'XS_AXIS', 10, 10, 20, 58, 11, 10, 21, 62,
      0, 'TEXT', 8, 'XS_TEXT', 10, 4, 20, 57, 1, 'PK 0+050',
      0, 'TEXT', 8, 'NOTE', 10, 0, 20, -20, 1, 'Profile transversale H 1:100 V 1:50',
    ]));
    final ly = guessXsLayers(d)!;
    expect((ly.design, ly.labels, ly.axis), ('XS_DESIGN', 'XS_TEXT', 'XS_AXIS'));
    expect(guessVScale(d)!.$1, 2);
    final r = sectionsFromDrawing(d, ly, vScale: 2, profile: Profile('t', const [Pvi(0, 101), Pvi(100, 101)]));
    expect(r.problems, isEmpty);
    final cs = r.sections!;
    expect(cs.rows.map((x) => x.$1), [25, 50]);
    final first = cs.rows.first.$2;
    expect(first.map((p) => p.$1), [-3.5, 0, 3.5]);
    expect(first[0].$2, closeTo(99.93, 1e-9));
    expect(first[1].$2, closeTo(100, 1e-9));
    final second = cs.rows.last.$2;
    expect(second.map((p) => p.$1), [-3, 3]);
    expect(zOnLine(second, 0), closeTo(101, 1e-9));
    expect(zOnLine(second, 3), closeTo(101 - 0.05 / 2, 1e-9)); // 5 см у кресленні при V 2:1 — 2.5 см
    // Без профілю другий поперечник пропускається з попередженням.
    final r2 = sectionsFromDrawing(d, ly, vScale: 2);
    expect(r2.sections!.rows.length, 1);
    expect(r2.problems.single.title, contains('Без відмітки осі: 1'));
  });
}
