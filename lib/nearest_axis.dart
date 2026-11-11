// Кілька осей поруч (основна дорога й примикання, з'їзди, дві проїзні частини): яка ближча і коли
// на неї перемкнутися — із запасом, щоб на стику програма не «стрибала» з осі на вісь.
import 'dart:math' as math;

import 'geometry.dart';

/// Відстань від точки до осі, м: поруч з віссю — зміщення; перед початком чи за кінцем — ще й уздовж до краю.
double distanceToAxis(RoadAxis ax, StationResult r) {
  final along = r.station < ax.startStation
      ? ax.startStation - r.station
      : (r.station > ax.endStation ? r.station - ax.endStation : 0.0);
  return math.sqrt(along * along + r.offset * r.offset);
}

/// Коли перемкнутися на іншу вісь: вона ближча щонайменше на [margin] м (за поганого GPS — на половину
/// точності, до 5 м), не далі за [reach] м, і так [fixes] визначень GPS поспіль.
class AxisSwitcher {
  final double margin;
  final double reach;
  final int fixes;
  AxisSwitcher({this.margin = 3, this.reach = 50, this.fixes = 3});

  String? _candidate;
  int _count = 0;

  /// [current] — відстань до осі відкритого об'єкта; [others] — (id об'єкта, відстань до його осі).
  /// Повертає id, на який пора перемкнутися, або null — лишаємось.
  String? update(double current, List<(String, double)> others, {double? accuracy}) {
    (String, double)? best;
    for (final o in others) {
      if (best == null || o.$2 < best.$2) best = o;
    }
    final m = math.max(margin, math.min(accuracy ?? 0, 10) / 2);
    if (best == null || best.$2 > reach || best.$2 + m >= current) {
      reset();
      return null;
    }
    if (best.$1 != _candidate) {
      _candidate = best.$1;
      _count = 0;
    }
    if (++_count < fixes) return null;
    reset();
    return best.$1;
  }

  void reset() {
    _candidate = null;
    _count = 0;
  }
}
