import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hangul_core/hangul_core.dart';

import '../../providers/dictation_providers.dart';
import '../../services/mistake_analysis.dart';
import '../../theme/jammin_tokens.dart';
import '../../widgets/jammin/jammin_brand_title.dart';
import '../../widgets/jammin/jammin_scaffold.dart';
import '../../widgets/jammin/jammin_section.dart';

class MistakeNoteKeys {
  const MistakeNoteKeys._();

  static const empty = Key('mistake.empty');
  static const jamoList = Key('mistake.jamo');
  static const syllableList = Key('mistake.syllables');
  static const makeWorksheet = Key('mistake.makeWorksheet');
}

/// 오답 노트 — **기기에 쌓인 답안만으로** 약한 자모·글자를 보여준다.
///
/// 서버도 AI 도 쓰지 않는다. 채점이 이미 글자별 정오를 남기므로, 정답의 자모
/// 분해와 겹치면 취약점이 나온다.
///
/// ⚠️화면에서 **근사라는 것을 밝힌다.** 채점이 음절 단위라 "이 자모를 틀렸다"가
/// 아니라 "이 자모가 든 글자를 자주 틀린다"이다. 과장하면 교사가 잘못된 처방을 한다.
class MistakeNoteScreen extends ConsumerWidget {
  const MistakeNoteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(dictationRepositoryProvider);
    final analysis = MistakeAnalysis.of(
      attempts: repo.attempts(),
      items: repo.loadItems(),
    );

    return JamminScaffold(
      titleWidget: const JamminBrandTitle(subtitle: '오답 노트'),
      body: analysis.isEmpty
          ? const _Empty()
          : ListView(
              children: [
                JamminSectionHeader(
                  heading: '자주 틀리는 자모',
                  subheading: '답안 ${analysis.gradedAttempts}개 · '
                      '글자 ${analysis.gradedSyllables}자를 봤습니다',
                ),
                const SizedBox(height: 8),
                _Caveat(),
                const SizedBox(height: 12),
                if (analysis.jamo.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('아직 표본이 적어 약한 자모를 고르지 않았습니다.'),
                  )
                else
                  Wrap(
                    key: MistakeNoteKeys.jamoList,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final w in analysis.jamo) _JamoChip(w),
                    ],
                  ),
                const SizedBox(height: 24),
                const JamminSectionHeader(heading: '자주 틀리는 글자'),
                const SizedBox(height: 8),
                if (analysis.syllables.isEmpty)
                  const Text('아직 없습니다.')
                else
                  Column(
                    key: MistakeNoteKeys.syllableList,
                    children: [
                      for (final s in analysis.syllables) _SyllableRow(s),
                    ],
                  ),
                const SizedBox(height: 24),
                if (analysis.jamo.isNotEmpty)
                  FilledButton.icon(
                    key: MistakeNoteKeys.makeWorksheet,
                    icon: const Icon(Icons.edit_note_outlined),
                    label: const Text('약한 자모만 가린 학습지 만들기'),
                    onPressed: () =>
                        _handOff(context, ref, analysis.toHideRule()),
                  ),
                const SizedBox(height: 32),
              ],
            ),
    );
  }

  /// 취약 자모를 그대로 **출제 가리기 규칙**으로 넘긴다.
  /// 오답 노트가 "보기만 하는 화면"으로 끝나지 않게 하는 것이 요점이다.
  void _handOff(BuildContext context, WidgetRef ref, HideRule rule) {
    ref.read(pendingHideRuleProvider.notifier).state = rule;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${rule.mode.label} ${rule.codes.length}자를 가리도록 출제 화면에 담았습니다.',
        ),
      ),
    );
    Navigator.of(context).maybePop();
  }
}

class _Caveat extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Text(
        '채점은 글자 단위라, 아래는 "이 자모가 든 글자를 자주 틀렸다"는 뜻입니다. '
        '어디를 더 연습할지 고르는 데 쓰세요.',
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: JamminTokens.textMuted),
      );
}

class _JamoChip extends StatelessWidget {
  const _JamoChip(this.w);
  final JamoWeakness w;

  @override
  Widget build(BuildContext context) {
    final pct = (w.errorRate * 100).round();
    return Chip(
      label: Text('${w.letter}  $pct%  (${w.wrong}/${w.total})'),
      backgroundColor: pct >= 50
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.surfaceContainerHighest,
    );
  }
}

class _SyllableRow extends StatelessWidget {
  const _SyllableRow(this.s);
  final SyllableWeakness s;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              s.syllable,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Expanded(
            child: Text(
              s.wroteInstead.isEmpty
                  ? '${s.wrong}번 틀림'
                  : '${s.wrong}번 틀림 · ${s.syllable}→${s.wroteInstead.join("·")}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Center(
        key: MistakeNoteKeys.empty,
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            '채점한 답안이 아직 없습니다.\n받아쓰기를 풀고 채점하면 여기에 쌓입니다.',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: JamminTokens.textMuted),
          ),
        ),
      );
}
