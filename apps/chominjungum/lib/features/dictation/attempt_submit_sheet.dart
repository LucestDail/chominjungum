import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hangul_core/hangul_core.dart';
import 'package:sync_protocol/sync_protocol.dart';
import 'package:uuid/uuid.dart';

import '../../domain/dictation_models.dart';
import '../../providers/dictation_providers.dart';
import '../../services/student_profile.dart';
import 'glyph_result_chip.dart';
import '../../theme/jammin_tokens.dart';
import '../../widgets/jammin/jammin_status_banner.dart';

/// 답안 입력 → 온디바이스 채점 → (허브 연결 시) 교사에게 제출.
class AttemptSubmitSheet extends ConsumerStatefulWidget {
  const AttemptSubmitSheet({super.key, required this.package});

  final DictationPackage package;

  static Future<void> show(BuildContext context, DictationPackage package) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: JamminTokens.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(JamminTokens.radiusLg)),
      ),
      builder: (_) => AttemptSubmitSheet(package: package),
    );
  }

  @override
  ConsumerState<AttemptSubmitSheet> createState() => _AttemptSubmitSheetState();
}

class _AttemptSubmitSheetState extends ConsumerState<AttemptSubmitSheet> {
  final _controllers = <int, TextEditingController>{};
  final _results = <int, DictationScoreResult>{};
  final _submitted = <int>{};

  /// 문항별 답안 id. 채점할 때 만들어 **로컬 이력과 교사 제출이 같은 id 를 쓰게** 한다
  /// (서버 업싱크가 `attemptId` 로 멱등하므로, 재전송해도 중복이 생기지 않는다).
  final _attemptIds = <int, String>{};

  /// 교사 화면이 "학생 a3f2…" 대신 이름으로 보이게 한다(선택 — 비면 종전대로).
  ///
  /// ⚠️**제출 시점에 읽지 않고 미리 읽어 둔다.** 처음엔 `_submit` 안에서
  /// `await StudentProfile.load()` 를 했는데, 그러면 **제출 경로에 플랫폼 채널 I/O가
  /// 끼어든다** — e2e 테스트가 그 대기에서 멈춰 제출이 아예 나가지 않았다.
  /// 이름 하나 때문에 제출이 느려지거나 막히면 안 된다.
  String? _studentName;

  @override
  void initState() {
    super.initState();
    // 실패해도 무시된다(StudentProfile.load 가 null 을 준다) — 이름은 선택이다.
    StudentProfile.load().then((v) {
      if (mounted) setState(() => _studentName = v);
    });
  }
  String? _status;
  JamminStatusTone _statusTone = JamminStatusTone.info;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(int index) {
    return _controllers.putIfAbsent(index, TextEditingController.new);
  }

  void _score(int index, DictationItem item) {
    final answer = _controllerFor(index).text.trim();
    if (answer.isEmpty) return;
    final result = DictationCompare.score(
      expected: item.expectedText,
      actual: answer,
    );
    // 다시 채점하면 답이 바뀐 것이므로 새 시도로 본다.
    final attemptId = const Uuid().v4();
    setState(() {
      _results[index] = result;
      _attemptIds[index] = attemptId;
      _submitted.remove(index);
      _status = null;
    });
    // 허브에 연결되지 않아도 채점 이력은 남는다.
    unawaited(_persistAttempt(attemptId, item, answer, result));
  }

