import 'package:chominjungum/services/dictation_speaker.dart';
import 'package:flutter_test/flutter_test.dart';

/// 문제 읽어 주기 — 플랫폼 척도 변환과 실패 삼키기.
///
/// 실제 발화는 기기 엔진이 하는 일이라 여기서 검증할 수 없다. 대신 **우리가
/// 책임지는 부분**을 잠근다: 속도 척도 변환과, 엔진이 없어도 앱이 멈추지 않는 것.
void main() {
  group('속도 척도 — 플랫폼마다 기준이 다르다', () {
    test('iOS 는 같은 값을 더 느리게 잡는다', () {
      // iOS 0~1 에서 0.5 가 보통, Android 는 1.0 이 보통이다.
      // 같은 숫자를 그대로 넘기면 두 기기에서 전혀 다르게 들린다.
      final ios = DictationSpeaker.platformRate(0.5, isIOS: true);
      final android = DictationSpeaker.platformRate(0.5, isIOS: false);
      expect(ios, lessThan(android));
    });

    test('경계를 벗어난 값은 잘린다', () {
      expect(DictationSpeaker.platformRate(-1, isIOS: true), 0.0);
      expect(DictationSpeaker.platformRate(9, isIOS: true), closeTo(0.6, 1e-9));
      expect(DictationSpeaker.platformRate(9, isIOS: false), closeTo(1.6, 1e-9));
    });

    test('느릴수록 작은 값 — 단조 증가', () {
      final rates = DictationSpeaker.presets.values.toList();
      for (var i = 1; i < rates.length; i++) {
        expect(
          DictationSpeaker.platformRate(rates[i], isIOS: true),
          greaterThan(DictationSpeaker.platformRate(rates[i - 1], isIOS: true)),
        );
      }
    });

    test('기본값은 "천천히" — 초등 받아쓰기는 또박또박 읽는다', () {
      expect(DictationSpeaker.defaultRate, DictationSpeaker.presets['천천히']);
    });
  });

  group('엔진이 없어도 앱은 멈추지 않는다', () {
    test('빈 문장은 아무 일도 하지 않는다', () async {
      final s = DictationSpeaker(engine: _ThrowingTts());
      await s.speak('   ');
      expect(s.isSpeaking, isFalse);
    });

    test('엔진이 던지면 available 이 꺼지고 예외는 새어 나오지 않는다', () async {
      final s = DictationSpeaker(engine: _ThrowingTts());
      await s.speak('학교'); // 예외를 던지면 이 테스트가 실패한다
      expect(s.isAvailable, isFalse,
          reason: '실패를 기억해야 UI 가 버튼을 감출 수 있다');
      // 꺼진 뒤에는 더 시도하지 않는다.
      await s.speak('친구');
      await s.stop();
    });
  });
}

/// 모든 호출이 실패하는 엔진. TTS 가 없는 기기·시뮬레이터를 흉내낸다.
class _ThrowingTts implements TtsEngine {
  @override
  Future<void> setLanguage(String language) async => throw StateError('TTS 없음');
  @override
  Future<void> setSpeechRate(double rate) async => throw StateError('TTS 없음');
  @override
  Future<void> awaitSpeakCompletion(bool await_) async =>
      throw StateError('TTS 없음');
  @override
  Future<void> speak(String text) async => throw StateError('TTS 없음');
  @override
  Future<void> stop() async => throw StateError('TTS 없음');
}
