// Відомість (CSV): ПК, проєктна відмітка, ширини → профіль і ширини об'єкта.
import 'dart:convert';
import 'dart:typed_data';

import 'chainage.dart';
import 'i18n.dart';
import 'problems.dart';
import 'profile.dart';

class CsvTable {
  final List<String> header;
  final List<List<String>> rows;

  /// Номер першого рядка даних у файлі (для повідомлень про помилки).
  final int firstLine;
  CsvTable(this.header, this.rows, this.firstLine);
}

enum ColumnRole {
  station('ПК'),
  z('Проєктна відмітка'),
  half('Напівширина'),
  width('Ширина (повна)');

  final String label;
  const ColumnRole(this.label);
}

const csvEmpty = Problem(Severity.error, 'Відомість порожня',
    fixes: ['Перевірте, що вибрано той файл; збережіть таблицю з Excel як «CSV UTF-8 (розділювач — кома)».']);

CsvTable parseCsv(Uint8List bytes) {
  var text = _decode(bytes);
  if (text.startsWith('﻿')) text = text.substring(1);
  final lines = const LineSplitter().convert(text).where((l) => l.trim().isNotEmpty).toList();
  if (lines.isEmpty) throw const VidomistException(csvEmpty);
  final first = lines.first;
  // Крапка з комою — найчастіше там, де десяткова кома (Excel українською, румунською).
  final sep = first.contains(';') ? ';' : (first.contains('\t') ? '\t' : ',');
  List<String> split(String l) => [for (final c in l.split(sep)) c.trim().replaceAll(RegExp(r'^"|"$'), '')];
  final cells = [for (final l in lines) split(l)];
  final hasHeader = cells.first.any((c) => c.isNotEmpty && _number(c) == null && parseChainageLabel(c) == null);
  final width = cells.fold(0, (a, r) => r.length > a ? r.length : a);
  final header = hasHeader
      ? [for (var i = 0; i < width; i++) i < cells.first.length ? cells.first[i] : t('Колонка {n}', {'n': i + 1})]
      : [for (var i = 0; i < width; i++) t('Колонка {n}', {'n': i + 1})];
  return CsvTable(header, hasHeader ? cells.sublist(1) : cells, hasHeader ? 2 : 1);
}

String _decode(Uint8List b) {
  try {
    return utf8.decode(b);
  } on FormatException {
    return latin1.decode(b); // старий CSV з Excel; числа читаються, кирилиця в назвах — ні
  }
}

double? _number(String s) => double.tryParse(s.replaceAll(' ', '').replaceAll(' ', '').replaceAll(',', '.'));

/// ПК з клітинки: «0+025.00», «ПК 12+34», або метри числом.
double? stationOf(String s) => parseChainageLabel(s)?.$1 ?? _number(s);

List<String> _tokens(String h) =>
    h.toLowerCase().split(RegExp(r'[^a-zа-яіїєґ0-9]+', unicode: true)).where((t) => t.isNotEmpty).toList();

/// Колонки за назвами. Відмітка — проєктна, не «земля».
Map<ColumnRole, int> guessColumns(CsvTable t) {
  final out = <ColumnRole, int>{};
  int? best(bool Function(List<String>) match, [int Function(List<String>)? score]) {
    int? pick;
    var top = -1;
    for (var i = 0; i < t.header.length; i++) {
      final tok = _tokens(t.header[i]);
      if (!match(tok)) continue;
      final s = score?.call(tok) ?? 0;
      if (s > top) {
        top = s;
        pick = i;
      }
    }
    return pick;
  }

  bool starts(List<String> tok, List<String> prefixes) => tok.any((x) => prefixes.any(x.startsWith));
  final st = best(
      (tok) => tok.any({'pk', 'пк', 'km', 'км', 's', 'station', 'sta', 'chainage', 'ch', 'dist', 'distance'}.contains) ||
          starts(tok, ['pichet', 'pozit', 'пікет', 'пикет', 'відстан']),
      // Текстовий ПК («0+025.00») надійніший за число, якщо прочитався.
      (tok) => tok.any({'pk', 'пк', 'km', 'км'}.contains) ? 2 : 1);
  if (st != null) out[ColumnRole.station] = st;
  final z = best(
      (tok) => tok.contains('z') || tok.contains('h') || tok.contains('rl') || starts(tok, ['cota', 'відміт', 'отмет', 'elev', 'height']),
      (tok) {
        if (starts(tok, ['teren', 'земл', 'ground', 'exist', 'існ', 'сущ', 'natural'])) return 0;
        if (starts(tok, ['proiect', 'проєкт', 'проект', 'design', 'red', 'project', 'chervon', 'черв'])) return 2;
        return 1;
      });
  if (z != null) out[ColumnRole.z] = z;
  final half = best((tok) => starts(tok, ['semilat', 'напівшир', 'полушир', 'halfwidth', 'half']));
  if (half != null) out[ColumnRole.half] = half;
  final width = best((tok) => tok.contains('b') || starts(tok, ['latime', 'ширин', 'width']));
  if (width != null && width != half) out[ColumnRole.width] = width;
  return out;
}

