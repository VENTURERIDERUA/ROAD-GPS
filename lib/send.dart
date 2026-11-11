// Надіслати файл (ZIP позначок, акт): пошта, Telegram, WhatsApp, Google Диск, OneDrive — або будь-куди
// через системне «Поділитися». Конкретну програму відкриває Android-частина (MainActivity.kt).
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'i18n.dart';
import 'problem_card.dart';
import 'problems.dart';

const _channel = MethodChannel('road_gps/send');

/// Пошта зазвичай не пропускає вкладень понад 20–25 МБ (Gmail — 25, з кодуванням — менше).
const emailLimit = 20 * 1024 * 1024;

class _Target {
  final String label;
  final IconData icon;

  /// Програми за порядком переваги; порожньо — пошта (будь-яка поштова програма).
  final List<String> packages;
  const _Target(this.label, this.icon, this.packages);
  bool get email => packages.isEmpty;
}

const _targets = [
  _Target('Пошта', Icons.email_outlined, []),
  _Target('Telegram', Icons.send_outlined, ['org.telegram.messenger', 'org.telegram.messenger.web']),
  _Target('WhatsApp', Icons.chat_outlined, ['com.whatsapp', 'com.whatsapp.w4b']),
  _Target('Google Диск', Icons.add_to_drive, ['com.google.android.apps.docs']),
  _Target('OneDrive', Icons.cloud_upload_outlined, ['com.microsoft.skydrive']),
];

String _mb(int bytes) => (bytes / 1024 / 1024).toStringAsFixed(1);

/// Запитати, куди надіслати, і надіслати. [smaller] — той самий файл зі зменшеними фото (для пошти).
Future<void> sendFile(
  BuildContext context, {
  required Uint8List bytes,
  required String name,
  required String mime,
  required String subject,
  required String text,
  Future<Uint8List> Function()? smaller,
}) async {
  if (kIsWeb || !Platform.isAndroid) return _shareAny(bytes, name, mime, subject, text);
  List<String> have;
  try {
    have = [
      for (final p in await _channel.invokeListMethod<String>(
              'installed', [for (final x in _targets) ...x.packages]) ??
          const <String>[])
        p
    ];
  } catch (_) {
    return _shareAny(bytes, name, mime, subject, text);
  }
  if (!context.mounted) return;
  final choice = await showModalBottomSheet<_Target?>(
    context: context,
    builder: (c) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        ListTile(
          title: Text(t('Надіслати «{name}»', {'name': name}), style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('${_mb(bytes.length)} ${t('МБ')}'),
        ),
        for (final x in _targets)
          ListTile(
            leading: Icon(x.icon),
            title: Text(t(x.label)),
            subtitle: x.email
                ? (bytes.length > emailLimit ? Text(t('завеликий для пошти — запропоную зменшити фото')) : null)
                : (x.packages.any(have.contains) ? null : Text(t('не встановлено'))),
            enabled: x.email || x.packages.any(have.contains),
            onTap: () => Navigator.pop(c, x),
          ),
        ListTile(
          leading: const Icon(Icons.more_horiz),
          title: Text(t('Інше…')),
          subtitle: Text(t('Viber, Bluetooth, зберегти у файли…')),
          onTap: () => Navigator.pop(c, const _Target('', Icons.more_horiz, ['*'])),
        ),
      ]),
    ),
  );
  if (choice == null || !context.mounted) return;
  if (choice.packages.firstOrNull == '*') return _shareAny(bytes, name, mime, subject, text);

  var data = bytes;
  if (choice.email && data.length > emailLimit) {
    final what = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t('Файл {mb} МБ — для пошти завеликий', {'mb': _mb(data.length)})),
        content: Text(t('Пошта зазвичай не пропускає вкладень понад 20–25 МБ. Можна зменшити фото (довша сторона '
            '1600 пікселів — у акті й на екрані їх видно добре) або надіслати через Telegram, WhatsApp чи диск — '
            'там такого обмеження немає.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(t('Скасувати'))),
          TextButton(onPressed: () => Navigator.pop(c, 'as-is'), child: Text(t('Надіслати як є'))),
          if (smaller != null)
            FilledButton(onPressed: () => Navigator.pop(c, 'small'), child: Text(t('Зменшити фото'))),
        ],
      ),
    );
    if (what == null || !context.mounted) return;
    if (what == 'small') {
      data = await smaller!();
      if (!context.mounted) return;
      if (data.length > emailLimit) {
        await showProblemDialog(
            context,
            Problem(Severity.warning, t('Навіть зі зменшеними фото — {mb} МБ', {'mb': _mb(data.length)}),
                fixes: const [
                  'Надішліть через Telegram, WhatsApp, Google Диск чи OneDrive.',
                  'Або відфільтруйте список позначок (пошук, «лише неусунені») — експортується лише показане.',
                ]));
        return;
      }
    }
  }

  final dir = Directory('${(await getTemporaryDirectory()).path}/send');
  // Попередні надіслані файли тут більше не потрібні.
  if (await dir.exists()) await dir.delete(recursive: true);
  await dir.create(recursive: true);
  final f = File('${dir.path}/$name');
  await f.writeAsBytes(data);
  final pkg = choice.email ? null : choice.packages.firstWhere(have.contains);
  final ok = await _channel.invokeMethod<bool>('send', {
    'path': f.path,
    'mime': mime,
    'subject': subject,
    'text': text,
    'package': pkg,
    'email': choice.email,
  });
  if (ok != true && context.mounted) {
    await showProblemDialog(
        context,
        Problem(Severity.warning, t('Не вдалося відкрити «{app}»', {'app': t(choice.label)}),
            fixes: const ['Перевірте, що програма встановлена й у ній виконано вхід.', 'Або виберіть «Інше…».']));
  }
}

Future<void> _shareAny(Uint8List bytes, String name, String mime, String subject, String text) =>
    SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(bytes, name: name, mimeType: mime)],
      fileNameOverrides: [name],
      subject: subject,
      text: text,
    ));
