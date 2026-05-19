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
  });

  final String sessionId;
  final SecretKey sessionKey;
  final int port;

  HttpServer? _server;
  final _channels = <WebSocketChannel>{};

  bool get isRunning => _server != null;

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
    channel.stream.listen(
      (_) {},
      onDone: () {
        _channels.remove(channel);
      },
    );
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
  StudentHubClient._(this._channel, this._subscription);

  final WebSocketChannel _channel;
  final StreamSubscription<dynamic> _subscription;

  static Future<StudentHubClient> connect({
    required String wsUrl,
    required SecretKey sessionKey,
    required String sessionId,
    required void Function(List<int> plain, SyncEnvelope env) onMessage,
  }) async {
    final channel = WebSocketChannel.connect(Uri.parse(wsUrl));
    final sub = channel.stream.listen((message) async {
      if (message is! String) return;
      try {
        final env = SyncEnvelope.decode(message);
        if (env.sessionId != sessionId) return;
        final plain = await SyncCrypto.open(sessionKey: sessionKey, envelope: env);
        onMessage(plain, env);
      } catch (_) {}
    });
    return StudentHubClient._(channel, sub);
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