  /// 제출 시각 기록 — 실패해도 조용히 넘어간다(제출 자체는 이미 성공했다).
  Future<void> _markSubmittedQuietly(String attemptId) async {
    try {
      await ref
          .read(dictationRepositoryProvider)
          .markSubmitted(attemptId, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      // 이력 갱신 실패가 제출 결과를 바꾸지는 않는다
    }
  }

  Future<void> _persistAttempt(
    String attemptId,
    DictationItem item,
    String answer,
    DictationScoreResult result,
  ) async {
    try {
      final deviceId = await ref.read(deviceBindingIdProvider.future);
      await ref.read(dictationRepositoryProvider).saveAttempt(
            DictationAttempt.fromScore(
              id: attemptId,
              itemId: item.id,
              deviceBindingId: deviceId,
              rawAnswer: answer,
              inputKind: AttemptInputKind.keyboard,
              createdAtMs: DateTime.now().millisecondsSinceEpoch,
              score: result,
            ),
          );
    } catch (_) {
      // 저장 실패가 채점·제출을 막아서는 안 된다 (화면은 이미 결과를 보여줬다)
    }
  }

  Future<void> _submit(int index, DictationItem item) async {
    final result = _results[index];
    final client = ref.read(studentHubClientProvider);
    if (result == null || client == null) return;

    final deviceId = await ref.read(deviceBindingIdProvider.future);
    // 채점 때 만든 id 를 그대로 쓴다 (로컬 이력 ↔ 교사 제출 ↔ 서버 업싱크가 같은 키).
    final attemptId = _attemptIds[index] ?? const Uuid().v4();
    final payload = AttemptSubmitPayload(
      attemptId: attemptId,
      itemId: item.id,
      expectedText: item.expectedText,
      rawAnswer: _controllerFor(index).text.trim(),
      deviceBindingId: deviceId,
      studentName: _studentName,
      correctCount: result.correctCount,
      totalCount: result.totalCount,
      submittedAtMs: DateTime.now().millisecondsSinceEpoch,
      // v2: 글자별 정오를 함께 보낸다 — 교사 서버의 취약 자모 분석 원천.
      matches: [
        for (final m in result.matches)
          GlyphMatchSummary(index: m.index, ok: m.isCorrect, why: m.mismatchReason),
      ],
    );

    try {
      await client.sendEncrypted(
        type: SyncMessageTypes.attemptSubmit,
        plainBytes: payload.toUtf8Bytes(),
      );
      // 여기까지 왔으면 제출은 나간 것이다.
      // 이력에 시각을 남기는 건 부수적이므로, 그 실패가 제출 성공을 뒤집지 않게 분리한다
      // (저장소가 없는 환경에서 "제출 실패"로 보이면 사실과 다르다).
      unawaited(_markSubmittedQuietly(attemptId));
      if (!mounted) return;
      setState(() {
        _submitted.add(index);
        _status = '${index + 1}번 답안을 선생님께 제출했습니다.';
        _statusTone = JamminStatusTone.success;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = '제출 실패: $e';
        _statusTone = JamminStatusTone.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = ref.watch(studentHubClientProvider) != null;
    final items = widget.package.items;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => ListView(
        controller: scrollController,
        padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + bottomInset),
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: JamminTokens.borderStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('답안 채점', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            connected
                ? '채점 후 선생님께 제출할 수 있습니다.'
                : '허브에 연결되어 있지 않아 채점만 가능합니다.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: JamminTokens.textMuted,
                ),
          ),
          if (_status != null) ...[
            const SizedBox(height: 16),
            JamminStatusBanner(message: _status!, tone: _statusTone),
          ],
          const SizedBox(height: 20),
          for (var index = 0; index < items.length; index++) ...[
            if (index > 0) const SizedBox(height: 20),
            _buildItemCard(context, index, items[index], connected),
          ],
        ],
      ),
    );
  }

  Widget _buildItemCard(
    BuildContext context,
    int index,
    DictationItem item,
    bool connected,
  ) {
    final result = _results[index];
    final isSubmitted = _submitted.contains(index);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${index + 1}번',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controllerFor(index),
              decoration: const InputDecoration(
                labelText: '내가 쓴 답',
                hintText: '들은 대로 입력하세요',
              ),
              onSubmitted: (_) => _score(index, item),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton(
                  onPressed: () => _score(index, item),
                  child: const Text('채점'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: connected && result != null && !isSubmitted
                      ? () => _submit(index, item)
                      : null,
                  child: Text(isSubmitted ? '제출 완료' : '선생님께 제출'),
                ),
              ],
            ),
            if (result != null) ...[
              const SizedBox(height: 16),
              _buildResult(context, item, result),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResult(
    BuildContext context,
    DictationItem item,
    DictationScoreResult result,
  ) {
    if (result.error != null) {
      return JamminStatusBanner(message: result.error!, tone: JamminStatusTone.error);
    }

    final isPerfect = result.correctCount == result.totalCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              '${result.scorePercent}점',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: isPerfect ? JamminTokens.success : JamminTokens.accent,
                  ),
            ),
            const SizedBox(width: 12),
            Text(
              '${result.correctCount}/${result.totalCount}글자',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: JamminTokens.textMuted,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final m in result.matches)
              GlyphResultChip(
                isCorrect: m.isCorrect,
                expected: m.expected?.word,
                actual: m.actual?.word,
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '정답: ${item.expectedText}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}
