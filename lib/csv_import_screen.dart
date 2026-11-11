// Відомість CSV → колонки ПК, відмітки, ширини (програма вгадує, людина перевіряє) → профіль і ширини;
// таблиця поперечників (ПК, зміщення, відмітка) → поперечники з відмітками.
import 'package:flutter/material.dart';

import 'i18n.dart';
import 'problem_card.dart';
import 'problems.dart';
import 'vidomist.dart';

class CsvImportScreen extends StatefulWidget {
  final CsvTable table;
  final String fileName;
  final double axisStart, axisEnd;
  const CsvImportScreen(
      {super.key, required this.table, required this.fileName, required this.axisStart, required this.axisEnd});

  @override
  State<CsvImportScreen> createState() => _CsvImportScreenState();
}

class _CsvImportScreenState extends State<CsvImportScreen> {
  late final Map<ColumnRole, int> _cols = guessColumns(widget.table);

  VidomistResult get _result => buildVidomist(widget.table, _cols, widget.fileName,
      axisStart: widget.axisStart, axisEnd: widget.axisEnd);

  @override
  Widget build(BuildContext context) {
    final tb = widget.table;
    final r = _result;
    final blocking = r.problems.any((p) => p.severity == Severity.error) || (r.profile == null && r.widths == null);
    return Scaffold(
      appBar: AppBar(title: Text(t('Відомість: {f}', {'f': widget.fileName}))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const T('Програма вибрала колонки за назвами — перевірте.'),
        const SizedBox(height: 8),
        for (final role in ColumnRole.values)
          Row(children: [
            SizedBox(width: 170, child: Text(t(role.label))),
            Expanded(
              child: DropdownButton<int?>(
                isExpanded: true,
                value: _cols[role],
                items: [
                  const DropdownMenuItem(value: null, child: T('— немає —')),
                  for (var i = 0; i < tb.header.length; i++) DropdownMenuItem(value: i, child: Text(tb.header[i])),
                ],
                onChanged: (i) => setState(() => i == null ? _cols.remove(role) : _cols[role] = i),
              ),
            ),
          ]),
        const SizedBox(height: 8),
        for (final p in r.problems) ProblemCard(p),
        if (r.profile != null)
          Text(t('Відміток: {n}, ПК {a}–{b} м.', {
            'n': r.profile!.pvis.length,
            'a': r.profile!.startStation.toStringAsFixed(1),
            'b': r.profile!.endStation.toStringAsFixed(1),
          })),
        if (r.widths != null) Text(t('Ширин: {n}.', {'n': r.widths!.rows.length})),
        const SizedBox(height: 12),
        const T('Перші рядки файлу:', style: TextStyle(fontWeight: FontWeight.w600)),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 32,
            dataRowMinHeight: 28,
            dataRowMaxHeight: 32,
            columns: [
              for (var i = 0; i < tb.header.length; i++)
                DataColumn(
                  label: Text(tb.header[i],
                      style: TextStyle(
                          fontWeight: _cols.containsValue(i) ? FontWeight.bold : FontWeight.normal,
                          color: _cols.containsValue(i) ? Theme.of(context).colorScheme.primary : null)),
                ),
            ],
            rows: [
              for (final row in tb.rows.take(6))
                DataRow(cells: [for (var i = 0; i < tb.header.length; i++) DataCell(Text(i < row.length ? row[i] : ''))]),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: blocking ? null : () => Navigator.of(context).pop(r),
          icon: const Icon(Icons.check),
          label: const T('Додати до об’єкта'),
        ),
      ]),
    );
  }
}

/// Таблиця поперечників (ПК, зміщення, відмітка): програма вгадує колонки, людина перевіряє — і лише тоді додає.
class CsvSectionsScreen extends StatefulWidget {
  final CsvTable table;
  final String fileName;
  final double axisStart, axisEnd;
  const CsvSectionsScreen(
      {super.key, required this.table, required this.fileName, required this.axisStart, required this.axisEnd});

  @override
  State<CsvSectionsScreen> createState() => _CsvSectionsScreenState();
}

class _CsvSectionsScreenState extends State<CsvSectionsScreen> {
  late final Map<XsRole, int> _cols = guessXsColumns(widget.table);

  @override
  Widget build(BuildContext context) {
    final tb = widget.table;
    final r = buildCrossSectionsCsv(tb, _cols, widget.fileName, axisStart: widget.axisStart, axisEnd: widget.axisEnd);
    final cs = r.sections;
    final blocking = cs == null || r.problems.any((p) => p.severity == Severity.error);
    return Scaffold(
      appBar: AppBar(title: Text(t('Поперечники: {f}', {'f': widget.fileName}))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const T('Одна точка поперечника в рядку. Програма вибрала колонки за назвами — перевірте.'),
        const SizedBox(height: 8),
        for (final role in XsRole.values)
          Row(children: [
            SizedBox(width: 170, child: Text(t(role.label))),
            Expanded(
              child: DropdownButton<int?>(
                isExpanded: true,
                value: _cols[role],
                items: [
                  const DropdownMenuItem(value: null, child: T('— немає —')),
                  for (var i = 0; i < tb.header.length; i++) DropdownMenuItem(value: i, child: Text(tb.header[i])),
                ],
                onChanged: (i) => setState(() => i == null ? _cols.remove(role) : _cols[role] = i),
              ),
            ),
          ]),
        const SizedBox(height: 8),
        for (final p in r.problems) ProblemCard(p),
        if (cs != null)
          Text(t('Поперечників: {n} (точок {p}), ПК {a}–{b} м.', {
            'n': cs.rows.length,
            'p': r.pointsUsed,
            'a': cs.startStation.toStringAsFixed(1),
            'b': cs.endStation.toStringAsFixed(1),
          })),
        const SizedBox(height: 12),
        const T('Перші рядки файлу:', style: TextStyle(fontWeight: FontWeight.w600)),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 32,
            dataRowMinHeight: 28,
            dataRowMaxHeight: 32,
            columns: [
              for (var i = 0; i < tb.header.length; i++)
                DataColumn(
                  label: Text(tb.header[i],
                      style: TextStyle(
                          fontWeight: _cols.containsValue(i) ? FontWeight.bold : FontWeight.normal,
                          color: _cols.containsValue(i) ? Theme.of(context).colorScheme.primary : null)),
                ),
            ],
            rows: [
              for (final row in tb.rows.take(6))
                DataRow(cells: [for (var i = 0; i < tb.header.length; i++) DataCell(Text(i < row.length ? row[i] : ''))]),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: blocking ? null : () => Navigator.of(context).pop(cs),
          icon: const Icon(Icons.check),
          label: const T('Додати до об’єкта'),
        ),
      ]),
    );
  }
}