class VidomistResult {
  final Profile? profile;
  final Widths? widths;
  final int rowsUsed;
  final List<Problem> problems;
  VidomistResult(this.profile, this.widths, this.rowsUsed, this.problems);
}

class VidomistException implements Exception {
  final Problem problem;
  const VidomistException(this.problem);
}

/// Профіль і ширини з таблиці за вибраними колонками. Проблеми — з порадами.
VidomistResult buildVidomist(CsvTable tb, Map<ColumnRole, int> cols, String fileName,
    {double? axisStart, double? axisEnd}) {
  final problems = <Problem>[];
  final si = cols[ColumnRole.station];
  if (si == null) {
    return VidomistResult(null, null, 0, [
      const Problem(Severity.error, 'Не вибрано колонку ПК',
          fixes: ['Виберіть у списку колонку з пікетажем (наприклад «PK», «ПК», «S_m»).',
            'Немає такої колонки — додайте її в Excel і збережіть CSV ще раз.'])
    ]);
  }
  final zi = cols[ColumnRole.z], hi = cols[ColumnRole.half], wi = cols[ColumnRole.width];
  if (zi == null && hi == null && wi == null) {
    problems.add(const Problem(Severity.error, 'Не вибрано жодної колонки з даними',
        fixes: ['Виберіть колонку проєктної відмітки та/або ширини.']));
  }
  final pvis = <Pvi>[];
  final widths = <(double, double, double)>[];
  final bad = <String>[];
  String? cell(List<String> r, int? i) => i == null || i >= r.length ? null : r[i];
  for (var k = 0; k < tb.rows.length; k++) {
    final r = tb.rows[k];
    final st = stationOf(cell(r, si) ?? '');
    if (st == null) {
      bad.add(t('рядок {n}: ПК «{v}»', {'n': tb.firstLine + k, 'v': cell(r, si) ?? ''}));
      continue;
    }
    if (zi != null) {
      final z = _number(cell(r, zi) ?? '');
      z == null ? bad.add(t('рядок {n}: відмітка «{v}»', {'n': tb.firstLine + k, 'v': cell(r, zi) ?? ''})) : pvis.add(Pvi(st, z));
    }
    final h = hi != null ? _number(cell(r, hi) ?? '') : (wi != null ? (_number(cell(r, wi) ?? '') ?? double.nan) / 2 : null);
    if (h != null && !h.isNaN) widths.add((st, h, h));
  }
  if (bad.isNotEmpty) {
    problems.add(Problem(Severity.warning, t('Не прочиталось клітинок: {n}', {'n': bad.length}),
        detail: t('Наприклад: {a}.', {'a': bad.take(3).join('; ')}),
        fixes: const [
          'Порожні клітинки й текст замість чисел програма пропускає — перевірте ці рядки в Excel.',
          'Десяткова кома й крапка читаються обидві; пробіли в числах — теж.',
        ]));
  }
  final stations = [...pvis.map((p) => p.station), ...widths.map((w) => w.$1)];
  if (stations.length != stations.toSet().length && pvis.length != pvis.map((p) => p.station).toSet().length) {
    problems.add(const Problem(Severity.warning, 'У відомості є однакові ПК',
        detail: 'Буває на розриві пікетажу або при повторі рядків. Береться перший за порядком.',
        fixes: ['Приберіть повтори в Excel; розриви пікетажу програма поки не враховує.']));
    final seen = <double>{};
    pvis.retainWhere((p) => seen.add(p.station));
  }
  if (axisStart != null && axisEnd != null && stations.isNotEmpty) {
    final lo = stations.reduce((a, b) => a < b ? a : b), hi2 = stations.reduce((a, b) => a > b ? a : b);
    if (hi2 < axisStart - 1 || lo > axisEnd + 1) {
      problems.add(Problem(Severity.error, 'ПК відомості не збігаються з віссю',
          detail: t('Відомість: {a}–{b} м, вісь: {c}–{d} м.', {
            'a': lo.toStringAsFixed(0),
            'b': hi2.toStringAsFixed(0),
            'c': axisStart.toStringAsFixed(0),
            'd': axisEnd.toStringAsFixed(0),
          }),
          fixes: const [
            'Перевірте ПК початку осі (екран об’єкта) — він має збігатися з пікетажем відомості.',
            'Перевірте колонку ПК: метри чи пікети (12+34 = 1234 м)?',
          ]));
    } else if (lo > axisStart + 1 || hi2 < axisEnd - 1) {
      problems.add(Problem(Severity.info, 'Відомість покриває не всю вісь',
          detail: t('Відмітки будуть лише на {a}–{b} м.', {'a': lo.toStringAsFixed(0), 'b': hi2.toStringAsFixed(0)})));
    }
  }
  final profile = pvis.length >= 2 ? Profile('CSV: $fileName', pvis) : null;
  if (zi != null && profile == null) {
    problems.add(const Problem(Severity.error, 'Відміток замало — потрібно щонайменше два рядки',
        fixes: ['Перевірте колонку відмітки й десятковий роздільник.']));
  }
  return VidomistResult(profile, widths.isEmpty ? null : Widths('CSV: $fileName', widths), tb.rows.length - bad.length, problems);
}

