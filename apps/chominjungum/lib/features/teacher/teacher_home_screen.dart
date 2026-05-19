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
import '../../services/jammin_add_word_service.dart';
import '../../services/local_hub_service.dart';
import '../../theme/jammin_tokens.dart';
import '../../widgets/jammin/jammin_brand_title.dart';
import '../../widgets/jammin/jammin_scaffold.dart';
import '../../widgets/jammin/jammin_section.dart';
import '../../widgets/jammin/jammin_status_banner.dart';

/// 교사: 로컬 허브 시작·QR·문제 전송.
class TeacherHomeScreen extends ConsumerStatefulWidget {
  const TeacherHomeScreen({super.key});

  @override
  ConsumerState<TeacherHomeScreen> createState() => _TeacherHomeScreenState();
}

class _TeacherHomeScreenState extends ConsumerState<TeacherHomeScreen> {
  final _sentence = TextEditingController(text: '안녕하세요');
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
    try {
      final glyphs = await JamminAddWordService().addWord(text);
      final item = DictationItem.fromGlyphs(text, glyphs);
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('jammin 분해 실패: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return JamminScaffold(
      titleWidget: const JamminBrandTitle(subtitle: '교사'),
      body: ListView(
        children: [
          const JamminSectionHeader(
            heading: '교실 허브',
            subheading: '학생과 같은 Wi-Fi에서 QR로 연결합니다. 세션 키는 QR로만 교환됩니다.',
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _hostOverride,
            decoration: const InputDecoration(
              labelText: '허브 IP (자동 인식 실패 시)',
              hintText: '예: 192.168.0.12',
            ),
          ),
          const SizedBox(height: 16),
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
            const SizedBox(height: 16),
            JamminStatusBanner(message: _error!, tone: JamminStatusTone.error),
          ],
          if (_pairing != null && (_pairing!.hubHost ?? '').isNotEmpty) ...[
            const SizedBox(height: 28),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(
                      '학생 스캔용 QR',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    QrImageView(
                      data: _pairing!.encode(),
                      version: QrVersions.auto,
                      size: 220,
                      backgroundColor: JamminTokens.surfaceElevated,
                    ),
                    const SizedBox(height: 12),
                    SelectableText(
                      _pairing!.encode(),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 24),
          const JamminSectionHeader(
            heading: '받아쓰기 출제',
            subheading: '정답 문장을 입력하고 학생 기기로 전송합니다.',
            center: false,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _sentence,
            decoration: const InputDecoration(
              labelText: '받아쓰기 정답 문장',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _hub != null ? _broadcast : null,
            child: const Text('문제 전송 (암호화)'),
          ),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () => context.push('/practice'),
            child: const Text('이 기기에서 미리보기'),
          ),
        ],
      ),
    );
  }
}
