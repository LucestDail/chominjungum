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

  @override
  void dispose() {
    _paste.dispose();
    final c = _client;
    if (c != null) {
      unawaited(c.close());
    }
    super.dispose();
  }

  Future<void> _connectFromPayloadString(String raw) async {
    setState(() => _status = '연결 중…');
    try {
      final payload = SessionPairingPayload.decode(raw.trim());
      final host = payload.hubHost?.trim();
      if (host == null || host.isEmpty) {
        setState(() => _status = 'QR에 hubHost(IP)가 없습니다. 교사 기기에서 IP를 확인하세요.');
        return;
      }
      final keyBytes = Uint8List.fromList(base64Decode(payload.publicKeyB64));
      final key = await SyncCrypto.sessionKeyFromBytes(keyBytes);
      await _client?.close();
      _client = await StudentHubClient.connect(
        wsUrl: 'ws://$host:${payload.hubPort}/',
        sessionKey: key,
        sessionId: payload.sessionId,
        onMessage: (plain, env) {
          final pkg = tryDecodeDictationPackage(plain, env);
          if (pkg != null && mounted) {
            ref.read(dictationPackageProvider.notifier).state = pkg;
            setState(() => _status = '문제 수신. 학습 화면으로 이동합니다.');
            context.push('/practice');
          }
        },
      );
      if (mounted) {
        setState(() => _status = '허브에 연결됨. 교사가 문제를 내면 자동으로 열립니다.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _status = '연결 실패: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('초민정음 · 학생')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('교사 QR 스캔', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SizedBox(
            height: 260,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
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
          ),
          const SizedBox(height: 24),
          Text('또는 페이로드 붙여넣기', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _paste,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'SessionPairingPayload JSON',
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => _connectFromPayloadString(_paste.text),
            child: const Text('연결'),
          ),
          if (_status != null) ...[
            const SizedBox(height: 16),
            Text(_status!),
          ],
          const SizedBox(height: 24),
          FilledButton.tonal(
            onPressed: () => context.push('/practice'),
            child: const Text('로컬 샘플 받아쓰기 열기'),
          ),
        ],
      ),
    );
  }
}
