import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:hangul_core/hangul_core.dart';

import '../domain/dictation_models.dart';

/// 빌드에 포함된 jammin `/addWord` 응답 (네트워크 없이 즉시 표시).
class BundledDictationLoader {
  static const _assetPath = 'assets/data/default_dictation.json';

  static DictationPackage? _cache;

  static Future<DictationPackage> load() async {
    if (_cache != null) return _cache!;
    final raw = await rootBundle.loadString(_assetPath);
    final root = jsonDecode(raw) as Map<String, dynamic>;
    final itemsRaw = root['items'] as List<dynamic>;
    final items = itemsRaw.map((entry) {
      final map = Map<String, dynamic>.from(entry as Map);
      final word = map['word'] as String;
      final glyphsJson = jsonEncode(map['glyphs']);
      final glyphs = HangulUtil.glyphsFromAddWordResponse(glyphsJson);
      return DictationItem.fromGlyphs(word, glyphs);
    }).toList();
    _cache = DictationPackage(
      version: root['version'] as String? ?? DictationPackage.currentVersion,
      items: items,
    );
    return _cache!;
  }
}
