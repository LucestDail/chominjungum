import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chominjungum/services/worksheet_pdf.dart';
import 'package:chominjungum/widgets/hangul_worksheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// 화면에 그린 학습지가 PDF 로 나오는 경로 전체.
///
/// 합성 이미지로만 테스트하면 "실제 화면 픽셀이 들어왔을 때"를 못 본다.
void main() {
  testWidgets('학습지를 래스터화해 PDF 로 담는다', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.white,
          body: RepaintBoundary(
            key: key,
            child: const HangulWorksheet(text: '나비', showGlyphGuides: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    late Uint8List pdf;
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      pdf = WorksheetPdf.fromRgba(
        rgba: data!.buffer.asUint8List(),
        width: image.width,
        height: image.height,
      );
      image.dispose();
    });

    expect(String.fromCharCodes(pdf.take(8)), startsWith('%PDF-1.'));
    expect(pdf.length, greaterThan(2000), reason: '빈 페이지가 아니다');
    final text = String.fromCharCodes(pdf);
    expect(text, contains('/Subtype /Image'));
    expect(text, contains('%%EOF'));
  });
}
