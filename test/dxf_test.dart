import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:road_gps/dxf.dart';
import 'package:road_gps/geometry.dart';

Uint8List dxf(List<Object> pairs) {
  final b = StringBuffer('  0\r\nSECTION\r\n  2\r\nENTITIES\r\n');
  for (var i = 0; i < pairs.length; i += 2) {
    b.write('${pairs[i].toString().padLeft(3)}\r\n${pairs[i + 1]}\r\n');
  }
  b.write('  0\r\nENDSEC\r\n  0\r\nEOF\r\n');
  return Uint8List.fromList(utf8.encode(b.toString()));
}

bool near(Vec a, Vec b) => a.dist(b) < 1e-6;

void main() {
  test('лінія, дзеркальна дуга, полілінії, підпис — по шарах', () {
    final d = parseDxf(dxf([
      0, 'LINE', 8, 'Ax', 10, 0, 20, 0, 30, 0, 11, 100, 21, 0, 31, 0,
      // Дуга, накреслена «дзеркально» (нормаль Z = −1): у звичайних координатах —
      // центр (100,100), від (100,0) до (200,100).
      0, 'ARC', 8, 'Ax', 10, -100, 20, 100, 30, 0, 40, 100, 210, 0, 220, 0, 230, -1, 50, 180, 51, 270,
      0, 'LWPOLYLINE', 8, 'Edge', 90, 3, 70, 0, 10, 0, 20, 10, 10, 100, 20, 10, 42, 0.41421356237, 10, 200, 20, 110,
      0, 'POLYLINE', 8, '3D', 66, 1, 70, 8,
      0, 'VERTEX', 8, '3D', 10, 1, 20, 2, 30, 300, 70, 32,
      0, 'VERTEX', 8, '3D', 10, 4, 20, 6, 30, 301, 70, 32,
      0, 'SEQEND', 8, '3D',
      0, 'TEXT', 8, 'Ax', 10, 5, 20, 8, 40, 2.5, 1, '0+000',
      0, 'MTEXT', 8, 'Ax', 10, 1005, 20, 8, 1, r'{\fArial|b0;1+000}',
      0, 'ACAD_PROXY_ENTITY', 8, 'C3D',
    ]));

    final ax = d.layers['Ax']!;
    expect(ax.segments.length, 2);
    expect(near(ax.segments[0].start, const Vec(0, 0)), isTrue);
    final arc = ax.segments[1] as ArcSeg;
    final ends = [arc.start, arc.end];
    expect(ends.any((p) => near(p, const Vec(100, 0))), isTrue);
    expect(ends.any((p) => near(p, const Vec(200, 100))), isTrue);
    expect(arc.length, closeTo(157.0796, 1e-3));
    expect([for (final l in ax.labels) l.text], ['0+000', '1+000']);
    expect(ax.counts, {'LINE': 1, 'ARC': 1, 'TEXT': 1, 'MTEXT': 1});

    final edge = d.layers['Edge']!;
    expect(edge.segments.length, 2);
    expect(edge.segments[1], isA<ArcSeg>());
    expect(near(edge.segments[1].end, const Vec(200, 110)), isTrue);

    final p3 = d.layers['3D']!;
    expect(p3.segments.length, 1);
    expect(near(p3.segments.single.end, const Vec(4, 6)), isTrue);

    expect(d.layers['C3D']!.unreadable, 1);
    expect(d.problems, hasLength(1));
  });

  test('двійковий DXF і не-DXF — зрозуміла помилка', () {
    expect(() => parseDxf(Uint8List.fromList(latin1.encode('AutoCAD Binary DXF\r\n\x1a\x00'))),
        throwsA(isA<FormatException>()));
    expect(() => parseDxf(Uint8List.fromList(utf8.encode('hello\nworld\n'))),
        throwsA(isA<FormatException>()));
  });

  group('блоки (INSERT)', () {
    // Розділ BLOCKS перед ENTITIES — як у справжньому DXF.
    Uint8List withBlocks(List<Object> blocks, List<Object> entities) {
      final b = StringBuffer();
      void pairs(List<Object> l) {
        for (var i = 0; i < l.length; i += 2) {
          b.write('${l[i].toString().padLeft(3)}\r\n${l[i + 1]}\r\n');
        }
      }

      pairs([0, 'SECTION', 2, 'BLOCKS']);
      pairs(blocks);
      pairs([0, 'ENDSEC', 0, 'SECTION', 2, 'ENTITIES']);
      pairs(entities);
      pairs([0, 'ENDSEC', 0, 'EOF']);
      return Uint8List.fromList(utf8.encode(b.toString()));
    }

    test('вісь у блоці: базова точка, масштаб, поворот; шар «0» бере шар вставки', () {
      final d = parseDxf(withBlocks([
        0, 'BLOCK', 8, '0', 2, 'AX_1', 70, 0, 10, 10, 20, 0,
        0, 'LINE', 8, '1.1. Ax', 10, 10, 20, 0, 11, 20, 21, 0, // 10 м на схід від базової точки
        0, 'LINE', 8, '0', 10, 10, 20, 0, 11, 10, 21, 5,
        0, 'TEXT', 8, '1.1. Ax', 10, 15, 20, 1, 1, 'km 0',
        0, 'ENDBLK', 8, '0',
      ], [
        // У точку (1000, 2000), удвічі більше, поворот 90°: відрізок іде на північ.
        0, 'INSERT', 8, 'Plan', 2, 'AX_1', 10, 1000, 20, 2000, 41, 2, 42, 2, 50, 90,
      ]));
      final ax = d.layers['1.1. Ax']!;
      expect(ax.segments.single.start.dist(const Vec(1000, 2000)), lessThan(1e-9));
      expect(ax.segments.single.end.dist(const Vec(1000, 2020)), lessThan(1e-9));
      expect(ax.labels.single.pos.dist(const Vec(998, 2010)), lessThan(1e-9));
      expect(d.layers['Plan']!.segments.single.end.dist(const Vec(990, 2000)), lessThan(1e-9));
      expect(d.layers['Plan']!.unreadable, 0); // вставку прочитано — про «блоки» не попереджаємо
    });

    test('вкладений блок, дуга з дзеркалом і нерівним масштабом, невідомий блок', () {
      final d = parseDxf(withBlocks([
        0, 'BLOCK', 2, 'ARC', 10, 0, 20, 0,
        0, 'ARC', 8, 'Edge', 10, 0, 20, 0, 40, 10, 50, 0, 51, 90,
        0, 'ENDBLK',
        0, 'BLOCK', 2, 'OUTER', 10, 0, 20, 0,
        0, 'INSERT', 8, '0', 2, 'ARC', 10, 100, 20, 0,
        0, 'ENDBLK',
      ], [
        0, 'INSERT', 8, 'A', 2, 'OUTER', 10, 0, 20, 0,
        0, 'INSERT', 8, 'B', 2, 'ARC', 10, 0, 20, 0, 41, -1, // дзеркало по X
        0, 'INSERT', 8, 'C', 2, 'ARC', 10, 0, 20, 0, 41, 2, // еліпс — ламаною
        0, 'INSERT', 8, 'D', 2, 'NOPE', 10, 0, 20, 0,
      ]));
      final a = d.layers['Edge']!.segments;
      // Вкладений: дуга від (110, 0) до (100, 10); дзеркальна: від (−10, 0) до (0, 10); еліпс — від (20, 0) до (0, 10).
      expect(a.any((s) => s.start.dist(const Vec(110, 0)) < 1e-9 && s.end.dist(const Vec(100, 10)) < 1e-9), isTrue);
      final mirrored = a.whereType<ArcSeg>().firstWhere((s) => s.start.dist(const Vec(-10, 0)) < 1e-9);
      expect(mirrored.end.dist(const Vec(0, 10)), lessThan(1e-9));
      final ellipse = a.whereType<LineSeg>().toList();
      expect(ellipse.first.start.dist(const Vec(20, 0)), lessThan(1e-9));
      expect(ellipse.last.end.dist(const Vec(0, 10)), lessThan(1e-9));
      expect(d.layers['D']!.unreadableKinds, {'INSERT': 1}); // блоку немає — попередження лишається
    });
  });
}
