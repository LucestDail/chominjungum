import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sync_protocol/sync_protocol.dart';
import 'package:uuid/uuid.dart';

import '../../domain/dictation_models.dart';
import '../../providers/dictation_providers.dart';
import '../../services/local_hub_service.dart';

/// 교사: 로컬 허브 시작·QR·문제 전송.
class TeacherHomeScreen extends ConsumerStatefulWidget {
  const TeacherHomeScreen({super.key});

  @override
  ConsumerState<TeacherHomeScreen> createState() => _TeacherHomeScreenState();
}

class _TeacherHomeScreenState extends ConsumerState<TeacherHomeScreen> {
  final _sentence = TextEditingController(text: '가나다');
  final _hostOverride = TextEditingController();
  LocalHubService? _hub;
  SessionPairingPayload? _pairing;
  SecretKey? _sessionKey;
  String? _error;

  @override
  void dispose() {
    _sentence.dispose();
    _hostOverride.dispose();
    _hub?.stop();
    super.dispose();
  }

  Future<void> _startHub() async {
    setState(() => _error = null);
    await _hub?.stop();
    final sessionId = const Uuid().v4();
    final key = await SyncCrypto.newSessionKey();
    final hub = LocalHubService(
      sessionId: sessionId,
      sessionKey: key,
      port: SyncDefaults.hubPort,
    );
    try {
      await hub.start();
    } catch (e) {
      setState(() => _error = '허브 시작 실패: $e');
      return;
    }
    final info = NetworkInfo();
    final wifiIp = await info.getWifiIP();
    final host = (_hostOverride.text.trim().isNotEmpty ? _hostOverride.text.trim() : wifiIp) ?? '';
    if (host.isEmpty) {
      setState(() {
        _error = 'IP를 확인할 수 없습니다. 아래에 수동으로 입력하세요.';
      });
    }
    final keyBytes = await SyncCrypto.sessionKeyBytes(key);
    final payload = SessionPairingPayload(
      sessionId: sessionId,
      hostDisplayName: '교사',
      publicKeyB64: base64Encode(keyBytes),
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      ttlSeconds: 600,
      hubPort: SyncDefaults.hubPort,
      hubHost: host.isEmpty ? null : host,
    );
    setState(() {
      _hub = hub;
      _sessionKey = key;
      _pairing = payload;
    });
  }

  Future<void> _stopHub() async {
    await _hub?.stop();
    setState(() {
      _hub = null;
      _pairing = null;
      _sessionKey = null;
    });
  }

  Future<void> _broadcast() async {
    final hub = _hub;
    final key = _sessionKey;
    if (hub == null || key == null) return;
    final text = _sentence.text.trim();
    if (text.isEmpty) return;
    final item = DictationItem.fromExpectedText(text);
    final pkg = DictationPackage(version: DictationPackage.currentVersion, items: [item]);
    ref.read(dictationPackageProvider.notifier).state = pkg;
    await hub.broadcastEncrypted(
      type: SyncMessageTypes.dictationPackage,
      plainBytes: pkg.toUtf8Bytes(),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('학생 기기로 암호화 전송했습니다.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('초민정음 · 교사')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('LAN WebSocket 허브', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            '학생과 같은 Wi-Fi에 두고, 아래 QR을 스캔하게 하세요. 세션 키는 QR로만 교환됩니다.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _hostOverride,
            decoration: const InputDecoration(
              labelText: '허브 IP (자동 인식 실패 시)',
              hintText: '예: 192.168.0.12',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton(
                onPressed: _hub == null ? _startHub : null,
                child: const Text('허브 시작'),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: _hub != null ? _stopHub : null,
                child: const Text('중지'),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          if (_pairing != null && (_pairing!.hubHost ?? '').isNotEmpty) ...[
            const SizedBox(height: 24),
            Center(
              child: QrImageView(
                data: _pairing!.encode(),
                version: QrVersions.auto,
                size: 220,
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(_pairing!.encode(), style: const TextStyle(fontSize: 11)),
          ],
          const SizedBox(height: 24),
          TextField(
            controller: _sentence,
            decoration: const InputDecoration(
              labelText: '받아쓰기 정답 문장',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: _hub != null ? _broadcast : null,
            child: const Text('문제 전송 (암호화)'),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => context.push('/practice'),
            child: const Text('이 기기에서 미리보기 (학습 화면)'),
          ),
        ],
      ),
    );
  }
}
