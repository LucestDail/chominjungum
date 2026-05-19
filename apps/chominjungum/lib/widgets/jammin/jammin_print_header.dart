import 'package:flutter/material.dart';

import '../../theme/jammin_tokens.dart';
import '../../theme/jammin_typography.dart';

/// jammin `.printAreaWrapper` — 받아쓰기 시험지 상단 헤더.
class JamminPrintHeader extends StatelessWidget {
  const JamminPrintHeader({
    super.key,
    this.leftLine1 = '초민정음',
    this.leftLine2 = '받아쓰기',
    this.rightLine1 = '초등학교',
    this.rightLine2 = '학년   반   번호',
    this.rightLine3 = '이름',
  });

  final String leftLine1;
  final String leftLine2;
  final String rightLine1;
  final String rightLine2;
  final String rightLine3;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 96,
      decoration: BoxDecoration(
        border: Border.all(color: JamminTokens.borderStrong, width: 2),
        borderRadius: BorderRadius.circular(JamminTokens.radiusMd),
        color: JamminTokens.surfaceElevated,
      ),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    leftLine1,
                    style: TextStyle(
                      fontFamily: JamminTypography.family,
                      fontSize: 28,
                      height: 1.1,
                      color: JamminTokens.text,
                    ),
                  ),
                  Text(
                    leftLine2,
                    style: TextStyle(
                      fontFamily: JamminTypography.family,
                      fontSize: 24,
                      height: 1.1,
                      color: JamminTokens.text,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 20, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _rightLine(context, rightLine1, 22),
                  _rightLine(context, rightLine2, 18),
                  _rightLine(context, rightLine3, 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rightLine(BuildContext context, String text, double size) {
    return Text(
      text,
      textAlign: TextAlign.right,
      style: TextStyle(
        fontFamily: JamminTypography.family,
        fontSize: size,
        height: 1.2,
        color: JamminTokens.text,
      ),
    );
  }
}
