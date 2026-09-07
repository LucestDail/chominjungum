import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:sync_protocol/sync_protocol.dart';

import '../domain/dictation_models.dart';

/// 업로드 대기 중인 한 수업(허브 세션).
///
/// 인터넷이 없어도 수업은 끝난다. 결과는 여기 쌓였다가 연결됐을 때 서버로 올라간다.
class PendingSession {
  PendingSession({
    required this.sessionId,
    required this.startedAtMs,
    this.endedAtMs,
    List<DictationItem>? items,
    List<AttemptSubmitPayload>? attempts,
  })  : items = items ?? [],
        attempts = attempts ?? [];

  final String sessionId;
  final int startedAtMs;
  int? endedAtMs;
  final List<DictationItem> items;
  final List<AttemptSubmitPayload> attempts;

  /// 같은 기기·같은 문항의 재제출은 최신 것만 남긴다(교사 화면 표시와 같은 규칙).
  void addAttempt(AttemptSubmitPayload attempt) {
    attempts.removeWhere(
      (a) => a.deviceBindingId == attempt.deviceBindingId && a.itemId == attempt.itemId,
    );
    attempts.add(attempt);
  }

  void addItem(DictationItem item) {
    if (items.any((i) => i.id == item.id)) return;
    items.add(item);
  }

  Map<String, Object?> toJson() => {
        'sessionId': sessionId,
        'startedAtMs': startedAtMs,
        if (endedAtMs != null) 'endedAtMs': endedAtMs,
        'items': items.map((i) => i.toJson()).toList(),
        'attempts': attempts.map((a) => a.toJson()).toList(),
      };

  factory PendingSession.fromJson(Map<String, Object?> json) {
    return PendingSession(
      sessionId: json['sessionId']! as String,
      startedAtMs: json['startedAtMs'] as int? ?? 0,
      endedAtMs: json['endedAtMs'] as int?,
      items: (json['items'] as List<dynamic>? ?? [])
          .map((e) => DictationItem.fromJson(Map<String, Object?>.from(e as Map)))
          .toList(),
      attempts: (json['attempts'] as List<dynamic>? ?? [])
          .map((e) => AttemptSubmitPayload.fromJson(Map<String, Object?>.from(e as Map)))
          .toList(),
    );
  }
}

/// 서버 연결 설정. 비어 있으면 서버 연동을 쓰지 않는다는 뜻(옵트인).
class UpsyncConfig {
  const UpsyncConfig({required this.baseUrl, required this.token, required this.classroomId});

  final String baseUrl;
  final String token;
  final String classroomId;

  bool get isComplete =>
      baseUrl.trim().isNotEmpty && token.trim().isNotEmpty && classroomId.trim().isNotEmpty;

  Map<String, Object?> toJson() =>
      {'baseUrl': baseUrl, 'token': token, 'classroomId': classroomId};

  factory UpsyncConfig.fromJson(Map<String, Object?> json) => UpsyncConfig(
        baseUrl: json['baseUrl'] as String? ?? '',
        token: json['token'] as String? ?? '',
        classroomId: json['classroomId'] as String? ?? '',
      );

  static const empty = UpsyncConfig(baseUrl: '', token: '', classroomId: '');
}

/// 업로드 결과 — 서버 응답을 그대로 옮긴다(docs/sync-protocol.md §3.2).
class UpsyncResult {
  const UpsyncResult({
    required this.accepted,
    required this.duplicated,
    required this.rejected,
    required this.unassignedDevices,
  });

  final int accepted;
  final int duplicated;
  final int rejected;
  final List<String> unassignedDevices;

