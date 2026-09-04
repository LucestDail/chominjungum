import 'package:flutter/material.dart';

import '../../theme/jammin_tokens.dart';

/// 채점 결과의 글자 한 칸.
///
/// 맞으면 글자와 체크만 보인다. **틀리면 "내가 쓴 글자 → 정답"을 함께 보여준다.**
///
/// 그전에는 정답 글자만 띄웠는데, 받아쓰기에서 배우는 지점은 "무엇이 맞다"가 아니라
/// **"내가 이렇게 썼고 실제로는 이렇다"** 는 대조다. 자기가 쓴 것이 안 보이면
/// 왜 틀렸는지 알 수 없다.
///
/// 틀린 이유 문구(`mismatchReason`)는 일부러 띄우지 않는다 —
/// "글자 불일치: \"갔\" vs \"갓\"" 같은 개발자 문구이고, 초등 저학년 화면에
/// 그대로 내보낼 말이 아니다. 두 글자를 나란히 보이는 것으로 충분하다.
class GlyphResultChip extends StatelessWidget {
  const GlyphResultChip({
    super.key,
    required this.isCorrect,
    this.expected,
    this.actual,
  });

  final bool isCorrect;

  /// 정답 글자. 학생이 덧붙여 쓴 글자라면 null.
  final String? expected;

  /// 학생이 쓴 글자. 빠뜨렸다면 null.
  final String? actual;

  static const _missing = '□';

  @override
  Widget build(BuildContext context) {
    final color = isCorrect ? JamminTokens.success : JamminTokens.danger;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(JamminTokens.radiusSm),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: isCorrect ? _correct(color) : _wrong(color),
      ),
    );
  }

  List<Widget> _correct(Color color) => [
        Text(
          expected ?? actual ?? _missing,
          style: TextStyle(color: color, fontSize: 16),
        ),
        const SizedBox(width: 4),
        Icon(Icons.check, size: 14, color: color),
      ];

  /// 쓴 글자 → 정답. 빠뜨린 자리는 빈 칸 기호(□)로 둔다.
  List<Widget> _wrong(Color color) => [
        Text(
          actual ?? _missing,
          style: TextStyle(
            color: color,
            fontSize: 16,
            // 지운 것이 아니라 "이건 아니다"는 표시
            decoration: TextDecoration.lineThrough,
            decorationColor: color,
          ),
        ),
        Icon(Icons.arrow_right_alt, size: 16, color: color),
        Text(
          expected ?? _missing,
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ];
}
