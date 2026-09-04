import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:hangul_core/hangul_core.dart';

/// 출제 단위 (jammin `addWord` 분해 결과를 함께 저장).
class DictationItem {
  const DictationItem({
    required this.id,
    required this.expectedText,
    required this.expectedGlyphsJson,
    required this.contentHash,
    this.promptAudioUrl,
  });

  final String id;
  final String expectedText;
  final String expectedGlyphsJson;
  final String contentHash;
  final String? promptAudioUrl;

  factory DictationItem.fromExpectedText(String expectedText, {String? id}) {
    return DictationItem.fromGlyphs(
      expectedText,
      HangulUtil.hangulSplit(expectedText),
      id: id,
    );
  }

  /// jammin `POST /addWord` 응답 glyphs 저장.
  factory DictationItem.fromGlyphs(
    String expectedText,
    List<HangulGlyph> glyphs, {
    String? id,
  }) {
    final jsonList = glyphs.map((g) => g.toJson()).toList();
    final glyphsJson = jsonEncode(jsonList);
    final hash = sha256.convert(utf8.encode(expectedText)).toString();
    return DictationItem(
      id: id ?? hash.substring(0, 12),
      expectedText: expectedText,
      expectedGlyphsJson: glyphsJson,
      contentHash: hash,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'expectedText': expectedText,
        'expectedGlyphsJson': expectedGlyphsJson,
        'contentHash': contentHash,
        if (promptAudioUrl != null) 'promptAudioUrl': promptAudioUrl!,
      };

  factory DictationItem.fromJson(Map<String, Object?> json) {
    return DictationItem(
      id: json['id']! as String,
      expectedText: json['expectedText']! as String,
      expectedGlyphsJson: json['expectedGlyphsJson']! as String,
      contentHash: json['contentHash']! as String,
      promptAudioUrl: json['promptAudioUrl'] as String?,
    );
  }
}

/// 입력 경로 구분.
enum AttemptInputKind { keyboard, ocrCanvas, ocrImage }

/// 학생 한 번의 답안.
///
/// 채점 결과를 [DictationScoreResult] 로 들고 있으면 저장할 수 없다 — 그 안의
/// [HangulGlyph] 는 직렬화 대상이 아니다. 그래서 **저장 가능한 요약**으로 담는다:
/// 맞은 개수·전체 개수와, 글자별 정오를 [matchesJson] (`[{i, ok, why}]`) 으로.
/// `expectedGlyphsJson` 이 이미 같은 방식이라 표현이 일관된다.
class DictationAttempt {
  const DictationAttempt({
    required this.id,
    required this.itemId,
    required this.deviceBindingId,
    required this.rawAnswer,
    required this.inputKind,
    required this.createdAtMs,
    this.correctCount,
    this.totalCount,
    this.matchesJson,
    this.submittedAtMs,
  });

  final String id;
  final String itemId;
  final String deviceBindingId;
  final String rawAnswer;
  final AttemptInputKind inputKind;
  final int createdAtMs;

  final int? correctCount;
  final int? totalCount;

  /// 글자별 정오 `[{"i":0,"ok":true,"why":null}, …]` — 결과 화면의 오답 표시 원천.
  final String? matchesJson;

  /// 교사 허브에 **제출이 성공한** 시각. 아직 못 보냈으면 null
  /// (허브에 연결되지 않아도 채점 이력은 로컬에 남는다).
  final int? submittedAtMs;

  bool get isSubmitted => submittedAtMs != null;

  double get ratio {
    final total = totalCount ?? 0;
    if (total == 0) return 0;
    return (correctCount ?? 0) / total;
  }

  int get scorePercent => (ratio * 100).round();

  /// 채점 직후 만든다.
  factory DictationAttempt.fromScore({
    required String id,
    required String itemId,
    required String deviceBindingId,
    required String rawAnswer,
    required AttemptInputKind inputKind,
    required int createdAtMs,
    required DictationScoreResult score,
  }) {
    return DictationAttempt(
      id: id,
      itemId: itemId,
      deviceBindingId: deviceBindingId,
      rawAnswer: rawAnswer,
      inputKind: inputKind,
      createdAtMs: createdAtMs,
      correctCount: score.correctCount,
      totalCount: score.totalCount,
      matchesJson: jsonEncode([
        for (final m in score.matches)
          {
            'i': m.index,
            'ok': m.isCorrect,
            if (m.mismatchReason != null) 'why': m.mismatchReason,
          },
      ]),
    );
  }

  DictationAttempt copyWith({int? submittedAtMs}) {
    return DictationAttempt(
      id: id,
      itemId: itemId,
      deviceBindingId: deviceBindingId,
      rawAnswer: rawAnswer,
      inputKind: inputKind,
      createdAtMs: createdAtMs,
      correctCount: correctCount,
      totalCount: totalCount,
      matchesJson: matchesJson,
      submittedAtMs: submittedAtMs ?? this.submittedAtMs,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'itemId': itemId,
        'deviceBindingId': deviceBindingId,
        'rawAnswer': rawAnswer,
        'inputKind': inputKind.name,
        'createdAtMs': createdAtMs,
        if (correctCount != null) 'correctCount': correctCount,
        if (totalCount != null) 'totalCount': totalCount,
        if (matchesJson != null) 'matchesJson': matchesJson,
        if (submittedAtMs != null) 'submittedAtMs': submittedAtMs,
      };

  factory DictationAttempt.fromJson(Map<String, Object?> json) {
    return DictationAttempt(
      id: json['id']! as String,
      itemId: json['itemId']! as String,
      deviceBindingId: json['deviceBindingId']! as String,
      rawAnswer: json['rawAnswer']! as String,
      inputKind: AttemptInputKind.values.firstWhere(
        (e) => e.name == json['inputKind'],
        // 옛 기록이나 알 수 없는 값은 기본 입력으로 본다 (읽기가 실패하면 안 된다)
        orElse: () => AttemptInputKind.keyboard,
      ),
      createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
      correctCount: (json['correctCount'] as num?)?.toInt(),
      totalCount: (json['totalCount'] as num?)?.toInt(),
      matchesJson: json['matchesJson'] as String?,
      submittedAtMs: (json['submittedAtMs'] as num?)?.toInt(),
    );
  }
}

/// 동기화용 문제 묶음.
class DictationPackage {
  const DictationPackage({
    required this.version,
    required this.items,
  });

  static const currentVersion = '1';

  final String version;
  final List<DictationItem> items;

  Map<String, Object?> toJson() => {
        'version': version,
        'items': items.map((e) => e.toJson()).toList(),
      };

  factory DictationPackage.fromJson(Map<String, Object?> json) {
    final raw = json['items'] as List<dynamic>? ?? [];
    return DictationPackage(
      version: json['version'] as String? ?? currentVersion,
      items: raw
          .map((e) => DictationItem.fromJson(Map<String, Object?>.from(e as Map)))
          .toList(),
    );
  }

  Uint8List toUtf8Bytes() => Uint8List.fromList(utf8.encode(jsonEncode(toJson())));
}
