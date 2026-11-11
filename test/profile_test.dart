import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:road_gps/chainage.dart';
import 'package:road_gps/geometry.dart';
import 'package:road_gps/landxml.dart';
import 'package:road_gps/notes.dart' show WorkType;
import 'package:road_gps/pdf_sections.dart';
import 'package:road_gps/problems.dart' show Severity;
import 'package:road_gps/profile.dart';
import 'package:road_gps/road_object.dart';
import 'package:road_gps/vidomist.dart';

Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  group('профіль', () {
    // +2 % до ПК 1+00, далі −2 %; вертикальна крива 40 м.
    final p = Profile('t', const [Pvi(0, 100), Pvi(100, 102, 40), Pvi(200, 100)]);

    test('прямі ділянки, вертикальна крива, ухил', () {
      expect(p.elevationAt(50), closeTo(101, 1e-9));
      expect(p.elevationAt(80), closeTo(101.6, 1e-9)); // початок кривої
      expect(p.elevationAt(100), closeTo(101.8, 1e-9)); // середина: 102 − 0.04·40/8
      expect(p.elevationAt(120), closeTo(101.6, 1e-9));
      expect(p.elevationAt(150), closeTo(101, 1e-9));
      expect(p.gradeAt(50), closeTo(0.02, 1e-12));
      expect(p.gradeAt(100), closeTo(0, 1e-12));
      expect(p.gradeAt(150), closeTo(-0.02, 1e-12));
      expect(p.elevationAt(-1), isNull);
      expect(p.elevationAt(201), isNull);
      expect(gradeText(-0.0042), '−4.2 ‰');
    });

    test('ширини', () {
      final w = Widths('t', const [(0, 5.25, 5.25), (100, 3.5, 3.5)]);
      expect(w.at(50)!.$1, closeTo(4.375, 1e-9));
      expect(w.at(101), isNull);
    });

    test('поперечники з відмітками: свій ПК, між сусідніми, а далеко — немає', () {
      final cs = CrossSections('t', const [
        (100, [(-5, 10.0), (0, 10.1), (5, 10.0)]),
        (120, [(-6, 11.0), (0, 11.1), (6, 11.0)]),
        (200, [(-5, 12.0), (5, 12.0)]),
      ]);
      expect(cs.lineAt(100.5)!.$2, 100);
      expect(zOnLine(cs.lineAt(100)!.$1, 2.5), closeTo(10.05, 1e-9));
      final mid = cs.lineAt(110)!;
      expect((mid.$2, mid.$3), (100, 120));
      expect(zOnLine(mid.$1, 0), closeTo(10.6, 1e-9));
      expect(zOnLine(mid.$1, 5), closeTo((10.0 + (11.1 - 0.1 * 5 / 6)) / 2, 1e-9));
      expect(zOnLine(mid.$1, 5.5), isNull); // лише там, де є обидва
      expect(cs.lineAt(160), isNull); // 80 м між поперечниками — поперечника тут немає
      expect(cs.lineAt(90), isNull);
      expect(cs.lineAt(250), isNull);
      final back = CrossSections.fromJson(jsonDecode(jsonEncode(cs.toJson())) as Map<String, dynamic>);
      expect(back.rows[1].$2[2], (6.0, 11.0));
    });
  });

  group('відомість CSV', () {
    test('кома в числах, кирилиця, проєкт — не земля, ширина → напівширина', () {
      final t = parseCsv(b('ПК;Відмітка землі;Відмітка проєкту;Ширина\n'
          '0+00;83,10;84,20;10,5\n0+50;83,00;84,00;10,5\nПК 1+00;82,90;83,80;7\n'));
      final cols = guessColumns(t);
      expect(cols[ColumnRole.station], 0);
      expect(cols[ColumnRole.z], 2);
      expect(cols[ColumnRole.width], 3);
      final r = buildVidomist(t, cols, 'v.csv', axisStart: 0, axisEnd: 100);
      expect(r.problems, isEmpty);
      expect(r.profile!.elevationAt(25), closeTo(84.1, 1e-9));
      expect(r.widths!.at(100)!.$2, closeTo(3.5, 1e-9));
    });

    test('без заголовка, табуляція; погані рядки й ПК поза віссю — попередження', () {
      final t = parseCsv(b('0\t84.2\n50\tx\n100\t83.8\n'));
      expect(t.header, ['Колонка 1', 'Колонка 2']);
      final r = buildVidomist(t, {ColumnRole.station: 0, ColumnRole.z: 1}, 'v.csv', axisStart: 5000, axisEnd: 6000);
      expect(r.profile!.pvis.length, 2);
      expect(r.problems.map((p) => p.title), contains('Не прочиталось клітинок: 1'));
      expect(r.problems.map((p) => p.title), contains('ПК відомості не збігаються з віссю'));
    });

    test('порожній файл і без колонки ПК — помилки з порадами', () {
      expect(() => parseCsv(b('\n\n')), throwsA(isA<VidomistException>()));
      final r = buildVidomist(parseCsv(b('a;b\n1;2\n')), const {}, 'v.csv');
      expect(r.problems.single.fixes, isNotEmpty);
    });
  });

  group('поперечники з таблиці CSV', () {
    test('колонки за назвами (укр., рум.), точки з одним ПК — один поперечник, зміщення по порядку', () {
      final t = parseCsv(b('ПК;Зміщення, м;Відмітка проєкту\n'
          '0+25;3,5;84,10\n0+25;-3,5;84,10\n0+25;0;84,20\n'
          '0+50;-3,5;84,00\n0+50;3,5;84,00\n'));
      final cols = guessXsColumns(t);
      expect(cols, {XsRole.station: 0, XsRole.offset: 1, XsRole.z: 2});
      final r = buildCrossSectionsCsv(t, cols, 'xs.csv', axisStart: 0, axisEnd: 100);
      expect(r.problems, isEmpty);
      final cs = r.sections!;
      expect(cs.source, 'CSV: xs.csv');
      expect(cs.rows.map((x) => x.$1), [25, 50]);
      expect(cs.rows.first.$2, [(-3.5, 84.1), (0.0, 84.2), (3.5, 84.1)]);
      expect(zOnLine(cs.lineAt(37.5)!.$1, 0), closeTo(84.1, 1e-9)); // на 0+50 вісь — посередині між ±3.5
      expect(zOnLine(cs.lineAt(37.5)!.$1, 3.5), closeTo(84.05, 1e-9));
      // Румунською: «Distanta fata de ax» — зміщення, а не пікетаж.
      final ro = guessXsColumns(parseCsv(b('Pozitie km;Distanta fata de ax;Cota proiect\n0+25;-3;84\n')));
      expect(ro, {XsRole.station: 0, XsRole.offset: 1, XsRole.z: 2});
    });

    test('попередження: одна точка, повтор зміщення, усі з одного боку, не та ділянка', () {
      final t = parseCsv(b('PK;offset;Z\n0+25;1;84\n0+25;1;85\n0+25;2;84\n0+50;3;84\nx;1;2\n'));
      final r = buildCrossSectionsCsv(t, guessXsColumns(t), 'xs.csv', axisStart: 1000, axisEnd: 2000);
      final titles = r.problems.map((p) => p.title).join(' | ');
      for (final s in ['Не прочиталось рядків: 1', 'Однакове зміщення', 'з однією точкою: 1', 'не збігаються з віссю']) {
        expect(titles, contains(s));
      }
      expect(r.sections!.rows.single.$2, [(1.0, 84.0), (2.0, 84.0)]);
      expect(offsetsOneSided([(0, [(1.0, 1.0), (2.0, 1.0), (3.0, 1.0)])]), isTrue);
      expect(buildCrossSectionsCsv(t, const {}, 'xs.csv').problems.single.severity, Severity.error);
    });
  });

  group('LandXML', () {
    // Пряма 100 м на схід → клотоїда 50 м (∞ → R200, ліворуч) → крива R200 ліворуч 50 м.
    // У LandXML точки — «північ схід». A² = R·L = 10000; кінець клотоїди: x ≈ L − L⁵/(40A⁴), y ≈ L³/(6A²) − L⁷/(336A⁶).
    const sx = 49.921875, sy = 2.081008;
    String xml({String unit = 'meter', String extra = ''}) => '''<?xml version="1.0"?>
<LandXML xmlns="http://www.landxml.org/schema/LandXML-1.2" version="1.2">
 <Units><Metric linearUnit="$unit"/></Units>
 <Alignments><Alignment name="A1" staStart="1000" length="200">$extra
  <CoordGeom>
   <Line><Start>5000 1000</Start><End>5000 1100</End></Line>
   <Spiral length="50" radiusStart="INF" radiusEnd="200" rot="ccw" spiType="clothoid">
     <Start>5000 1100</Start><PI>5000 1133.34</PI><End>${5000 + sy} ${1100 + sx}</End></Spiral>
  </CoordGeom>
  <Profile name="P"><ProfAlign name="Червона лінія">
   <PVI>1000 100</PVI><ParaCurve length="40">1100 102</ParaCurve><PVI>1150 101</PVI>
  </ProfAlign></Profile>
 </Alignment></Alignments>
</LandXML>''';

    test('пряма, клотоїда, профіль з вертикальною кривою; «північ схід» → X/Y', () {
      final a = parseLandXml(b(xml())).single;
      expect(a.name, 'A1');
      expect(a.staStart, 1000);
      expect(a.problems, isEmpty);
      expect(a.segs.first.start.dist(const Vec(1000, 5000)), lessThan(1e-9));
      expect(a.segs.last.end.dist(const Vec(1100 + sx, 5000 + sy)), lessThan(0.001));
      expect(a.length, closeTo(150, 0.001));
      final pr = a.profiles.single;
      expect(pr.source, 'LandXML: Червона лінія');
      expect(pr.elevationAt(1100), closeTo(102 - (0.02 + 0.02) * 40 / 8, 1e-9));
      expect(a.sections, isNull);
    });

    test('поперечники CrossSects: поверхня верху, точки «зміщення відмітка»', () {
      final a = parseLandXml(b(xml(extra: '''
  <CrossSects><CrossSect sta="1050">
   <DesignCrossSectSurf name="Datum"><CrossSectPnt>-5 99</CrossSectPnt><CrossSectPnt>5 99</CrossSectPnt></DesignCrossSectSurf>
   <DesignCrossSectSurf name="Top"><CrossSectPnt code="ETW">3.5 100.41</CrossSectPnt><CrossSectPnt code="CL">0 100.5</CrossSectPnt>
    <CrossSectPnt code="ETW">-3.5 100.41</CrossSectPnt></DesignCrossSectSurf>
  </CrossSect><CrossSect sta="1060"><DesignCrossSectSurf name="Datum"><CrossSectPnt>-5 98</CrossSectPnt>
   <CrossSectPnt>5 98</CrossSectPnt></DesignCrossSectSurf></CrossSect></CrossSects>'''))).single;
      final cs = a.sections!;
      expect(cs.rows.length, 2);
      expect(cs.rows.first.$2, [(-3.5, 100.41), (0.0, 100.5), (3.5, 100.41)]);
      expect(cs.rows.last.$2.first, (-5.0, 98.0)); // одна поверхня — вона й береться
    });

    test('клотоїда — до мм проти розкладу в ряд', () {
      final a = parseLandXml(b(xml())).single;
      final end = a.segs.last.end;
      expect(end.x - 1100, closeTo(sx, 0.001));
      expect(end.y - 5000, closeTo(sy, 0.001));
      // Остання хорда (1 м) має напрям дотичної в її середині, s = 49.5: s²/(2RL).
      final last = a.segs.last;
      expect(math.atan2(last.end.y - last.start.y, last.end.x - last.start.x), closeTo(49.5 * 49.5 / 20000, 1e-4));
    });

    test('розриви пікетажу, фути, не LandXML — попередження й помилки з порадами', () {
      final a = parseLandXml(b(xml(extra: '<StaEquation staBack="1050" staAhead="1060"/>'))).single;
      expect(a.problems.single.title, contains('розриви пікетажу'));
      expect(() => parseLandXml(b(xml(unit: 'foot'))), throwsA(isA<LandXmlException>()));
      expect(() => parseLandXml(b('<html></html>')), throwsA(isA<LandXmlException>()));
      expect(() => parseLandXml(b('not xml')), throwsA(isA<LandXmlException>()));
    });
  });

  test('профіль, ширини, поперечники, вид робіт і підписи PDF зберігаються в об’єкті', () {
    final o = RoadObject(
      id: '1',
      name: 't',
      sourceFile: 't.dxf',
      axisLayer: 'AXIS',
      crsId: 'stereo70',
      startStation: 0,
      style: ChainageStyle.km,
      axis: [LineSeg(const Vec(0, 0), const Vec(100, 0))],
      profile: Profile('CSV: v.csv', const [Pvi(0, 84.2), Pvi(50, 84, 10), Pvi(100, 83.9)]),
      widths: Widths('CSV: v.csv', const [(0, 5.25, 5.25)]),
      crossSections: CrossSections('LandXML', const [(10, [(-3, 84.1), (3, 84.1)])]),
      work: WorkType.repair,
      surfaceSource: 'з точок креслення',
      surfaceTriangles: 62596,
      surfaceGround: true,
      sections: PdfSections('x.pdf', 3, const [SectionLabel(25, 1, LabelRect(1, 20, 30, 10))]),
      created: DateTime(2026, 10, 26),
    );
    final back = RoadObject.fromJson(o.toJson());
    expect(back.profile!.pvis[1].curve, 10);
    expect(back.profile!.elevationAt(25), o.profile!.elevationAt(25));
    expect(back.widths!.at(0)!.$1, 5.25);
    expect(back.work, WorkType.repair);
    expect((back.surfaceSource, back.surfaceTriangles, back.surfaceGround), ('з точок креслення', 62596, true));
    expect(back.crossSections!.rows.single.$2.last, (3.0, 84.1));
    expect(back.sections!.labels.single.rect!.top, 20);
    // Старий файл без нових полів — читається.
    final old = o.toJson()..remove('profile')..remove('widths')..remove('sections')
      ..remove('crossSections');
    expect(RoadObject.fromJson(old).profile, isNull);
    expect(RoadObject.fromJson({...o.toJson(), 'crossfall': 2.5, 'roadside': {'shoulder': 3}}).name, 't');
    expect(RoadObject.fromJson(old..remove('work')).work, WorkType.construction);
  });

  test('PDF: підписи поперечників на сторінці; голі «0+025» відкидаються, коли є «PK»', () {
    final all = [
      ...labelsOnPage(1, 'PK 0+000.00 Z ax = 84.20 B = 10.5 m\nPK 0+025.00 Z ax = 84.09'),
      ...labelsOnPage(2, '0+050.00 10.0 7.5 PK 0+050.00 Z ax'),
    ];
    final picked = pickLabels(all);
    expect([for (final l in picked) (l.station, l.page)], [(0.0, 1), (25.0, 1), (50.0, 2)]);
    final s = PdfSections('x.pdf', 2, picked);
    expect(s.nearest(30)!.station, 25);
    expect(s.nearest(500), isNull);
  });

  test('PDF М1 (Молдова, розпізнаний скан): «Pc 10+50.00» і кириличне «Рс 14+00.00»', () {
    // Уривки тексту сторінок «Vol 2_Book 2_Transversal cross section_OCR.pdf» — шум розпізнавання навколо.
    final picked = pickLabels([
      ...labelsOnPage(4, 'CE Ea т 3.33 450 [1.43 9.32 089 6.73 270 |231| 3.50\nша | Distante ,\nPc 10+50.00\nio: ater'),
      ...labelsOnPage(11, 'ь a 8.00 6.41 1.50 5.54 5.96 1.8107 437 |235 5.86\nРс 14+00.00\nVerificator de proiecte 074'),
    ]);
    expect([for (final l in picked) (l.station, l.page)], [(1050.0, 4), (1400.0, 11)]);
  });
}
