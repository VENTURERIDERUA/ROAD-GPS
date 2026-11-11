import 'package:flutter_test/flutter_test.dart';
import 'package:road_gps/geometry.dart';
import 'package:road_gps/i18n.dart';
import 'package:road_gps/nearest_axis.dart';

void main() {
  // Основна дорога вздовж X (ПК 10+00 … 20+00), примикання праворуч від ПК 15+00 — на південь (Y меншає),
  // вісь примикання починається на осі основної дороги.
  final main = RoadAxis([LineSeg(const Vec(0, 0), const Vec(1000, 0))], startStation: 1000);
  final side = RoadAxis([LineSeg(const Vec(500, 0), const Vec(500, -200))]);

  double toMain(Vec p) => distanceToAxis(main, main.locate(p));
  double toSide(Vec p) => distanceToAxis(side, side.locate(p));

  test('відстань до осі: збоку — зміщення, за кінцем — ще й уздовж', () {
    expect(toMain(const Vec(300, 4)), closeTo(4, 1e-6));
    expect(toMain(const Vec(1003, 4)), closeTo(5, 1e-6));
    expect(toMain(const Vec(-3, -4)), closeTo(5, 1e-6));
  });

  /// Пройти точками (кожна — одне визначення GPS) і сказати, куди перемкнулося б.
  String? walk(AxisSwitcher s, List<Vec> pts, {double? accuracy}) {
    for (final p in pts) {
      final id = s.update(toMain(p), [('side', toSide(p))], accuracy: accuracy);
      if (id != null) return id;
    }
    return null;
  }

  test('на основній дорозі біля стику — лишаємось на ній', () {
    final s = AxisSwitcher();
    // Права смуга навпроти примикання: до осі примикання 0 м, до основної — 1.75 м: різниця менша за запас.
    expect(walk(s, List.filled(10, const Vec(500, -1.75))), isNull);
    // Далеко від примикання — тим паче.
    expect(walk(s, List.filled(10, const Vec(300, -1.75))), isNull);
  });

  test('зайшли на примикання — перемикається після кількох визначень поспіль', () {
    final s = AxisSwitcher();
    expect(walk(s, [const Vec(500.5, -10), const Vec(500.4, -11)]), isNull, reason: 'два визначення — ще рано');
    expect(walk(s, [const Vec(500.3, -12)]), 'side');
  });

  test('один стрибок GPS не перемикає', () {
    final s = AxisSwitcher();
    expect(walk(s, [const Vec(500, -10), const Vec(500, -11), const Vec(300, -1), const Vec(500, -12)]), isNull);
  });

  test('за поганого GPS запас більший', () {
    // До основної 6 м, до примикання 1.5 м: різниця 4.5 м. Звичайно — перемикає; за точності ±12 м — ні (запас 5 м).
    final pts = List.filled(5, const Vec(501.5, -6));
    expect(walk(AxisSwitcher(), pts, accuracy: 4), 'side');
    expect(walk(AxisSwitcher(), pts, accuracy: 12), isNull);
  });

  test('інша вісь далі за межу — не перемикає, навіть коли своя ще далі', () {
    final s = AxisSwitcher();
    for (var i = 0; i < 5; i++) {
      expect(s.update(500, [('far', 80)]), isNull);
    }
  });

  test('дві проїзні частини: та, на якій стоїш', () {
    final left = RoadAxis([LineSeg(const Vec(0, 7), const Vec(1000, 7))]);
    final right = RoadAxis([LineSeg(const Vec(0, -7), const Vec(1000, -7))]);
    final s = AxisSwitcher();
    String? id;
    for (var i = 0; i < 3; i++) {
      const p = Vec(400, -6);
      id = s.update(distanceToAxis(left, left.locate(p)), [('right', distanceToAxis(right, right.locate(p)))]);
    }
    expect(id, 'right');
  });

  test('написи про сусідні осі перекладено', () {
    const all = [
      'Ближча вісь — «{name}»: ПК тепер по ній',
      'Вісь «{name}»',
      'Не перемикати',
      'Поруч вісь «{name}»',
      'Сама переходити на ближчу вісь (за GPS)',
    ];
    expect(missing(Lang.en, all), isEmpty);
    expect(missing(Lang.ro, all), isEmpty);
  });
}
