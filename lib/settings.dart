// Налаштування людини на цьому пристрої: ім'я для позначок, штамп на фото, власні шаблони опису.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'i18n.dart';

class AppSettings {
  String author = '';
  bool stampPhotos = true;
  List<String> templates = [];

  /// Вібрувати, коли до неусуненої позначки ближче за стільки метрів; 0 — не вібрувати.
  int nearNote = 20;

  /// Кілька осей поруч (примикання, з'їзди): самій переходити на ту, до якої людина ближча (за GPS).
  bool autoAxis = true;

  Map<String, dynamic> toJson() => {
        'author': author,
        'stampPhotos': stampPhotos,
        'templates': templates,
        'lang': lang.value.name,
        'nearNote': nearNote,
        'autoAxis': autoAxis,
      };

  void _read(Map<String, dynamic> j) {
    author = j['author'] as String? ?? '';
    stampPhotos = j['stampPhotos'] as bool? ?? true;
    templates = [for (final t in j['templates'] as List? ?? const []) t as String];
    nearNote = (j['nearNote'] as num?)?.toInt() ?? 20;
    autoAxis = j['autoAxis'] as bool? ?? true;
    lang.value = Lang.values.where((l) => l.name == j['lang']).firstOrNull ?? Lang.uk;
  }
}

final settings = AppSettings();
bool _loaded = false;

Future<File> _file() async => File('${(await getApplicationDocumentsDirectory()).path}/settings.json');

/// Прочитати один раз за запуск; у браузері налаштування живуть лише в пам'яті сторінки.
Future<AppSettings> loadSettings() async {
  if (_loaded || kIsWeb) return settings;
  _loaded = true;
  try {
    final f = await _file();
    if (await f.exists()) settings._read(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
  } catch (_) {
    // Пошкоджений файл налаштувань — працюємо з типовими, при збереженні він перезапишеться.
  }
  return settings;
}

Future<void> saveSettings() async {
  if (kIsWeb) return;
  final f = await _file();
  final tmp = File('${f.path}.tmp');
  await tmp.writeAsString(jsonEncode(settings.toJson()));
  await tmp.rename(f.path);
}
