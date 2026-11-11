// PDF поперечників: на якій сторінці (і де на ній) підпис «PK 0+025.00» — щоб відкрити поперечник поточного ПК.
// Тут — без бібліотеки PDF (перевіряється тестами на комп'ютері); читання й показ PDF — pdf_reader.dart.
import 'chainage.dart';

/// Прямокутник у координатах сторінки PDF (початок — лівий нижній кут, top > bottom).
class LabelRect {
  final double left, top, right, bottom;
  const LabelRect(this.left, this.top, this.right, this.bottom);
}

class SectionLabel {
  final double station;
  final int page;

  /// Де підпис на сторінці, у координатах PDF (початок — лівий нижній кут), або null.
  final LabelRect? rect;
  const SectionLabel(this.station, this.page, this.rect);

  List<num> toJson() => [station, page, if (rect != null) ...[rect!.left, rect!.top, rect!.right, rect!.bottom]];

  factory SectionLabel.fromJson(List v) => SectionLabel(
        (v[0] as num).toDouble(),
        (v[1] as num).toInt(),
        v.length >= 6
            ? LabelRect((v[2] as num).toDouble(), (v[3] as num).toDouble(), (v[4] as num).toDouble(), (v[5] as num).toDouble())
            : null,
      );
}

class PdfSections {
  final String fileName;
  final int pageCount;
  final List<SectionLabel> labels;
  PdfSections(this.fileName, this.pageCount, List<SectionLabel> labels)
      : labels = List.unmodifiable([...labels]..sort((a, b) => a.station.compareTo(b.station)));

  /// Найближчий підписаний поперечник до ПК [st] — не далі [maxGap] м.
  SectionLabel? nearest(double st, {double maxGap = 60}) {
    SectionLabel? best;
    for (final l in labels) {
      if (best == null || (l.station - st).abs() < (best.station - st).abs()) best = l;
    }
    return best != null && (best.station - st).abs() <= maxGap ? best : null;
  }

  Map<String, dynamic> toJson() => {
        'file': fileName,
        'pages': pageCount,
        'labels': [for (final l in labels) l.toJson()],
      };

  factory PdfSections.fromJson(Map<String, dynamic> j) => PdfSections(
      j['file'] as String, (j['pages'] as num).toInt(), [for (final v in j['labels'] as List) SectionLabel.fromJson(v as List)]);
}

// «Pc» — пікет на аркушах Молдови й Румунії («Pc 10+50.00»); розпізнаний скан дає й кириличне «Рс».
final _label =
    RegExp(r'(?:(ПК|PK|KM|КМ|PC|РС)\s*)?(\d+\s*\+\s*\d+(?:[.,]\d+)?)', caseSensitive: false, unicode: true);

/// Підписи ПК у тексті сторінки. [rects] — рамки символів (якщо є) для місця підпису.
/// Підписи з «PK / ПК / km» перед числом — надійніші; якщо такі є, голі «0+025» відкидаються.
List<(SectionLabel, bool prefixed)> labelsOnPage(int page, String text, [List<LabelRect>? rects]) {
  final out = <(SectionLabel, bool)>[];
  for (final m in _label.allMatches(text)) {
    final v = parseChainageLabel(m[2]!.replaceAll(RegExp(r'\s+'), ''));
    if (v == null) continue;
    LabelRect? r;
    if (rects != null && m.end <= rects.length) {
      final rs = rects.sublist(m.start, m.end);
      r = LabelRect(
        rs.map((x) => x.left).reduce((a, b) => a < b ? a : b),
        rs.map((x) => x.top).reduce((a, b) => a > b ? a : b),
        rs.map((x) => x.right).reduce((a, b) => a > b ? a : b),
        rs.map((x) => x.bottom).reduce((a, b) => a < b ? a : b),
      );
    }
    out.add((SectionLabel(v.$1, page, r), m[1] != null));
  }
  return out;
}

/// Усі підписи документа: один на ПК (перший), з урахуванням правила про «PK».
List<SectionLabel> pickLabels(List<(SectionLabel, bool)> all) {
  final anyPrefixed = all.any((x) => x.$2);
  final seen = <double>{};
  return [
    for (final (l, pref) in all)
      if ((!anyPrefixed || pref) && seen.add(l.station)) l,
  ];
}
