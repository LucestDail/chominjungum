import 'package:flutter/material.dart';
import 'package:hangul_core/hangul_core.dart';

import 'hangul_glyph_cell.dart';
import 'hangul_worksheet_profile.dart';

/// 문장을 jammin 스타일 지험지 행으로 표시.
class HangulWorksheet extends StatelessWidget {
  const HangulWorksheet({
    super.key,
    required this.text,
    this.profile = HangulWorksheetProfile.editor,
    this.showGlyphGuides = false,
    this.scale = 1.0,
  });

  final String text;
  final HangulWorksheetProfile profile;
  final bool showGlyphGuides;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final glyphs = HangulUtil.hangulSplit(text);
    if (glyphs.isEmpty) {
      return const SizedBox.shrink();
    }

    final cellW = profile.cellWidth * scale;
    final cellH = profile.cellHeight * scale;
    final rowH = profile.rowHeight * scale;
    final lb = profile.lineBreakCount;

    final rows = <Widget>[];
    for (var i = 0; i < glyphs.length; i += lb) {
      final end = (i + lb < glyphs.length) ? i + lb : glyphs.length;
      final slice = glyphs.sublist(i, end);
      rows.add(
        SizedBox(
          height: rowH,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final g in slice)
                  SizedBox(
                    width: cellW,
                    height: cellH,
                    child: HangulGlyphCell(
                      glyph: g,
                      profile: profile,
                      showGlyphGuides: showGlyphGuides,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}
