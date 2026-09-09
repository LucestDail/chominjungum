import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
    this.hostKeyPair,
    this.onAttempt,
    this.onClientCountChanged,
  });

  /// 교사의 X25519 키 쌍 — 페어링 v2.
  ///
  /// 주면 **QR 에서 세션 대칭키를 뺄 수 있다**: QR 에는 공개키만 담고, 접속한 학생이
  /// 자기 공개키를 보내면(`hello`) 그 학생만 풀 수 있게 세션 키를 감싸 보낸다
  /// (`session.key`). 안 주면 v1 처럼 동작한다(QR 에 대칭키 — 테스트 호환용).
  final SimpleKeyPair? hostKeyPair;

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
      // 평문 `hello` 와 암호 봉투가 같은 소켓으로 온다 — 열기 전에 종류부터 가른다.
      if (peekMessageType(message) == SyncMessageTypes.hello) {
        await _replyWithWrappedSessionKey(HelloPayload.decode(message), from);
        return;
      }

      final env = SyncEnvelope.decode(message);
      if (env.sessionId != sessionId) return;
      final handler = onAttempt;
      if (handler == null) return;
      if (env.type != SyncMessageTypes.attemptSubmit) return;
      final plain = await SyncCrypto.open(sessionKey: sessionKey, envelope: env);
      handler(AttemptSubmitPayload.decode(utf8.decode(plain)));
    } catch (_) {
      // 다른 세션 키·손상 메시지는 무시 (교실망 잡음 방어).
    }
  }

  /// `hello`(학생 공개키, 평문) → ECDH 로 **그 학생 전용 래핑 키**를 만들고
  /// 그것으로 수업 세션 키를 감싸 `session.key` 로 돌려준다.
  ///
  /// 이렇게 하는 이유: ECDH 는 학생마다 다른 비밀을 만들어서, 그것을 세션 키로 쓰면
  /// 브로드캐스트를 학생 수만큼 암호화해야 한다. 수업 키는 하나로 두고 **전달만**
  /// 학생별로 감싼다(키 래핑).
  Future<void> _replyWithWrappedSessionKey(
    HelloPayload hello,
    WebSocketChannel to,
  ) async {
    final pair = hostKeyPair;
    if (pair == null) return; // v1 모드 — 학생은 이미 QR 로 키를 안다
    if (hello.sessionId != sessionId) return;
    final wrapKey = await SyncKeyExchange.deriveWrapKey(
      myKeyPair: pair,
      theirPublicKey: SyncKeyExchange.publicKeyFromB64(hello.publicKeyB64),
      sessionId: sessionId,
    );
    final wrapped = await SyncCrypto.seal(
      sessionKey: wrapKey,
      sessionId: sessionId,
      type: SyncMessageTypes.sessionKey,
      plainBytes: await SyncCrypto.sessionKeyBytes(sessionKey),
    );
    try {
      to.sink.add(wrapped.encode());
    } catch (_) {}
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
  /// v1 이면 QR 에서 온 대칭키, v2 면 **핸드셰이크로 받은 뒤** 채워진다.
  SecretKey? _sessionKey;
  final String sessionId;

  /// 세션 키를 확보했는가(= 출제를 받을 수 있는 상태).
  bool get isReady => _sessionKey != null;

  /// [onDisconnected] — 허브와의 연결이 **끊어졌을 때** 한 번 불린다.
  ///
  /// ⚠️이게 없던 동안에는 끊겨도 학생 화면이 "허브에 연결됨" 그대로였고,
  /// 제출을 눌러도 **조용히 실패**했다. 교실에서 앱을 잠깐 다른 데로 돌리거나
  /// 화면이 꺼지면 소켓이 끊기므로 드문 일이 아니다.
  /// [hostPublicKeyB64] 를 주면 **페어링 v2**로 붙는다 — QR 에 세션 대칭키가 없고
  /// 교사 공개키만 있는 경우다. 접속 직후 자기 공개키를 `hello` 로 보내고,
  /// 교사가 감싸 보낸 세션 키(`session.key`)를 풀어 쓴다.
  /// 이 값이 없으면 v1(=[sessionKey] 를 그대로 사용).
  static Future<StudentHubClient> connect({
    required String wsUrl,
    required String sessionId,
    required void Function(List<int> plain, SyncEnvelope env) onMessage,
    SecretKey? sessionKey,
    String? hostPublicKeyB64,
    void Function()? onDisconnected,
    void Function()? onSessionKeyReady,
  }) async {
    assert(sessionKey != null || hostPublicKeyB64 != null,
        'v1 이면 sessionKey, v2 면 hostPublicKeyB64 가 필요하다');
    final channel = WebSocketChannel.connect(Uri.parse(wsUrl));
    await channel.ready;
    var notified = false;
    void notifyOnce() {
      if (notified) return;
      notified = true;
      onDisconnected?.call();
    }

    // v2: 내 키 쌍을 만들어 공개키를 보내고, 교사가 감싸 보낸 세션 키를 기다린다.
    SimpleKeyPair? myPair;
    SecretKey? wrapKey;
    late final StudentHubClient client;

    final sub = channel.stream.listen(
      (message) async {
        if (message is! String) return;
        try {
          final env = SyncEnvelope.decode(message);
          if (env.sessionId != sessionId) return;

          // v2 핸드셰이크 응답 — 이걸 풀어야 비로소 수업 메시지를 읽을 수 있다.
          if (env.type == SyncMessageTypes.sessionKey) {
            final wk = wrapKey;
            if (wk == null) return;
            final raw = await SyncCrypto.open(sessionKey: wk, envelope: env);
            client._sessionKey =
                await SyncCrypto.sessionKeyFromBytes(Uint8List.fromList(raw));
            onSessionKeyReady?.call();
            return;
          }

          final key = client._sessionKey;
          if (key == null) return; // 아직 세션 키가 없다(핸드셰이크 진행 중)
          final plain = await SyncCrypto.open(sessionKey: key, envelope: env);
          onMessage(plain, env);
        } catch (_) {}
      },
      onDone: notifyOnce,
      onError: (_) => notifyOnce(),
      cancelOnError: false,
    );

    client = StudentHubClient._(channel, sub, sessionKey, sessionId);

    if (hostPublicKeyB64 != null) {
      myPair = await SyncKeyExchange.newKeyPair();
      wrapKey = await SyncKeyExchange.deriveWrapKey(
        myKeyPair: myPair,
        theirPublicKey: SyncKeyExchange.publicKeyFromB64(hostPublicKeyB64),
        sessionId: sessionId,
      );
      channel.sink.add(HelloPayload(
        sessionId: sessionId,
        publicKeyB64: await SyncKeyExchange.publicKeyB64(myPair),
      ).encode());
    }

    return client;
  }

  /// 세션 키로 암호화해 교사 허브로 전송 (답안 제출 등).
  /// 세션 키가 아직 없으면(v2 핸드셰이크 진행 중) [StateError].
  /// 화면은 [isReady] 로 제출 버튼을 막는다.
  Future<void> sendEncrypted({
    required String type,
    required List<int> plainBytes,
  }) async {
    final key = _sessionKey;
    if (key == null) {
      throw StateError('세션 키를 아직 받지 못했습니다(연결 직후일 수 있습니다).');
    }
    final env = await SyncCrypto.seal(
      sessionKey: key,
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
