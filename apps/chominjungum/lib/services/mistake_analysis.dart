import 'dart:convert';

import 'package:hangul_core/hangul_core.dart';

import '../domain/dictation_models.dart';

/// 한 자모가 얼마나 자주 틀렸는지.
class JamoWeakness {
  const JamoWeakness({
    required this.code,
    required this.letter,
    required this.kind,
    required this.wrong,
    required this.total,
  });

  /// 자모 유니코드(초성 4352~ · 중성 4449~ · 종성 4520~).
  final int code;

  /// 화면에 보일 글자(호환 자모 `ㄱ`·`ㅏ`). 결합 자모를 그대로 쓰면 깨져 보인다.
  final String letter;
  final JamoKind kind;

  /// 이 자모가 든 글자를 틀린 횟수 / 나온 횟수.
  final int wrong;
  final int total;

  double get errorRate => total == 0 ? 0 : wrong / total;

  @override
  String toString() => '$letter $wrong/$total';
}

/// 한 음절(글자)을 얼마나 자주 틀렸는지.
class SyllableWeakness {
  const SyllableWeakness({
    required this.syllable,
    required this.wrong,
    required this.total,
    required this.wroteInstead,
  });

  final String syllable;
  final int wrong;
  final int total;

  /// 대신 쓴 글자들 — 많이 나온 순. `갓→갔` 처럼 보여 주면 교정이 빠르다.
  final List<String> wroteInstead;

  double get errorRate => total == 0 ? 0 : wrong / total;
}

/// 오답 노트 — **이미 쌓여 있는 답안 이력에서** 취약한 자모·음절을 뽑는다.
///
/// ## 왜 계산으로 뽑나
///
/// 채점은 이미 글자 단위로 정오를 남긴다(`matchesJson` = `[{i, ok, why}]`).
/// 여기에 정답 글자의 자모 분해를 겹치면 **"이 학생은 겹받침에서 자주 틀린다"**
/// 같은 것이 추가 입력 없이 나온다. 서버도, AI 도 필요 없다.
///
/// ## 정확히 무엇을 세는가 — 자모 단위 채점이 아니다
///
/// ⚠️앱의 채점은 **음절 단위**다("갔" 이 틀렸다는 것만 안다). 그래서
/// "종성 ㅆ 를 틀렸다"고 단정할 수 없고, **틀린 글자에 들어 있던 자모에
/// 책임을 나눠 싣는** 근사다. 그 대신 표본이 쌓이면 실제로 약한 자모가
/// 올라온다 — 정확한 인과가 아니라 **어디를 더 연습할지**를 고르는 도구다.
/// 화면에서도 그렇게 설명해야 한다.
class MistakeAnalysis {
  const MistakeAnalysis({
    required this.jamo,
    required this.syllables,
    required this.gradedAttempts,
    required this.gradedSyllables,
  });

  /// 오답률 높은 순. 표본이 너무 적은 것은 빠진다([minSamples]).
  final List<JamoWeakness> jamo;
  final List<SyllableWeakness> syllables;

  /// 분석에 실제로 쓰인 답안 수 / 글자 수. 화면에 표본 크기를 밝히기 위해서다.
  final int gradedAttempts;
  final int gradedSyllables;

  bool get isEmpty => gradedAttempts == 0;

  /// 이만큼은 나와야 통계로 보여준다. 한두 번 틀린 것을 "약점"이라 하면 안 된다.
  static const minSamples = 3;

  /// 화면에 보여줄 상위 개수.
  static const topN = 8;

  static const _choCompat = 'ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ';
  static const _jungCompat = 'ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ';
  static const _jongCompat = 'ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ';

