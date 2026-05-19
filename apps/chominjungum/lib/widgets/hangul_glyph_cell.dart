import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hangul_core/hangul_core.dart';

import 'hangul_cell_grid_background.dart';
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

  String _assetForCode(int code) => 'assets/hangul/$code.svg';

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

  /// 특수문자(마침표, 쉼표 등)는 별도 크기.
  Widget _svgSpecial(int code) {
    final h = profile.specialHeightFor(code);
    return Positioned(
      top: 2,
      left: 2,
      child: SvgPicture.asset(
        _assetForCode(code),
        height: h,
        fit: BoxFit.contain,
        alignment: Alignment.topLeft,
        colorFilter: const ColorFilter.mode(Color(0xFF231F20), BlendMode.srcIn),
        errorBuilder: (_, error, __) {
          debugPrint('SVG special $code: $error');
          return SizedBox(height: h, width: h);
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
            if (showBackground && !glyph.specialFlag)
              HangulCellGridBackground(profile: profile),
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
      return [_svgSpecial(code)];
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
