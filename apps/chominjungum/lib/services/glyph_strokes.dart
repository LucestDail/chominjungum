import 'package:flutter/services.dart';
import 'package:hangul_core/hangul_core.dart';
import 'package:xml/xml.dart';

/// 자모 자산에서 **획을 뽑아낸다** — 획순 안내용.
///
/// 자산 구조(jammin 원본):
///
/// ```xml
/// <g> …점선 안내 테두리… </g>
/// <g id="_x3131_…">              ← 글리프 그룹. id 가 호환 자모 코드포인트다
///   <line stroke-width="20" …/>  ← 선분
///   <line stroke-width="20" …/>
/// </g>
/// ```
///
/// ⚠️**선분 ≠ 획.** ㄱ 은 선분 2개지만 1획이다. 묶는 규칙은 `hangul_core` 의
/// [strokeGroups] 가 들고 있고, 여기서는 **선분을 순서대로 꺼내기만** 한다.
class GlyphStrokes {
  const GlyphStrokes({
    required this.letter,
    required this.segments,
    required this.strokes,
    required this.isKnownOrder,
  });

  /// 호환 자모(`ㄱ`). 자산 그룹 id 에서 읽는다.
  final String letter;

  /// 문서 순서대로의 선분(각 선분은 SVG 조각 문자열이 아니라 인덱스로만 쓴다).
  final int segments;

  /// 각 획이 어느 선분들로 이루어지는지.
  final List<List<int>> strokes;

  /// 획순 안내를 **믿을 수 있는가**. 거짓이면 화면이 "획순"이라 말하지 않는다.
  final bool isKnownOrder;

  int get strokeCountOf => strokes.length;
}

/// 자산을 읽어 획 정보를 만든다. 결과는 캐시한다(자산은 안 바뀐다).
class GlyphStrokeLoader {
  GlyphStrokeLoader({AssetBundle? bundle}) : _bundle = bundle;

  final AssetBundle? _bundle;
  final _cache = <int, GlyphStrokes?>{};

  static const _strokeWidthMark = 'stroke-width="20"';

  Future<GlyphStrokes?> load(int code) async {
    if (_cache.containsKey(code)) return _cache[code];
    try {
      final bundle = _bundle ?? rootBundle;
      final xml = await bundle.loadString('assets/hangul/$code.svg');
      final result = parse(xml, code: code);
      _cache[code] = result;
      return result;
    } catch (_) {
      // 자산을 못 읽으면 안내를 포기한다 — 수업이 멈추지는 않는다.
      _cache[code] = null;
      return null;
    }
  }

  /// SVG 문자열에서 획을 뽑는다. 테스트가 직접 부를 수 있게 분리해 둔다.
  ///
  /// ⚠️[code] 는 **파일명**(= jammin 규약의 자모 코드)이고, 이것이 정본이다.
  /// 자산 안의 그룹 `id` 는 믿으면 안 된다 — ㅟ(4465) 자산의 id 가 `_x3157_`(ㅗ)로
  /// 붙어 있는 것을 실측으로 확인했다. id 를 믿으면 **엉뚱한 자모의 획순 표**를
  /// 찾게 된다.
  static GlyphStrokes? parse(String xml, {required int code}) {
    final doc = XmlDocument.parse(xml);

    // 글리프 그룹은 **여러 개일 수 있다** — 복합 모음(ㅞ = ㅜ + ㅔ)이 그렇다.
    final groups = doc
        .findAllElements('g')
        .where((g) => _glyphIdRe.hasMatch(g.getAttribute('id') ?? ''))
        .toList();
    if (groups.isEmpty) return null;

    // 중첩된 안쪽 그룹은 빼고 바깥 것만 센다.
    final outer = <XmlElement>[];
    for (final g in groups) {
      if (!groups.any((o) => o != g && o.descendants.contains(g))) {
        outer.add(g);
      }
    }

    var segments = 0;
    for (final g in outer) {
      segments += g.descendants
          .whereType<XmlElement>()
          .where((e) => const {'line', 'path', 'polyline'}
              .contains(e.name.local))
          .length;
    }
    if (segments == 0) return null;

    final letter = compatLetterOf(code);
    if (letter == null) return null;

    return GlyphStrokes(
      letter: letter,
      segments: segments,
      strokes: groupSegments(letter, segments),
      isKnownOrder: isStrokeOrderKnown(letter, segments),
    );
  }

  /// 글리프 그룹 id — `_x3131_` 또는 `_x3131__0000…`(편집기가 붙인 접미).
  /// **그룹을 찾는 데만** 쓴다. 어떤 자모인지는 파일명으로 판단한다(위 주석).
  static final _glyphIdRe = RegExp(r'^_x([0-9A-Fa-f]{4})_');

  /// 자모 코드(파일명) → 호환 자모 글자. 획순 표의 키다.
  static const _cho = 'ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ';
  static const _jung = 'ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ';
  static const _jong = 'ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ';

  static String? compatLetterOf(int code) {
    if (code >= JamoRanges.choFirst && code <= JamoRanges.choLast) {
      return _cho[code - JamoRanges.choFirst];
    }
    if (code >= JamoRanges.jungFirst && code <= JamoRanges.jungLast) {
      return _jung[code - JamoRanges.jungFirst];
    }
    if (code >= JamoRanges.jongFirst && code <= JamoRanges.jongLast) {
      return _jong[code - JamoRanges.jongFirst];
    }
    return null;
  }

  /// 굵은 획인지 — 안내 테두리(가는 점선)와 구분한다. 진단용.
  static bool looksLikeStroke(String svgFragment) =>
      svgFragment.contains(_strokeWidthMark);
}