  factory UpsyncResult.fromJson(Map<String, Object?> json) => UpsyncResult(
        accepted: json['accepted'] as int? ?? 0,
        duplicated: json['duplicated'] as int? ?? 0,
        rejected: (json['rejected'] as List<dynamic>? ?? []).length,
        unassignedDevices: (json['unassignedDevices'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
      );
}

class UpsyncException implements Exception {
  UpsyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 로컬 큐 영속화 + 서버 업로드.
class UpsyncService {
  UpsyncService({FlutterSecureStorage? storage, http.Client? client})
      : _storage = storage ?? const FlutterSecureStorage(),
        _client = client ?? http.Client();

  static const _queueKey = 'upsync_queue_v1';
  static const _configKey = 'upsync_config_v1';

  final FlutterSecureStorage _storage;
  final http.Client _client;

  Future<List<PendingSession>> loadQueue() async {
    final raw = await _storage.read(key: _queueKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => PendingSession.fromJson(Map<String, Object?>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveQueue(List<PendingSession> queue) async {
    await _storage.write(
      key: _queueKey,
      value: jsonEncode(queue.map((s) => s.toJson()).toList()),
    );
  }

  Future<UpsyncConfig> loadConfig() async {
    final raw = await _storage.read(key: _configKey);
    if (raw == null || raw.isEmpty) return UpsyncConfig.empty;
    try {
      return UpsyncConfig.fromJson(Map<String, Object?>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return UpsyncConfig.empty;
    }
  }

  Future<void> saveConfig(UpsyncConfig config) async {
    await _storage.write(key: _configKey, value: jsonEncode(config.toJson()));
  }

  /// 한 세션을 서버로 올린다. 같은 배치를 다시 보내도 안전하다(attemptId 가 멱등 키).
  Future<UpsyncResult> upload(UpsyncConfig config, PendingSession session) async {
    if (!config.isComplete) {
      throw UpsyncException('서버 주소·토큰·학급 ID를 모두 입력하세요.');
    }

    final uri = Uri.parse('${config.baseUrl.trim().replaceAll(RegExp(r'/+$'), '')}/api/sync/sessions');
    final body = {
      'sessionId': session.sessionId,
      'classroomId': config.classroomId.trim(),
      'source': 'LAN',
      'startedAtMs': session.startedAtMs,
      if (session.endedAtMs != null) 'endedAtMs': session.endedAtMs,
      'items': session.items
          .map((i) => {'id': i.id, 'expectedText': i.expectedText})
          .toList(),
      'attempts': session.attempts
          .map((a) => {
                'attemptId': a.attemptId,
                'itemId': a.itemId,
                'deviceBindingId': a.deviceBindingId,
                'rawAnswer': a.rawAnswer,
                'correctCount': a.correctCount,
                'totalCount': a.totalCount,
                'inputKind': a.inputKind,
                'submittedAtMs': a.submittedAtMs,
                if (a.matches != null)
                  'matches': a.matches!.map((m) => m.toJson()).toList(),
              })
          .toList(),
    };

    final http.Response response;
    try {
      response = await _client.post(
        uri,
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          // ★앱 토큰은 전용 헤더로 보낸다. 서버가 게이트웨이(nginx) 뒤에 있고
          // 외부 요청에는 HTTP Basic 을 요구하므로, `Authorization` 에 Bearer 를 실으면
          // Basic 을 덮어써 **게이트웨이에서 401** 이 되고 토큰이 서버에 닿지도 못한다.
          // 서버는 X-Auth-Token 을 먼저 본다(JwtAuthFilter.TOKEN_HEADER).
          // 2026-09-07 외부 경로 실측: Basic+Bearer → nginx 401 / Basic+X-Auth-Token → 서버 도달.
          'X-Auth-Token': config.token.trim(),
        },
        body: jsonEncode(body),
      );
    } catch (e) {
      throw UpsyncException('서버에 연결하지 못했습니다: $e');
    }

    if (response.statusCode == 401) {
      throw UpsyncException('토큰이 만료되었거나 잘못되었습니다. 다시 로그인하세요.');
    }
    if (response.statusCode >= 400) {
      throw UpsyncException('업로드 실패 (${response.statusCode}) ${response.body}');
    }

    return UpsyncResult.fromJson(
      Map<String, Object?>.from(jsonDecode(utf8.decode(response.bodyBytes)) as Map),
    );
  }

  void close() => _client.close();
}
