import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:road_gps/chainage.dart';
import 'package:road_gps/geometry.dart';
import 'package:road_gps/lines.dart';
import 'package:road_gps/road_object.dart';

List<Segment> poly(List<Vec> pts) => [for (var i = 1; i < pts.length; i++) LineSeg(pts[i - 1], pts[i])];

void main() {
  // Вісь на схід; ліворуч за ходом — це +Y.
  final axis = RoadAxis([LineSeg(const Vec(0, 0), const Vec(100, 0))]);
  final lines = [
    ...linesOfLayer(LineRole.edge, 'EDGE', [
      ...poly(const [Vec(-5, 3.5), Vec(40, 3.5), Vec(105, 3.5)]),
      ...poly(const [Vec(105, -3.5), Vec(-5, -3.5)]),
    ]),
    ...linesOfLayer(LineRole.row, 'ROW', [
      ...poly(const [Vec(-5, 15), Vec(105, 15)]),
      ...poly(const [Vec(-5, -15), Vec(105, -15)]),
    ]),
  ];

  test('лінії шару розкладаються на окремі ланцюжки', () {
    expect(lines.where((l) => l.role == LineRole.edge).length, 2);
    expect(lines.first.length, closeTo(110, 1e-9));
    // Риска 0.5 м — пропускається.
    expect(linesOfLayer(LineRole.other, 'x', [LineSeg(const Vec(0, 0), const Vec(0.5, 0))]), isEmpty);
  });

  test('поперечник: кромки й межі відводу на своїх місцях', () {
    final hits = crossSection(axis, lines, 50);
    expect([for (final h in hits) h.offset], [-15, -3.5, 3.5, 15].map((v) => closeTo(v, 1e-9)).toList());
    expect(hits.first.role, LineRole.row);
    expect(hits[1].role, LineRole.edge);
  });

  test('де людина: найближчі лінії й вихід за межу відводу', () {
    final hits = crossSection(axis, lines, 50);
    final w = whereabouts(hits, -5);
    expect(w.left!.$1.role, LineRole.row);
    expect(w.left!.$2, closeTo(10, 1e-9));
    expect(w.right!.$1.role, LineRole.edge);
    expect(w.right!.$2, closeTo(1.5, 1e-9));
    expect(w.outsideRow, isNull);
    expect(whereabouts(hits, -17).outsideRow, closeTo(2, 1e-9));
    expect(whereabouts(hits, 20).outsideRow, closeTo(5, 1e-9));
    expect(whereabouts(hits, 20).right, isNull);
  });

  test('перетин з дугою — лише там, де дуга є', () {
    final arc = ArcSeg(const Vec(50, 0), 10, 0, math.pi); // верхнє півколо
    final hits = crossSection(axis, [RoadLine(LineRole.brow, 'B', [arc])], 50);
    expect(hits.length, 1);
    expect(hits.single.offset, closeTo(-10, 1e-9));
  });

  test('поворот під прямим кутом: дальня лінія іншої ділянки не потрапляє в поперечник', () {
    // Вісь: 100 м на схід, далі 100 м на північ. ПК 98 — за 2 м до повороту.
    final l = RoadAxis([LineSeg(const Vec(0, 0), const Vec(100, 0)), LineSeg(const Vec(100, 0), const Vec(100, 100))]);
    final lines = [
      // Ліва кромка першої ділянки — біля внутрішнього кута, ближча до другої ділянки, але своя.
      RoadLine(LineRole.edge, 'E', [LineSeg(const Vec(0, 5), const Vec(100, 5))]),
      // Лінія впоперек другої ділянки на 60 м від повороту — перпендикуляр з ПК 98 її «дістає».
      RoadLine(LineRole.row, 'R', [LineSeg(const Vec(90, 60), const Vec(110, 60))]),
      // Межа відводу першої ділянки праворуч, 30 м — далека, але своя.
      RoadLine(LineRole.row, 'R', [LineSeg(const Vec(-10, -30), const Vec(130, -30))]),
    ];
    final hits = crossSection(l, lines, 98);
    expect([for (final h in hits) h.offset], [closeTo(-5, 1e-9), closeTo(30, 1e-9)]);
    // На прямій ділянці далеко від повороту межа на 30 м теж є.
    expect(crossSection(l, lines, 40).map((h) => h.offset), contains(closeTo(30, 1e-9)));
  });

  test('петля кромки на повороті зрізається в чистий кут; велика петля — ні', () {
    final loop = poly(const [Vec(0, 0), Vec(10, 0), Vec(8, -2), Vec(8, 10)]); // відрізок униз перехльостує
    final clean = removeLoops(loop);
    expect(clean.length, 2);
    expect(clean[0].end.dist(const Vec(8, 0)), lessThan(1e-9));
    expect(clean[1].end.dist(const Vec(8, 10)), lessThan(1e-9));
    // «Вісімка» з петлею близько 180 м — не помилка побудови, лишаємо як є.
    final big = poly(const [Vec(0, 0), Vec(40, 0), Vec(40, -60), Vec(20, -60), Vec(20, 10)]);
    expect(removeLoops(big).length, big.length);
    // Лінія без самоперетинів не змінюється.
    expect(removeLoops(poly(const [Vec(0, 0), Vec(10, 0), Vec(10, 10)])).length, 2);
  });

  test('роль шару за назвою', () {
    expect(guessRole('EDGE'), LineRole.edge);
    expect(guessRole('Bordura sus'), LineRole.curb);
    expect(guessRole('Retea gaz'), LineRole.gas);
    expect(guessRole('Cablu electric'), LineRole.power);
    expect(guessRole('Rigola'), LineRole.ditch);
    expect(guessRole('Trotuar'), LineRole.sidewalk);
    expect(guessRole('Canalizare'), LineRole.sewer);
    expect(guessRole('Retea apa'), LineRole.water);
    expect(guessRole('Margine carosabil'), LineRole.edge);
    expect(guessRole('Кромка проїзної частини'), LineRole.edge);
    expect(guessRole('Taluz sus'), LineRole.brow);
    expect(guessRole('БРОВКА'), LineRole.brow);
    expect(guessRole('Taluz jos'), LineRole.toe);
    expect(guessRole('Coridor Expropriere'), LineRole.row);
    expect(guessRole('Межа смуги відводу'), LineRole.row);
    expect(guessRole('Ax drum'), isNull);
    expect(guessRole('Drum de asfalt'), isNull);
  });

  test('об\'єкт з лініями зберігається у файл і читається назад', () async {
    final tmp = await Directory.systemTemp.createTemp('road_gps_test');
    try {
      final store = ObjectStore(dir: tmp);
      final o = RoadObject(
        id: '1',
        name: 'Тест',
        sourceFile: 't.dxf',
        axisLayer: 'AXIS',
        crsId: 'stereo70',
        startStation: 1000,
        style: ChainageStyle.pk,
        axis: axis.segs,
        lines: lines,
        created: DateTime(2026, 10, 26),
      );
      await store.save(o);
      final back = (await store.loadAll()).single;
      expect(back.lines.length, 4);
      expect(back.lines.last.role, LineRole.row);
      expect(back.startStation, 1000);
      expect(crossSection(back.roadAxis, back.lines, 1050).length, 4);
      // Призначення шару змінено вручну, з попередженням — зберігається.
      o.lines = [for (final l in o.lines) l.layer == 'ROW' ? l.withRole(LineRole.gas, 2) : l];
      await store.save(o);
      final gas = (await store.loadAll()).single.lines.where((l) => l.layer == 'ROW').toList();
      expect([for (final l in gas) (l.role, l.alert)], [(LineRole.gas, 2.0), (LineRole.gas, 2.0)]);
      // Відстань — у будь-якому напрямку: збоку від лінії й за її кінцем.
      final south = gas.firstWhere((l) => l.segs.first.start.y < 0);
      expect(south.distanceTo(const Vec(50, 0)), closeTo(15, 1e-9));
      expect(south.distanceTo(const Vec(110, -15)), closeTo(5, 1e-9));
      // Креслення об'єкта — поруч, для ЦММ і поперечників без повторного вибору файлу; з об'єктом і прибирається.
      expect(await store.hasDrawing('1'), isFalse);
      await store.saveDrawing('1', Uint8List.fromList([1, 2, 3]));
      expect(await store.loadDrawing('1'), [1, 2, 3]);
      await store.delete('1');
      expect(await store.loadAll(), isEmpty);
      expect(await store.hasDrawing('1'), isFalse);
      expect(tmp.listSync(), isEmpty);
    } finally {
      await tmp.delete(recursive: true);
    }
  });
}
