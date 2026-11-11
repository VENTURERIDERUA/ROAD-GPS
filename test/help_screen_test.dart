import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:road_gps/help_screen.dart';
import 'package:road_gps/i18n.dart';

void main() {
  testWidgets('довідка: розділи, приклади файлів розгортаються, є «Копіювати»', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: HelpScreen()));
    expect(find.text('Що робить програма'), findsOneWidget);
    expect(find.text('Поперечники з відмітками'), findsOneWidget);
    await tester.tap(find.text('Поперечники з відмітками'));
    await tester.pumpAndSettle();
    expect(find.textContaining('0+000;-10.00;84.28'), findsOneWidget);
    expect(find.textContaining('<CrossSectPnt>-10.00 84.17</CrossSectPnt>'), findsOneWidget);
    expect(find.text('Копіювати'), findsNWidgets(2));
  });

  testWidgets('довідка арабською (справа наліво) і китайською на вузькому екрані — без переповнень', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() => lang.value = Lang.uk);
    for (final l in [Lang.ar, Lang.zh]) {
      lang.value = l;
      await tester.pumpWidget(MaterialApp(
          key: ValueKey(l),
          builder: (context, child) =>
              Directionality(textDirection: l.rtl ? TextDirection.rtl : TextDirection.ltr, child: child!),
          home: const HelpScreen()));
      expect(find.text(t('Що робить програма')), findsOneWidget);
      expect(t('Що робить програма'), isNot('Що робить програма'));
      await tester.tap(find.text(t('Поперечники з відмітками')));
      await tester.pumpAndSettle();
      expect(find.text(t('Копіювати')), findsNWidgets(2));
      expect(Directionality.of(tester.element(find.byType(HelpScreen))), l.rtl ? TextDirection.rtl : TextDirection.ltr);
      expect(tester.takeException(), isNull, reason: l.name);
    }
  });
}