// ---------- Поперечники з таблиці: рядок = точка поперечника (ПК, зміщення від осі, відмітка) ----------

enum XsRole {
  station('ПК'),
  offset('Зміщення від осі (ліворуч — мінус)'),
  z('Відмітка');

  final String label;
  const XsRole(this.label);
}

/// Колонки таблиці поперечників за назвами: спершу зміщення (щоб «відстань від осі» не стала ПК), далі ПК і відмітка.
Map<XsRole, int> guessXsColumns(CsvTable t) {
  final out = <XsRole, int>{};
  bool starts(List<String> tok, List<String> p) => tok.any((x) => p.any(x.startsWith));
  for (var i = 0; i < t.header.length; i++) {
    final tok = _tokens(t.header[i]);
    if (!out.containsKey(XsRole.offset) &&
        (tok.contains('offset') || tok.contains('off') || starts(tok, ['зміщ', 'смещ', 'decal']) ||
            // «Відстань від осі», «Distanta fata de ax» — але не «Distanta» (пікетаж) сама.
            (starts(tok, ['відстан', 'расстоян', 'distan', 'dist']) && starts(tok, ['ос', 'ax'])))) {
      out[XsRole.offset] = i;
    }
  }
  final v = guessColumns(t);
  final st = v[ColumnRole.station];
  if (st != null && st != out[XsRole.offset]) out[XsRole.station] = st;
  final z = v[ColumnRole.z];
  if (z != null && z != out[XsRole.offset] && z != out[XsRole.station]) out[XsRole.z] = z;
  return out;
}

class XsResult {
  final CrossSections? sections;
  final int pointsUsed;
  final List<Problem> problems;
  XsResult(this.sections, this.pointsUsed, this.problems);
}

