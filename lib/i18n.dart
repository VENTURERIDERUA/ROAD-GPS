// Мови інтерфейсу: українська — основна (текст у коді українською й є ключем), англійська, румунська,
// іспанська, французька, португальська, німецька, польська, турецька, російська, арабська (справа наліво),
// китайська.
// t('Текст') → переклад для вибраної мови; немає перекладу — лишається українською.
// Підстановки — {назва}: t('Позначок: {n}', {'n': 5}).
import 'package:flutter/widgets.dart';

import 'l10n/l10n_a.dart' as a;
import 'l10n/l10n_b.dart' as b;
import 'l10n/l10n_c.dart' as c;
import 'l10n/l10n_d.dart' as d;
import 'l10n/l10n_e.dart' as e;
import 'l10n/l10n_f.dart' as f;
import 'l10n/l10n_es.dart' as es;
import 'l10n/l10n_fr.dart' as fr;
import 'l10n/l10n_pt.dart' as pt;
import 'l10n/l10n_de.dart' as de;
import 'l10n/l10n_pl.dart' as pl;
import 'l10n/l10n_tr.dart' as tr;
import 'l10n/l10n_ru.dart' as ru;
import 'l10n/l10n_ar.dart' as ar;
import 'l10n/l10n_zh.dart' as zh;

enum Lang {
  uk('Українська', 'UA'),
  en('English', 'EN'),
  ro('Română', 'RO'),
  es('Español', 'ES'),
  fr('Français', 'FR'),
  pt('Português', 'PT'),
  de('Deutsch', 'DE'),
  pl('Polski', 'PL'),
  tr('Türkçe', 'TR'),
  ru('Русский', 'RU'),
  ar('العربية', 'AR'),
  zh('中文', 'ZH');

  final String label, short;
  const Lang(this.label, this.short);

  /// Арабська пишеться справа наліво — і весь екран дзеркалиться.
  bool get rtl => this == Lang.ar;
}

/// Вибрана мова; зміна перемальовує всю програму (див. RoadGpsApp).
final lang = ValueNotifier<Lang>(Lang.uk);

final _en = <String, String>{...a.en, ...b.en, ...c.en, ...d.en, ...e.en, ...f.en};
final _ro = <String, String>{...a.ro, ...b.ro, ...c.ro, ...d.ro, ...e.ro, ...f.ro};

Map<String, String> _dict(Lang l) => switch (l) {
      Lang.uk => const {},
      Lang.en => _en,
      Lang.ro => _ro,
      Lang.es => es.es,
      Lang.fr => fr.fr,
      Lang.pt => pt.pt,
      Lang.de => de.de,
      Lang.pl => pl.pl,
      Lang.tr => tr.tr,
      Lang.ru => ru.ru,
      Lang.ar => ar.ar,
      Lang.zh => zh.zh,
    };

String t(String uk, [Map<String, Object?> args = const {}]) {
  // Нова мова без перекладу цього рядка — англійською (зрозуміліше, ніж українською).
  var s = switch (lang.value) {
    Lang.uk => uk,
    Lang.en || Lang.ro => _dict(lang.value)[uk] ?? uk,
    final l => _dict(l)[uk] ?? _en[uk] ?? uk,
  };
  args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
  return s;
}

/// Скільки рядків ще не перекладено (для перевірки повноти словників).
Iterable<String> missing(Lang l, Iterable<String> keys) =>
    keys.where((k) => !_dict(l).containsKey(k));

/// Усі ключі англійського словника — повний перелік рядків інтерфейсу (для перевірки нових мов).
Iterable<String> get allKeys => _en.keys;

/// Text, що перекладається, — і лишається const там, де був const Text.
class T extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  const T(this.text, {super.key, this.style, this.textAlign, this.maxLines, this.overflow});

  @override
  Widget build(BuildContext context) =>
      Text(t(text), style: style, textAlign: textAlign, maxLines: maxLines, overflow: overflow);
}
