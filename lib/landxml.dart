// LandXML (Civil 3D та інші): вісь у плані (прямі, кругові криві, клотоїди) і поздовжні профілі.
// Точки в LandXML записані «північ схід» — тут переводяться в X = схід, Y = північ.
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:xml/xml.dart';

import 'geometry.dart';
import 'i18n.dart';
import 'problems.dart';
import 'profile.dart';

class LxAlignment {
  final String name;
  final double staStart;
  final List<Segment> segs;
  final List<Profile> profiles;

  /// Зауваження до цієї осі (клотоїда не зійшлася з кінцем, розриви пікетажу…).
  final List<Problem> problems;

  /// Поперечники з відмітками (CrossSects), якщо їх експортовано разом з віссю.
  final CrossSections? sections;
  LxAlignment(this.name, this.staStart, this.segs, this.profiles, this.problems, [this.sections]);

  double get length => segs.fold(0.0, (a, s) => a + s.length);
}

class LandXmlException implements Exception {
  final Problem problem;
  const LandXmlException(this.problem);
}

Problem _notLandXml(String why) => Problem(Severity.error, 'Файл не схожий на LandXML',
    detail: why,
    fixes: const [
      'Civil 3D: «Вивід → Експорт у LandXML», позначте вісь і її профіль.',
      'Або збережіть вісь як DXF («Експорт у AutoCAD», потім «Зберегти як DXF»).',
    ]);

List<LxAlignment> parseLandXml(Uint8List bytes) {
  XmlDocument doc;
  try {
    doc = XmlDocument.parse(utf8.decode(bytes, allowMalformed: true));
  } catch (e) {
    throw LandXmlException(_notLandXml(t('XML не читається: {e}', {'e': e})));
  }
  final root = doc.rootElement;
  if (root.localName != 'LandXML') throw LandXmlException(_notLandXml(t('Кореневий елемент — «{n}».', {'n': root.localName})));

  final unit = root.findAllElements('Metric').firstOrNull?.getAttribute('linearUnit') ??
      (root.findAllElements('Imperial').isNotEmpty ? 'foot' : 'meter');
  if (unit != 'meter') {
    throw LandXmlException(Problem(Severity.error, t('Одиниці LandXML — «{u}», а не метри', {'u': unit}),
        fixes: const ['Експортуйте LandXML з метричними одиницями (налаштування креслення Civil 3D → Units: Meters).']));
  }

  final out = <LxAlignment>[];
  for (final a in root.findAllElements('Alignment')) {
    final problems = <Problem>[];
    final segs = <Segment>[];
    for (final g in a.findElements('CoordGeom').expand((c) => c.childElements)) {
      switch (g.localName) {
        case 'Line':
          segs.add(LineSeg(_pt(g, 'Start'), _pt(g, 'End')));
        case 'Curve':
          segs.add(_curve(g));
        case 'Spiral':
          final (pieces, miss) = _spiral(g);
          segs.addAll(pieces);
          if (miss > 0.05) {
            problems.add(Problem(Severity.warning,
                t('Клотоїда «{n}» не зійшлася з кінцем на {m} м',
                    {'n': g.getAttribute('name') ?? '', 'm': miss.toStringAsFixed(2)}),
                fixes: const ['Перевірте параметри клотоїди в Civil 3D; ПК на ній може відрізнятися на цю величину.']));
          }
        default:
          problems.add(Problem(Severity.warning, t('Елемент осі «{n}» програма не читає', {'n': g.localName}),
              fixes: const ['Повідомте розробнику, з якої програми цей LandXML.']));
      }
    }
    if (a.findElements('StaEquation').isNotEmpty) {
      problems.add(const Problem(Severity.warning, 'В осі є розриви пікетажу (StaEquation)',
          detail: 'Програма рахує пікетаж без розривів — після розриву ПК відрізнятиметься.',
          fixes: ['Розбийте вісь у Civil 3D на ділянки між розривами й додайте їх окремими об’єктами.']));
    }
    final profiles = <Profile>[];
    for (final p in a.findElements('Profile')) {
      for (final pa in p.findElements('ProfAlign')) {
        final pvis = <Pvi>[];
        for (final e in pa.childElements) {
          final v = _nums(e.innerText);
          if (v.length < 2) continue;
          switch (e.localName) {
            case 'PVI':
              pvis.add(Pvi(v[0], v[1]));
            case 'ParaCurve' || 'UnsymParaCurve' || 'CircCurve':
              // Кругову вертикальну криву з довжиною наближаємо параболою — різниця міліметри.
              final len = double.tryParse(e.getAttribute('length') ?? '') ??
                  ((double.tryParse(e.getAttribute('lengthIn') ?? '') ?? 0) +
                      (double.tryParse(e.getAttribute('lengthOut') ?? '') ?? 0));
              pvis.add(Pvi(v[0], v[1], len));
          }
        }
        if (pvis.length >= 2) {
          profiles.add(Profile('LandXML: ${pa.getAttribute('name') ?? p.getAttribute('name') ?? t('профіль')}', pvis));
        }
      }
    }
    if (segs.isEmpty) continue;
    out.add(LxAlignment(a.getAttribute('name') ?? t('Вісь {n}', {'n': out.length + 1}),
        double.tryParse(a.getAttribute('staStart') ?? '') ?? 0, segs, profiles, problems, _crossSects(a)));
  }
  if (out.isEmpty) {
    throw LandXmlException(_notLandXml(t('У файлі немає осей (Alignment з CoordGeom).')));
  }
  return out;
}

