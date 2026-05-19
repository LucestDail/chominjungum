import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hangul_core/hangul_core.dart';

import '../theme/jammin_tokens.dart';
import 'hangul_worksheet_profile.dart';
import 'hangul_writing_cell.dart';

enum HangulWriteTool { pen, eraser }

/// jammin `hangulWrapper` + 셀별 캔버스(밑그림 위에 따라 쓰기).
///
/// jammin 웹과 동일하게 [lineBreakCount] 기준 고정 셀 크기.
/// 각 셀이 자체 State에서 스트로크를 관리 (드로잉 성능/반응성 최적화).
class HangulWritingWorksheet extends StatefulWidget {
  const HangulWritingWorksheet({
    super.key,
    required this.text,
    this.glyphs,
    this.baseProfile = HangulWorksheetProfile.editor,
    this.showGlyphGuides = true,
    this.guideOpacity = 0.45,
    this.tool = HangulWriteTool.pen,
    this.onInteraction,
  });

  final String text;
  final List<HangulGlyph>? glyphs;
  final HangulWorksheetProfile baseProfile;
  final bool showGlyphGuides;
  final double guideOpacity;
  final HangulWriteTool tool;
  final VoidCallback? onInteraction;

  @override
  State<HangulWritingWorksheet> createState() => HangulWritingWorksheetState();
}

class HangulWritingWorksheetState extends State<HangulWritingWorksheet> {
  int? get selectedCell => _selectedCell;
  late List<HangulGlyph> _glyphs;
  int? _selectedCell;

  final Map<int, GlobalKey<HangulWritingCellState>> _cellKeys = {};

  @override
  void initState() {
    super.initState();
    _resetGlyphs();
  }

  @override
  void didUpdateWidget(covariant HangulWritingWorksheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        !listEquals(oldWidget.glyphs, widget.glyphs)) {
      _resetGlyphs();
    }
  }

  void _resetGlyphs() {
    _glyphs = widget.glyphs ?? HangulUtil.hangulSplit(widget.text);
    _cellKeys.clear();
    _selectedCell = null;
  }

  GlobalKey<HangulWritingCellState> _keyFor(int index) {
    return _cellKeys.putIfAbsent(index, () => GlobalKey<HangulWritingCellState>());
  }

  void clearCell(int index) {
    _cellKeys[index]?.currentState?.clearStrokes();
    if (_selectedCell == index) {
      setState(() => _selectedCell = null);
    }
    widget.onInteraction?.call();
  }

  void clearAll() {
    for (final entry in _cellKeys.entries) {
      entry.value.currentState?.clearStrokes();
    }
    setState(() => _selectedCell = null);
    widget.onInteraction?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_glyphs.isEmpty) return const SizedBox.shrink();

    final lb = widget.baseProfile.lineBreakCount;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final cellW = (maxW / lb).floorToDouble().clamp(60.0, 140.0);
        final profile = widget.baseProfile.scaledToCellWidth(cellW);
        final rows = <Widget>[];

        for (var i = 0; i < _glyphs.length; i += lb) {
          final end = (i + lb < _glyphs.length) ? i + lb : _glyphs.length;
          final slice = _glyphs.sublist(i, end);

          rows.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var j = 0; j < slice.length; j++)
                    HangulWritingCell(
                      key: _keyFor(i + j),
                      glyph: slice[j],
                      profile: profile,
                      showGlyphGuides: widget.showGlyphGuides,
                      guideOpacity: widget.guideOpacity,
                      selected: _selectedCell == i + j,
                      tool: widget.tool,
                      onSelected: () {
                        if (_selectedCell == i + j) return;
                        setState(() => _selectedCell = i + j);
                        widget.onInteraction?.call();
                      },
                      onStrokesChanged: (_) {
                        widget.onInteraction?.call();
                      },
                    ),
                ],
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: rows,
        );
      },
    );
  }
}

/// 하단 도구 모음: 펜 / 지우개 / 선택 칸 지우기 / 전체 지우기.
class HangulWritingToolbar extends StatelessWidget {
  const HangulWritingToolbar({
    super.key,
    required this.tool,
    required this.onToolChanged,
    required this.onClearSelected,
    required this.onClearAll,
    this.hasSelection = false,
  });

  final HangulWriteTool tool;
  final ValueChanged<HangulWriteTool> onToolChanged;
  final VoidCallback onClearSelected;
  final VoidCallback onClearAll;
  final bool hasSelection;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      color: JamminTokens.surfaceElevated,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              _ToolButton(
                icon: Icons.edit,
                label: '펜',
                selected: tool == HangulWriteTool.pen,
                onTap: () => onToolChanged(HangulWriteTool.pen),
              ),
              const SizedBox(width: 8),
              _ToolButton(
                icon: Icons.auto_fix_off,
                label: '지우개',
                selected: tool == HangulWriteTool.eraser,
                onTap: () => onToolChanged(HangulWriteTool.eraser),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: hasSelection ? onClearSelected : null,
                icon: const Icon(Icons.layers_clear, size: 20),
                label: const Text('이 칸 지우기'),
              ),
              TextButton.icon(
                onPressed: onClearAll,
                icon: const Icon(Icons.delete_outline, size: 20),
                label: const Text('전체'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonal(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: selected ? JamminTokens.brandSoft : null,
        foregroundColor: selected ? JamminTokens.brandDark : JamminTokens.textMuted,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }
}
