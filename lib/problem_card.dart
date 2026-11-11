import 'package:flutter/material.dart';

import 'i18n.dart';
import 'problems.dart';

/// Попередження з поясненням і кроками «як виправити»; [actions] — кнопки, що допомагають одразу.
class ProblemCard extends StatelessWidget {
  final Problem problem;
  final List<(String, VoidCallback)> actions;
  const ProblemCard(this.problem, {super.key, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (problem.severity) {
      Severity.error => (Colors.red.shade800, Icons.error_outline),
      Severity.warning => (Colors.orange.shade900, Icons.warning_amber),
      Severity.info => (Colors.blueGrey.shade700, Icons.info_outline),
    };
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      // Світле тло поверх будь-якої панелі (на темнішій панелі напівпрозоре тло ставало сірим).
      color: Color.alphaBlend(color.withValues(alpha: 0.07), Colors.white),
      shape: RoundedRectangleBorder(
          side: BorderSide(color: color.withValues(alpha: 0.4)), borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(t(problem.title), style: TextStyle(color: color, fontWeight: FontWeight.bold))),
          ]),
          if (problem.detail != null && problem.detail!.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 4, left: 28), child: Text(t(problem.detail!))),
          if (problem.fixes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 28),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const T('Як виправити:', style: TextStyle(fontWeight: FontWeight.w600)),
                for (final f in problem.fixes)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('•  '),
                      Expanded(child: Text(t(f))),
                    ]),
                  ),
              ]),
            ),
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 20),
              child: Wrap(spacing: 8, children: [
                for (final (label, onTap) in actions) OutlinedButton(onPressed: onTap, child: Text(label)),
              ]),
            ),
        ]),
      ),
    );
  }
}

/// Вікно з проблемою — коли далі йти нема куди (файл не той).
Future<void> showProblemDialog(BuildContext context, Problem p) => showDialog(
      context: context,
      builder: (c) => AlertDialog(
        content: SingleChildScrollView(child: ProblemCard(p)),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const T('Зрозуміло'))],
      ),
    );
