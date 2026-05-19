import 'dart:convert';

import 'package:hangul_core/hangul_core.dart';
import 'package:http/http.dart' as http;

/// jammin 서버 `POST /addWord` — 한글 자모 분해 JSON.
class JamminAddWordService {
  JamminAddWordService({http.Client? client, this.baseUrl = defaultBaseUrl})
      : _client = client ?? http.Client();

  static const defaultBaseUrl = 'https://xn--lg3by0shrak2n.com';

  final String baseUrl;
  final http.Client _client;

  /// jammin과 동일: `{"requestWord":"안녕하세요"}` → Hangul JSON 배열.
  Future<List<HangulGlyph>> addWord(String requestWord) async {
    final word = requestWord.trim();
    if (word.isEmpty) return [];

    final uri = Uri.parse('$baseUrl/addWord');
    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode({'requestWord': word}),
    );

    if (response.statusCode != 200) {
      throw JamminAddWordException(
        'addWord 실패 (${response.statusCode}): ${response.body}',
      );
    }

    final glyphs = HangulUtil.glyphsFromAddWordResponse(response.body);
    if (glyphs.isEmpty) {
      throw JamminAddWordException('한글이 아니거나 분해 결과가 비었습니다: $word');
    }
    return glyphs;
  }

  void close() => _client.close();
}

class JamminAddWordException implements Exception {
  JamminAddWordException(this.message);
  final String message;
  @override
  String toString() => message;
}
