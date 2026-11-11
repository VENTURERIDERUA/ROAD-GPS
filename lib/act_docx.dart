// Акт огляду у Word (.docx): шапка, таблиця позначок за ПК, фотофіксація «до / після», підписи.
// Файл Word — це ZIP з кількома XML і теками знімків; пишемо його сами, без сторонньої бібліотеки.
// PDF — з Word («Зберегти як PDF»): так менеджер ще може поправити текст перед підписом.
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

import 'basemaps.dart' show imageSize;
import 'chainage.dart';
import 'i18n.dart';
import 'notes.dart';

String _x(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

String _run(String text, {bool bold = false, int? size}) {
  final rpr = [if (bold) '<w:b/>', if (size != null) '<w:sz w:val="$size"/><w:szCs w:val="$size"/>'].join();
  final parts = text.split('\n');
  return [
    for (var i = 0; i < parts.length; i++)
      '<w:r>${rpr.isEmpty ? '' : '<w:rPr>$rpr</w:rPr>'}${i > 0 ? '<w:br/>' : ''}<w:t xml:space="preserve">${_x(parts[i])}</w:t></w:r>',
  ].join();
}

String _p(String inner, {String align = 'left', int after = 80}) =>
    '<w:p><w:pPr><w:spacing w:after="$after"/><w:jc w:val="$align"/></w:pPr>$inner</w:p>';

String _cell(int width, String inner, {bool head = false}) =>
    '<w:tc><w:tcPr><w:tcW w:w="$width" w:type="dxa"/>${head ? '<w:shd w:val="clear" w:color="auto" w:fill="E7E6E6"/>' : ''}</w:tcPr>'
    '${inner.isEmpty ? '<w:p/>' : inner}</w:tc>';

String _table(List<int> widths, List<String> rows, {bool borders = true}) {
  final b = borders
      ? '<w:tblBorders>${['top', 'left', 'bottom', 'right', 'insideH', 'insideV'].map((s) => '<w:$s w:val="single" w:sz="4" w:space="0" w:color="808080"/>').join()}</w:tblBorders>'
      : '';
  return '<w:tbl><w:tblPr><w:tblW w:w="${widths.fold(0, (a, b) => a + b)}" w:type="dxa"/>$b'
      '<w:tblLayout w:type="fixed"/><w:tblCellMar><w:left w:w="70" w:type="dxa"/><w:right w:w="70" w:type="dxa"/></w:tblCellMar></w:tblPr>'
      '<w:tblGrid>${widths.map((w) => '<w:gridCol w:w="$w"/>').join()}</w:tblGrid>${rows.join()}</w:tbl>';
}

String _date(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.day)}.${two(t.month)}.${t.year}';
}

