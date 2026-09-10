import 'hangul_glyph.dart';

/// 자모 가리기(`hidebox`) — jammin 학습지의 핵심 출제 기능.
///
/// 학습지에서 특정 자모를 **빈칸으로 비워** 학생이 채우게 하는 출제다.
/// "이번 주는 받침만 가려서 내자" 같은 수업이 이걸로 만들어진다.
///
/// jammin 원본은 이 상태를 **DOM 클래스로만** 들고 있어(`worksheet-app.js` 의
/// 체크박스 핸들러 + `.hidebox`) 저장·재사용이 불가능했다. 여기서는 **데이터로
/// 모델링**해 출제 패키지에 실어 학생 기기까지 보낸다.
///
/// ## 세 이식본이 같아야 한다
///
/// 웹 TS 구현(`chominjungum-web/packages/hangul-core-ts/src/hide-rules.ts`)과
/// **동작이 같아야 한다** — 같은 문항을 앱과 웹에서 내면 같은 칸이 비어야 한다.
/// `test/hide_rules_test.dart` 가 TS 테스트와 같은 사례를 검사한다.
///
/// 원본 규칙:
///  - 모드 4종(`#removeCombo`): jaremove(초성+종성=자음) / choremove / jungremove / jongremove
///  - 체크박스 value: `"4352"` 단일 코드, `"4352_4520"` 초성·종성 쌍
enum HideMode {
  /// 자음 — 초성과 종성을 함께 가린다(원본 `jaremove`).
  ja('ja', '초성 + 종성'),
  cho('cho', '초성'),
  jung('jung', '중성'),
  jong('jong', '종성');

  const HideMode(this.wire, this.label);

  /// 직렬화 값. 웹·서버와 이 문자열로 주고받으므로 바꾸면 호환이 깨진다.
  final String wire;
  final String label;

  static HideMode fromWire(String? v) =>
      HideMode.values.firstWhere((m) => m.wire == v, orElse: () => HideMode.ja);
}

/// 자모 코드가 초성/중성/종성 중 어디에 속하는지.
enum JamoKind { cho, jung, jong }

/// 자모 유니코드 구간 — jammin 파일명 규약과 같다.
class JamoRanges {
  const JamoRanges._();

  static const choFirst = 0x1100; // ㄱ
  static const choLast = 0x1112; // ㅎ
  static const jungFirst = 0x1161; // ㅏ
  static const jungLast = 0x1175; // ㅣ

  /// ⚠️`0x11A7`(4519)은 **"종성 없음" 표식**이라 글리프가 아니다. 종성은 그 다음부터다.
  static const jongFirst = 0x11a8; // ㄱ
  static const jongLast = 0x11c2; // ㅎ
}

JamoKind? jamoKindOf(int code) {
  if (code >= JamoRanges.choFirst && code <= JamoRanges.choLast) {
    return JamoKind.cho;
  }
  if (code >= JamoRanges.jungFirst && code <= JamoRanges.jungLast) {
    return JamoKind.jung;
  }
  if (code >= JamoRanges.jongFirst && code <= JamoRanges.jongLast) {
    return JamoKind.jong;
  }
  return null;
}

/// 현재 모드에서 이 코드를 가릴 수 있는가(모드와 자모 종류가 맞는지).
bool isHidableInMode(int code, HideMode mode) {
  final kind = jamoKindOf(code);
  if (kind == null) return false;
  switch (mode) {
    case HideMode.ja:
      return kind == JamoKind.cho || kind == JamoKind.jong;
    case HideMode.cho:
      return kind == JamoKind.cho;
    case HideMode.jung:
      return kind == JamoKind.jung;
    case HideMode.jong:
      return kind == JamoKind.jong;
  }
}

/// 한 글자에서 실제로 가려지는 부위. 렌더러가 이걸 보고 글리프를 숨긴다.
class HiddenParts {
  const HiddenParts({
    required this.cho,
    required this.jung,
    required this.jong,
  });

  static const none = HiddenParts(cho: false, jung: false, jong: false);

  final bool cho;
  final bool jung;
  final bool jong;

  bool get any => cho || jung || jong;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HiddenParts &&
          cho == other.cho &&
          jung == other.jung &&
          jong == other.jong;

  @override
  int get hashCode => Object.hash(cho, jung, jong);

  @override
  String toString() => 'HiddenParts(cho: $cho, jung: $jung, jong: $jong)';
}

