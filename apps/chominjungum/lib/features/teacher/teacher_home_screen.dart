import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hangul_core/hangul_core.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:sync_protocol/sync_protocol.dart';
import 'package:uuid/uuid.dart';

import '../../domain/dictation_models.dart';
import '../../providers/dictation_providers.dart';
import '../../services/dictation_composer.dart';
import '../../services/dictation_repository.dart';
import '../../services/local_hub_service.dart';
import '../../services/upsync_service.dart';
import '../../theme/jammin_tokens.dart';
import '../../widgets/jammin/jammin_brand_title.dart';
import '../../widgets/jammin/jammin_scaffold.dart';
import '../../widgets/jammin/jammin_section.dart';
import '../../widgets/jammin/jammin_status_banner.dart';
import 'hide_rule_picker.dart';
import 'pairing_info_card.dart';

/// 통합 테스트가 교사 화면 요소를 찾는 손잡이.
///
/// 라벨 문구로 찾으면 문구를 다듬는 순간 테스트가 깨진다. 교사 화면은
/// `NetworkInfo` 플러그인에 묶여 **위젯 테스트가 불가능**해서 실기동
/// 통합 테스트가 유일한 검증 수단이므로, 그 손잡이를 코드로 고정해 둔다.
class TeacherHomeKeys {
  const TeacherHomeKeys._();

