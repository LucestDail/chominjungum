import 'package:flutter/material.dart';

/// 받아쓰기 손글씨 캔버스 (여러 스트로크).
class StrokeCanvas extends StatefulWidget {
  const StrokeCanvas({
    super.key,
    required this.onStrokesChanged,
  });

  final ValueChanged<List<List<Offset>>> onStrokesChanged;

  @override
  State<StrokeCanvas> createState() => _StrokeCanvasState();
}

class _StrokeCanvasState extends State<StrokeCanvas> {
  final _strokes = <List<Offset>>[];
  List<Offset>? _current;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Listener(
          onPointerDown: (e) {
            _current = [e.localPosition];
            _strokes.add(_current!);
            setState(() {});
            widget.onStrokesChanged(List.from(_strokes));
          },
          onPointerMove: (e) {
            if (_current == null) return;
            _current!.add(e.localPosition);
            setState(() {});
            widget.onStrokesChanged(List.from(_strokes));
          },
          onPointerUp: (_) {
            _current = null;
          },
          onPointerCancel: (_) {
            _current = null;
          },
          child: CustomPaint(
            painter: _StrokePainter(_strokes),
            size: Size(constraints.maxWidth, constraints.maxHeight),
          ),
        );
      },
    );
  }

  void clear() {
    _strokes.clear();
    setState(() {});
    widget.onStrokesChanged(const []);
  }
}

class _StrokePainter extends CustomPainter {
  _StrokePainter(this.strokes);

  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black87
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final s in strokes) {
      if (s.length < 2) continue;
      final path = Path()..moveTo(s.first.dx, s.first.dy);
      for (var i = 1; i < s.length; i++) {
        path.lineTo(s[i].dx, s[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StrokePainter oldDelegate) =>
      oldDelegate.strokes != strokes;
}
