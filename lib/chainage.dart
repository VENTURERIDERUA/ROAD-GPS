// Пікетаж: запис «ПК 125+43.2» / «км 12+543.2», читання підписів з креслення,
// визначення ПК початку осі й напряму за підписами.
import 'geometry.dart';
import 'i18n.dart';

/// pk — пікети по 100 м (ПК 125+43.2); km — кілометри (км 12+543.2, як у Румунії).
enum ChainageStyle { pk, km }

String formatStation(double m, ChainageStyle style) {
  final neg = m < 0;
  final tenths = (m.abs() * 10).round(); // округлення до 0.1 м з переносом (99.96 → 100.0)
  final unit = style == ChainageStyle.pk ? 1000 : 10000; // у десятих метра
  final whole = tenths ~/ unit;
  final rest = tenths % unit;
  final plusDigits = style == ChainageStyle.pk ? 2 : 3;
  final plus = '${(rest ~/ 10).toString().padLeft(plusDigits, '0')}.${rest % 10}';
  final prefix = style == ChainageStyle.pk ? t('ПК') : t('км');
  return '$prefix ${neg ? '-' : ''}$whole+$plus';
}

final _labelRe = RegExp(r'^\s*(?:ПК|PK|КМ|KM)?\s*(\d+)\s*\+\s*(\d+)(?:[.,](\d+))?\s*$',
    caseSensitive: false, unicode: true);

/// Підпис пікетажу з креслення: «0+000», «12+543.2» (км), «125+43» (ПК). Інакше — null.
(double, ChainageStyle)? parseChainageLabel(String text) {
  final m = _labelRe.firstMatch(text);
  if (m == null) return null;
  final big = int.parse(m[1]!);
  final plusInt = m[2]!;
  final plus = double.parse('$plusInt.${m[3] ?? '0'}');
  return switch (plusInt.length) {
    3 => (big * 1000 + plus, ChainageStyle.km),
    2 => (big * 100 + plus, ChainageStyle.pk),
    _ => null,
  };
}

class LabelPoint {
  final String text;
  final Vec pos;
  const LabelPoint(this.text, this.pos);
}

class StartGuess {
  /// ПК початку, м — для ланцюжка в напрямі [reversed].
  final double startStation;

  /// true — пікетаж іде від кінця зібраного ланцюжка до початку.
  final bool reversed;
  final ChainageStyle style;
  final int labelsUsed;

  /// true — ПК початку взято з підпису біля самого початку осі; false — оцінка за іншими підписами.
  final bool exact;

  /// Найбільша розбіжність між підписами, м (мала — підписи узгоджені).
  final double spread;
  StartGuess(this.startStation, this.reversed, this.style, this.labelsUsed, this.exact, this.spread);
}

/// Підписи, що стоять не далі [maxOffset] м від осі, дають ПК початку й напрям пікетажу.
StartGuess? guessStart(List<Segment> chain, List<LabelPoint> labels, {double maxOffset = 30}) {
  if (chain.isEmpty) return null;
  final al = RoadAxis(chain);
  final pts = <(double value, double along, ChainageStyle style)>[];
  for (final l in labels) {
    final v = parseChainageLabel(l.text);
    if (v == null) continue;
    final r = al.locate(l.pos);
    if (r.beyond && (r.station < -maxOffset || r.station > al.length + maxOffset)) continue;
    if (r.offset.abs() > maxOffset) continue;
    pts.add((v.$1, r.station, v.$2));
  }
  if (pts.isEmpty) return null;

  double spreadOf(List<double> xs) =>
      xs.reduce((a, b) => a > b ? a : b) - xs.reduce((a, b) => a < b ? a : b);
  final fwd = [for (final p in pts) p.$1 - p.$2];
  final bwd = [for (final p in pts) p.$1 - (al.length - p.$2)];
  // Один підпис напряму не визначає — тоді прямий, якщо він не дає від'ємного ПК початку.
  final reversed = pts.length >= 2 ? spreadOf(bwd) < spreadOf(fwd) : (fwd.first < 0 && bwd.first >= 0);
  final est = reversed ? bwd : fwd;
  final sorted = [...est]..sort();
  var start = sorted[sorted.length ~/ 2];
  var exact = false;
  // Підпис біля самого початку осі — беремо його значення як є.
  for (final p in pts) {
    final fromStart = reversed ? al.length - p.$2 : p.$2;
    if (fromStart.abs() < maxOffset) {
      start = p.$1;
      exact = true;
      break;
    }
  }
  if (!exact) start = start.roundToDouble();
  final kmCount = pts.where((p) => p.$3 == ChainageStyle.km).length;
  final style = kmCount * 2 >= pts.length ? ChainageStyle.km : ChainageStyle.pk;
  return StartGuess(start, reversed, style, pts.length, exact, spreadOf(est));
}