  static const hostOverride = Key('teacher.hostOverride');
  static const startHub = Key('teacher.startHub');
  static const sentence = Key('teacher.sentence');
  static const broadcast = Key('teacher.broadcast');
  static const serverUrl = Key('teacher.serverUrl');
  static const serverToken = Key('teacher.serverToken');
  static const classroomId = Key('teacher.classroomId');
  static const uploadNow = Key('teacher.uploadNow');
}

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
  int _connectedCount = 0;
  final _attempts = <AttemptSubmitPayload>[];

  /// 자모 가리기 — 출제와 함께 학생 기기로 간다(jammin `hidebox`).
  HideRule _hideRule = HideRule.empty;

  // 서버 업싱크 (옵트인 — 비워두면 교실 모드만 쓴다)
  final _upsync = UpsyncService();
  final _serverUrl = TextEditingController();
  final _serverToken = TextEditingController();
  final _classroomId = TextEditingController();
  PendingSession? _pending;
  String? _upsyncStatus;
  JamminStatusTone _upsyncTone = JamminStatusTone.info;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _restoreUpsync();
  }

  @override
  void dispose() {
    _sentence.dispose();
    _hostOverride.dispose();
    _serverUrl.dispose();
    _serverToken.dispose();
    _classroomId.dispose();
    _upsync.close();
    _hub?.stop();
    super.dispose();
  }

  Future<void> _restoreUpsync() async {
    final config = await _upsync.loadConfig();
    final queue = await _upsync.loadQueue();
    if (!mounted) return;
    setState(() {
      _serverUrl.text = config.baseUrl;
      _serverToken.text = config.token;
      _classroomId.text = config.classroomId;
      if (queue.isNotEmpty) {
        _upsyncStatus = '업로드 대기 중인 수업 ${queue.length}건이 있습니다.';
        _upsyncTone = JamminStatusTone.info;
      }
    });
  }

  UpsyncConfig get _upsyncConfig => UpsyncConfig(
        baseUrl: _serverUrl.text,
        token: _serverToken.text,
        classroomId: _classroomId.text,
      );

  /// 큐를 통째로 다시 쓴다. 현재 세션은 항상 마지막 항목이다.
  Future<void> _persistQueue() async {
    final session = _pending;
    if (session == null) return;
    final queue = await _upsync.loadQueue();
    queue.removeWhere((s) => s.sessionId == session.sessionId);
    queue.add(session);
    await _upsync.saveQueue(queue);
  }

  Future<void> _uploadNow() async {
    final session = _pending;
    if (session == null || session.attempts.isEmpty) {
      setState(() {
        _upsyncStatus = '올릴 제출이 없습니다.';
        _upsyncTone = JamminStatusTone.info;
      });
      return;
    }

    setState(() => _uploading = true);
    await _upsync.saveConfig(_upsyncConfig);

    try {
      session.endedAtMs = DateTime.now().millisecondsSinceEpoch;
      final result = await _upsync.upload(_upsyncConfig, session);

      // 성공한 세션은 큐에서 뺀다(로컬 표시는 화면에 그대로 남는다).
      final queue = await _upsync.loadQueue();
      queue.removeWhere((s) => s.sessionId == session.sessionId);
      await _upsync.saveQueue(queue);

      // 큐에서 빠져도 이력은 남는다 — 올린 시각만 표시해 둔다.
      unawaited(
        _repo.updateSession(
          session.sessionId,
          (s) => s.copyWith(
            uploadedAtMs: DateTime.now().millisecondsSinceEpoch,
            endedAtMs: session.endedAtMs,
          ),
        ),
      );

      if (!mounted) return;
      final unassigned = result.unassignedDevices.length;
      setState(() {
        _upsyncStatus = '업로드 완료 — 신규 ${result.accepted}건'
            '${result.duplicated > 0 ? ' · 중복 ${result.duplicated}건' : ''}'
            '${result.rejected > 0 ? ' · 거부 ${result.rejected}건' : ''}'
            '${unassigned > 0 ? ' · 명단 연결 필요한 기기 $unassigned대' : ''}';
        _upsyncTone = JamminStatusTone.success;
      });
    } on UpsyncException catch (e) {
      if (!mounted) return;
      setState(() {
        _upsyncStatus = e.message; // 큐는 그대로 남는다 — 나중에 다시 시도할 수 있다
        _upsyncTone = JamminStatusTone.error;
      });
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
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
      onAttempt: _onAttempt,
      onClientCountChanged: (count) {
        if (mounted) setState(() => _connectedCount = count);
      },
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
    final startedAtMs = DateTime.now().millisecondsSinceEpoch;
    setState(() {
      _hub = hub;
      _sessionKey = key;
      _pairing = payload;
      _pending = PendingSession(
        sessionId: sessionId,
        startedAtMs: startedAtMs,
      );
    });
    // 업싱크 큐와 별개로, 이 수업을 이력으로 남긴다
    // (큐는 업로드가 성공하면 비워지지만 이력은 남아야 한다).
    unawaited(
      _repo.saveSession(
        TeacherSession(sessionId: sessionId, startedAtMs: startedAtMs),
      ),
    );
  }

  Future<void> _stopHub() async {
    final sessionId = _pending?.sessionId;
    await _hub?.stop();
    if (sessionId != null) {
      unawaited(
        _repo.updateSession(
          sessionId,
          (s) => s.copyWith(endedAtMs: DateTime.now().millisecondsSinceEpoch),
        ),
      );
    }
    setState(() {
      _hub = null;
      _pairing = null;
      _sessionKey = null;
      _connectedCount = 0;
    });
  }

  DictationRepository get _repo => ref.read(dictationRepositoryProvider);

  /// 받은 답안을 이력으로 남기고 이 수업에 묶는다.
  /// 저장 실패가 수업 진행을 막지 않는다(화면은 이미 제출을 보여줬다).
  Future<void> _recordAttempt(AttemptSubmitPayload attempt) async {
    try {
      await _repo.saveReceivedAttempt(
        attemptId: attempt.attemptId,
        itemId: attempt.itemId,
        deviceBindingId: attempt.deviceBindingId,
        rawAnswer: attempt.rawAnswer,
        correctCount: attempt.correctCount,
        totalCount: attempt.totalCount,
        submittedAtMs: attempt.submittedAtMs,
        inputKind: attempt.inputKind,
        matchesJson: attempt.matches == null
            ? null
            : jsonEncode([for (final m in attempt.matches!) m.toJson()]),
      );
      final sessionId = _pending?.sessionId;
      if (sessionId != null) {
        await _repo.updateSession(sessionId, (s) => s.withAttempt(attempt.attemptId));
      }
    } catch (_) {
      // 이력 저장 실패는 수업을 멈추지 않는다
    }
  }

  /// 낸 문제를 이력에 남긴다.
  Future<void> _recordBroadcast(DictationItem item) async {
    try {
      await _repo.savePackage(
        DictationPackage(version: DictationPackage.currentVersion, items: [item]),
      );
      final sessionId = _pending?.sessionId;
      if (sessionId != null) {
        await _repo.updateSession(sessionId, (s) => s.withItem(item.id));
      }
    } catch (_) {
      // 위와 같다
    }
  }

  /// 학생 제출 수신 — 같은 기기·같은 문항이면 최신 것으로 대체.
  void _onAttempt(AttemptSubmitPayload attempt) {
    if (!mounted) return;
    setState(() {
      _attempts.removeWhere(
        (a) => a.deviceBindingId == attempt.deviceBindingId && a.itemId == attempt.itemId,
      );
      _attempts.insert(0, attempt);
    });
    // 인터넷이 없어도 수업은 계속된다. 결과는 기기에 쌓아두고 나중에 올린다.
    _pending?.addAttempt(attempt);
    unawaited(_persistQueue());
    unawaited(_recordAttempt(attempt));
  }

  Future<void> _broadcast() async {
    final hub = _hub;
    final key = _sessionKey;
    if (hub == null || key == null) return;
    final text = _sentence.text.trim();
    if (text.isEmpty) return;
    try {
      // 분해는 기기에서 한다 — 교실에 인터넷이 없어도 출제되어야 한다. DictationComposer 주석 참조.
      // 한 줄이 한 문항이다 — 받아쓰기 수업은 보통 열 문항쯤을 한 번에 낸다.
      final items = DictationComposer.composeAll(text, hideRule: _hideRule);
      final pkg = DictationPackage(version: DictationPackage.currentVersion, items: items);
      ref.read(dictationPackageProvider.notifier).state = pkg;
      for (final item in items) {
        _pending?.addItem(item);
      }
      unawaited(_persistQueue());
      for (final item in items) {
        unawaited(_recordBroadcast(item));
      }
      await hub.broadcastEncrypted(
        type: SyncMessageTypes.dictationPackage,
        plainBytes: pkg.toUtf8Bytes(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${items.length}문항을 학생 기기로 암호화 전송했습니다.'
              '${_hideRule.hasEffect ? " (${_hideRule.mode.label} 가림)" : ""}',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('출제 실패: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 오답 노트가 넘긴 규칙이 있으면 집어 든다(한 번만).
    final handed = ref.watch(pendingHideRuleProvider);
    if (handed != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _hideRule = handed);
        ref.read(pendingHideRuleProvider.notifier).state = null;
      });
    }

    return JamminScaffold(
      titleWidget: const JamminBrandTitle(subtitle: '교사'),
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
            heading: '교실 허브',
            subheading: '학생과 같은 Wi-Fi에서 QR로 연결합니다. 세션 키는 QR로만 교환됩니다.',
          ),
          const SizedBox(height: 24),
          TextField(
            // Key 는 통합 테스트가 필드를 찾는 안정된 손잡이다(라벨 문구는 바뀔 수 있다).
            key: TeacherHomeKeys.hostOverride,
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
                key: TeacherHomeKeys.startHub,
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
            // key 에 세션 id 를 주어, 새 수업을 열면 "연결 정보 보기"가 다시 접힌다.
            PairingInfoCard(
              key: ValueKey(_pairing!.sessionId),
              pairing: _pairing!,
            ),
          ],
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 24),
          const JamminSectionHeader(
            heading: '받아쓰기 출제',
            subheading: '한 줄에 한 문항씩 적고 학생 기기로 전송합니다. '
                '문장 목록을 그대로 붙여넣어도 됩니다.',
            center: false,
          ),
          const SizedBox(height: 16),
          TextField(
            key: TeacherHomeKeys.sentence,
            controller: _sentence,
            // 받아쓰기는 보통 열 문항쯤을 한 번에 낸다 — 한 줄 = 한 문항.
            maxLines: null,
            minLines: 4,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              labelText: '받아쓰기 정답 문장 (한 줄에 하나)',
              helperMaxLines: 2,
              helperText: '한 문장 ${DictationComposer.maxGlyphsPerItem}글자까지 · '
                  '학습지 전체 ${DictationComposer.maxTotalRows}줄까지',
            ),
          ),
          const SizedBox(height: 8),
          HideRulePicker(
            value: _hideRule,
            onChanged: (r) => setState(() => _hideRule = r),
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: TeacherHomeKeys.broadcast,
            onPressed: _hub != null ? _broadcast : null,
            child: const Text('문제 전송 (암호화)'),
          ),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () => context.push('/practice'),
            child: const Text('이 기기에서 미리보기'),
          ),
          if (_hub != null) ...[
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 24),
            _buildSubmissionBoard(context),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 24),
            _buildUpsyncPanel(context),
          ],
        ],
      ),
    );
  }

  /// 수업이 끝난 뒤 결과를 종합 서버로 올린다. 비워두면 교실 모드만 쓰는 것이고, 그래도 수업은 완결된다.
  Widget _buildUpsyncPanel(BuildContext context) {
    final pendingCount = _pending?.attempts.length ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const JamminSectionHeader(
          heading: '서버로 올리기 (선택)',
          subheading: '수업이 끝난 뒤 결과를 성적부로 보냅니다. 인터넷이 없으면 기기에 보관했다가 나중에 올릴 수 있습니다.\n'
              '서버 주소는 같은 망의 주소(http://192.168.0.10:8100)도, 외부 주소도 됩니다.',
          center: false,
        ),
        const SizedBox(height: 16),
        TextField(
          key: TeacherHomeKeys.serverUrl,
          controller: _serverUrl,
          decoration: const InputDecoration(
            labelText: '서버 주소',
            hintText: 'http://192.168.0.10:8100',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: TeacherHomeKeys.serverToken,
          controller: _serverToken,
          obscureText: true,
          decoration: const InputDecoration(labelText: '교사 토큰'),
        ),
        const SizedBox(height: 12),
        TextField(
          key: TeacherHomeKeys.classroomId,
          controller: _classroomId,
          decoration: const InputDecoration(labelText: '학급 ID'),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            FilledButton(
              key: TeacherHomeKeys.uploadNow,
              onPressed: _uploading || pendingCount == 0 ? null : _uploadNow,
              child: Text(_uploading ? '올리는 중…' : '지금 올리기 ($pendingCount건)'),
            ),
          ],
        ),
        if (_upsyncStatus != null) ...[
          const SizedBox(height: 16),
          JamminStatusBanner(message: _upsyncStatus!, tone: _upsyncTone),
        ],
      ],
    );
  }

  Widget _buildSubmissionBoard(BuildContext context) {
    final average = _attempts.isEmpty
        ? null
        : _attempts.map((a) => a.scorePercent).reduce((a, b) => a + b) / _attempts.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        JamminSectionHeader(
          heading: '제출 현황',
          subheading: '접속 학생 $_connectedCount명 · 제출 ${_attempts.length}건'
              '${average == null ? '' : ' · 평균 ${average.round()}점'}',
          center: false,
        ),
        const SizedBox(height: 16),
        if (_attempts.isEmpty)
          const JamminStatusBanner(
            message: '아직 제출이 없습니다. 학생이 채점 후 제출하면 여기에 표시됩니다.',
          )
        else
          for (final attempt in _attempts) ...[
            _buildAttemptTile(context, attempt),
            const SizedBox(height: 8),
          ],
      ],
    );
  }

  Widget _buildAttemptTile(BuildContext context, AttemptSubmitPayload attempt) {
    final isPerfect = attempt.totalCount > 0 && attempt.correctCount == attempt.totalCount;
    final at = DateTime.fromMillisecondsSinceEpoch(attempt.submittedAtMs);
    final hhmm = '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    final who = attempt.studentName?.trim().isNotEmpty == true
        ? attempt.studentName!
        : '학생 ${_shortId(attempt.deviceBindingId)}';

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isPerfect ? JamminTokens.success : JamminTokens.accent,
          child: Text(
            '${attempt.scorePercent}',
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
        title: Text('$who · ${attempt.correctCount}/${attempt.totalCount}글자'),
        subtitle: Text(
          '“${attempt.rawAnswer}” (정답: ${attempt.expectedText}) · $hhmm',
        ),
      ),
    );
  }

  static String _shortId(String deviceBindingId) {
    if (deviceBindingId.length <= 6) return deviceBindingId;
    return deviceBindingId.substring(0, 6);
  }
}
