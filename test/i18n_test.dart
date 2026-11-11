import 'package:flutter_test/flutter_test.dart';
import 'package:road_gps/chainage.dart';
import 'package:road_gps/crs.dart';
import 'package:road_gps/i18n.dart';
import 'package:road_gps/notes.dart';
import 'package:road_gps/problems.dart';

void main() {
  tearDown(() => lang.value = Lang.uk);

  test('перемикання мови: ПК, сторона, назви систем, підстановки', () {
    expect(formatStation(1250.5, ChainageStyle.km), 'км 1+250.5');
    lang.value = Lang.en;
    expect(formatStation(1250.5, ChainageStyle.km), 'km 1+250.5');
    expect(sideText(3), 'right');
    expect(crsName(coordSystemById('ucs2000_tm10')), isNot(contains('зона')));
    lang.value = Lang.ro;
    expect(sideText(-3), 'stânga');
    expect(t('Позначка тут'), isNot('Позначка тут'));
    // Невідомий текст лишається як є — програма не ламається на неперекладеному.
    expect(t('якийсь новий текст'), 'якийсь новий текст');
  });

  test('попередження перекладаються там, де їх показують', () {
    lang.value = Lang.en;
    expect(t(outsideCountry.title), isNot(outsideCountry.title));
    for (final f in outsideCountry.fixes) {
      expect(t(f), isNot(f), reason: f);
    }
  });

  test('готові фрази обох видів робіт перекладено', () {
    final all = [
      for (final w in WorkType.values) ...[w.label, for (final l in noteTemplates[w]!.values) ...l]
    ];
    expect(missing(Lang.en, all), isEmpty);
    expect(missing(Lang.ro, all), isEmpty);
  });

  test('нові мови: перекладено все, підстановки {…} на місці', () {
    final ph = RegExp(r'\{\w+\}');
    for (final l in Lang.values.where((l) => l != Lang.uk && l != Lang.en && l != Lang.ro)) {
      expect(missing(l, allKeys), isEmpty, reason: l.name);
      lang.value = l;
      for (final k in allKeys) {
        expect(ph.allMatches(t(k)).map((m) => m[0]).toSet(), ph.allMatches(k).map((m) => m[0]).toSet(),
            reason: '${l.name}: $k');
      }
    }
    expect(Lang.ar.rtl, isTrue);
    expect(Lang.zh.rtl, isFalse);
  });
}
