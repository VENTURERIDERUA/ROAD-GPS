import 'package:flutter_test/flutter_test.dart';
import 'package:road_gps/geometry.dart';
import 'package:road_gps/pdf_vector.dart';

void main() {
  test('дотик бере кольорову лінію проєктного профілю, а не ближчу сіру сітку; риски переломів не збивають', () {
    const red = 0xFF0000, grey = 0xB0B0B0;
    final strokes = [
      // Сітка — сіра горизонталь.
      const PdfStroke([Vec(0, 10), Vec(200, 10)], grey, 0.2),
      // Лінія проєктного профілю — двома шматками, з уступом униз на x = 100.
      const PdfStroke([Vec(20, 13), Vec(100, 13)], red, 0.5),
      const PdfStroke([Vec(100, 13), Vec(100, 16), Vec(180, 18)], red, 0.5),
      // Червона вертикальна риска перелому вгору від x = 60 — не продовження лінії.
      const PdfStroke([Vec(60, 13), Vec(60, 0)], red, 0.5),
    ];
    // Палець ближче до сірої (1 пункт), ніж до червоної (2 пункти).
    final line = pickVectorLine(strokes, const Vec(50, 11), radius: 8);
    expect(line.first, const Vec(20, 13));
    expect(line.last, const Vec(180, 18));
    expect(line.any((p) => p.y < 12), isFalse, reason: 'не пішла ні сіткою, ні рискою');
    expect(isGrey(grey), isTrue);
    expect(isGrey(0x000000), isTrue);
    expect(isGrey(red), isFalse);
    // Далеко від усього — порожньо.
    expect(pickVectorLine(strokes, const Vec(50, 60), radius: 8), isEmpty);
  });
}
