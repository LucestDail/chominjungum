/// jammin `profiles.js`의 `editor` 프로필 (모바일 지험지).
class HangulWorksheetProfile {
  const HangulWorksheetProfile({
    required this.lineBreakCount,
    required this.rowHeight,
    required this.cellWidth,
    required this.cellHeight,
    required this.backgroundHeight,
    required this.backgroundTop,
    required this.backgroundLeft,
    required this.choHeight,
    required this.choTop,
    required this.jungHeight,
    required this.jungTop,
    required this.jongHeight,
    required this.jongTop,
    required this.specialHeights,
  });

  final int lineBreakCount;
  final double rowHeight;
  final double cellWidth;
  final double cellHeight;
  final double backgroundHeight;
  final double backgroundTop;
  final double backgroundLeft;
  final double choHeight;
  final double choTop;
  final double jungHeight;
  final double jungTop;
  final double jongHeight;
  final double jongTop;
  final Map<String, double> specialHeights;

  static const double baseCellWidth = 100;

  double specialHeightFor(int? code) {
    if (code == null) return specialHeights['default'] ?? 136;
    final key = code.toString();
    return specialHeights[key] ?? specialHeights['default'] ?? 136;
  }

  /// 화면 너비에 맞춰 jammin editor 비율 유지 스케일.
  HangulWorksheetProfile scaledToCellWidth(double targetCellWidth) {
    final s = targetCellWidth / baseCellWidth;
    return HangulWorksheetProfile(
      lineBreakCount: lineBreakCount,
      rowHeight: rowHeight * s,
      cellWidth: targetCellWidth,
      cellHeight: cellHeight * s,
      backgroundHeight: backgroundHeight * s,
      backgroundTop: backgroundTop * s,
      backgroundLeft: backgroundLeft * s,
      choHeight: choHeight * s,
      choTop: choTop * s,
      jungHeight: jungHeight * s,
      jungTop: jungTop * s,
      jongHeight: jongHeight * s,
      jongTop: jongTop * s,
      specialHeights: specialHeights.map((k, v) => MapEntry(k, v * s)),
    );
  }

  static const editor = HangulWorksheetProfile(
    lineBreakCount: 8,
    rowHeight: 170,
    cellWidth: baseCellWidth,
    cellHeight: 100,
    backgroundHeight: 90,
    backgroundTop: 2,
    backgroundLeft: 13,
    choHeight: 32.5,
    choTop: 0,
    jungHeight: 59.5,
    jungTop: 0,
    jongHeight: 33,
    jongTop: 59,
    specialHeights: {
      '32': 114,
      '33': 114,
      '63': 114,
      '46': 142,
      'default': 136,
    },
  );
}
