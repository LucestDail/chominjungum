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
class DictationAttempt {
  const DictationAttempt({
    required this.id,
    required this.itemId,
    required this.deviceBindingId,
    required this.rawAnswer,
    required this.inputKind,
    required this.createdAtMs,
    this.score,
  });

  final String id;
  final String itemId;
  final String deviceBindingId;
  final String rawAnswer;
  final AttemptInputKind inputKind;
  final int createdAtMs;
  final DictationScoreResult? score;

  Map<String, Object?> toJson() => {
        'id': id,
        'itemId': itemId,
        'deviceBindingId': deviceBindingId,
        'rawAnswer': rawAnswer,
        'inputKind': inputKind.name,
        'createdAtMs': createdAtMs,
        if (score != null) 'scoreRatio': score!.ratio,
      };
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
