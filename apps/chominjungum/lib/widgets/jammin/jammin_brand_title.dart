import 'package:flutter/material.dart';

import '../../theme/jammin_typography.dart';

/// AppBar용 초민정음 로고 + 제목.
///
/// ## 로고는 jammin 원본 PNG 를 **바이트 그대로** 쓴다
///
/// 2026-09-09 이전에는 `navbar-logo.svg` 를 썼는데, 그것은 원본이 아니라
/// **SVG 편집기로 손수 그린 재현물**이었다 — `font-family="Noto Sans JP"`(한글을
/// 일본어 폰트로), `style="cursor: move;"` 같은 편집기 잔재가 남아 있었고, 글자를
/// `<text>` 로 직접 그려서 기기에 그 폰트가 없으면 렌더가 제각각이 된다.
///
/// jammin 은 **로직과 자산의 참조 원본**이므로 임의 재현이 아니라 원본을 복사해
/// 쓰는 것이 맞다(`chominjungum-web` 이 자모 SVG 83개를 그렇게 쓰고 있다).
/// 출처 = `jammin/src/main/resources/static/img/navbar-logo.png`
/// (sha256 `3a1deff1…`, 1360×544). 원본이 바뀌면 이 파일도 다시 복사할 것.
class JamminBrandTitle extends StatelessWidget {
  const JamminBrandTitle({super.key, required this.subtitle});

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    // 로고는 고정 크기라서, 뒤로가기 + 액션 아이콘이 함께 놓이는 화면에서는
    // 제목 슬롯이 좁아져 오른쪽으로 넘쳤다(받아쓰기 화면 실측). 넘칠 때 통째로
    // 줄어들게 감싼다 — 로고 비율이 유지되고 글자도 함께 작아진다.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/images/navbar-logo.png',
            height: 30,
            fit: BoxFit.contain,
            // 원본은 흰 글자 투명 배경이다. 초록 앱바 위에 그대로 얹힌다.
            filterQuality: FilterQuality.medium,
            semanticLabel: '초민정음',
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
