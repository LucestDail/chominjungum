import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:sync_protocol/sync_protocol.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../domain/dictation_models.dart';

/// 교사 기기에서 동작하는 LAN WebSocket 허브 (평문 WS — 교실망 전용).
class LocalHubService {
  LocalHubService({
    required this.sessionId,
    required this.sessionKey,
    required this.port,
    this.onAttempt,
    this.onClientCountChanged,
  });

  final String sessionId;
  final SecretKey sessionKey;
  final int port;

  /// 학생이 보낸 `attempt.submit` 수신 콜백.
  final void Function(AttemptSubmitPayload attempt)? onAttempt;

  /// 접속 학생 수 변화 콜백.
  final void Function(int count)? onClientCountChanged;

  HttpServer? _server;
  final _channels = <WebSocketChannel>{};

  bool get isRunning => _server != null;

  int get clientCount => _channels.length;

  /// 실제 바인딩된 포트 (테스트에서 port 0 사용 시 확인용).
  int? get boundPort => _server?.port;

  Future<void> start() async {
    if (_server != null) return;
    final handler = webSocketHandler(_onClient);
    _server = await shelf_io.serve(
      handler,
      InternetAddress.anyIPv4,
      port,
    );
  }

  void _onClient(WebSocketChannel channel) {
    _channels.add(channel);
    onClientCountChanged?.call(_channels.length);
    channel.stream.listen(
      (message) async {
        if (message is! String) return;
        await _handleUpstream(message);
      },
      onDone: () {
        _channels.remove(channel);
        onClientCountChanged?.call(_channels.length);
      },
      onError: (_) {
        _channels.remove(channel);
        onClientCountChanged?.call(_channels.length);
      },
    );
  }

  Future<void> _handleUpstream(String message) async {
    final handler = onAttempt;
    if (handler == null) return;
    try {
      final env = SyncEnvelope.decode(message);
      if (env.sessionId != sessionId) return;
      if (env.type != SyncMessageTypes.attemptSubmit) return;
      final plain = await SyncCrypto.open(sessionKey: sessionKey, envelope: env);
      handler(AttemptSubmitPayload.decode(utf8.decode(plain)));
    } catch (_) {
      // 다른 세션 키·손상 메시지는 무시 (교실망 잡음 방어).
    }
  }

  /// [plainBytes] JSON 등 평문을 암호화해 모든 접속 클라이언트에 전송.
  Future<void> broadcastEncrypted({
    required String type,
    required List<int> plainBytes,
  }) async {
    final env = await SyncCrypto.seal(
      sessionKey: sessionKey,
      sessionId: sessionId,
      type: type,
      plainBytes: plainBytes,
    );
    final line = env.encode();
    for (final c in _channels.toList()) {
      try {
        c.sink.add(line);
      } catch (_) {}
    }
  }

  Future<void> stop() async {
    for (final c in _channels.toList()) {
      await c.sink.close();
    }
    _channels.clear();
    await _server?.close(force: true);
    _server = null;
  }
}

/// 학생 기기에서 교사 허브로 수신.
class StudentHubClient {
  StudentHubClient._(this._channel, this._subscription, this._sessionKey, this.sessionId);

  final WebSocketChannel _channel;
  final StreamSubscription<dynamic> _subscription;
  final SecretKey _sessionKey;
  final String sessionId;

  static Future<StudentHubClient> connect({
    required String wsUrl,
    required SecretKey sessionKey,
    required String sessionId,
    required void Function(List<int> plain, SyncEnvelope env) onMessage,
  }) async {
    final channel = WebSocketChannel.connect(Uri.parse(wsUrl));
    await channel.ready;
    final sub = channel.stream.listen((message) async {
      if (message is! String) return;
      try {
        final env = SyncEnvelope.decode(message);
        if (env.sessionId != sessionId) return;
        final plain = await SyncCrypto.open(sessionKey: sessionKey, envelope: env);
        onMessage(plain, env);
      } catch (_) {}
    });
    return StudentHubClient._(channel, sub, sessionKey, sessionId);
  }

  /// 세션 키로 암호화해 교사 허브로 전송 (답안 제출 등).
  Future<void> sendEncrypted({
    required String type,
    required List<int> plainBytes,
  }) async {
    final env = await SyncCrypto.seal(
      sessionKey: _sessionKey,
      sessionId: sessionId,
      type: type,
      plainBytes: plainBytes,
    );
    _channel.sink.add(env.encode());
  }

  Future<void> close() async {
    await _subscription.cancel();
    await _channel.sink.close();
  }
}

DictationPackage? tryDecodeDictationPackage(List<int> plain, SyncEnvelope env) {
  if (env.type != SyncMessageTypes.dictationPackage) return null;
  try {
    final map = jsonDecode(utf8.decode(plain)) as Map<String, Object?>;
    return DictationPackage.fromJson(map);
  } catch (_) {
    return null;
  }
}
