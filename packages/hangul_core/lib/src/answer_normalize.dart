/// 답안 **정규화** — 채점 전에 "같은 답인데 다르게 적힌 것"을 맞춘다.
///
/// ## 왜 필요한가
///
/// 지금 채점은 글자를 그대로 비교한다. 그래서 학생이 맞게 썼는데도 틀리게
/// 세는 경우가 생긴다:
///
///   - **자판 조합이 덜 끝난 글자** — iOS 한글 자판은 조합 중에 `ᄒ`(초성 낱자)
///     같은 **결합 자모**를 내놓는다. 화면에는 "학"으로 보여도 문자열은 다르다
///   - **호환 자모 vs 결합 자모** — `ㄱ`(U+3131)과 `ᄀ`(U+1100)은 눈에 같지만
///     코드가 다르다. 붙여넣기·OCR 결과에 섞여 들어온다
///   - **공백** — 문장 앞뒤 공백, 두 칸 띄어쓰기
///   - **전각 문자** — `？`·`，`·`１` 이 자판 설정에 따라 들어온다
///
/// 손글씨 인식을 붙이면 이런 잡음이 더 늘어난다. 그래서 인식 수단과 **무관하게**
/// 여기서 한 번 걸러 낸다.
///
/// ## 하지 않는 것
///
/// ⚠️**맞춤법을 고치지 않는다.** `갓`→`갔` 같은 것은 **학생이 틀린 것**이고
/// 그걸 맞춰 주면 받아쓰기의 의미가 없다. 여기서 다루는 것은 오직
/// **"같은 글자를 다르게 표현한 것"** 뿐이다.
library;

/// 답안을 채점 가능한 형태로 고친다.
///
/// 순서가 중요하다 — 자모를 먼저 합치고(NFC), 그다음 공백을 정리한다.
String normalizeAnswer(String raw) {
  var s = raw;
  s = _toCompatibilityDigitsAndPunct(s);
  s = composeJamo(s);
  s = collapseSpaces(s);
  return s;
}

/// 전각·유사 문자를 학습지가 쓰는 반각으로.
///
/// jammin 자산은 `. , ? !` 와 숫자만 그린다. 전각으로 들어오면 **특수문자 자산을
/// 못 찾아** 빈 칸이 된다.
String _toCompatibilityDigitsAndPunct(String s) {
  final buf = StringBuffer();
  for (final r in s.runes) {
    // 전각 숫자·영문·기호 (U+FF01~U+FF5E) → 반각
    if (r >= 0xFF01 && r <= 0xFF5E) {
      buf.writeCharCode(r - 0xFEE0);
      continue;
    }
    buf.writeCharCode(switch (r) {
      0x3000 => 0x20, // 전각 공백
      0x2018 || 0x2019 => 0x27, // ‘ ’
      0x201C || 0x201D => 0x22, // “ ”
      0x2026 => 0x2E, // … → . (한 글자로 줄인다)
      _ => r,
    });
  }
  return buf.toString();
}

/// 결합 자모(초성+중성+종성)를 완성형 음절로 합친다.
///
/// 한글 조합 규칙 그대로다: `((초성 * 21) + 중성) * 28 + 종성 + 0xAC00`.
/// 합칠 수 없는 낱자는 **호환 자모로 바꿔** 남긴다 — `ᄀ` 를 그대로 두면
/// 학습지에서 자모 자산을 못 찾는다.
String composeJamo(String s) {
  const choFirst = 0x1100, choLast = 0x1112;
  const jungFirst = 0x1161, jungLast = 0x1175;
  const jongFirst = 0x11A8, jongLast = 0x11C2;

  final runes = s.runes.toList();
  final out = StringBuffer();
  var i = 0;

  while (i < runes.length) {
    final c = runes[i];
    final isCho = c >= choFirst && c <= choLast;
    if (!isCho) {
      out.writeCharCode(_toCompatJamo(c));
      i++;
      continue;
    }

    // 초성 다음에 중성이 와야 음절이 된다.
    if (i + 1 >= runes.length ||
        runes[i + 1] < jungFirst ||
        runes[i + 1] > jungLast) {
      out.writeCharCode(_toCompatJamo(c));
      i++;
      continue;
    }

    final cho = c - choFirst;
    final jung = runes[i + 1] - jungFirst;
    var jong = 0;
    var consumed = 2;

    if (i + 2 < runes.length &&
        runes[i + 2] >= jongFirst &&
        runes[i + 2] <= jongLast) {
      // ⚠️다음 글자의 초성일 수도 있다. 종성으로 쓸 수 있는 자모라도
      // **그 뒤에 중성이 이어지면** 그건 다음 음절의 초성이다("각오" vs "가고").
      final maybeJongIsNextCho = i + 3 < runes.length &&
          runes[i + 3] >= jungFirst &&
          runes[i + 3] <= jungLast &&
          _jongHasChoForm(runes[i + 2]);
      if (!maybeJongIsNextCho) {
        jong = runes[i + 2] - jongFirst + 1;
        consumed = 3;
      }
    }

    out.writeCharCode(((cho * 21) + jung) * 28 + jong + 0xAC00);
    i += consumed;
  }
  return out.toString();
}

/// 이 종성 자모가 **초성으로도 쓰이는 글자**인가.
/// 겹받침(ㄳ·ㄵ…)은 초성이 될 수 없으므로 다음 음절의 초성일 리 없다.
bool _jongHasChoForm(int jongRune) {
  const jongCompat = 'ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ';
  const choCompat = 'ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ';
  final idx = jongRune - 0x11A8;
  if (idx < 0 || idx >= jongCompat.length) return false;
  return choCompat.contains(jongCompat[idx]);
}

/// 결합 자모 낱자 → 호환 자모. 그 외는 그대로.
int _toCompatJamo(int r) {
  const cho = 'ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ';
  const jung = 'ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ';
  const jong = 'ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ';
  if (r >= 0x1100 && r <= 0x1112) return cho.codeUnitAt(r - 0x1100);
  if (r >= 0x1161 && r <= 0x1175) return jung.codeUnitAt(r - 0x1161);
  if (r >= 0x11A8 && r <= 0x11C2) return jong.codeUnitAt(r - 0x11A8);
  return r;
}

/// 앞뒤 공백을 없애고 연속 공백을 한 칸으로.
///
/// ⚠️**띄어쓰기를 없애지는 않는다** — 받아쓰기에서 띄어쓰기는 채점 대상이다.
/// 정리하는 것은 "실수로 두 번 눌린 것"뿐이다.
String collapseSpaces(String s) =>
    s.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
