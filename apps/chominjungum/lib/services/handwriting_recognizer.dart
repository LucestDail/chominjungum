import 'handwriting_ink.dart';

/// 손글씨 인식기 — **실행을 갈아 끼울 수 있는 자리**.
///
/// ## 왜 인터페이스부터인가 (2026-09-16)
///
/// 수단은 **ML Kit Digital Ink** 로 정했다(양 플랫폼·한국어 `ko`). 그런데 그 네이티브
/// 의존성을 붙이면 **iOS 시뮬레이터 빌드가 깨지고**, 이 저장소는 실기기가 한 대뿐이라
/// 유일한 잔여 과제인 **교실 2대 리허설을 시뮬레이터 허브로** 치러야 한다.
///
/// ⇒ 사용자 결정(2026-09-16): **기본 구현을 먼저 하고, 네이티브는 리허설이 끝난 뒤**.
/// 그래서 오늘은 좌표를 다루는 부분과 이 계약까지만 만든다 — 그러면 그때 꽂을 때
/// **잃을 것이 없다.**
///
/// 🔴 이 파일은 **네이티브를 import 하지 않는다.** 여기 무언가를 import 하는 순간
/// 시뮬레이터가 깨지고, 그것이 정확히 미루기로 한 이유다.
abstract class HandwritingRecognizer {
  /// 이 기기에서 쓸 수 있는가 — 모델이 내려받아져 있는가까지 포함한다.
  ///
  /// ⚠️ "설치돼 있다" 와 "쓸 수 있다" 는 다르다. ML Kit 은 언어 모델을
  /// **따로 내려받아야** 하고, 교실에 인터넷이 없으면 그 시점에 실패한다.
  Future<bool> isAvailable();

  /// 잉크를 글자로. 자신 있는 순서대로 최대 [maxCandidates] 개.
  ///
  /// ⚠️ **틀릴 수 있다는 전제로 쓴다.** 받아쓰기 채점을 이걸로 하면 안 된다 —
  /// 채점은 지금처럼 `DictationCompare` 가 타이핑 입력으로 한다. 이건 **보조**다.
  Future<HandwritingResult> recognize(
    HandwritingInk ink, {
    int maxCandidates = 3,
  });
}

/// 결과 — 성공·실패를 **예외가 아니라 값으로** 낸다.
/// 교실에서 예외가 화면을 덮으면 수업이 멈춘다.
class HandwritingResult {
  const HandwritingResult._(this.candidates, this.error);

  factory HandwritingResult.success(List<String> candidates) =>
      HandwritingResult._(candidates, null);
  factory HandwritingResult.failure(String message) =>
      HandwritingResult._(const [], message);

  /// 자신 있는 순서. 비어 있을 수 있다.
  final List<String> candidates;
  final String? error;

  bool get ok => error == null;

  String? get best => candidates.isEmpty ? null : candidates.first;

  /// ⚠️ **불렀는데 후보가 0개**인 경우 — 성공으로 보여 주면 사용자는 이유를 모른다.
  bool get isEmptyAfterRecognize => ok && candidates.isEmpty;
}

/// 기본 구현 — **아직 없다고 정직하게 답한다.**
///
/// 🔴 여기서 "빈 결과 + 성공" 을 내면 안 된다. 그러면 화면은 "인식했는데 아무것도 없다"
/// 로 보이고, 사용자는 자기 글씨가 나쁜 줄 안다. **없는 것은 없다고 말한다.**
class UnavailableHandwritingRecognizer implements HandwritingRecognizer {
  const UnavailableHandwritingRecognizer();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<HandwritingResult> recognize(
    HandwritingInk ink, {
    int maxCandidates = 3,
  }) async =>
      HandwritingResult.failure('이 빌드에는 손글씨 인식이 포함되어 있지 않습니다');
}
