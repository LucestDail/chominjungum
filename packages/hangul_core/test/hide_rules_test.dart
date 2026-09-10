import 'package:hangul_core/hangul_core.dart';
import 'package:test/test.dart';

/// 자모 가리기 — **웹 TS 구현과 동치임을 강제**한다.
///
/// 사례는 `chominjungum-web/packages/hangul-core-ts/test/hide-rules.test.ts` 와
/// 같은 것을 쓴다. 같은 문항을 앱과 웹에서 내면 **같은 칸이 비어야** 하는데,
/// 자모 분해에는 골든 벡터가 있지만 가리기 규칙에는 없었다.
/// (09-09 에 자산이 조용히 갈라져 있던 것과 같은 종류의 위험이다.)
void main() {
  group('jammin 체크박스 value 해석', () {
    test('단일 코드', () {
      expect(parseCheckboxValue('4352'), [4352]);
    });

    test('초성·종성 쌍은 펼친다', () {
      expect(parseCheckboxValue('4352_4520'), [4352, 4520]);
    });

    test('쓰레기 값은 버린다', () {
      expect(parseCheckboxValue('4352_abc'), [4352]);
    });
  });

  group('자모 종류 판정', () {
    test('초성 ᄀ(4352) / 중성 ᅡ(4449) / 종성 ᆨ(4520)', () {
      expect(jamoKindOf(4352), JamoKind.cho);
      expect(jamoKindOf(4449), JamoKind.jung);
      expect(jamoKindOf(4520), JamoKind.jong);
    });

    test('종성 없음 표식(4519)은 글리프가 아니다', () {
      expect(jamoKindOf(4519), isNull);
    });
  });

  group('모드별 가리기 가능 여부', () {
    test('자음 모드는 초성·종성 모두', () {
      expect(isHidableInMode(4352, HideMode.ja), isTrue);
      expect(isHidableInMode(4520, HideMode.ja), isTrue);
      expect(isHidableInMode(4449, HideMode.ja), isFalse);
    });

    test('초성 모드는 초성만', () {
      expect(isHidableInMode(4352, HideMode.cho), isTrue);
      expect(isHidableInMode(4520, HideMode.cho), isFalse);
    });
  });

  group('실제 글자에 적용', () {
    // 값 = 초성 ᄀ4352 · 중성 ᅡ4449 · 종성 ᆹ4537
    final gap = HangulUtil.hangulSplit('값').first;

    test('선택한 초성만 가려진다', () {
      const rule = HideRule(mode: HideMode.cho, codes: {4352});
      expect(rule.partsOf(gap),
          const HiddenParts(cho: true, jung: false, jong: false));
    });

    test('자음 모드에서 초성·종성 쌍이 함께 가려진다', () {
      final rule = const HideRule(mode: HideMode.ja).toggle('4352_4537', true);
      expect(rule.partsOf(gap),
          const HiddenParts(cho: true, jung: false, jong: true));
    });

    test('모드와 맞지 않는 코드는 무시된다', () {
      const rule = HideRule(mode: HideMode.jung, codes: {4352});
      expect(rule.partsOf(gap), HiddenParts.none);
      expect(rule.hasEffect, isFalse);
    });

    test('특수문자는 가려지지 않는다', () {
      final space = HangulUtil.hangulSplit(' ').first;
      final rule = const HideRule(mode: HideMode.ja).selectAll();
      expect(rule.partsOf(space), HiddenParts.none);
    });

    test('전체 토글은 해당 모드의 자모를 모두 덮는다', () {
      final rule = const HideRule(mode: HideMode.ja).selectAll();
      expect(rule.partsOf(gap),
          const HiddenParts(cho: true, jung: false, jong: true));
    });

    test('받침 없는 글자는 종성이 가려지지 않는다', () {
      final na = HangulUtil.hangulSplit('나').first;
      final rule = const HideRule(mode: HideMode.ja).selectAll();
      expect(rule.partsOf(na).jong, isFalse,
          reason: '받침이 없는데 가릴 것이 있다고 하면 빈 칸이 생긴다');
      expect(rule.partsOf(na).cho, isTrue);
    });
  });

  group('모드 변경', () {
    test('다른 모드로 바꾸면 선택이 초기화된다 (원본 radio 동작)', () {
      const rule = HideRule(mode: HideMode.cho, codes: {4352});
      final next = rule.withMode(HideMode.jung);
      expect(next.mode, HideMode.jung);
      expect(next.codes, isEmpty);
    });

    test('같은 모드면 유지', () {
      const rule = HideRule(mode: HideMode.cho, codes: {4352});
      expect(rule.withMode(HideMode.cho), rule);
    });
  });

  group('직렬화 — 출제 패키지에 실려 학생 기기까지 간다', () {
    test('왕복', () {
      final rule = const HideRule(mode: HideMode.jong).toggle('4520_4537', true);
      final back = HideRule.fromJson(rule.toJson());
      expect(back, rule);
      expect(back.mode, HideMode.jong);
    });

    test('코드는 정렬해 담는다 — 같은 규칙이면 같은 JSON', () {
      const a = HideRule(mode: HideMode.ja, codes: {4537, 4352});
      const b = HideRule(mode: HideMode.ja, codes: {4352, 4537});
      expect(a.toJson().toString(), b.toJson().toString());
      expect(a.toJson()['codes'], [4352, 4537]);
    });

    test('알 수 없는 모드는 기본값으로 떨어진다', () {
      expect(HideRule.fromJson({'mode': 'nope', 'codes': []}).mode, HideMode.ja);
    });
  });
}
