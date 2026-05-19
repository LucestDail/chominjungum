import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 터치 스트로크를 PNG 바이트로 래스터 (ML Kit OCR 입력용).
Future<Uint8List?> strokesToPng({
  required List<List<Offset>> strokes,
  required Size size,
  double strokeWidth = 6,
}) async {
  if (size.width <= 0 || size.height <= 0) return null;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    Rect.fromLTWH(0, 0, size.width, size.height),
  );
  canvas.drawRect(
    Offset.zero & size,
    Paint()..color = Colors.white,
  );
  final paint = Paint()
    ..color = Colors.black
    ..strokeWidth = strokeWidth
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  for (final stroke in strokes) {
    if (stroke.length < 2) continue;
    final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
    for (var i = 1; i < stroke.length; i++) {
      path.lineTo(stroke[i].dx, stroke[i].dy);
    }
    canvas.drawPath(path, paint);
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.ceil(), size.height.ceil());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes?.buffer.asUint8List();
}
