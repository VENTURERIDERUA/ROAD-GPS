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
      LabelPoint('0+000', Vec(6, 8)),
      LabelPoint('1+000', Vec(1006, 8)),
      LabelPoint('2+000', Vec(2006, 8)),
      LabelPoint('Pod', Vec(500, 0)),
    ])!;
    expect(g.startStation, 0);
    expect(g.exact, isTrue);
    expect(g.reversed, isFalse);
    expect(g.style, ChainageStyle.km);
    expect(g.labelsUsed, 3);
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
