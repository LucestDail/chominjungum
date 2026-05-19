import 'package:flutter/material.dart';

import 'hangul_worksheet_profile.dart';

/// jammin 지험지 격자 — 셀 전체를 채움 (hangul_1 SVG 좌표계와 일치).
///
/// 598×598 viewBox SVG 좌표 기준:
///  · 외곽 사각형: (1.5, 1.5) – (596.78, 596.78)
///  · 가로 파선: y ≈ 33.4%, 66.1%
///  · 세로 파선: x ≈ 66.6%
class HangulCellGridBackground extends StatelessWidget {
  const HangulCellGridBackground({
    super.key,
    required this.profile,
  });

  final HangulWorksheetProfile profile;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: profile.cellWidth,
      height: profile.cellHeight,
      child: CustomPaint(
        painter: _HangulCellGridPainter(),
        size: Size(profile.cellWidth, profile.cellHeight),
      ),
    );
  }
}

class _HangulCellGridPainter extends CustomPainter {
  static const _color = Color(0xFF231F20);

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 1.5;
    final rect = Rect.fromLTWH(pad, pad, size.width - pad * 2, size.height - pad * 2);

    final solid = Paint()
      ..color = _color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.square;

    canvas.drawRect(rect, solid);

    final midY1 = rect.top + rect.height * 0.334;
    final midY2 = rect.top + rect.height * 0.661;
    final midX = rect.left + rect.width * 0.666;

    _drawDashedHLine(canvas, rect.left, rect.right, midY2, solid);
    _drawDashedHLine(canvas, rect.left, midX, midY1, solid);
    _drawDashedVLine(canvas, midX, rect.top, rect.bottom, solid);
  }

  void _drawDashedHLine(Canvas canvas, double x1, double x2, double y, Paint base) {
    const dash = 8.0;
    const gap = 6.0;
    var x = x1;
    final paint = base..strokeWidth = 2.0;
    while (x < x2) {
      final end = (x + dash).clamp(x1, x2);
      canvas.drawLine(Offset(x, y), Offset(end, y), paint);
      x += dash + gap;
    }
  }

  void _drawDashedVLine(Canvas canvas, double x, double y1, double y2, Paint base) {
    const dash = 8.0;
    const gap = 6.0;
    var y = y1;
    final paint = base..strokeWidth = 2.0;
    while (y < y2) {
      final end = (y + dash).clamp(y1, y2);
      canvas.drawLine(Offset(x, y), Offset(x, end), paint);
      y += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