/// 어떤 자모를 가릴지에 대한 완전한 상태. 출제 패키지에 그대로 실린다.
class HideRule {
  const HideRule({this.mode = HideMode.ja, this.codes = const <int>{}});

  static const empty = HideRule();

  final HideMode mode;

  /// 가릴 자모 코드. 쌍(`4352_4520`)은 **펼쳐서** 담는다.
  final Set<int> codes;

  bool get isEmpty => codes.isEmpty;

  /// 이 규칙이 실제로 무언가를 가리는가.
  /// 모드와 맞지 않는 코드만 담겨 있으면 아무것도 안 가려진다.
  bool get hasEffect => codes.any((c) => isHidableInMode(c, mode));

  /// 한 글자에서 가려질 부위를 계산한다.
  ///
  /// 특수문자·숫자는 가리지 않는다 — 자모가 아니라 통짜 글리프라 부위가 없다.
  HiddenParts partsOf(HangulGlyph glyph) {
    if (glyph.specialFlag || glyph.errorFlag) return HiddenParts.none;
    bool hit(int? code) =>
        code != null && codes.contains(code) && isHidableInMode(code, mode);
    return HiddenParts(
      cho: hit(glyph.choCode),
      jung: hit(glyph.jungCode),
      // 받침이 없으면 가릴 것도 없다.
      jong: !glyph.emptyJongsung && hit(glyph.jongCode),
    );
  }

  /// 코드 토글(체크박스 on/off). 쌍 value 문자열도 그대로 받는다.
  HideRule toggle(Object value, bool on) {
    final targets = value is String
        ? parseCheckboxValue(value)
        : (value as Iterable<int>).toList();
    final next = Set<int>.of(codes);
    for (final code in targets) {
      if (on) {
        next.add(code);
      } else {
        next.remove(code);
      }
    }
    return HideRule(mode: mode, codes: next);
  }

  /// 모드에 해당하는 모든 자모를 가린다(원본의 `all-*` 전체 토글).
  HideRule selectAll() => HideRule(mode: mode, codes: allCodesForMode(mode));

  HideRule clearCodes() => HideRule(mode: mode);

  /// 모드를 바꾸면 원본은 **체크를 모두 푼다**(`worksheet-app.js` radio change).
  /// 모드가 그대로면 선택을 유지한다.
  HideRule withMode(HideMode next) =>
      next == mode ? this : HideRule(mode: next);

  Map<String, Object?> toJson() => {
        'mode': mode.wire,
        // 정렬해서 담는다 — 같은 규칙이면 항상 같은 JSON 이어야
        // `contentHash` 로 문항을 재사용하는 서버 쪽이 흔들리지 않는다.
        'codes': (codes.toList()..sort()),
      };

  factory HideRule.fromJson(Map<String, Object?> json) => HideRule(
        mode: HideMode.fromWire(json['mode'] as String?),
        codes: {
          for (final v in (json['codes'] as List? ?? const []))
            if (v is int) v else if (v is num) v.toInt(),
        },
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HideRule &&
          mode == other.mode &&
          codes.length == other.codes.length &&
          codes.containsAll(other.codes);

  @override
  int get hashCode => Object.hash(mode, Object.hashAllUnordered(codes));

  @override
  String toString() =>
      'HideRule(${mode.wire}, ${(codes.toList()..sort()).join(",")})';
}

/// jammin 체크박스 value 를 코드 목록으로 편다.
///  - `"4352"`      → [4352]
///  - `"4352_4520"` → [4352, 4520]
List<int> parseCheckboxValue(String value) => value
    .split('_')
    .map((p) => int.tryParse(p.trim()))
    .whereType<int>()
    .toList();

/// 모드에 해당하는 자모 코드 전체.
Set<int> allCodesForMode(HideMode mode) {
  final codes = <int>{};
  void addRange(int from, int to) {
    for (var c = from; c <= to; c++) {
      codes.add(c);
    }
  }

  if (mode == HideMode.cho || mode == HideMode.ja) {
    addRange(JamoRanges.choFirst, JamoRanges.choLast);
  }
  if (mode == HideMode.jung) {
    addRange(JamoRanges.jungFirst, JamoRanges.jungLast);
  }
  if (mode == HideMode.jong || mode == HideMode.ja) {
    addRange(JamoRanges.jongFirst, JamoRanges.jongLast);
  }
  return codes;
}
