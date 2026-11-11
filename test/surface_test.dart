// ЦММ проєкту: відмітка з трикутників, файл, LandXML, 3D-грані DXF.
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:road_gps/dxf.dart';
import 'package:road_gps/geometry.dart';
import 'package:road_gps/surface.dart';

Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

Uint8List dxf(List<Object> pairs) {
  final s = StringBuffer('  0\r\nSECTION\r\n  2\r\nENTITIES\r\n');
  for (var i = 0; i < pairs.length; i += 2) {
    s.write('${pairs[i].toString().padLeft(3)}\r\n${pairs[i + 1]}\r\n');
  }
  s.write('  0\r\nENDSEC\r\n  0\r\nEOF\r\n');
  return b(s.toString());
}

void main() {
  test('відмітка з площини трикутника; поза ЦММ — null; вертикальна грань не заважає; файл без втрат', () {
    double z(double x, double y) => 100 + 0.01 * x + 0.02 * y;
    List<double> v(double x, double y) => [x, y, z(x, y)];
    final s = Surface('t', Float64List.fromList([
      ...v(0, 0), ...v(10, 0), ...v(10, 10), //
      ...v(0, 0), ...v(10, 10), ...v(0, 10),
      10, 0, 50, 10, 0, 60, 10, 10, 70, // вертикальна (бордюр) — у плані без площі
    ]));
    expect(s.elevationAt(const Vec(3, 4)), closeTo(z(3, 4), 1e-9));
    expect(s.elevationAt(const Vec(10, 5)), closeTo(z(10, 5), 1e-9)); // на ребрі
    expect(s.elevationAt(const Vec(11, 5)), isNull);
    final back = Surface.decode(s.encode());
    expect(back.source, 't');
    expect(back.count, 3);
    expect(back.elevationAt(const Vec(7, 1)), closeTo(z(7, 1), 1e-9));
  });

  test('LandXML: дві поверхні, «північ схід», невидима грань, проєкт першою', () {
    final all = parseLandXmlSurfaces(b('''<?xml version="1.0"?>
<LandXML xmlns="http://www.landxml.org/schema/LandXML-1.2"><Units><Metric linearUnit="meter"/></Units><Surfaces>
 <Surface name="EG"><Definition surfType="TIN"><Pnts><P id="1">0 0 50</P><P id="2">0 10 50</P><P id="3">10 0 50</P></Pnts>
  <Faces><F>1 2 3</F></Faces></Definition></Surface>
 <Surface name="Corridor Top"><Definition surfType="TIN"><Pnts>
  <P id="1">2000 1000 100</P><P id="2">2000 1010 101</P><P id="3">2010 1000 102</P><P id="4">2010 1010 103</P></Pnts>
  <Faces><F>1 2 3</F><F i="1">2 4 3</F></Faces></Definition></Surface>
</Surfaces></LandXML>'''));
    expect(all.map((s) => s.source), ['LandXML: EG', 'LandXML: Corridor Top']);
    expect(designScore('LandXML: Corridor Top'), 1);
    expect(designScore('LandXML: EG'), -1);
    final top = all.last;
    expect(top.count, 1); // невидима грань пропущена
    // Точка (1000 схід, 2000 північ) — 100; на 10 м на схід — 101.
    expect(top.elevationAt(const Vec(1000, 2000)), closeTo(100, 1e-9));
    expect(top.elevationAt(const Vec(1005, 2000)), closeTo(100.5, 1e-9));
    expect(() => parseLandXmlSurfaces(b('<LandXML/>')), throwsA(isA<SurfaceException>()));
  });

  test('DXF: 3DFACE (чотирикутна — два трикутники), багатогранник, у блоці — зі зсувом', () {
    final d = parseDxf(dxf([
      0, '3DFACE', 8, 'TIN', 10, 0, 20, 0, 30, 1, 11, 10, 21, 0, 31, 2, 12, 10, 22, 10, 32, 3, 13, 0, 23, 10, 33, 2,
      0, 'POLYLINE', 8, 'MESH', 66, 1, 70, 64, 71, 4, 72, 1,
      0, 'VERTEX', 8, 'MESH', 10, 20, 20, 0, 30, 5, 70, 192,
      0, 'VERTEX', 8, 'MESH', 10, 30, 20, 0, 30, 5, 70, 192,
      0, 'VERTEX', 8, 'MESH', 10, 30, 20, 10, 30, 6, 70, 192,
      0, 'VERTEX', 8, 'MESH', 10, 20, 20, 10, 30, 6, 70, 192,
      0, 'VERTEX', 8, 'MESH', 10, 0, 20, 0, 30, 0, 70, 128, 71, 1, 72, 2, 73, -3, 74, 4,
      0, 'SEQEND', 8, 'MESH',
    ]));
    expect(d.layers['TIN']!.faces.length, 18);
    expect(d.layers['MESH']!.faces.length, 18);
    final s = Surface('DXF', Float64List.fromList(d.layers['TIN']!.faces));
    expect(s.elevationAt(const Vec(5, 1)), isNotNull);
    expect(Surface('m', Float64List.fromList(d.layers['MESH']!.faces)).elevationAt(const Vec(25, 5)), closeTo(5.5, 1e-9));
  });

  test('тріангуляція Делоне: сітка, площина, «порожні кола», довгі ребра відкинуто', () {
    // Сітка 20 × 20 через 5 м на площині — 2 трикутники на клітинку, відмітка всередині точна.
    double z(double x, double y) => 300 + 0.03 * x - 0.01 * y;
    final grid = [
      for (var i = 0; i < 20; i++)
        for (var j = 0; j < 20; j++) ...[600000 + i * 5.0, 700000 + j * 5.0, z(i * 5.0, j * 5.0)]
    ];
    final g = Surface('g', triangulate(grid));
    expect(g.count, 2 * 19 * 19);
    expect(g.elevationAt(const Vec(600012.3, 700047.9)), closeTo(z(12.3, 47.9), 1e-6));
    // Випадкові точки: жодна точка не всередині кола, описаного навколо будь-якого трикутника.
    final rnd = math.Random(7);
    final pts = [for (var i = 0; i < 300; i++) ...[rnd.nextDouble() * 200, rnd.nextDouble() * 200, 0.0]];
    final t = triangulate(pts, maxEdge: 1e9);
    expect(t.length ~/ 9, greaterThan(500));
    for (var k = 0; k < t.length; k += 9) {
      final ax = t[k], ay = t[k + 1], bx = t[k + 3], by = t[k + 4], cx = t[k + 6], cy = t[k + 7];
      final d = 2 * (ax * (by - cy) + bx * (cy - ay) + cx * (ay - by));
      final ux = ((ax * ax + ay * ay) * (by - cy) + (bx * bx + by * by) * (cy - ay) + (cx * cx + cy * cy) * (ay - by)) / d;
      final uy = ((ax * ax + ay * ay) * (cx - bx) + (bx * bx + by * by) * (ax - cx) + (cx * cx + cy * cy) * (bx - ax)) / d;
      final r2 = (ax - ux) * (ax - ux) + (ay - uy) * (ay - uy);
      for (var i = 0; i < pts.length; i += 3) {
        final d2 = (pts[i] - ux) * (pts[i] - ux) + (pts[i + 1] - uy) * (pts[i + 1] - uy);
        expect(d2, greaterThanOrEqualTo(r2 * (1 - 1e-9)));
      }
    }
    // Дві купки точок за 500 м одна від одної — між ними трикутників немає.
    final near = grid.sublist(0, 3 * 60); // перші три ряди сітки: 15 × 95 м
    final two = [...near, for (var i = 0; i < near.length; i += 3) ...[near[i] + 500, near[i + 1], near[i + 2]]];
    final tt = triangulate(two);
    expect(tt.length ~/ 9, 2 * (2 * 2 * 19)); // кожна купка — своя сітка 3 × 20 точок
    for (var k = 0; k < tt.length; k += 3) {
      expect(tt[k] < 600100 || tt[k] > 600400, isTrue);
    }
  });
}