  static String letterOf(int code) {
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

  /// [attempts] 중 **채점된 것**만으로 분석한다.
  ///
  /// [items] 는 문항 조회용(`itemId` → 정답 글자). 문항을 못 찾은 답안은 건너뛴다
  /// — 정답을 모르면 무엇을 틀렸는지도 모른다.
  static MistakeAnalysis of({
    required List<DictationAttempt> attempts,
    required List<DictationItem> items,
  }) {
    final byId = {for (final i in items) i.id: i};

    final jamoWrong = <int, int>{};
    final jamoTotal = <int, int>{};
    final sylWrong = <String, int>{};
    final sylTotal = <String, int>{};
    final wroteInstead = <String, Map<String, int>>{};

    var gradedAttempts = 0;
    var gradedSyllables = 0;

    for (final a in attempts) {
      final matches = _decodeMatches(a.matchesJson);
      final item = byId[a.itemId];
      if (matches == null || item == null) continue;

      final expected = HangulUtil.hangulSplit(item.expectedText);
      final answer = a.rawAnswer.runes.map(String.fromCharCode).toList();
      gradedAttempts++;

      for (final m in matches) {
        final i = m.index;
        if (i < 0 || i >= expected.length) continue;
        final glyph = expected[i];
        // 공백·특수문자는 학습 대상이 아니다.
        if (glyph.specialFlag || glyph.errorFlag) continue;

        final syllable = glyph.word ?? '';
        if (syllable.isEmpty) continue;
        gradedSyllables++;

        sylTotal[syllable] = (sylTotal[syllable] ?? 0) + 1;
        for (final code in _codesOf(glyph)) {
          jamoTotal[code] = (jamoTotal[code] ?? 0) + 1;
        }

        if (m.ok) continue;

        sylWrong[syllable] = (sylWrong[syllable] ?? 0) + 1;
        for (final code in _codesOf(glyph)) {
          jamoWrong[code] = (jamoWrong[code] ?? 0) + 1;
        }
        // 대신 쓴 글자 — 같은 자리의 답안 글자. 길이가 안 맞으면 없을 수 있다.
        if (i < answer.length && answer[i].trim().isNotEmpty) {
          final bucket = wroteInstead.putIfAbsent(syllable, () => {});
          bucket[answer[i]] = (bucket[answer[i]] ?? 0) + 1;
        }
      }
    }

    final jamo = <JamoWeakness>[
      for (final e in jamoTotal.entries)
        if (e.value >= minSamples && (jamoWrong[e.key] ?? 0) > 0)
          JamoWeakness(
            code: e.key,
            letter: letterOf(e.key),
            kind: jamoKindOf(e.key) ?? JamoKind.cho,
            wrong: jamoWrong[e.key] ?? 0,
            total: e.value,
          ),
    ]..sort((a, b) {
        final r = b.errorRate.compareTo(a.errorRate);
        return r != 0 ? r : b.wrong.compareTo(a.wrong);
      });

    final syllables = <SyllableWeakness>[
      for (final e in sylTotal.entries)
        if ((sylWrong[e.key] ?? 0) > 0)
          SyllableWeakness(
            syllable: e.key,
            wrong: sylWrong[e.key] ?? 0,
            total: e.value,
            wroteInstead: _topKeys(wroteInstead[e.key]),
          ),
    ]..sort((a, b) {
        final r = b.wrong.compareTo(a.wrong);
        return r != 0 ? r : b.errorRate.compareTo(a.errorRate);
      });

    return MistakeAnalysis(
      jamo: jamo.take(topN).toList(),
      syllables: syllables.take(topN).toList(),
      gradedAttempts: gradedAttempts,
      gradedSyllables: gradedSyllables,
    );
  }

  /// 이 취약 자모들을 그대로 **가리기 규칙**으로 바꾼다.
  ///
  /// 오답 노트에서 "이 자모만 가린 학습지"로 바로 이어지는 것이 이 기능의 값이다
  /// (웹 교사 콘솔의 `handoff` 와 같은 발상).
  /// 모드는 가장 많이 걸린 종류로 고른다 — 섞이면 아무것도 안 가려진다.
  HideRule toHideRule() {
    if (jamo.isEmpty) return HideRule.empty;
    final counts = <JamoKind, int>{};
    for (final w in jamo) {
      counts[w.kind] = (counts[w.kind] ?? 0) + 1;
    }
    final kind =
        (counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
            .first
            .key;
    final mode = switch (kind) {
      JamoKind.cho => HideMode.cho,
      JamoKind.jung => HideMode.jung,
      JamoKind.jong => HideMode.jong,
    };
    return HideRule(
      mode: mode,
      codes: {for (final w in jamo) if (w.kind == kind) w.code},
    );
  }

  static List<int> _codesOf(HangulGlyph g) => [
        if (g.choCode != null) g.choCode!,
        if (g.jungCode != null) g.jungCode!,
        if (!g.emptyJongsung && g.jongCode != null) g.jongCode!,
      ];

  static List<String> _topKeys(Map<String, int>? m) {
    if (m == null || m.isEmpty) return const [];
    final e = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return [for (final x in e.take(3)) x.key];
  }

  static List<_Match>? _decodeMatches(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      final list = jsonDecode(json) as List;
      return [
        for (final e in list)
          if (e is Map)
            _Match(
              index: (e['i'] as num?)?.toInt() ?? -1,
              ok: e['ok'] == true,
            ),
      ];
    } catch (_) {
      // 손상된 이력 하나가 오답 노트 전체를 막으면 안 된다.
      return null;
    }
  }
}

class _Match {
  const _Match({required this.index, required this.ok});
  final int index;
  final bool ok;
}
