// Вібрація біля позначки — через Android (MainActivity.kt); де його немає (браузер) — звичайний відгук.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('road_gps/vibrate');

Future<void> vibrate() async {
  if (kIsWeb) return HapticFeedback.heavyImpact();
  try {
    await _channel.invokeMethod('vibrate', 400);
  } catch (_) {
    await HapticFeedback.vibrate();
  }
}
