// Клавіатури для полів, де вводяться лише числа: цифрова замість повної з літерами.
import 'package:flutter/material.dart';

import 'i18n.dart';

/// Число: відмітка, відстань, координата, масштаб — системна цифрова клавіатура (цифри, «.», «-»).
const numberKeyboard = TextInputType.numberWithOptions(decimal: true, signed: true);

/// Символи панелі для ПК: «0+125.50», кілька — через «;».
const stationKeys = '+.;';

/// Символи панелі для «широта, довгота».
const latLonKeys = '.,-';

/// Своя цифрова панель для ПК і «широта, довгота»: на системних цифрових клавіатурах «+» і «.» нема або вони на
/// другій сторінці. Великі кнопки — і в рукавицях. Поле з нею: `readOnly: true, showCursor: true,
/// onTap: () => showDigitPad(...)`. Пише в кінець [c]; [onChanged] — як у поля (програмну зміну поле не помічає).
Future<void> showDigitPad(
  BuildContext context,
  TextEditingController c, {
  required String label,
  String keys = stationKeys,
  ValueChanged<String>? onChanged,
}) {
  void put(String v) {
    c.value = TextEditingValue(
      text: v,
      selection: TextSelection.collapsed(offset: v.length),
    );
    onChanged?.call(v);
  }

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        Widget key(String text, VoidCallback onTap, {Color? color}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: SizedBox(
              height: 60,
              child: FilledButton.tonal(
                style: FilledButton.styleFrom(
                  backgroundColor: color,
                  padding: EdgeInsets.zero,
                  textStyle: const TextStyle(fontSize: 26),
                ),
                onPressed: () => set(onTap),
                child: FittedBox(child: Text(text)),
              ),
            ),
          ),
        );
        Widget digit(String d) => key(d, () => put(c.text + d));
        final extra = keys.split('');
        return SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(label, style: const TextStyle(color: Colors.black54)),
                    Text(
                      c.text.isEmpty ? ' ' : c.text,
                      style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        digit('7'),
                        digit('8'),
                        digit('9'),
                        key('⌫', () {
                          if (c.text.isNotEmpty) put(c.text.substring(0, c.text.length - 1));
                        }),
                      ],
                    ),
                    Row(children: [digit('4'), digit('5'), digit('6'), key(extra[0], () => put(c.text + extra[0]))]),
                    Row(children: [digit('1'), digit('2'), digit('3'), key(extra[1], () => put(c.text + extra[1]))]),
                    Row(
                      children: [
                        key(t('Стерти'), () => put('')),
                        digit('0'),
                        key(extra[2], () => put(c.text + extra[2])),
                        key(t('Готово'), () => Navigator.pop(ctx), color: Theme.of(ctx).colorScheme.primaryContainer),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
