import 'package:flutter/material.dart';
import 'package:hangul_core/hangul_core.dart';

import '../../theme/jammin_tokens.dart';

/// 통합·위젯 테스트가 가리기 UI 를 찾는 손잡이.
class HideRulePickerKeys {
  const HideRulePickerKeys._();

  static const expand = Key('hideRule.expand');
  static const mode = Key('hideRule.mode');
  static const selectAll = Key('hideRule.selectAll');
  static const clear = Key('hideRule.clear');
  static Key jamo(int code) => Key('hideRule.jamo.$code');
}

/// 자모 가리기 출제 UI — jammin `hidebox` 를 모바일로 옮긴 것.
///
/// ## 무엇을 하는 화면인가
///
/// 받아쓰기를 "빈칸 채우기"로 낼 수 있게 한다. 예를 들어 **받침만 가리면**
/// 학생은 초성·중성이 그려진 칸에 받침만 써 넣는다. 받아쓰기 수업에서
/// 가장 많이 쓰는 변형이고, jammin 웹 학습지의 핵심 기능이다.
///
/// ## 원본 동작을 그대로 따른다
///
/// - 모드 4종(자음=초성+종성 / 초성 / 중성 / 종성)
/// - **모드를 바꾸면 선택이 초기화된다**(원본 radio change 핸들러)
/// - 자음 모드에서는 초성·종성을 **쌍으로** 토글한다(`"4352_4520"`)
///
/// 규칙 자체는 `hangul_core` 의 [HideRule] 이 들고 있고, 웹 TS 구현과 동치임이
/// `hide_rules_test.dart` 로 강제된다 — 같은 문항이면 앱과 웹이 같은 칸을 비운다.
class HideRulePicker extends StatefulWidget {
  const HideRulePicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final HideRule value;
  final ValueChanged<HideRule> onChanged;

  @override
  State<HideRulePicker> createState() => _HideRulePickerState();
}

class _HideRulePickerState extends State<HideRulePicker> {
  bool _expanded = false;

  /// 화면에 늘어놓을 자모 — 모드에 해당하는 것만 보여준다.
  /// 자음 모드는 초성 기준으로 놓되 토글은 종성까지 함께 건다.
  List<int> get _codes {
    switch (widget.value.mode) {
      case HideMode.ja:
      case HideMode.cho:
        return [
          for (var c = JamoRanges.choFirst; c <= JamoRanges.choLast; c++) c,
        ];
      case HideMode.jung:
        return [
          for (var c = JamoRanges.jungFirst; c <= JamoRanges.jungLast; c++) c,
        ];
      case HideMode.jong:
        return [
          for (var c = JamoRanges.jongFirst; c <= JamoRanges.jongLast; c++) c,
        ];
    }
  }

  /// 자음 모드에서 초성 ㄱ 을 누르면 **종성 ㄱ 도 함께** 걸린다
  /// (원본 체크박스 value `"4352_4520"`).
  ///
  /// ⚠️초성 19자와 종성 27자는 **개수도 순서도 다르다** — 종성에는 겹받침(ㄳ·ㄵ…)이
  /// 있고 초성 ㄸ·ㅃ·ㅉ 은 종성에 없다. 인덱스로 짝지으면 엉뚱한 자모가 걸리므로
  /// **호환 자모 글자로** 짝을 찾는다.
  List<int> _targetsFor(int code) {
    if (widget.value.mode != HideMode.ja) return [code];
    final jong = _choToJong[code];
    return jong == null ? [code] : [code, jong];
  }

  /// 초성 코드 → 같은 글자의 종성 코드. 없으면(ㄸ·ㅃ·ㅉ) 빠진다.
  static final Map<int, int> _choToJong = () {
    final byLetter = <String, int>{
      for (var c = JamoRanges.jongFirst; c <= JamoRanges.jongLast; c++)
        _jongCompat[c - JamoRanges.jongFirst]: c,
    };
    return <int, int>{
      for (var c = JamoRanges.choFirst; c <= JamoRanges.choLast; c++)
        if (byLetter[_choCompat[c - JamoRanges.choFirst]] != null)
          c: byLetter[_choCompat[c - JamoRanges.choFirst]]!,
    };
  }();

  // 유니코드 자모 순서와 1:1 로 대응하는 호환 자모(화면 표시용이자 짝 찾기 기준).
  static const _choCompat = 'ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ';
  static const _jongCompat = 'ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ';
  static const _jungCompat = 'ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ';

  /// 화면에 보일 글자. 결합 자모(`ᄀ`)를 그대로 쓰면 폰트에 따라 깨져 보인다.
  static String _label(int code) {
    if (code >= JamoRanges.choFirst && code <= JamoRanges.choLast) {
      return _choCompat[code - JamoRanges.choFirst];
    }
    if (code >= JamoRanges.jungFirst && code <= JamoRanges.jungLast) {
      return _jungCompat[code - JamoRanges.jungFirst];
    }
    if (code >= JamoRanges.jongFirst && code <= JamoRanges.jongLast) {
      return _jongCompat[code - JamoRanges.jongFirst];
    }
    return String.fromCharCode(code);
  }

  bool _isOn(int code) => widget.value.codes.contains(code);

  @override
  Widget build(BuildContext context) {
    final rule = widget.value;
    final onCount = rule.codes.where((c) => isHidableInMode(c, rule.mode)).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                onCount == 0
                    ? '자모 가리기 — 끔'
                    : '자모 가리기 — ${rule.mode.label} $onCount자',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            TextButton.icon(
              key: HideRulePickerKeys.expand,
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
              label: Text(_expanded ? '접기' : '고르기'),
            ),
          ],
        ),
        if (onCount > 0 && !_expanded)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '가린 자모는 학생 학습지에서 빈칸으로 나옵니다.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: JamminTokens.textMuted,
                  ),
            ),
          ),
        if (_expanded) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<HideMode>(
            key: HideRulePickerKeys.mode,
            initialValue: rule.mode,
            decoration: const InputDecoration(labelText: '가릴 부위'),
            items: [
              for (final m in HideMode.values)
                DropdownMenuItem(value: m, child: Text(m.label)),
            ],
            onChanged: (m) {
              if (m == null) return;
              // 모드를 바꾸면 선택이 풀린다 — 원본과 같은 동작이다.
              widget.onChanged(rule.withMode(m));
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final code in _codes)
                FilterChip(
                  key: HideRulePickerKeys.jamo(code),
                  label: Text(_label(code)),
                  selected: _isOn(code),
                  onSelected: (on) =>
                      widget.onChanged(rule.toggle(_targetsFor(code), on)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(
                key: HideRulePickerKeys.selectAll,
                onPressed: () => widget.onChanged(rule.selectAll()),
                child: const Text('전체 선택'),
              ),
              TextButton(
                key: HideRulePickerKeys.clear,
                onPressed: () => widget.onChanged(rule.clearCodes()),
                child: const Text('전체 해제'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
