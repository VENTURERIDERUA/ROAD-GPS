// Схема поперечника: вісь, лінії плану, які він перетинає (кромки, бровки, межі відводу…), і «я тут»; якщо є
// поперечник з відмітками — ще й його лінія проєкту (вертикаль перебільшено) з відмітками.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'i18n.dart';
import 'lines.dart';

class CrossStrip extends StatelessWidget {
  final List<CrossHit> hits;

  /// Де людина: відстань від осі, м («+» — праворуч).
  final double offset;

  /// Лінія проєкту з поперечника: (зміщення, відмітка) зліва направо. null — поперечника тут немає.
  final List<(double, double)>? section;

  /// Відмітка проєкту там, де людина (null — поза лінією проєкту чи невідомо).
  final double? myZ;
  const CrossStrip({super.key, required this.hits, required this.offset, this.section, this.myZ});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: section == null ? 74 : 104,
        width: double.infinity,
        child: CustomPaint(painter: _StripPainter(hits, offset, section, myZ)),
      );
}

class _StripPainter extends CustomPainter {
  final List<CrossHit> hits;
  final double offset;
  final List<(double, double)>? section;
  final double? myZ;

  /// Мова підписів: змінилась — перемалювати.
  final Lang _lang = lang.value;
  _StripPainter(this.hits, this.offset, this.section, this.myZ);

  @override
  void paint(Canvas canvas, Size size) {
    var extent = offset.abs();
    for (final h in hits) {
      extent = math.max(extent, h.offset.abs());
    }
    for (final p in section ?? const <(double, double)>[]) {
      extent = math.max(extent, p.$1.abs());
    }
    extent = math.max(extent + 2, 8);
    const pad = 14.0;
    final cx = size.width / 2;
    final base = section == null ? 34.0 : 64.0;
    double x(double v) => cx + v / extent * (cx - pad);

    final grey = Paint()
      ..color = Colors.black26
      ..strokeWidth = 1;
    canvas.drawLine(Offset(pad, base), Offset(size.width - pad, base), grey);

    void text(String s, Offset at, Color c, {double size = 10, bool bold = false, bool center = true}) {
      final tp = TextPainter(
        text: TextSpan(
            text: s, style: TextStyle(fontSize: size, color: c, fontWeight: bold ? FontWeight.bold : null)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, at - Offset(center ? tp.width / 2 : 0, 0));
    }

    text(t('ліворуч'), const Offset(pad, 0), Colors.black45, center: false);
    final rightLabel = TextPainter(
      text: TextSpan(text: t('праворуч'), style: const TextStyle(fontSize: 10)),
      textDirection: TextDirection.ltr,
    )..layout();
    text(t('праворуч'), Offset(size.width - pad - rightLabel.width, 0), Colors.black45, center: false);

    // Вісь.
    canvas.drawLine(Offset(cx, base - 14), Offset(cx, base + 10),
        Paint()
          ..color = const Color(0xFFD32F2F)
          ..strokeWidth = 2.5);

    var lastLabelX = -1000.0;
    for (final h in hits) {
      final hx = x(h.offset);
      final tall = h.role == LineRole.row ? 14.0 : 9.0;
      canvas.drawLine(Offset(hx, base - tall), Offset(hx, base + tall),
          Paint()
            ..color = h.role.color
            ..strokeWidth = h.role == LineRole.row ? 3 : 2);
      if (hx - lastLabelX > 30) {
        text(h.offset.abs().toStringAsFixed(1), Offset(hx, base + 16), h.role.color);
        lastLabelX = hx;
      }
    }

    // Лінія проєкту з відмітками: перебільшено по вертикалі, у смузі над схемою.
    double? Function(double z)? y;
    final sec = section;
    if (sec != null) {
      final zs = [for (final p in sec) p.$2];
      final zMax = zs.reduce(math.max), zMin = zs.reduce(math.min);
      final span = math.max(zMax - zMin, 0.05);
      y = (z) => base - 22 - (z - zMin) / span * 14;
      final path = Path()..moveTo(x(sec.first.$1), y(sec.first.$2)!);
      for (final p in sec.skip(1)) {
        path.lineTo(x(p.$1), y(p.$2)!);
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0xFFD32F2F)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
      var last = -1000.0;
      for (final p in sec) {
        final px = x(p.$1);
        if (px - last > 44) {
          text(p.$2.toStringAsFixed(2), Offset(px, y(p.$2)! - 14), const Color(0xFFB71C1C));
          last = px;
        }
      }
    }

    // «Я тут» — на лінії проєкту, якщо відмітка в точці відома, інакше на схемі.
    final mx = x(offset).clamp(pad, size.width - pad).toDouble();
    final my = (myZ != null && y != null) ? y(myZ!)! : base;
    canvas.drawCircle(Offset(mx, my), 7, Paint()..color = const Color(0xFF1E88E5));
    canvas.drawCircle(
        Offset(mx, my),
        7,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    // Праворуч від точки (біля правого краю — ліворуч), щоб не налазити на числа під рисками.
    final meRight = mx < size.width - 30;
    text(t('я'), Offset(meRight ? mx + 10 : mx - 20, my - 8), const Color(0xFF1E88E5), size: 12, bold: true, center: false);
  }

  @override
  bool shouldRepaint(_StripPainter old) =>
      old.offset != offset || old.hits != hits || old.section != section || old.myZ != myZ || old._lang != _lang;
}
