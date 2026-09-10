import 'dart:io';
import 'dart:typed_data';

import 'package:chominjungum/services/worksheet_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

/// 의존성 없이 쓴 PDF 가 **정말 PDF 인지**.
///
/// 라이브러리를 안 쓰기로 했으므로 구조를 직접 책임진다. 헤더만 맞고 xref 가
/// 어긋나면 뷰어가 "손상됨"이라 한다 — 그건 눈으로 열어 봐야 알던 종류라
/// 여기서 구조를 검사한다.
void main() {
  Uint8List solid(int w, int h, int r, int g, int b, [int a = 255]) {
    final px = Uint8List(w * h * 4);
    for (var i = 0; i < px.length; i += 4) {
      px[i] = r;
      px[i + 1] = g;
      px[i + 2] = b;
      px[i + 3] = a;
    }
    return px;
  }

  test('PDF 헤더와 꼬리가 있다', () {
    final pdf = WorksheetPdf.fromRgba(rgba: solid(4, 4, 0, 0, 0), width: 4, height: 4);
    final head = String.fromCharCodes(pdf.take(8));
    expect(head, startsWith('%PDF-1.'));
    final tail = String.fromCharCodes(pdf.skip(pdf.length - 8));
    expect(tail.trim(), endsWith('%%EOF'));
  });

  test('xref 오프셋이 실제 객체 위치를 가리킨다', () {
    final pdf = WorksheetPdf.fromRgba(
      rgba: solid(8, 8, 255, 0, 0),
      width: 8,
      height: 8,
    );
    final text = String.fromCharCodes(pdf);

    final startxref = RegExp(r'startxref\s+(\d+)').firstMatch(text);
    expect(startxref, isNotNull, reason: 'startxref 가 없으면 뷰어가 못 연다');
    final xrefPos = int.parse(startxref!.group(1)!);
    expect(text.substring(xrefPos, xrefPos + 4), 'xref');

    // 각 오프셋이 "<n> 0 obj" 를 가리켜야 한다.
    final entries = RegExp(r'^(\d{10}) 00000 n', multiLine: true)
        .allMatches(text)
        .map((m) => int.parse(m.group(1)!))
        .toList();
    expect(entries, hasLength(6), reason: '객체 6개');
    for (var i = 0; i < entries.length; i++) {
      expect(
        text.startsWith('${i + 1} 0 obj', entries[i]),
        isTrue,
        reason: '${i + 1}번 객체 오프셋이 어긋났다',
      );
    }
  });

  test('이미지가 A4 여백 안에 비율을 지켜 들어간다', () {
    // 가로로 아주 긴 이미지 — 폭에 맞춰 줄어야 한다.
    final pdf = WorksheetPdf.fromRgba(
      rgba: solid(1000, 100, 0, 0, 0),
      width: 1000,
      height: 100,
    );
    final text = String.fromCharCodes(pdf);
    final cm = RegExp(r'([\d.]+) 0 0 ([\d.]+) ([\d.]+) ([\d.]+) cm')
        .firstMatch(text)!;
    final w = double.parse(cm.group(1)!);
    final h = double.parse(cm.group(2)!);

    final avail = WorksheetPdf.a4Width - WorksheetPdf.margin * 2;
    expect(w, closeTo(avail, 0.01), reason: '폭을 여백에 맞춘다');
    expect(h / w, closeTo(100 / 1000, 1e-3), reason: '비율이 유지돼야 한다');
    expect(w, lessThanOrEqualTo(WorksheetPdf.a4Width));
  });

  test('🔴투명 픽셀은 흰색 위에 합성한다 — 검게 나오면 안 된다', () {
    // 완전 투명한 검정. 그대로 RGB 로 떨구면 새까만 학습지가 나온다.
    final pdf = WorksheetPdf.fromRgba(
      rgba: solid(2, 2, 0, 0, 0, 0),
      width: 2,
      height: 2,
    );
    // 압축을 풀어 실제 픽셀을 본다.
    final text = String.fromCharCodes(pdf);
    final start = text.indexOf('stream\n', text.indexOf('/Image')) + 7;
    final end = text.indexOf('\nendstream', start);
    final raw = ZLibDecoder().convert(pdf.sublist(start, end));
    expect(raw.every((b) => b == 255), isTrue, reason: '흰색이어야 한다');
  });

  test('한글 제목은 아스키만 남긴다 — 깨진 글자를 넣느니 비운다', () {
    final pdf = WorksheetPdf.fromRgba(
      rgba: solid(2, 2, 0, 0, 0),
      width: 2,
      height: 2,
      title: '받아쓰기 2026',
    );
    final text = String.fromCharCodes(pdf);
    expect(text, contains('/Title ( 2026)'));
  });

  test('잘못된 입력은 거부한다', () {
    expect(
      () => WorksheetPdf.fromRgba(rgba: Uint8List(0), width: 0, height: 0),
      throwsArgumentError,
    );
    expect(
      () => WorksheetPdf.fromRgba(rgba: Uint8List(4), width: 10, height: 10),
      throwsArgumentError,
    );
  });
}
