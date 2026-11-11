// Читання PDF бібліотекою pdfrx (PDFium): текст сторінок → підписи поперечників.
import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

import 'pdf_sections.dart';

Future<PdfSections> indexPdf(Uint8List bytes, String fileName) async {
  await pdfrxFlutterInitialize();
  final doc = await PdfDocument.openData(bytes, sourceName: fileName);
  try {
    final all = <(SectionLabel, bool)>[];
    for (final p in doc.pages) {
      final t = await p.loadText();
      if (t == null) continue;
      final rects = [for (final r in t.charRects) LabelRect(r.left, r.top, r.right, r.bottom)];
      all.addAll(labelsOnPage(p.pageNumber, t.fullText, rects));
    }
    return PdfSections(fileName, doc.pages.length, pickLabels(all));
  } finally {
    await doc.dispose();
  }
}
