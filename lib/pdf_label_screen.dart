// Поперечники в сканованому PDF: підписів-тексту немає, тож людина вписує ПК кожної сторінки
// (або першої й крок — решту програма заповнить, людина перевірить). Далі — як з векторним PDF:
// найближчий поперечник до місця чи точки на карті.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'chainage.dart';
import 'i18n.dart';
import 'pdf_sections.dart';
import 'keyboards.dart';

/// ПК з рядка: «0+025», «ПК 12+40», «25.5» (метри); кілька — через кому чи крапку з комою.
List<double>? parseStations(String s) {
  final parts = s.split(RegExp(r'[;,]\s+|;|\s{2,}')).map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
  final out = <double>[];
  for (final p in parts) {
    final v = parseChainageLabel(p)?.$1 ?? double.tryParse(p.replaceAll(',', '.'));
    if (v == null) return null;
    out.add(v);
  }
  return out;
}

class PdfLabelScreen extends StatefulWidget {
  final Uint8List bytes;
  final String fileName;
  final ChainageStyle style;
  const PdfLabelScreen({super.key, required this.bytes, required this.fileName, required this.style});

  @override
  State<PdfLabelScreen> createState() => _PdfLabelScreenState();
}

class _PdfLabelScreenState extends State<PdfLabelScreen> {
  final _ctrl = PdfViewerController();
  int _page = 1, _pages = 0;
  final _byPage = <int, String>{};
  final _field = TextEditingController();
  final _step = TextEditingController(text: '25');

  void _remember() {
    final v = _field.text.trim();
    v.isEmpty ? _byPage.remove(_page) : _byPage[_page] = v;
  }

  void _show(int page) {
    _remember();
    setState(() {
      _page = page;
      _field.text = _byPage[page] ?? '';
    });
  }

  Future<void> _go(int page) async {
    if (page < 1 || page > _pages) return;
    await _ctrl.goToPage(pageNumber: page);
    _show(page);
  }

  /// Від поточної сторінки до кінця: по одному поперечнику на сторінку з кроком.
  void _fillRest() {
    _remember();
    final first = parseStations(_byPage[_page] ?? '');
    final step = double.tryParse(_step.text.replaceAll(',', '.'));
    if (first == null || first.isEmpty || step == null || step <= 0) return;
    var st = first.last;
    for (var p = _page + 1; p <= _pages; p++) {
      st += step;
      _byPage[p] = formatStation(st, widget.style).split(' ').last;
    }
    setState(() {});
  }

  List<SectionLabel>? get _labels {
    final out = <SectionLabel>[];
    for (final e in _byPage.entries) {
      final v = parseStations(e.value);
      if (v == null) return null;
      out.addAll([for (final st in v) SectionLabel(st, e.key, null)]);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final cur = parseStations(_field.text);
    final labels = _labels;
    return Scaffold(
      appBar: AppBar(
        title: Text(t('Розмітка поперечників: {f}', {'f': widget.fileName}), overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(
            onPressed: labels == null || labels.isEmpty
                ? null
                : () {
                    _remember();
                    Navigator.pop(context, PdfSections(widget.fileName, _pages, _labels!));
                  },
            child: Text(t('Готово ({n})', {'n': labels?.length ?? 0})),
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: PdfViewer.data(
            widget.bytes,
            sourceName: widget.fileName,
            controller: _ctrl,
            params: PdfViewerParams(
              onViewerReady: (doc, _) => setState(() => _pages = doc.pages.length),
              onPageChanged: (p) {
                if (p != null && p != _page) _show(p);
              },
            ),
          ),
        ),
        Material(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                IconButton(onPressed: _page > 1 ? () => _go(_page - 1) : null, icon: const Icon(Icons.chevron_left)),
                Text(t('Сторінка {p} з {n}', {'p': _page, 'n': _pages})),
                IconButton(onPressed: _page < _pages ? () => _go(_page + 1) : null, icon: const Icon(Icons.chevron_right)),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _field,
                    readOnly: true,
                    showCursor: true,
                    onTap: () =>
                        showDigitPad(context, _field, label: t('ПК на цій сторінці'), onChanged: (_) => setState(_remember)),
                    onSubmitted: (_) => _go(_page + 1),
                    decoration: InputDecoration(
                      labelText: t('ПК на цій сторінці'),
                      hintText: '0+025; 0+050',
                      isDense: true,
                      errorText: _field.text.trim().isNotEmpty && cur == null ? t('Не розібрав ПК') : null,
                    ),
                  ),
                ),
              ]),
              Row(children: [
                Expanded(
                  child: Text(t('Однаковий крок — впишіть ПК цієї сторінки й заповніть решту, потім перевірте.'),
                      style: const TextStyle(color: Colors.black54, fontSize: 12)),
                ),
                SizedBox(
                  width: 70,
                  child: TextField(
                    controller: _step,
                    keyboardType: numberKeyboard,
                    decoration: InputDecoration(labelText: t('крок, м'), isDense: true),
                  ),
                ),
                TextButton(onPressed: cur == null || cur.isEmpty ? null : _fillRest, child: T('Заповнити решту')),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }
}
