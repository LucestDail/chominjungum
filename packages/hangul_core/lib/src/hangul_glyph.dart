import 'dart:convert';

/// jammin `com.jammin.util.Hangul#toJSON` 필드와 동일한 의미.
class HangulGlyph {
  const HangulGlyph({
    this.word,
    this.chosung,
    this.choCode,
    this.jungsung,
    this.jungCode,
    this.jongsung,
    this.jongCode,
    this.specialType,
    this.specialTypeCode,
    required this.specialFlag,
    required this.emptyJongsung,
    required this.errorFlag,
  });

  final String? word;
  final String? chosung;
  final int? choCode;
  final String? jungsung;
  final int? jungCode;
  final String? jongsung;
  final int? jongCode;
  final String? specialType;
  final int? specialTypeCode;
  final bool specialFlag;
  final bool emptyJongsung;
  final bool errorFlag;

  /// jammin `JSONObject` 직렬화와 동일한 키 구성.
  Map<String, Object?> toJson() {
    final map = <String, Object?>{
      'specialFlag': specialFlag,
      'emptyJongsung': emptyJongsung,
      'errorFlag': errorFlag,
    };
    if (specialFlag) {
      map['specialType'] = specialType;
      if (specialTypeCode != null) {
        map['specialTypeCode'] = specialTypeCode!;
      }
    } else {
      if (word != null) map['word'] = word;
      if (chosung != null) map['chosung'] = chosung;
      if (choCode != null) map['choCode'] = choCode;
      if (jungsung != null) map['jungsung'] = jungsung;
      if (jungCode != null) map['jungCode'] = jungCode;
      if (!emptyJongsung) {
        if (jongsung != null) map['jongsung'] = jongsung;
        if (jongCode != null) map['jongCode'] = jongCode;
      }
    }
    return map;
  }

  String toJsonString() => jsonEncode(toJson());

  factory HangulGlyph.fromJson(Map<String, Object?> json) {
    final specialFlag = json['specialFlag'] == true;
    return HangulGlyph(
      word: json['word'] as String?,
      chosung: json['chosung'] as String?,
      choCode: _asInt(json['choCode']),
      jungsung: json['jungsung'] as String?,
      jungCode: _asInt(json['jungCode']),
      jongsung: json['jongsung'] as String?,
      jongCode: _asInt(json['jongCode']),
      specialType: json['specialType'] as String?,
      specialTypeCode: _asInt(json['specialTypeCode']),
      specialFlag: specialFlag,
      emptyJongsung: json['emptyJongsung'] != false,
      errorFlag: json['errorFlag'] == true,
    );
  }

  static int? _asInt(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HangulGlyph &&
          runtimeType == other.runtimeType &&
          word == other.word &&
          chosung == other.chosung &&
          choCode == other.choCode &&
          jungsung == other.jungsung &&
          jungCode == other.jungCode &&
          jongsung == other.jongsung &&
          jongCode == other.jongCode &&
          specialType == other.specialType &&
          specialTypeCode == other.specialTypeCode &&
          specialFlag == other.specialFlag &&
          emptyJongsung == other.emptyJongsung &&
          errorFlag == other.errorFlag;

  @override
  int get hashCode => Object.hash(
        word,
        chosung,
        choCode,
        jungsung,
        jungCode,
        jongsung,
        jongCode,
        specialType,
        specialTypeCode,
        specialFlag,
        emptyJongsung,
        errorFlag,
      );
}
