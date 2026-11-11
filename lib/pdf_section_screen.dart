// Поперечник з PDF для поточного ПК: потрібна сторінка, наближення до підпису, «попередній / наступний».
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'chainage.dart';
import 'i18n.dart';
import 'pdf_sections.dart';

class PdfSectionScreen extends StatefulWidget {
  final Uint8List bytes;
  final PdfSections sections;
  final SectionLabel start;
  final ChainageStyle style;
  const PdfSectionScreen(
      {super.key, required this.bytes, required this.sections, required this.start, required this.style});

  @override
  State<PdfSectionScreen> createState() => _PdfSectionScreenState();
}

class _PdfSectionScreenState extends State<PdfSectionScreen> {
  late SectionLabel _cur = widget.start;
  final _ctrl = PdfViewerController();
  PdfDocument? _doc;

  int get _index => widget.sections.labels.indexOf(_cur);

  void _go(int i) {
    final labels = widget.sections.labels;
    if (i < 0 || i >= labels.length) return;
    setState(() => _cur = labels[i]);
    _focus();
  }

  /// Наближає до підпису й місця під ним (там зазвичай креслення поперечника).
  Future<void> _focus() async {
    final r = _cur.rect, doc = _doc;
    if (doc == null) return;
    if (r == null) {
      await _ctrl.goToPage(pageNumber: _cur.page);
      return;
    }
    final page = doc.pages[_cur.page - 1];
    final w = page.width, h = page.height;
    final cx = (r.left + r.right) / 2;
    final area = PdfRect(
      math.max(0, cx - w * 0.2),
      math.min(h, r.top + h * 0.02),
      math.min(w, cx + w * 0.2),
      math.max(0, r.bottom - h * 0.25),
    );
    await _ctrl.goToRectInsidePage(pageNumber: _cur.page, rect: area);
  }

  @override
  Widget build(BuildContext context) {
    final labels = widget.sections.labels;
    final i = _index;
    return Scaffold(
      appBar: AppBar(
        title: Text(t('Поперечник {pk}', {'pk': formatStation(_cur.station, widget.style)})),
        actions: [
          IconButton(
            tooltip: t('Попередній поперечник'),
            icon: const Icon(Icons.chevron_left),
            onPressed: i > 0 ? () => _go(i - 1) : null,
          ),
          IconButton(
            tooltip: t('Наступний поперечник'),
            icon: const Icon(Icons.chevron_right),
            onPressed: i < labels.length - 1 ? () => _go(i + 1) : null,
          ),
        ],
      ),
      body: PdfViewer.data(
        widget.bytes,
        sourceName: widget.sections.fileName,
        controller: _ctrl,
        initialPageNumber: _cur.page,
        params: PdfViewerParams(
          onViewerReady: (doc, _) {
            _doc = doc;
            _focus();
          },
          pageOverlaysBuilder: (context, pageRect, page) {
            final r = _cur.rect;
            if (r == null || page.pageNumber != _cur.page) return const [];
            final rect = PdfRect(r.left, r.top, r.right, r.bottom).toRect(page: page, scaledPageSize: pageRect.size);
            return [
              Positioned.fromRect(
                rect: rect.inflate(4),
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(border: Border.all(color: const Color(0xFFD32F2F), width: 2)),
                  ),
                ),
              ),
            ];
          },
        ),
      ),
    );
  }
}
