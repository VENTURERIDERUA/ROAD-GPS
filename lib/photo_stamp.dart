// Штамп на фото: унизу знімка — смуга з ПК, датою й координатами, щоб фото «говорило» саме за себе
// і поза програмою (у пошті, в акті, у Telegram).
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

/// Намалювати рядки на смузі внизу фото; повертає JPEG.
Future<Uint8List> stampPhoto(Uint8List src, List<String> lines, {int quality = 85}) async {
  final codec = await ui.instantiateImageCodec(src);
  final image = (await codec.getNextFrame()).image;
  codec.dispose();
  final w = image.width, h = image.height;
  final rec = ui.PictureRecorder();
  final c = Canvas(rec)..drawImage(image, Offset.zero, Paint());
  // Розмір літер — від ширини знімка: читається і на телефоні, і в акті.
  final fs = (w / 40).clamp(12, 64).toDouble();
  final pad = fs * 0.5;
  final tp = TextPainter(
    text: TextSpan(
      text: lines.join('\n'),
      style: TextStyle(color: Colors.white, fontSize: fs, height: 1.25, fontWeight: FontWeight.w600),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: w - 2 * pad);
  final band = tp.height + 2 * pad;
  c.drawRect(Rect.fromLTWH(0, h - band, w.toDouble(), band), Paint()..color = const Color(0xA0000000));
  tp.paint(c, Offset(pad, h - band + pad));
  tp.dispose();
  final out = await rec.endRecording().toImage(w, h);
  image.dispose();
  final rgba = (await out.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  out.dispose();
  // Стискання в JPEG — окремим потоком, щоб екран не завмирав.
  return compute(_encodeJpg, (w, h, rgba.buffer.asUint8List(), quality));
}

Uint8List _encodeJpg((int, int, Uint8List, int) a) {
  final (w, h, rgba, q) = a;
  final m = img.Image.fromBytes(width: w, height: h, bytes: rgba.buffer, numChannels: 4, order: img.ChannelOrder.rgba);
  return img.encodeJpg(m, quality: q);
}

/// Зменшити фото для пошти: довша сторона до [maxSide] пікселів, JPEG якості [quality]. Не JPEG, не
/// прочиталось чи вийшло не менше — повертає як було.
Future<Uint8List> shrinkPhoto(Uint8List src, {int maxSide = 1600, int quality = 75}) =>
    compute(_shrink, (src, maxSide, quality));

Uint8List _shrink((Uint8List, int, int) a) {
  final (src, maxSide, q) = a;
  final im = img.decodeJpg(src);
  if (im == null) return src;
  final wide = im.width >= im.height;
  final r = (wide ? im.width : im.height) > maxSide
      ? img.copyResize(im, width: wide ? maxSide : null, height: wide ? null : maxSide, interpolation: img.Interpolation.average)
      : im;
  final out = img.encodeJpg(r, quality: q);
  return out.length < src.length ? out : src;
}
