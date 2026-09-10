import 'package:flutter/material.dart';
import 'package:hangul_core/hangul_core.dart';

import '../theme/jammin_tokens.dart';
import 'hangul_glyph_cell.dart';
import 'hangul_worksheet_profile.dart';
import 'hangul_writing_worksheet.dart';

class HangulWritingCell extends StatefulWidget {
  const HangulWritingCell({
    super.key,
    required this.glyph,
    required this.profile,
    this.showGlyphGuides = true,
    this.guideOpacity = 0.45,
    this.hidden = HiddenParts.none,
    required this.selected,
    this.tool = HangulWriteTool.pen,
    this.onStrokesChanged,
    this.onSelected,
  });

  final HangulGlyph glyph;
  final HangulWorksheetProfile profile;
  final bool showGlyphGuides;
  final double guideOpacity;

  /// 자모 가리기 — 이 부위는 밑그림을 안 그린다. 학생이 직접 채우는 칸이다.
  final HiddenParts hidden;

  final bool selected;
  final HangulWriteTool tool;
  final ValueChanged<List<List<Offset>>>? onStrokesChanged;
  final VoidCallback? onSelected;

  @override
  State<HangulWritingCell> createState() => HangulWritingCellState();
}

class HangulWritingCellState extends State<HangulWritingCell> {
  /// Painter가 직접 listen → cell rebuild 없이 paint만 trigger.
  final ChangeNotifier _strokeNotifier = ChangeNotifier();
  final List<List<Offset>> _strokes = [];
  List<Offset>? _current;

  bool get hasStrokes => _strokes.isNotEmpty;

  @override
  void dispose() {
    _strokeNotifier.dispose();
    super.dispose();
  }

  void _notify() {
    // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
    _strokeNotifier.notifyListeners();
  }

  void _selectIfNeeded() {
    if (!widget.selected) widget.onSelected?.call();
  }

  void clearStrokes() {
    _strokes.clear();
    _current = null;
    _notify();
    widget.onStrokesChanged?.call(const []);
  }

  void _dot(Offset local) {
    if (widget.tool == HangulWriteTool.eraser) {
      _eraseAt(local);
      return;
    }
    _strokes.add([local]);
    _notify();
    widget.onStrokesChanged?.call(List.from(_strokes));
  }

  void _startStroke(Offset local) {
    if (widget.tool == HangulWriteTool.eraser) {
      _eraseAt(local);
      return;
    }
    _current = [local];
    _strokes.add(_current!);
    _notify();
  }

  void _extendStroke(Offset local) {
    if (widget.tool == HangulWriteTool.eraser) {
      _eraseAt(local);
      return;
    }
    final cur = _current;
    if (cur == null) return;
    // sampling: 인접 점이 너무 가까우면 skip해서 paint 부담 감소.
    final last = cur.last;
    if ((local - last).distanceSquared < 1.0) return;
    cur.add(local);
    _notify();
  }

  void _endStroke() {
    if (_current == null) return;
    _current = null;
    widget.onStrokesChanged?.call(List.from(_strokes));
  }

  void _eraseAt(Offset local) {
    const radius = 14.0;
    final before = _strokes.length;
    _strokes.removeWhere((s) {
      for (final p in s) {
        if ((p - local).distance <= radius) return true;
      }
      return false;
    });
    if (_strokes.length != before) {
      _notify();
      widget.onStrokesChanged?.call(List.from(_strokes));
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.profile.cellWidth;
    final h = widget.profile.cellHeight;
    final borderColor =
        widget.selected ? JamminTokens.brand : Colors.grey.shade400;
    final borderWidth = widget.selected ? 2.0 : 1.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _selectIfNeeded(),
      onTapUp: (d) {
        // 짧은 탭(드래그 안 됨) = 점 한 개.
        _dot(d.localPosition);
      },
      onPanStart: (d) {
        _selectIfNeeded();
        _startStroke(d.localPosition);
      },
      onPanUpdate: (d) => _extendStroke(d.localPosition),
      onPanEnd: (_) => _endStroke(),
      onPanCancel: () => _current = null,
      child: SizedBox(
        width: w,
        height: h,
        child: Stack(
          children: [
            Container(
              width: w,
              height: h,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: borderColor, width: borderWidth),
              ),
            ),
            RepaintBoundary(
              child: IgnorePointer(
                child: HangulGlyphCell(
                  glyph: widget.glyph,
                  profile: widget.profile,
                  showGlyphGuides: widget.showGlyphGuides,
                  guideOpacity: widget.guideOpacity,
                  showBackground: true,
                  hidden: widget.hidden,
                ),
              ),
            ),
            RepaintBoundary(
              child: IgnorePointer(
                child: CustomPaint(
                  size: Size(w, h),
                  painter: _StrokePainter(_strokes, _strokeNotifier),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StrokePainter extends CustomPainter {
  _StrokePainter(this.strokes, Listenable repaint) : super(repaint: repaint);

  final List<List<Offset>> strokes;

  static final _strokePaint = Paint()
    ..color = const Color(0xFF111111)
    ..strokeWidth = 3
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;
  static final _dotPaint = Paint()..color = const Color(0xFF111111);

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      if (s.isEmpty) continue;
      if (s.length == 1) {
        canvas.drawCircle(s.first, 1.6, _dotPaint);
        continue;
      }
      final path = Path()..moveTo(s.first.dx, s.first.dy);
      for (var i = 1; i < s.length; i++) {
        path.lineTo(s[i].dx, s[i].dy);
      }
      canvas.drawPath(path, _strokePaint);
    }
  }

  // CustomPainter는 super.repaint Listenable로 자동 repaint trigger.
  // 동일 strokes 참조 + Listenable로 trigger되므로 false 반환해도 안전.
  @override
  bool shouldRepaint(covariant _StrokePainter old) => false;
}
