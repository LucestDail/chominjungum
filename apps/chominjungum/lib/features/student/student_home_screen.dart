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
import '../../services/student_profile.dart';
import '../../theme/jammin_tokens.dart';
import '../../widgets/jammin/jammin_brand_title.dart';
import '../../widgets/jammin/jammin_scaffold.dart';
import '../../widgets/jammin/jammin_section.dart';
import '../../widgets/jammin/jammin_status_banner.dart';

/// 학생: QR 스캔 또는 페이로드 붙여넣기로 허브 연결.
/// 통합 테스트·위젯 테스트가 학생 화면 요소를 찾는 손잡이.
class StudentHomeKeys {
  const StudentHomeKeys._();

  static const studentName = Key('student.name');
}

class StudentHomeScreen extends ConsumerStatefulWidget {
  const StudentHomeScreen({super.key});

  @override
  ConsumerState<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends ConsumerState<StudentHomeScreen> {
  final _studentName = TextEditingController();

  @override
  void initState() {
    super.initState();
    StudentProfile.load().then((v) {
      if (mounted && v != null) _studentName.text = v;
    });
  }

  final _paste = TextEditingController();
  StudentHubClient? _client;
  String? _status;
  JamminStatusTone _statusTone = JamminStatusTone.info;

  /// 마지막으로 성공한 페어링 문자열 — 끊겼을 때 **자동 재연결**에 쓴다.
  /// (세션 키가 들어 있으므로 화면에 다시 보여주지 않는다)
  String? _lastPayload;
  Timer? _reconnectTimer;
  int _reconnectTries = 0;

  /// 자동 재시도 상한. 교실에서 잠깐 끊긴 것은 대부분 몇 초 안에 붙는다.
  /// 계속 실패하면 사람이 다시 스캔하는 편이 빠르다(그 안내를 띄운다).
  static const _maxReconnectTries = 5;

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _studentName.dispose();
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

  /// 허브와 끊어졌을 때. **화면에 알리고** 몇 번 자동으로 다시 붙어 본다.
  ///
  /// 그전에는 끊겨도 "허브에 연결됨"이 그대로 남아 있었고, 제출을 눌러도
  /// 조용히 실패했다 — 교실에서 앱을 잠깐 다른 데로 돌리면 생기는 일이다.
  void _onDisconnected() {
    if (!mounted) return;
    _client = null;
    ref.read(studentHubClientProvider.notifier).state = null;

    final payload = _lastPayload;
    if (payload == null || _reconnectTries >= _maxReconnectTries) {
      _setStatus(
        '선생님 기기와 연결이 끊어졌습니다. QR을 다시 스캔해 주세요.',
        tone: JamminStatusTone.error,
      );
      return;
    }

    _reconnectTries++;
    _setStatus(
      '연결이 끊어져 다시 연결하는 중… ($_reconnectTries/$_maxReconnectTries)',
      tone: JamminStatusTone.info,
    );
    // 붙자마자 또 끊기는 상황에서 몰아치지 않게 간격을 늘린다.
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: _reconnectTries * 2), () {
      if (mounted) unawaited(_connectFromPayloadString(payload));
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
        onDisconnected: _onDisconnected,
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
      _lastPayload = raw.trim();
      _reconnectTries = 0;
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
      actions: [
        IconButton(
          tooltip: '설정',
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => context.push('/settings'),
        ),
      ],
      body: ListView(
        children: [
          const JamminSectionHeader(
            heading: '학생 연결',
            subheading: '교사 QR을 스캔하거나 페이로드를 붙여넣으세요.',
          ),
          const SizedBox(height: 24),
          // 이름을 적으면 선생님 화면에 이름으로 보인다. 비워 두면 기기 번호로 보인다.
          TextField(
            key: StudentHomeKeys.studentName,
            controller: _studentName,
            maxLength: StudentProfile.maxLength,
            textInputAction: TextInputAction.done,
            onChanged: (v) => unawaited(StudentProfile.save(v)),
            decoration: const InputDecoration(
              labelText: '내 이름 (선택)',
              helperText: '적으면 선생님 화면에 이름으로 보입니다. 비워 두면 기기 번호로 보입니다.',
              helperMaxLines: 2,
              counterText: '',
            ),
          ),
          const SizedBox(height: 20),
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
