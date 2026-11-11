import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:road_gps/geometry.dart';

void main() {
  // Вісь: пряма 100 м на схід, далі крива R=100 ліворуч (проти годинникової) на 90°.
  final line = LineSeg(const Vec(0, 0), const Vec(100, 0));
  final arc = ArcSeg(const Vec(100, 100), 100, -math.pi / 2, math.pi / 2);

  test('дуга з bulge полілінії', () {
    final a = ArcSeg.fromBulge(const Vec(100, 0), const Vec(200, 100), math.tan(math.pi / 8));
    expect(a.center.x, closeTo(100, 1e-9));
    expect(a.center.y, closeTo(100, 1e-9));
    expect(a.radius, closeTo(100, 1e-9));
    expect(a.end.dist(const Vec(200, 100)), lessThan(1e-9));
  });

  test('ПК і зміщення на прямій: праворуч — плюс', () {
    final al = RoadAxis([line, arc], startStation: 1000);
    final r = al.locate(const Vec(40, -3));
    expect(r.station, closeTo(1040, 1e-9));
    expect(r.offset, closeTo(3, 1e-9));
    expect(r.beyond, isFalse);
  });

  test('ПК і зміщення на кривій: ліворуч — мінус', () {
    final al = RoadAxis([line, arc], startStation: 1000);
    final p = const Vec(100, 100) + Vec(math.cos(-math.pi / 4), math.sin(-math.pi / 4)) * 90;
    final r = al.locate(p);
    expect(r.station, closeTo(1100 + 100 * math.pi / 4, 1e-6));
    expect(r.offset, closeTo(-10, 1e-6));
  });

  test('перед початком і за кінцем осі', () {
    final al = RoadAxis([line, arc], startStation: 1000);
    final before = al.locate(const Vec(-5, 2));
    expect(before.beyond, isTrue);
    expect(before.station, closeTo(995, 1e-9));
    expect(before.offset, closeTo(-2, 1e-9));
    final after = al.locate(const Vec(203, 130)); // кінець (200,100), напрям на північ
    expect(after.beyond, isTrue);
    expect(after.station, closeTo(al.endStation + 30, 1e-6));
    expect(after.offset, closeTo(3, 1e-6));
  });

  test('точка осі на ПК і перпендикуляр праворуч', () {
    final al = RoadAxis([line, arc], startStation: 1000);
    expect(al.pointAtStation(1050).dist(const Vec(50, 0)), lessThan(1e-9));
    final n = al.rightNormalAt(1050);
    expect(n.x, closeTo(0, 1e-9));
    expect(n.y, closeTo(-1, 1e-9));
  });

  test('збирання осі з перемішаних і розвернутих шматків, позначка пропускається', () {
    final tick = LineSeg(const Vec(50, -5), const Vec(50, 5)); // риска пікету впоперек осі
    final pieces = <Segment>[
      arc.reversed(),
      tick,
      LineSeg(const Vec(60, 0), const Vec(100, 0)),
      LineSeg(const Vec(60.01, 0), const Vec(0, 0)).reversed(), // зазор 1 см — у межах допуску
    ];
    final c = buildChain(pieces);
    expect(c.usedPieces, 3);
    expect(c.ignoredPieces, 1);
    expect(c.ignoredLength, closeTo(10, 1e-9));
    expect(c.branchNodes, 0);
    final total = c.segments.fold(0.0, (a, s) => a + s.length);
    expect(total, closeTo(100 + 50 * math.pi, 0.02));
    for (var i = 1; i < c.segments.length; i++) {
      expect(c.segments[i - 1].end.dist(c.segments[i].start), lessThan(0.05));
    }
  });

  test('X↔Y: дуга переставляється разом з кінцями', () {
    final s = arc.swapXY();
    expect(s.start.dist(Vec(arc.start.y, arc.start.x)), lessThan(1e-9));
    expect(s.end.dist(Vec(arc.end.y, arc.end.x)), lessThan(1e-9));
    expect(s.length, closeTo(arc.length, 1e-9));
  });

  test('збереження шматків у JSON і назад', () {
    for (final s in [line, arc]) {
      final back = Segment.fromJson(s.toJson());
      expect(back.start.dist(s.start), lessThan(1e-12));
      expect(back.end.dist(s.end), lessThan(1e-12));
    }
  });
}
