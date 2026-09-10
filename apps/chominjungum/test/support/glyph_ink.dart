import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

/// 자모 자산 한 장의 **잉크 분포**. 렌더 결과를 눈이 아니라 수치로 붙든다.
///
/// 왜 이런 걸 재나 — 자산은 `tool/build_hangul_assets.py` 가 jammin 원본에서
/// 좌표를 그대로 옮겨 만든다. "좌표가 그대로"인지는 파일을 봐서 알 수 있지만,
/// **렌더러가 그 좌표대로 그리는지**는 실제로 그려 봐야 안다. 특히 기기에서는
/// 폰트가 없거나(`<text>` 자산) SVG 기능이 빠지면 조용히 다른 그림이 나온다.
class GlyphInk {
  const GlyphInk({
    required this.code,
    required this.coverage,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.signature,
  });

  /// 자산 코드(파일명). 빈 칸 격자는 0.
  final int code;

  /// 잉크 픽셀 비율 0~1. 0 이면 **아무것도 안 그려졌다**는 뜻이다.
  final double coverage;

  /// 잉크가 실제로 닿은 영역(0~1 정규화). 잉크가 없으면 전부 -1.
  final double left;
  final double top;
  final double right;
  final double bottom;

  /// 8×8 격자별 잉크 비율 — **모양의 지문**.
  ///
  /// 경계 상자와 총 잉크량만으로는 부족하다. 특수문자·숫자 자산은 **테두리가 함께
  /// 들어 있어** 글자가 무엇으로 그려지든 경계가 상자 전체다. 즉 글꼴이 없어
  /// 대체 글리프(`.notdef`)가 그려져도 경계로는 안 걸린다. 격자로 나눠 보면
  /// 잉크가 **어디에 있는지**가 잡혀서 그 경우가 드러난다.
  final List<double> signature;

  bool get isBlank => coverage <= 0.00001;

  Map<String, dynamic> toJson() => {
        'code': code,
        'coverage': _r(coverage),
        'left': _r(left),
        'top': _r(top),
        'right': _r(right),
        'bottom': _r(bottom),
        'signature': signature.map(_r).toList(),
      };

  static double _r(double v) => double.parse(v.toStringAsFixed(4));

  static GlyphInk fromJson(Map<String, dynamic> j) => GlyphInk(
        code: j['code'] as int,
        coverage: (j['coverage'] as num).toDouble(),
        left: (j['left'] as num).toDouble(),
        top: (j['top'] as num).toDouble(),
        right: (j['right'] as num).toDouble(),
        bottom: (j['bottom'] as num).toDouble(),
        signature: ((j['signature'] as List?) ?? const [])
            .map((v) => (v as num).toDouble())
            .toList(),
      );

  @override
  String toString() => '$code cov=${_r(coverage)} '
      'box=(${_r(left)},${_r(top)})-(${_r(right)},${_r(bottom)})';
}

/// 측정 캔버스 한 변(논리 픽셀). 기기 배율과 무관하게 같은 값을 쓴다.
const double kInkCanvas = 240;

/// 잉크 판정 임계값. 자산은 `0xFF231F20`(거의 검정)으로 칠해지고 배경은 흰색이라
/// 중간값을 쓰면 안티에일리어싱 가장자리에 휘둘리지 않는다.
const int kInkThreshold = 160;

/// 모양 지문 격자 한 변. 8×8 이면 자모 획 하나가 여러 칸에 걸쳐 위치가 잡히고,
/// 안티에일리어싱 차이에는 둔감할 만큼 칸이 크다(240/8 = 30px).
const int kSignatureGrid = 8;

