// Не гасити екран, поки відкрито екран траси (MainActivity.kt); у браузері й на інших платформах — нічого.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('road_gps/screen');

Future<void> keepScreenOn(bool on) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await _channel.invokeMethod('keepOn', on);
  } catch (_) {
    // Старіша збірка без каналу — екран просто гасне, як раніше.
  }
}
