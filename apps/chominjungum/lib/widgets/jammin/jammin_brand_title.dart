import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/jammin_typography.dart';

/// AppBar용 초민정음 로고 + 제목.
class JamminBrandTitle extends StatelessWidget {
  const JamminBrandTitle({super.key, required this.subtitle});

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    // 로고는 고정 크기 SVG 라서, 뒤로가기 + 액션 아이콘이 함께 놓이는 화면에서는
    // 제목 슬롯이 좁아져 오른쪽으로 넘쳤다(받아쓰기 화면 실측). 넘칠 때 통째로
    // 줄어들게 감싼다 — 로고 비율이 유지되고 글자도 함께 작아진다.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            'assets/images/navbar-logo.svg',
            height: 36,
            fit: BoxFit.contain,
          ),
          const SizedBox(width: 10),
          Text(
            subtitle,
            maxLines: 1,
            style: TextStyle(
              fontFamily: JamminTypography.family,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 0.04,
            ),
          ),
        ],
      ),
    );
  }
}