/// Поперечники з таблиці за вибраними колонками: точки з однаковим ПК (до 1 мм) — один поперечник.
XsResult buildCrossSectionsCsv(CsvTable tb, Map<XsRole, int> cols, String fileName,
    {double? axisStart, double? axisEnd}) {
  final si = cols[XsRole.station], oi = cols[XsRole.offset], zi = cols[XsRole.z];
  if (si == null || oi == null || zi == null) {
    return XsResult(null, 0, [
      const Problem(Severity.error, 'Потрібні три колонки: ПК, зміщення від осі, відмітка',
          fixes: [
            'Виберіть їх у списках угорі.',
            'Таблиця — одна точка поперечника в рядку: ПК; зміщення (ліворуч від осі — з мінусом); відмітка.',
          ])
    ]);
  }
  final problems = <Problem>[];
  final bad = <String>[];
  final byStation = <int, (double, Map<double, double>)>{};
  var dup = 0, used = 0;
  String cell(List<String> r, int i) => i < r.length ? r[i] : '';
  for (var k = 0; k < tb.rows.length; k++) {
    final r = tb.rows[k];
    final st = stationOf(cell(r, si)), off = _number(cell(r, oi)), z = _number(cell(r, zi));
    if (st == null || off == null || z == null) {
      bad.add(t('рядок {n}', {'n': tb.firstLine + k}));
      continue;
    }
    final key = (st * 1000).round();
    final pts = (byStation[key] ??= (st, <double, double>{})).$2;
    if (pts.containsKey(off)) {
      dup++;
      continue;
    }
    pts[off] = z;
    used++;
  }
  if (bad.isNotEmpty) {
    problems.add(Problem(Severity.warning, t('Не прочиталось рядків: {n}', {'n': bad.length}),
        detail: t('Наприклад: {a}.', {'a': bad.take(3).join('; ')}),
        fixes: const ['Порожні клітинки й текст замість чисел програма пропускає — перевірте ці рядки в Excel.']));
  }
  if (dup > 0) {
    problems.add(Problem(Severity.warning, t('Однакове зміщення в одному поперечнику: {n} разів', {'n': dup}),
        fixes: const ['Береться перша точка; перевірте повтори в Excel.']));
  }
  final rows = <(double, List<(double, double)>)>[];
  var single = 0;
  for (final e in byStation.values) {
    if (e.$2.length < 2) {
      single++;
      continue;
    }
    rows.add((e.$1, [for (final o in e.$2.keys.toList()..sort()) (o, e.$2[o]!)]));
  }
  if (single > 0) {
    problems.add(Problem(Severity.warning, t('Поперечників з однією точкою: {n} — пропущено', {'n': single}),
        fixes: const ['Поперечник — щонайменше дві точки з однаковим ПК і різними зміщеннями.']));
  }
  if (rows.isEmpty) {
    problems.add(const Problem(Severity.error, 'Жодного поперечника не вийшло',
        fixes: ['Перевірте колонки: ПК однаковий для всіх точок одного поперечника, зміщення — різні.']));
    return XsResult(null, used, problems);
  }
  final cs = CrossSections('CSV: $fileName', rows);
  if (axisStart != null && axisEnd != null &&
      (cs.endStation < axisStart - 1 || cs.startStation > axisEnd + 1)) {
    problems.add(Problem(Severity.error, 'ПК поперечників не збігаються з віссю',
        detail: t('Поперечники: {a}–{b} м, вісь: {c}–{d} м.', {
          'a': cs.startStation.toStringAsFixed(0),
          'b': cs.endStation.toStringAsFixed(0),
          'c': axisStart.toStringAsFixed(0),
          'd': axisEnd.toStringAsFixed(0),
        }),
        fixes: const [
          'Перевірте ПК початку осі (екран об’єкта) — він має збігатися з пікетажем таблиці.',
          'Перевірте колонку ПК: метри чи пікети (12+34 = 1234 м)?',
        ]));
  }
  if (offsetsOneSided(rows)) {
    problems.add(const Problem(Severity.warning, 'Усі зміщення одного знака',
        detail: 'Поперечник лише з одного боку осі — або ліва сторона записана без мінуса.',
        fixes: ['Ліворуч від осі (за напрямом пікетажу) — зміщення з мінусом, праворуч — з плюсом.']));
  }
  return XsResult(cs, used, problems);
}

/// Чи всі точки всіх поперечників по один бік осі (підказка, що мінус для лівої сторони загубився).
bool offsetsOneSided(List<(double, List<(double, double)>)> rows) {
  final all = [for (final r in rows) ...r.$2.map((p) => p.$1)];
  return all.length > 2 && (all.every((o) => o >= 0) || all.every((o) => o <= 0));
}
