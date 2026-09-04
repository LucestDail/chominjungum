import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sync_protocol/sync_protocol.dart';

import '../../providers/dictation_providers.dart';
import '../../services/local_hub_service.dart';
import '../../theme/jammin_tokens.dart';
import '../../widgets/jammin/jammin_brand_title.dart';
import '../../widgets/jammin/jammin_scaffold.dart';
import '../../widgets/jammin/jammin_section.dart';
import '../../widgets/jammin/jammin_status_banner.dart';

/// 학생: QR 스캔 또는 페이로드 붙여넣기로 허브 연결.
class StudentHomeScreen extends ConsumerStatefulWidget {
  const StudentHomeScreen({super.key});

  @override
  ConsumerState<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends ConsumerState<StudentHomeScreen> {
  final _paste = TextEditingController();
  StudentHubClient? _client;
  String? _status;
  JamminStatusTone _statusTone = JamminStatusTone.info;

  @override
  void dispose() {
    _paste.dispose();
    final c = _client;
    if (c != null) {
      unawaited(c.close());
    }
    super.dispose();
  }

  void _setStatus(String msg, {JamminStatusTone tone = JamminStatusTone.info}) {
    setState(() {
      _status = msg;
      _statusTone = tone;
    });
  }

  Future<void> _connectFromPayloadString(String raw) async {
    _setStatus('연결 중…');
    try {
      final payload = SessionPairingPayload.decode(raw.trim());
      final host = payload.hubHost?.trim();
      if (host == null || host.isEmpty) {
        _setStatus(
          'QR에 hubHost(IP)가 없습니다. 교사 기기에서 IP를 확인하세요.',
          tone: JamminStatusTone.error,
        );
        return;
      }
      final keyBytes = Uint8List.fromList(base64Decode(payload.publicKeyB64));
      final key = await SyncCrypto.sessionKeyFromBytes(keyBytes);
      await _client?.close();
      ref.read(studentHubClientProvider.notifier).state = null;
      _client = await StudentHubClient.connect(
        wsUrl: 'ws://$host:${payload.hubPort}/',
        sessionKey: key,
        sessionId: payload.sessionId,
        onMessage: (plain, env) {
          final pkg = tryDecodeDictationPackage(plain, env);
          if (pkg != null && mounted) {
            ref.read(dictationPackageProvider.notifier).state = pkg;
            // 받은 문제를 남긴다 — 앱을 다시 켜도 그 문제로 이어서 풀 수 있게.
            unawaited(ref.read(dictationRepositoryProvider).savePackage(pkg));
            _setStatus('문제 수신. 학습 화면으로 이동합니다.', tone: JamminStatusTone.success);
            context.push('/practice');
          }
        },
      );
      ref.read(studentHubClientProvider.notifier).state = _client;
      if (mounted) {
        _setStatus('허브에 연결됨. 교사가 문제를 내면 자동으로 열립니다.', tone: JamminStatusTone.success);
      }
    } catch (e) {
      if (mounted) {
        _setStatus('연결 실패: $e', tone: JamminStatusTone.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bundled = ref.watch(dictationPackageProvider);
    final wordCount = bundled?.items.length ?? 0;

    return JamminScaffold(
      titleWidget: const JamminBrandTitle(subtitle: '학생'),
      body: ListView(
        children: [
          const JamminSectionHeader(
            heading: '학생 연결',
            subheading: '교사 QR을 스캔하거나 페이로드를 붙여넣으세요.',
          ),
          const SizedBox(height: 28),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  color: JamminTokens.brandSoft,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Text(
                    'QR 스캔',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                SizedBox(
                  height: 260,
                  child: MobileScanner(
                    onDetect: (capture) {
                      for (final b in capture.barcodes) {
                        final v = b.rawValue;
                        if (v != null && v.trim().startsWith('{')) {
                          unawaited(_connectFromPayloadString(v));
                          break;
                        }
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '페이로드 붙여넣기',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _paste,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'SessionPairingPayload JSON',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => _connectFromPayloadString(_paste.text),
            child: const Text('연결'),
          ),
          if (_status != null) ...[
            const SizedBox(height: 20),
            JamminStatusBanner(message: _status!, tone: _statusTone),
          ],
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 24),
          JamminSectionHeader(
            heading: '연습',
            subheading: wordCount > 0
                ? '안녕하세요 · 강아지와고양이 (앱 번들, $wordCount문항)'
                : '데이터 로딩 중…',
            center: false,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: wordCount > 0 ? () => context.push('/practice') : null,
            child: const Text('받아쓰기 연습 열기'),
          ),
        ],
      ),
    );
  }
}
