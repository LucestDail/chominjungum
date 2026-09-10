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
        await _handleUpstream(message, channel);
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

  Future<void> _handleUpstream(String message, WebSocketChannel from) async {
    try {
      final env = SyncEnvelope.decode(message);
      if (env.sessionId != sessionId) return;
      if (env.type != SyncMessageTypes.attemptSubmit) return;
      final plain = await SyncCrypto.open(sessionKey: sessionKey, envelope: env);
      final attempt = AttemptSubmitPayload.decode(utf8.decode(plain));

      onAttempt?.call(attempt);

      // **받았다고 회신한다.** 이게 없으면 학생은 소켓에 밀어 넣은 것만으로
      // 성공했다고 여기고, 중간에 끊기면 제출이 조용히 사라진다.
      // ⚠️처리 결과와 무관하게 "도착했다"만 알린다 — 화면 갱신 실패로 회신을
      // 미루면 학생이 같은 답안을 계속 재전송한다.
      await _ackTo(from, attempt.attemptId);
    } catch (_) {
      // 다른 세션 키·손상 메시지는 무시 (교실망 잡음 방어).
    }
  }

  Future<void> _ackTo(WebSocketChannel channel, String attemptId) async {
    try {
      final env = await SyncCrypto.seal(
        sessionKey: sessionKey,
        sessionId: sessionId,
        type: SyncMessageTypes.ack,
        plainBytes: utf8.encode(AckPayload(attemptId: attemptId).encode()),
      );
      channel.sink.add(env.encode());
    } catch (_) {
      // 회신 실패는 학생 쪽 재전송이 덮는다.
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

  /// [onDisconnected] — 허브와의 연결이 **끊어졌을 때** 한 번 불린다.
  ///
  /// ⚠️이게 없던 동안에는 끊겨도 학생 화면이 "허브에 연결됨" 그대로였고,
  /// 제출을 눌러도 **조용히 실패**했다. 교실에서 앱을 잠깐 다른 데로 돌리거나
  /// 화면이 꺼지면 소켓이 끊기므로 드문 일이 아니다.
  static Future<StudentHubClient> connect({
    required String wsUrl,
    required SecretKey sessionKey,
    required String sessionId,
    required void Function(List<int> plain, SyncEnvelope env) onMessage,
    void Function()? onDisconnected,
  }) async {
    final channel = WebSocketChannel.connect(Uri.parse(wsUrl));
    await channel.ready;
    var notified = false;
    void notifyOnce() {
      if (notified) return;
      notified = true;
      onDisconnected?.call();
    }

    // 리스너가 인스턴스 필드(`_pendingAcks`)를 봐야 해서 **먼저 만들고** 붙인다.
    late final StudentHubClient client;
    final sub = channel.stream.listen(
      (message) async {
        if (message is! String) return;
        try {
          final env = SyncEnvelope.decode(message);
          if (env.sessionId != sessionId) return;
          final plain =
              await SyncCrypto.open(sessionKey: sessionKey, envelope: env);
          if (env.type == SyncMessageTypes.ack) {
            client._completeAck(plain);
            return;
          }
          onMessage(plain, env);
        } catch (_) {}
      },
      onDone: notifyOnce,
      onError: (_) => notifyOnce(),
      cancelOnError: false,
    );
    client = StudentHubClient._(channel, sub, sessionKey, sessionId);
    return client;
  }

  /// 회신을 받아 대기 중인 제출을 완료 처리한다.
  void _completeAck(List<int> plain) {
    try {
      final ack = AckPayload.decode(utf8.decode(plain));
      final waiter = _pendingAcks.remove(ack.attemptId);
      if (waiter != null && !waiter.isCompleted) waiter.complete(ack);
    } catch (_) {
      // 손상된 회신은 무시한다 — 타임아웃이 덮는다.
    }
  }

  /// 회신(ACK)을 기다리는 제출들. 키는 `attemptId`.
  final _pendingAcks = <String, Completer<AckPayload>>{};

  /// 회신이 올 때까지 **다시 보낸다.**
  ///
  /// 소켓에 밀어 넣는 것과 상대가 받는 것은 다르다. 끊기는 중이거나 교사 앱이
  /// 잠깐 멈춰 있으면 제출이 **조용히 사라지고**, 학생 화면만 "제출됨"이 된다.
  ///
  /// [attempts] 번까지 시도하고 그래도 못 받으면 실패로 돌려준다 —
  /// 화면이 "선생님께 전달되지 않았다"고 알릴 수 있어야 한다.
  /// ⚠️같은 `attemptId` 로 보내므로 **교사 쪽은 멱등**이다(중복 제출이 아니다).
  Future<bool> sendWithAck({
    required String type,
    required List<int> plainBytes,
    required String attemptId,
    int attempts = 3,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    for (var i = 0; i < attempts; i++) {
      final completer = Completer<AckPayload>();
      _pendingAcks[attemptId] = completer;
      try {
        await sendEncrypted(type: type, plainBytes: plainBytes);
        final ack = await completer.future.timeout(timeout);
        _pendingAcks.remove(attemptId);
        // 거절은 재전송해도 소용없다(세션이 끝났다 등).
        return ack.ok;
      } on TimeoutException {
        _pendingAcks.remove(attemptId);
        // 다음 회차에 다시 보낸다. 간격을 늘려 몰아치지 않게.
        if (i + 1 < attempts) {
          await Future<void>.delayed(Duration(seconds: i + 1));
        }
      } catch (_) {
        _pendingAcks.remove(attemptId);
        return false;
      }
    }
    return false;
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