// Верх конструкції (проєкт): Civil 3D пише Top / FG / Finished Grade, румунською — Proiect.
final _topSurface = RegExp(r'top|finish|(^|[^a-z])fg([^a-z]|$)|верх|проєкт|проект|proiect', caseSensitive: false);

/// Поперечники осі: у кожному CrossSect — поверхня проєкту (DesignCrossSectSurf; верх, якщо їх кілька),
/// точки «зміщення відмітка», «−» — ліворуч.
CrossSections? _crossSects(XmlElement alignment) {
  final rows = <(double, List<(double, double)>)>[];
  for (final cs in alignment.findElements('CrossSects').expand((c) => c.findElements('CrossSect'))) {
    final sta = double.tryParse(cs.getAttribute('sta') ?? '');
    final surfs = cs.findElements('DesignCrossSectSurf').toList();
    if (sta == null || surfs.isEmpty) continue;
    final surf = surfs.firstWhere((s) => _topSurface.hasMatch(s.getAttribute('name') ?? ''), orElse: () => surfs.first);
    final pts = <(double, double)>[
      for (final p in surf.findElements('CrossSectPnt'))
        if (_nums(p.innerText) case [final off, final z, ...]) (off, z)
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    if (pts.length >= 2) rows.add((sta, pts));
  }
  return rows.isEmpty ? null : CrossSections('LandXML', rows);
}

List<double> _nums(String s) =>
    [for (final t in s.trim().split(RegExp(r'\s+'))) if (double.tryParse(t) != null) double.parse(t)];

/// «північ схід» → Vec(схід, північ).
Vec _pt(XmlElement g, String tag) {
  final e = g.findElements(tag).firstOrNull;
  final v = e == null ? const <double>[] : _nums(e.innerText);
  if (v.length < 2) throw LandXmlException(_notLandXml(t('У елементі {e} немає точки {tag}.', {'e': g.localName, 'tag': tag})));
  return Vec(v[1], v[0]);
}

Segment _curve(XmlElement g) {
  final s = _pt(g, 'Start'), c = _pt(g, 'Center'), e = _pt(g, 'End');
  final r = s.dist(c);
  final a0 = math.atan2(s.y - c.y, s.x - c.x);
  final a1 = math.atan2(e.y - c.y, e.x - c.x);
  final ccw = (g.getAttribute('rot') ?? 'ccw') == 'ccw';
  final len = double.tryParse(g.getAttribute('length') ?? '');
  var sweep = ccw ? (a1 - a0) % (2 * math.pi) : -((a0 - a1) % (2 * math.pi));
  if (len != null && r > 0) sweep = (ccw ? 1 : -1) * len / r; // довжина з файлу точніша за кути
  return ArcSeg(c, r, a0, sweep);
}

/// Клотоїда: кривина змінюється лінійно від 1/radiusStart до 1/radiusEnd. Рахується чисельно й
/// подається короткими відрізками (до 1 м, відхилення від кривої — частки міліметра).
/// Повертає шматки й розбіжність кінця з точкою End, м.
(List<Segment>, double) _spiral(XmlElement g) {
  final start = _pt(g, 'Start'), pi = _pt(g, 'PI'), end = _pt(g, 'End');
  final len = double.tryParse(g.getAttribute('length') ?? '') ?? 0;
  double curv(String a) {
    final v = g.getAttribute(a);
    if (v == null || v == 'INF' || v.toLowerCase() == 'infinity') return 0;
    final r = double.tryParse(v) ?? 0;
    return r == 0 ? 0 : 1 / r;
  }

  final sign = (g.getAttribute('rot') ?? 'ccw') == 'ccw' ? 1.0 : -1.0;
  final k0 = sign * curv('radiusStart'), k1 = sign * curv('radiusEnd');
  final h0 = math.atan2(pi.y - start.y, pi.x - start.x);
  double heading(double s) => h0 + k0 * s + (k1 - k0) * s * s / (2 * len);
  final n = math.max(1, len.ceil());
  final pts = <Vec>[start];
  var p = start;
  for (var i = 0; i < n; i++) {
    final a = len * i / n, b = len * (i + 1) / n, m = (a + b) / 2;
    // Сімпсон для ∫cos h і ∫sin h на кроці — точність набагато вища за міліметр.
    double ix(double Function(double) f) => (b - a) / 6 * (f(heading(a)) + 4 * f(heading(m)) + f(heading(b)));
    p = p + Vec(ix(math.cos), ix(math.sin));
    pts.add(p);
  }
  return ([for (var i = 1; i < pts.length; i++) LineSeg(pts[i - 1], pts[i])], p.dist(end));
}
