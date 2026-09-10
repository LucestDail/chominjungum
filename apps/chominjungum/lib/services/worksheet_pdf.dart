import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// 학습지를 **PDF 한 장**으로 쓴다 — 의존성 없이.
///
/// ## 왜 직접 쓰나
///
/// `printing`·`pdf` 패키지를 넣으면 iOS 파드 구성이 바뀌고, 그러면 **흰 화면
/// 함정이 재발**한다(2026-09-10 하루에 두 번 겪었다). 그런데 우리가 필요한
/// PDF 는 **이미지 한 장을 A4 에 얹은 것**뿐이다 — 학습지는 이미 화면에
/// 그려지므로 그걸 래스터화해 담으면 된다.
///
/// 그 정도는 PDF 스펙의 아주 작은 부분만 쓰면 되고, 표준 라이브러리
/// (`ZLibCodec`)로 충분하다. 플러그인을 안 늘리는 값이 더 크다고 봤다.
///
/// ## 왜 이미지인가 — 레이아웃을 두 번 그리지 않는다
///
/// PDF 안에 자모를 다시 배치하면 **화면과 다른 학습지**가 나올 수 있다.
/// 09-09 에 자산을 다시 그려서 앱과 웹이 갈라졌던 것과 같은 함정이다.
/// 화면에 그린 것을 **그대로** 담으면 어긋날 자리가 없다.
///
/// ⚠️그래서 텍스트 선택·검색은 안 된다. 학습지는 인쇄해서 연필로 쓰는 물건이라
/// 그 손해가 없다.
class WorksheetPdf {
  const WorksheetPdf._();

  /// A4 세로, 72dpi 포인트 단위.
  static const a4Width = 595.28;
  static const a4Height = 841.89;

  /// 가장자리 여백(포인트). 프린터 여백에 잘리지 않을 만큼.
  static const margin = 36.0;

  /// RGBA 픽셀 [rgba]([width]×[height])를 A4 한 장에 얹은 PDF 바이트.
  ///
  /// 이미지는 가로·세로 비율을 지키며 여백 안에 **맞춰 넣는다**(잘리지 않는다).
  static Uint8List fromRgba({
    required Uint8List rgba,
    required int width,
    required int height,
    String title = '받아쓰기',
  }) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('이미지 크기가 잘못됐습니다: ${width}x$height');
    }
    final expected = width * height * 4;
    if (rgba.length < expected) {
      throw ArgumentError(
        '픽셀이 모자랍니다: ${rgba.length} < $expected',
      );
    }

    // PDF 이미지는 알파를 따로 다뤄야 한다. 학습지는 흰 배경이라
    // **흰색 위에 합성**해 RGB 로 떨군다 — 투명이 검게 나오는 사고를 막는다.
    final rgb = Uint8List(width * height * 3);
    for (var i = 0, o = 0; i < expected; i += 4, o += 3) {
      final a = rgba[i + 3];
      if (a == 255) {
        rgb[o] = rgba[i];
        rgb[o + 1] = rgba[i + 1];
        rgb[o + 2] = rgba[i + 2];
      } else {
        final inv = 255 - a;
        rgb[o] = ((rgba[i] * a) + 255 * inv) ~/ 255;
        rgb[o + 1] = ((rgba[i + 1] * a) + 255 * inv) ~/ 255;
        rgb[o + 2] = ((rgba[i + 2] * a) + 255 * inv) ~/ 255;
      }
    }
    final deflated = Uint8List.fromList(ZLibEncoder().convert(rgb));

    // 여백 안에 비율 유지로 맞춘다.
    final availW = a4Width - margin * 2;
    final availH = a4Height - margin * 2;
    final scale = (availW / width) < (availH / height)
        ? availW / width
        : availH / height;
    final drawW = width * scale;
    final drawH = height * scale;
    final x = (a4Width - drawW) / 2;
    // 위쪽부터 채운다 — 학습지가 페이지 가운데 떠 있으면 어색하다.
    final y = a4Height - margin - drawH;

    final out = BytesBuilder();
    final offsets = <int>[];
    void write(String s) => out.add(latin1.encode(s));
    void startObject(int n) {
      offsets.add(out.length);
      write('$n 0 obj\n');
    }

    write('%PDF-1.4\n');
    // 바이너리가 들어 있음을 알리는 관례적 주석. 없으면 일부 도구가 텍스트로 본다.
    out.add([0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A]);

    startObject(1);
    write('<< /Type /Catalog /Pages 2 0 R >>\nendobj\n');

    startObject(2);
    write('<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n');

    startObject(3);
    write('<< /Type /Page /Parent 2 0 R '
        '/MediaBox [0 0 ${_n(a4Width)} ${_n(a4Height)}] '
        '/Resources << /XObject << /Im0 4 0 R >> >> '
        '/Contents 5 0 R >>\nendobj\n');

    startObject(4);
    write('<< /Type /XObject /Subtype /Image '
        '/Width $width /Height $height '
        '/ColorSpace /DeviceRGB /BitsPerComponent 8 '
        '/Filter /FlateDecode /Length ${deflated.length} >>\nstream\n');
    out.add(deflated);
    write('\nendstream\nendobj\n');

    final content =
        'q\n${_n(drawW)} 0 0 ${_n(drawH)} ${_n(x)} ${_n(y)} cm\n/Im0 Do\nQ\n';
    startObject(5);
    write('<< /Length ${content.length} >>\nstream\n$content'
        'endstream\nendobj\n');

    startObject(6);
    write('<< /Title (${_escape(title)}) /Producer (chominjungum) >>\nendobj\n');

    final xref = out.length;
    write('xref\n0 ${offsets.length + 1}\n');
    write('0000000000 65535 f \n');
    for (final off in offsets) {
      write('${off.toString().padLeft(10, '0')} 00000 n \n');
    }
    write('trailer\n<< /Size ${offsets.length + 1} /Root 1 0 R /Info 6 0 R >>\n'
        'startxref\n$xref\n%%EOF\n');

    return out.toBytes();
  }

  /// PDF 숫자 표기 — 지수 표기(`1e3`)를 쓰면 안 된다.
  static String _n(double v) => v.toStringAsFixed(2);

  /// PDF 문자열 안의 특수문자.
  ///
  /// ⚠️PDF 기본 인코딩은 한글을 그대로 담지 못한다. 제목은 부가 정보라
  /// **아스키만 남긴다** — 깨진 글자를 넣느니 비우는 편이 낫다.
  static String _escape(String s) {
    final ascii = s.runes.where((r) => r >= 0x20 && r < 0x7F);
    return String.fromCharCodes(ascii)
        .replaceAll(r'\', r'\\')
        .replaceAll('(', r'\(')
        .replaceAll(')', r'\)');
  }
}
