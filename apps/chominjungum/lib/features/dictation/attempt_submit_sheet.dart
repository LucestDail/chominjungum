import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hangul_core/hangul_core.dart';
import 'package:sync_protocol/sync_protocol.dart';
import 'package:uuid/uuid.dart';

import '../../domain/dictation_models.dart';
import '../../providers/dictation_providers.dart';
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
    setState(() {
      _results[index] = DictationCompare.score(
        expected: item.expectedText,
        actual: answer,
      );
      _submitted.remove(index);
      _status = null;
    });
  }

  Future<void> _submit(int index, DictationItem item) async {
    final result = _results[index];
    final client = ref.read(studentHubClientProvider);
    if (result == null || client == null) return;

    final deviceId = await ref.read(deviceBindingIdProvider.future);
    final payload = AttemptSubmitPayload(
      attemptId: const Uuid().v4(),
      itemId: item.id,
      expectedText: item.expectedText,
      rawAnswer: _controllerFor(index).text.trim(),
      deviceBindingId: deviceId,
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
              _GlyphChip(
                label: m.expected?.word ?? m.actual?.word ?? '?',
                isCorrect: m.isCorrect,
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

class _GlyphChip extends StatelessWidget {
  const _GlyphChip({required this.label, required this.isCorrect});

  final String label;
  final bool isCorrect;

  @override
  Widget build(BuildContext context) {
    final color = isCorrect ? JamminTokens.success : JamminTokens.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(JamminTokens.radiusSm),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(color: color, fontSize: 16)),
          const SizedBox(width: 4),
          Icon(isCorrect ? Icons.check : Icons.close, size: 14, color: color),
        ],
      ),
    );
  }
}
