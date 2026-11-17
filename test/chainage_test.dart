import 'package:flutter_test/flutter_test.dart';
import 'package:road_gps/chainage.dart';
import 'package:road_gps/geometry.dart';

void main() {
  test('запис ПК і км', () {
    expect(formatStation(12543.2, ChainageStyle.pk), 'ПК 125+43.2');
    expect(formatStation(99.96, ChainageStyle.pk), 'ПК 1+00.0');
    expect(formatStation(5.04, ChainageStyle.pk), 'ПК 0+05.0');
    expect(formatStation(12543.26, ChainageStyle.km), 'км 12+543.3');
    expect(formatStation(-12.3, ChainageStyle.pk), 'ПК -0+12.3');
  });

  test('читання підписів пікетажу', () {
    expect(parseChainageLabel('0+000'), (0.0, ChainageStyle.km));
    expect(parseChainageLabel('km 12+543.5'), (12543.5, ChainageStyle.km));
    expect(parseChainageLabel('ПК 125+43'), (12543.0, ChainageStyle.pk));
    expect(parseChainageLabel('125+43,2'), (12543.2, ChainageStyle.pk));
    expect(parseChainageLabel('Podet 3'), isNull);
    expect(parseChainageLabel('1+5'), isNull);
  });

  final straight = <Segment>[LineSeg(const Vec(0, 0), const Vec(3000, 0))];

  test('ПК початку з підпису біля початку осі', () {
    final g = guessStart(straight, const [
      LabelPoint('0+000', Vec(1, 8)),
      LabelPoint('1+000', Vec(1001, 8)),
      LabelPoint('2+000', Vec(2001, 8)),
      LabelPoint('Pod', Vec(500, 0)),
    ])!;
    expect(g.startStation, 0);
    expect(g.exact, isTrue);
    expect(g.reversed, isFalse);
    expect(g.style, ChainageStyle.km);
    expect(g.labelsUsed, 3);
  });

  test('перший підпис за 15 м від початку — ПК початку з поправкою, а не значення підпису', () {
    // Вісь починається на ПК 0+085: підпис «0+100» стоїть за 15 м від початку, «0+200» — за 115 м.
    final g = guessStart(straight, const [
      LabelPoint('ПК 2+00', Vec(115, 5)),
      LabelPoint('ПК 1+00', Vec(15, 5)),
    ])!;
    expect(g.startStation, 85);
    expect(g.exact, isFalse); // вікно попросить перевірити
  });

  test('пікетаж іде назустріч ланцюжку — напрям розвертається', () {
    final g = guessStart(straight, const [
      LabelPoint('ПК 10+00', Vec(2000, -5)),
      LabelPoint('ПК 20+00', Vec(1000, -5)),
    ])!;
    expect(g.reversed, isTrue);
    expect(g.exact, isFalse);
    expect(g.startStation, 0); // кінець ланцюжка (x=3000) — ПК 0+00
    expect(g.style, ChainageStyle.pk);
  });

  test('підписи далеко від осі не враховуються', () {
    expect(guessStart(straight, const [LabelPoint('0+000', Vec(0, 200))]), isNull);
  });
}