/// 자산 하나를 홀로 그려서 잉크를 잰다(배경 격자 없이).
///
/// 앱 렌더 경로(`HangulGlyphCell._svgFullCell`)와 **같은 파라미터**를 쓴다 —
/// `BoxFit.fill` + 단색 채움. 여기가 어긋나면 측정이 앱을 대변하지 못한다.
Future<GlyphInk> measureAsset(WidgetTester tester, int code) async {
  final key = GlobalKey();
  final asset =
      code == 0 ? 'assets/hangul/000000.svg' : 'assets/hangul/$code.svg';

  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: Container(
              width: kInkCanvas,
              height: kInkCanvas,
              color: Colors.white,
              child: SvgPicture.asset(
                asset,
                width: kInkCanvas,
                height: kInkCanvas,
                fit: BoxFit.fill,
                colorFilter:
                    const ColorFilter.mode(Color(0xFF231F20), BlendMode.srcIn),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  // SVG 는 비동기로 로드된다. 정착까지 기다리지 않으면 빈 화면을 재게 된다.
  await tester.pumpAndSettle(const Duration(milliseconds: 50));

  return _measureBoundary(tester, key, code);
}

Future<GlyphInk> _measureBoundary(
  WidgetTester tester,
  GlobalKey key,
  int code,
) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;

  ByteData? data;
  // 기기에서는 `runAsync` 밖에서 `toImage` 를 기다리면 교착된다.
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: 1.0);
    data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
  });

  final bytes = data!.buffer.asUint8List();
  final w = kInkCanvas.round();
  final h = kInkCanvas.round();

  int inkPixels = 0;
  int minX = w, minY = h, maxX = -1, maxY = -1;
  final cells = List<int>.filled(kSignatureGrid * kSignatureGrid, 0);

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      if (i + 2 >= bytes.length) continue;
      // 회색조 근사 — 자산은 단색이라 채널 하나만 봐도 되지만 안전하게 평균.
      final lum = (bytes[i] + bytes[i + 1] + bytes[i + 2]) ~/ 3;
      if (lum < kInkThreshold) {
        inkPixels++;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
        final cx = (x * kSignatureGrid) ~/ w;
        final cy = (y * kSignatureGrid) ~/ h;
        cells[cy * kSignatureGrid + cx]++;
      }
    }
  }

  final perCell = (w / kSignatureGrid) * (h / kSignatureGrid);
  final signature = cells.map((c) => c / perCell).toList();

  if (maxX < 0) {
    return GlyphInk(
      code: code,
      coverage: 0,
      left: -1,
      top: -1,
      right: -1,
      bottom: -1,
      signature: signature,
    );
  }

  return GlyphInk(
    code: code,
    coverage: inkPixels / (w * h),
    left: minX / w,
    top: minY / h,
    right: (maxX + 1) / w,
    bottom: (maxY + 1) / h,
    signature: signature,
  );
}

/// 앱 자산 목록 — 코드 범위는 jammin 파일명 규약 그대로.
class GlyphAssetCatalog {
  static const cho = 19; // 4352..4370
  static const jung = 21; // 4449..4469
  static const jong = 27; // 4520..4546

  static List<int> get choCodes =>
      List.generate(cho, (i) => 4352 + i);
  static List<int> get jungCodes =>
      List.generate(jung, (i) => 4449 + i);
  static List<int> get jongCodes =>
      List.generate(jong, (i) => 4520 + i);

  /// 특수문자·숫자 — 파일명이 아스키 코드다.
  /// ⚠️공백(32)도 **빈 파일이 아니라 원고지 칸 그림**이다(원본 실측). 즉 83개
  /// 전부 잉크가 있어야 하고, 비어 있으면 그건 렌더 실패다.
  static const space = 32;
  static const special = <int>[
    32, 33, 44, 46, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 63,
  ];

  /// 빈 원고지 격자.
  static const emptyCell = 0;

  /// 자산 83개 전부. (`4519` 받침없음 자산은 원본에 없다 — 앱도 그 코드를 건너뛴다.)
  static List<int> get all => [
        emptyCell,
        ...choCodes,
        ...jungCodes,
        ...jongCodes,
        ...special,
      ];
}