/// Скласти акт огляду з позначок (у тому порядку, у якому їх передали, — зазвичай за ПК).
Future<Uint8List> buildInspectionDocx({
  required String objectName,
  required ChainageStyle style,
  required String crsName,
  required List<Note> notes,
  required Future<Uint8List?> Function(String name) file,
  DateTime? date,
}) async {
  final today = date ?? DateTime.now();
  final media = <(String, Uint8List)>[]; // (ім'я в word/media, байти)
  final body = StringBuffer();

  String where(Note n) => [
        formatStation(n.station, style),
        if (n.toStation != null)
          '– ${formatStation(n.toStation!, style)} (${t('{n} м', {'n': n.length.toStringAsFixed(0)})})',
      ].join(' ');
  String side(Note n) => n.offset.abs() < 0.05
      ? t('на осі')
      : t('{n} м {side}', {'n': n.offset.abs().toStringAsFixed(1), 'side': sideText(n.offset)});
  String kind(Note n) => [t(n.kind.label), if (n.status != null) t(n.status!.label).toLowerCase()].join(', ');

  // Шапка.
  body
    ..write(_p(_run(t('АКТ ОГЛЯДУ'), bold: true, size: 32), align: 'center', after: 60))
    ..write(_p(_run(t('автомобільної дороги (за позначками ROAD-GPS)'), size: 20), align: 'center', after: 240));
  final authors = {for (final n in notes) n.author.trim()}..remove('');
  final defects = notes.where((n) => n.kind == NoteKind.defect).toList();
  final dates = [for (final n in notes) n.created]..sort();
  final stations = [for (final n in notes) ...[n.station, ?n.toStation]]..sort();
  final head = <(String, String)>[
    (t('Об’єкт'), objectName),
    (t('Дата складання'), _date(today)),
    if (dates.isNotEmpty)
      (t('Огляд проведено'), dates.first.day == dates.last.day && dates.first.month == dates.last.month && dates.first.year == dates.last.year
          ? _date(dates.first)
          : '${_date(dates.first)} – ${_date(dates.last)}'),
    if (stations.isNotEmpty) (t('Ділянка'), '${formatStation(stations.first, style)} – ${formatStation(stations.last, style)}'),
    if (authors.isNotEmpty) (t('Позначки записали'), authors.join(', ')),
    (t('Позначок'), '${notes.length}'
        '${defects.isEmpty ? '' : t(', з них дефектів {n}: {list}', {'n': defects.length, 'list': [
            for (final s in NoteStatus.values)
              if (defects.any((d) => (d.status ?? NoteStatus.open) == s)) '${t(s.label).toLowerCase()} ${defects.where((d) => (d.status ?? NoteStatus.open) == s).length}',
          ].join(', ')})}'),
    (t('Координати'), crsName),
  ];
  body.write(_table([2600, 7038], [
    for (final (k, v) in head) '<w:tr>${_cell(2600, _p(_run(k, bold: true)))}${_cell(7038, _p(_run(v)))}</w:tr>',
  ], borders: false));

  // Перелік.
  body.write(_p(_run(t('1. Перелік зауважень і дефектів'), bold: true, size: 26), after: 120));
  const w = [450, 2050, 1250, 1400, 3138, 1350];
  body.write(_table(w, [
    '<w:tr><w:trPr><w:tblHeader/></w:trPr>${[
      for (final (i, h) in ['№', 'ПК', 'Від осі', 'Тип, стан', 'Опис', 'Дата'].indexed) _cell(w[i], _p(_run(t(h), bold: true)), head: true),
    ].join()}</w:tr>',
    for (final (i, n) in notes.indexed)
      '<w:tr>${[
        _cell(w[0], _p(_run('${i + 1}'))),
        _cell(w[1], _p(_run(where(n)))),
        _cell(w[2], _p(_run(side(n)))),
        _cell(w[3], _p(_run(kind(n)))),
        _cell(w[4], _p(_run([
          n.text.isEmpty ? '—' : n.text,
          if (n.files.isNotEmpty)
            [
              if (n.photos.isNotEmpty) t('фото {n}', {'n': n.photos.length}),
              if (n.photosAfter.isNotEmpty) t('після усунення {n}', {'n': n.photosAfter.length}),
              if (n.audios.isNotEmpty) t('голосових {n}', {'n': n.audios.length}),
            ].join(', '),
        ].join('\n')))),
        _cell(w[5], _p(_run([_date(n.created), if (n.fixedAt != null) t('усунено {d}', {'d': _date(n.fixedAt!)})].join('\n')))),
      ].join()}</w:tr>',
  ]));

  // Фотофіксація: по два знімки в рядку, підпис під кожним.
  final withPhotos = [for (final (i, n) in notes.indexed) if (n.photos.isNotEmpty || n.photosAfter.isNotEmpty) (i, n)];
  if (withPhotos.isNotEmpty) {
    body.write(_p(_run(t('2. Фотофіксація'), bold: true, size: 26), after: 120));
    for (final (i, n) in withPhotos) {
      body.write(_p(_run('${t('№')} ${i + 1} · ${where(n)}, ${side(n)} · ${kind(n)}', bold: true), after: 60));
      if (n.text.isNotEmpty) body.write(_p(_run(n.text), after: 60));
      final cells = <String>[];
      for (final (name, after) in [for (final p in n.photos) (p, false), for (final p in n.photosAfter) (p, true)]) {
        final b = await file(name);
        if (b == null) continue;
        final size = imageSize(b);
        if (size == null) continue;
        media.add((name, b));
        final rid = 'rIdImg${media.length}';
        // Ширина в акті — 8 см; висота — за пропорцією знімка, не більше 10 см.
        var cx = 8 * 360000, cy = (cx * size.$2 / size.$1).round();
        if (cy > 10 * 360000) {
          cx = (cx * 10 * 360000 / cy).round();
          cy = 10 * 360000;
        }
        final ft = fileTime(name);
        final label = after ? t('Фото після усунення') : (n.photosAfter.isEmpty ? t('Фото') : t('Фото до'));
        cells.add(_p(_drawing(rid, media.length, name, cx, cy), align: 'center', after: 0) +
            _p(_run('$label${ft == null ? '' : ', ${stampText(ft)}'}', size: 18), align: 'center'));
      }
      if (cells.isEmpty) continue;
      body.write(_table([4819, 4819], [
        for (var k = 0; k < cells.length; k += 2)
          '<w:tr><w:trPr><w:cantSplit/></w:trPr>${_cell(4819, cells[k])}${_cell(4819, k + 1 < cells.length ? cells[k + 1] : '')}</w:tr>',
      ], borders: false));
    }
  }

  // Підписи.
  body
    ..write(_p('', after: 240))
    ..write(_p(_run('${t('Склав:')} ________________  ${authors.isEmpty ? '' : '/ ${authors.join(', ')} /'}'), after: 200))
    ..write(_p(_run('${t('Представник підрядника:')} ________________'), after: 200))
    ..write(_p(_run('${t('Представник замовника:')} ________________'), after: 200));

  const ns = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
      'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
      'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"';
  final document = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document $ns><w:body>$body'
      '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1134" w:right="850" w:bottom="1134" w:left="1418" '
      'w:header="709" w:footer="709" w:gutter="0"/></w:sectPr></w:body></w:document>';
  final rels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
      '${[for (final (k, (name, _)) in media.indexed) '<Relationship Id="rIdImg${k + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/${k + 1}_${_x(name)}"/>'].join()}'
      '</Relationships>';
  const styles = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:docDefaults>'
      '<w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri" w:eastAsia="Calibri"/>'
      '<w:sz w:val="21"/><w:szCs w:val="21"/><w:lang w:val="uk-UA"/></w:rPr></w:rPrDefault>'
      '<w:pPrDefault><w:pPr><w:spacing w:after="0" w:line="252" w:lineRule="auto"/></w:pPr></w:pPrDefault>'
      '</w:docDefaults></w:styles>';
  final files = <String, List<int>>{
    '[Content_Types].xml': utf8.encode('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Default Extension="jpg" ContentType="image/jpeg"/><Default Extension="jpeg" ContentType="image/jpeg"/>'
        '<Default Extension="png" ContentType="image/png"/>'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
        '</Types>'),
    '_rels/.rels': utf8.encode('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
        '</Relationships>'),
    'word/document.xml': utf8.encode(document),
    'word/_rels/document.xml.rels': utf8.encode(rels),
    'word/styles.xml': utf8.encode(styles),
    for (final (k, (name, b)) in media.indexed) 'word/media/${k + 1}_$name': b,
  };
  final a = Archive();
  for (final e in files.entries) {
    a.addFile(ArchiveFile(e.key, e.value.length, e.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(a));
}

String _drawing(String rid, int id, String name, int cx, int cy) =>
    '<w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="$cx" cy="$cy"/>'
    '<wp:docPr id="$id" name="Фото $id"/><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
    '<pic:pic><pic:nvPicPr><pic:cNvPr id="$id" name="${_x(name)}"/><pic:cNvPicPr/></pic:nvPicPr>'
    '<pic:blipFill><a:blip r:embed="$rid"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
    '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
    '</pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>';
