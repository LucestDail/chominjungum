import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/dictation_models.dart';
import '../../providers/dictation_providers.dart';
import '../../theme/jammin_tokens.dart';
import '../../widgets/hangul_writing_worksheet.dart';
import '../../widgets/jammin/jammin_brand_title.dart';
import '../../widgets/jammin/jammin_print_header.dart';
import '../../widgets/jammin/jammin_scaffold.dart';
import '../../widgets/jammin/jammin_worksheet_box.dart';

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
          tooltip: _dictationMode ? '획순 가이드 보기' : '받아쓰기 모드 (빈칸)',
          icon: Icon(_dictationMode ? Icons.visibility_outlined : Icons.visibility_off_outlined),
          onPressed: () => setState(() => _dictationMode = !_dictationMode),
        ),
        IconButton(
          tooltip: '서버에서 다시 불러오기',
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
                              child: Text(
                                '${index + 1}. ${item.expectedText} (${glyphs.length}칸)',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            HangulWritingWorksheet(
                              key: _keyForIndex(index),
                              text: item.expectedText,
                              glyphs: glyphs,
                              showGlyphGuides: true,
                              guideOpacity: _guideOpacity,
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
