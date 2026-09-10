import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/app_role.dart';
import '../../domain/dictation_models.dart';
import '../../providers/app_role_provider.dart';
import '../../providers/dictation_providers.dart';
import '../../services/dictation_speaker.dart';
import '../../theme/jammin_tokens.dart';
import '../../widgets/hangul_writing_worksheet.dart';
import '../../widgets/jammin/jammin_brand_title.dart';
import '../../widgets/jammin/jammin_print_header.dart';
import '../../widgets/jammin/jammin_scaffold.dart';
import '../../widgets/jammin/jammin_worksheet_box.dart';
import 'attempt_submit_sheet.dart';

/// 테스트가 받아쓰기 화면 요소를 찾는 손잡이.
class DictationPracticeKeys {
  const DictationPracticeKeys._();

  static const dictationMode = Key('practice.dictationMode');
  static const speechRate = Key('practice.speechRate');
  static Key speak(int index) => Key('practice.speak.$index');
}

/// jammin 받아쓰기: 번들/허브 자모 + 지험지 위 손글씨.
class DictationPracticeScreen extends ConsumerStatefulWidget {
  const DictationPracticeScreen({super.key});

  @override
  ConsumerState<DictationPracticeScreen> createState() => _DictationPracticeScreenState();
}

class _DictationPracticeScreenState extends ConsumerState<DictationPracticeScreen> {
  final _worksheetKeys = <GlobalKey<HangulWritingWorksheetState>>[];
  HangulWriteTool _tool = HangulWriteTool.pen;
  bool _dictationMode = false;

  /// 문제 읽어 주기. 받아쓰기는 원래 **듣고 받아 적는** 수업이다.
  final _speaker = DictationSpeaker();
  double _speechRate = DictationSpeaker.defaultRate;

  @override
  void dispose() {
    _speaker.dispose();
    super.dispose();
  }

  GlobalKey<HangulWritingWorksheetState> _keyForIndex(int index) {
    while (_worksheetKeys.length <= index) {
      _worksheetKeys.add(GlobalKey<HangulWritingWorksheetState>());
    }
    return _worksheetKeys[index];
  }

  double get _guideOpacity => _dictationMode ? 0.0 : 0.45;

