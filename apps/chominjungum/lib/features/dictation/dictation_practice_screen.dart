import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hangul_core/hangul_core.dart';

import '../../domain/dictation_models.dart';
import '../../providers/dictation_providers.dart';
import '../../services/device_binding_id.dart';
import '../../services/ocr_service.dart';
import '../../widgets/stroke_canvas.dart';
import '../../widgets/stroke_raster.dart';

/// 받아쓰기 MVP: 키보드 채점 + 캔버스/갤러리 OCR → [hangul_core] 채점.
class DictationPracticeScreen extends ConsumerStatefulWidget {
  const DictationPracticeScreen({super.key});

  @override
  ConsumerState<DictationPracticeScreen> createState() => _DictationPracticeScreenState();
}

class _DictationPracticeScreenState extends ConsumerState<DictationPracticeScreen> {
  final _keyboard = TextEditingController();
  List<List<Offset>> _strokes = [];
  int _canvasKey = 0;
  DictationScoreResult? _keyboardScore;
  DictationScoreResult? _ocrScore;
  String? _ocrText;
  bool _busy = false;

  DictationItem _itemFromPackage(DictationPackage? pkg) {
    if (pkg != null && pkg.items.isNotEmpty) {
      return pkg.items.first;
    }
    return DictationItem.fromExpectedText('가나다');
  }

  Future<void> _scoreKeyboard() async {
    final item = _itemFromPackage(ref.read(dictationPackageProvider));
    final r = DictationCompare.score(
      expected: item.expectedText,
      actual: _keyboard.text.trim(),
    );
    setState(() => _keyboardScore = r);
  }

  Future<void> _scoreCanvasOcr() async {
    setState(() {
      _busy = true;
      _ocrScore = null;
      _ocrText = null;
    });
    try {
      final item = _itemFromPackage(ref.read(dictationPackageProvider));
      final size = const Size(800, 400);
      final png = await strokesToPng(strokes: _strokes, size: size);
      if (png == null || png.isEmpty) {
        setState(() => _busy = false);
        return;
      }
      final text = await OcrService.recognizePngBytes(
        png,
        width: size.width.ceil(),
        height: size.height.ceil(),
      );
      final r = DictationCompare.score(
        expected: item.expectedText,
        actual: text.replaceAll(RegExp(r'\s+'), ''),
      );
      setState(() {
        _ocrText = text;
        _ocrScore = r;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scoreGalleryOcr() async {
    setState(() => _busy = true);
    try {
      final item = _itemFromPackage(ref.read(dictationPackageProvider));
      final text = await OcrService.pickAndRecognizeGallery();
      if (text == null || !mounted) return;
      final r = DictationCompare.score(
        expected: item.expectedText,
        actual: text.replaceAll(RegExp(r'\s+'), ''),
      );
      setState(() {
        _ocrText = text;
        _ocrScore = r;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _keyboard.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pkg = ref.watch(dictationPackageProvider);
    final item = _itemFromPackage(pkg);
    return Scaffold(
      appBar: AppBar(title: const Text('받아쓰기')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('정답(출제)', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(item.expectedText, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          FutureBuilder(
            future: DeviceBindingId.getOrCreate(),
            builder: (context, snap) {
              final id = snap.data;
              if (id == null) return const SizedBox.shrink();
              return Text('기기 바인딩 ID: $id', style: Theme.of(context).textTheme.bodySmall);
            },
          ),
          const Divider(height: 32),
          Text('키보드 입력', style: Theme.of(context).textTheme.titleMedium),
          TextField(
            controller: _keyboard,
            decoration: const InputDecoration(labelText: '답안'),
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _scoreKeyboard, child: const Text('키보드 채점')),
          if (_keyboardScore != null) _scoreCard('키보드', _keyboardScore!),
          const Divider(height: 32),
          Text('손글씨 (캔버스 → OCR)', style: Theme.of(context).textTheme.titleMedium),
          SizedBox(
            height: 200,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).colorScheme.outline),
                borderRadius: BorderRadius.circular(16),
              ),
              child: StrokeCanvas(
                key: ValueKey(_canvasKey),
                onStrokesChanged: (s) => setState(() => _strokes = s),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton.tonal(
                onPressed: _busy ? null : _scoreCanvasOcr,
                child: const Text('캔버스 OCR 채점'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => setState(() {
                  _strokes = [];
                  _canvasKey++;
                }),
                child: const Text('지우기'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: _busy ? null : _scoreGalleryOcr,
            child: const Text('갤러리 이미지 OCR 채점'),
          ),
          if (_ocrText != null) ...[
            const SizedBox(height: 8),
            Text('OCR 텍스트: $_ocrText'),
          ],
          if (_ocrScore != null) _scoreCard('OCR', _ocrScore!),
          if (_busy) const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      ),
    );
  }

  Widget _scoreCard(String label, DictationScoreResult r) {
    if (r.error != null) {
      return Card(
        child: ListTile(title: Text(label), subtitle: Text(r.error!)),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$label 점수: ${r.scorePercent}% (${r.correctCount}/${r.totalCount})'),
            if (r.hasExtraInput) const Text('입력이 더 깁니다.', style: TextStyle(color: Colors.orange)),
            const SizedBox(height: 8),
            ...r.matches.take(12).map(
                  (m) => Text(
                    '#${m.index + 1} ${m.isCorrect ? "✓" : "✗"} ${m.mismatchReason ?? ""}',
                    style: TextStyle(
                      color: m.isCorrect
                          ? Theme.of(context).colorScheme.secondary
                          : Theme.of(context).colorScheme.tertiary,
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
