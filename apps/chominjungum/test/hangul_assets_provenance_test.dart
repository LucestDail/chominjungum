import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 자모 자산이 **jammin 원본에서 나온 것임을 강제**한다.
///
/// ## 왜 필요한가 (2026-09-09에 실제로 당했다)
///
/// 앱의 자모 SVG 83개는 원본을 준용한다고 적혀 있었지만 실제로는 **전부 다시 그린
/// 것**이었다 — 부위별로 크롭된 원본을 598 정사각으로 옮겨 그리는 과정에서 좌표가
/// 밀렸고(ㄱ 기준 2.5%), `data-name` 도 어긋나 있었다. 웹은 원본을 그대로 써서
/// 멀쩡했으니, **같은 문항인데 앱과 웹의 학습지가 달랐다.**
///
/// 아무도 몰랐던 이유는 단순하다 — **자산의 출처를 확인하는 장치가 없었다.**
/// 자모 분해 로직에는 골든 벡터가 있어 Java·Dart·TS 가 어긋나면 즉시 깨지는데,
/// 자산에는 그런 게 없었다. 이 테스트가 그 자리를 메운다.
///
/// ## 무엇을 하나
///
/// 변환기를 `--check` 로 돌려 **지금 자산이 원본에서 재생성한 것과 바이트까지
/// 같은지** 본다. 손으로 고쳤거나, 원본이 바뀌었는데 다시 안 돌렸거나, 변환 규칙을
/// 바꾸고 자산을 갱신 안 했으면 여기서 깨진다.
///
/// ## 참조 저장소가 없을 때
///
/// jammin·chominjungum-web 은 별도 저장소라 항상 옆에 있으리라 보장할 수 없다.
/// 없으면 **건너뛴다**(실패시키지 않는다). 다만 🔴**조용히 통과시키지는 않는다** —
/// 검사하지 않은 것이 초록불로 보이면 그것이야말로 이 파일이 막으려는 실패다.
/// 검사기가 종료코드 **2 = "검사 못 함"**(1 = "검사했고 틀렸다")을 내고,
/// 여기서 `markTestSkipped` 로 **화면에 남긴다.**
///
/// 경로는 ①환경변수(`JAMMIN_DIR` / `CHOMINJUNGUM_WEB_DIR`) ②워크스페이스 형제
/// 저장소 순으로 찾는다. 절대경로를 박아 두면 이 맥 한 대에서만 동작한다.
/// 검사기가 "참조 저장소가 없어 검사하지 못했다"를 알리는 종료코드.
/// 0(통과)·1(불일치)과 반드시 구분되어야 한다.
const _exitCannotCheck = 2;

void main() {
  test('자모 자산 83개가 jammin 원본에서 재생성한 것과 동일하다', () {
    final converter = File('tool/build_hangul_assets.py');
    expect(converter.existsSync(), isTrue, reason: '변환기가 없다');

    final r = Process.runSync('python3', ['tool/build_hangul_assets.py', '--check']);
    final out = '${r.stdout}${r.stderr}'.trim();

    if (r.exitCode == _exitCannotCheck) {
      markTestSkipped('jammin 원본이 없어 자산 출처 검사를 건너뛴다.\n$out');
      return;
    }

    expect(
      r.exitCode,
      0,
      reason: '자산이 원본에서 재생성한 결과와 다르다.\n'
          '$out\n\n'
          '→ `python3 tool/build_hangul_assets.py` 로 갱신하고 결과를 눈으로 확인한 뒤 커밋할 것.',
    );
  });

  test('학습지 글꼴이 웹과 같은 글꼴이다', () {
    // 학습지의 **숫자·문장부호는 SVG 가 아니라 글꼴로** 그려진다(`<text>`).
    // 그래서 글꼴이 갈리면 자모는 멀쩡한데 숫자만 앱과 웹이 달라진다 — 눈에 잘
    // 띄지 않는 종류의 어긋남이다. jammin 이 v2(13789자)와 v3(18180자)를 **둘 다**
    // 배포하고 있어 실수로 바뀔 여지가 실제로 있다.
    //
    // ⚠️판정은 바이트가 아니라 **윤곽**으로 한다. 앱은 ttf, 웹은 woff 라 해시는
    // 물론이고 `glyf` 테이블조차 다르지만(97.2%), 좌표를 디코딩하면 전부 같다.
    final checker = File('tool/check_font_provenance.py');
    expect(checker.existsSync(), isTrue, reason: '글꼴 검사기가 없다');

    final r = Process.runSync('python3', ['tool/check_font_provenance.py']);
    final out = '${r.stdout}${r.stderr}'.trim();

    if (r.exitCode == _exitCannotCheck) {
      markTestSkipped('웹 저장소가 없어 글꼴 대조를 건너뛴다.\n$out');
      return;
    }

    expect(r.exitCode, 0, reason: '앱 글꼴이 웹과 다르다.\n$out');
  });
}