  @override
  Widget build(BuildContext context) {
    final packageAsync = ref.watch(practicePackageProvider);

    return JamminScaffold(
      titleWidget: const JamminBrandTitle(subtitle: '받아쓰기'),
      denseTop: true,
      actions: [
        IconButton(
          tooltip: '답안 채점·제출',
          icon: const Icon(Icons.fact_check_outlined),
          onPressed: () {
            final pkg = ref.read(practicePackageProvider).valueOrNull;
            if (pkg == null || pkg.items.isEmpty) return;
            AttemptSubmitSheet.show(context, pkg);
          },
        ),
        if (_speaker.isAvailable)
          PopupMenuButton<double>(
            key: DictationPracticeKeys.speechRate,
            tooltip: '읽기 속도',
            icon: const Icon(Icons.speed_outlined),
            initialValue: _speechRate,
            onSelected: (r) => setState(() => _speechRate = r),
            itemBuilder: (_) => [
              for (final e in DictationSpeaker.presets.entries)
                PopupMenuItem(value: e.value, child: Text(e.key)),
            ],
          ),
        IconButton(
          key: DictationPracticeKeys.dictationMode,
          tooltip: _dictationMode ? '획순 가이드 보기' : '받아쓰기 모드 (빈칸)',
          icon: Icon(_dictationMode ? Icons.visibility_outlined : Icons.visibility_off_outlined),
          onPressed: () => setState(() => _dictationMode = !_dictationMode),
        ),
        IconButton(
          tooltip: '오답 노트',
          icon: const Icon(Icons.history_edu_outlined),
          onPressed: () => context.push('/mistakes'),
        ),
        // 🔴학생 기기에서는 **외부로 나가지 않는다.**
        // jammin 서버 갱신은 콘텐츠 제작용이라 교사 빌드에만 둔다. 인터넷 없는
        // 교실에서 학생이 이걸 누르면 실패만 보게 되고, 앱의 전제("중앙 서버
        // 없음")와도 어긋난다. 09-07 에 출제가 이 서버에 묶여 통째로 실패한 적이 있다.
        if (ref.watch(appRoleProvider) == AppRole.teacher)
          IconButton(
            tooltip: '서버에서 다시 불러오기 (교사용)',
            icon: const Icon(Icons.cloud_download_outlined),
            onPressed: () => _refreshFromServer(),
          ),
      ],
      body: packageAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: JamminTokens.brand)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: JamminTokens.danger),
                const SizedBox(height: 16),
                Text('문제를 불러오지 못했습니다', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text('$e', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(bundledDefaultPackageProvider),
                  child: const Text('다시 시도'),
                ),
              ],
            ),
          ),
        ),
        data: (pkg) => _buildWorksheetBody(context, pkg),
      ),
      bottomNavigationBar: packageAsync.maybeWhen(
        data: (_) => _buildToolbar(),
        orElse: () => null,
      ),
    );
  }

  Future<void> _refreshFromServer() async {
    try {
      final pkg = await ref.read(jamminNetworkPackageProvider.future);
      ref.read(dictationPackageProvider.notifier).state = pkg;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('jammin 서버에서 갱신했습니다.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('서버 갱신 실패: $e')),
        );
      }
    }
  }

  Widget _buildWorksheetBody(BuildContext context, DictationPackage package) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const JamminPrintHeader(),
        const SizedBox(height: 8),
        Expanded(
          child: JamminWorksheetBox(
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < package.items.length; index++) ...[
                    if (index > 0) const SizedBox(height: 24),
                    Builder(
                      builder: (context) {
                        final item = package.items[index];
                        final glyphs = dictationItemGlyphs(item);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 4, bottom: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      // 🔴받아쓰기 모드에서는 **정답을 보여주면 안 된다.**
                                      // 밑그림만 지우고 제목에 정답을 적어 두면
                                      // 그건 받아쓰기가 아니라 베껴 쓰기다.
                                      _dictationMode
                                          ? '${index + 1}번 · ${glyphs.length}칸'
                                          : '${index + 1}. ${item.expectedText} '
                                              '(${glyphs.length}칸)',
                                      style:
                                          Theme.of(context).textTheme.titleMedium,
                                    ),
                                  ),
                                  if (_speaker.isAvailable)
                                    IconButton(
                                      key: DictationPracticeKeys.speak(index),
                                      tooltip: '문제 듣기',
                                      icon: const Icon(Icons.volume_up_outlined),
                                      onPressed: () => _speaker.speak(
                                        item.expectedText,
                                        rate: _speechRate,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            HangulWritingWorksheet(
                              key: _keyForIndex(index),
                              text: item.expectedText,
                              glyphs: glyphs,
                              showGlyphGuides: true,
                              guideOpacity: _guideOpacity,
                              hideRule: item.hideRule,
                              tool: _tool,
                              onInteraction: () => setState(() {}),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget? _buildToolbar() {
    HangulWritingWorksheetState? selectedSheet;
    for (final key in _worksheetKeys) {
      final state = key.currentState;
      if (state?.selectedCell != null) {
        selectedSheet = state;
        break;
      }
    }

    return HangulWritingToolbar(
      tool: _tool,
      onToolChanged: (t) => setState(() => _tool = t),
      hasSelection: selectedSheet?.selectedCell != null,
      onClearSelected: () {
        final idx = selectedSheet?.selectedCell;
        if (idx != null) selectedSheet?.clearCell(idx);
      },
      onClearAll: () {
        for (final key in _worksheetKeys) {
          key.currentState?.clearAll();
        }
      },
    );
  }
}
