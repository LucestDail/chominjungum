import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hangul_core/hangul_core.dart';

import '../services/stroke_order_check.dart';
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
    this.hideRule = HideRule.empty,
    this.onStrokeAdvice,
  });

  final String text;
  final List<HangulGlyph>? glyphs;
  final HangulWorksheetProfile baseProfile;
  final bool showGlyphGuides;
  final double guideOpacity;
  final HangulWriteTool tool;
  final VoidCallback? onInteraction;

  /// 자모 가리기 — 가려진 부위는 밑그림 없이 빈칸으로 나온다(jammin `hidebox`).
  final HideRule hideRule;

  /// 획을 그을 때마다 **획순 지적**이 있으면 알린다(없으면 null).
  ///
  /// 글씨를 잘 썼는지가 아니라 **순서·방향**만 본다 — 좌표로 확실히 말할 수
  /// 있는 것만. 화면이 이 문구를 그대로 보여 준다.
  final ValueChanged<String?>? onStrokeAdvice;

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
        // 한 줄에 몇 칸을 넣을지는 **화면 폭이 정한다**.
        //
        // 예전에는 프로필의 lineBreakCount(=8)로 고정하고 셀 폭만
        // `(maxW / 8).clamp(60, 140)` 으로 잡았는데, 좁은 화면에서 `maxW / 8` 이
        // 60 미만이 되면 clamp 하한이 60으로 끌어올려 **칸수 × 60 > maxW** 가 되어
        // 오른쪽 칸이 화면 밖으로 잘렸다(iPhone 17 Pro Max 에서 7칸이 32px 초과).
        // 잘린 칸에는 학생이 답을 쓸 수 없으므로 미관 문제가 아니라 기능 장애다.
        //
        // 인쇄용 학습지는 lineBreakCount 를 지켜야 하지만(jammin 준용), 이 위젯은
        // 화면 응시 전용이라 접는 위치를 화면에 맞추는 것이 맞다.
        const minCellW = 60.0; // 손가락으로 쓸 수 있는 최소 칸
        final fits = (maxW / minCellW).floor();
        final perRow = fits < 1 ? 1 : (fits < lb ? fits : lb);
        final cellW = (maxW / perRow).floorToDouble().clamp(minCellW, 140.0);
        final profile = widget.baseProfile.scaledToCellWidth(cellW);
        final rows = <Widget>[];

        for (var i = 0; i < _glyphs.length; i += perRow) {
          final end = (i + perRow < _glyphs.length) ? i + perRow : _glyphs.length;
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
                      hidden: widget.hideRule.partsOf(slice[j]),
                      selected: _selectedCell == i + j,
                      tool: widget.tool,
                      onSelected: () {
                        if (_selectedCell == i + j) return;
                        setState(() => _selectedCell = i + j);
                        widget.onInteraction?.call();
                      },
                      onStrokesChanged: (strokes) {
                        widget.onInteraction?.call();
                        final advise = widget.onStrokeAdvice;
                        if (advise == null) return;
                        advise(
                          StrokeOrderCheck.summarize(
                            StrokeOrderCheck.check(
                              strokes,
                              cellSize: profile.cellWidth,
                            ),
                          ),
                        );
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
          // 좁은 화면에서 Row 가 넘쳤다(1.4px). 여유를 만들어 **라벨을 살린다** —
          // 지우기는 되돌릴 수 없는 동작이라 아이콘만 남으면 초등학생이 뜻을 모른다.
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
              Flexible(
                child: TextButton.icon(
                  style: _clearButtonStyle,
                  onPressed: hasSelection ? onClearSelected : null,
                  icon: const Icon(Icons.layers_clear, size: 18),
                  // "이 칸 지우기" 는 4개 버튼과 함께 한 줄에 들어가지 않아
                  // `이…` 로 잘렸다. 잘린 라벨보다 짧고 온전한 라벨이 낫다 —
                  // 지우개 옆 문맥과 아이콘이 "지우기"를 지탱한다.
                  label: const Text('이 칸',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
              Flexible(
                child: TextButton.icon(
                  style: _clearButtonStyle,
                  onPressed: onClearAll,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('전체',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 지우기 버튼: 라벨을 살리려고 여백·글자를 조금 줄였다(툴바가 1.4px 넘쳤다).
final _clearButtonStyle = TextButton.styleFrom(
  padding: const EdgeInsets.symmetric(horizontal: 8),
  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
  visualDensity: VisualDensity.compact,
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
);

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
