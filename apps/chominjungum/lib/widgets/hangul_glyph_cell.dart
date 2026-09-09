import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hangul_core/hangul_core.dart';

import 'hangul_worksheet_profile.dart';

/// jammin `hangulSet` 한 칸 — 지험지(밑그림) + 초·중·종 SVG.
///
/// `hangul_1` SVG는 viewBox 598×598 전체 셀 좌표계에 각 자모 위치가 이미 잡혀 있으므로,
/// 셀 크기 그대로 렌더하면 초·중·종이 자동으로 올바른 영역에 위치합니다.
class HangulGlyphCell extends StatelessWidget {
  const HangulGlyphCell({
    super.key,
    required this.glyph,
    required this.profile,
    this.showGlyphGuides = true,
    this.guideOpacity = 0.45,
    this.showBackground = true,
  });

  final HangulGlyph glyph;
  final HangulWorksheetProfile profile;
  final bool showGlyphGuides;
  final double guideOpacity;
  final bool showBackground;

  static const _noJongCode = 4519;

  /// 빈 원고지 칸(격자) 자산. jammin 파일명 규약을 그대로 따른다.
  static const _emptyCellAsset = 0;

  String _assetForCode(int code) =>
      code == _emptyCellAsset ? 'assets/hangul/000000.svg' : 'assets/hangul/$code.svg';

  /// 셀 전체 크기(cellWidth × cellHeight)로 렌더. SVG 내부 좌표가 위치를 잡음.
  Widget _svgFullCell(int code) {
    return Positioned.fill(
      child: SvgPicture.asset(
        _assetForCode(code),
        width: profile.cellWidth,
        height: profile.cellHeight,
        fit: BoxFit.fill,
        colorFilter: const ColorFilter.mode(Color(0xFF231F20), BlendMode.srcIn),
        errorBuilder: (_, error, __) {
          debugPrint('SVG $code: $error');
          return SizedBox(
            width: profile.cellWidth,
            height: profile.cellHeight,
            child: Icon(Icons.broken_image, size: 20, color: Colors.red.shade300),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: profile.cellWidth,
      height: profile.cellHeight,
      child: ClipRect(
        child: Stack(
          children: [
            // 원고지 격자도 jammin 원본 자산(`000000.svg`)을 쓴다.
            // 예전에는 CustomPaint 로 직접 그렸는데 598 좌표를 가정하고 있어
            // 623.6 좌표계인 자모와 미세하게 어긋났다.
            if (showBackground) _svgFullCell(_emptyCellAsset),
            if (showGlyphGuides && guideOpacity > 0.01)
              Opacity(
                opacity: guideOpacity.clamp(0.0, 1.0),
                child: Stack(children: _glyphLayers()),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _glyphLayers() {
    if (glyph.specialFlag) {
      final code = glyph.specialTypeCode;
      if (code == null) return const [];
      // 특수문자·숫자도 **전체 셀 경로**를 쓴다.
      // 예전에는 프로필의 픽셀 높이(`specialHeights`)로 따로 그렸는데, 자산을
      // jammin 원본에서 변환한 뒤로는 배치가 자산 안에 들어 있어 그럴 필요가 없다
      // (변환기가 폭을 상자에 맞춰 `scale` 을 적용한다 — 웹 `placeSpecial()` 과 같다).
      return [_svgFullCell(code)];
    }
    if (glyph.errorFlag) return const [];
    final layers = <Widget>[];
    if (glyph.choCode != null) {
      layers.add(_svgFullCell(glyph.choCode!));
    }
    if (glyph.jungCode != null) {
      layers.add(_svgFullCell(glyph.jungCode!));
    }
    if (!glyph.emptyJongsung && glyph.jongCode != null && glyph.jongCode != _noJongCode) {
      layers.add(_svgFullCell(glyph.jongCode!));
    }
    return layers;
  }
}
