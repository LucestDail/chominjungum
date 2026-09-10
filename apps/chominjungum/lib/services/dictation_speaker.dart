import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// 받아쓰기 문제 **읽어 주기**.
///
/// ## 왜 필요한가
///
/// 받아쓰기는 원래 **선생님이 읽어 주고 학생이 받아 적는** 수업이다. 지금 앱은
/// 문장을 화면에 보여 주는데, 그러면 그건 받아쓰기가 아니라 베껴 쓰기다.
/// 교사가 직접 읽는 것이 기본이지만, 읽어 주는 기능이 있으면
///
///   - 학생이 **자기 속도로 다시 들을** 수 있고(교사가 스무 번 반복하지 않아도 된다)
///   - 혼자 연습할 때도 받아쓰기가 성립한다
///
/// ## 속도
///
/// 초등 저학년 받아쓰기는 **또박또박 천천히** 읽는다. 기본값을 느리게 두고
/// 교사·학생이 조절할 수 있게 한다. ⚠️`flutter_tts` 의 `speechRate` 는
/// **플랫폼마다 척도가 다르다** — iOS 는 0~1 에서 0.5 가 보통이고 Android 는
/// 1.0 이 보통이다. 그래서 0~1 의 "우리 척도"를 받아 플랫폼 값으로 바꾼다.
///
/// ## 실패는 조용히
///
/// TTS 엔진이 없는 기기·시뮬레이터가 있다. 읽기는 **보조 기능**이므로 실패해도
/// 수업이 멈추면 안 된다 — 예외를 삼키고 `isAvailable` 로만 알린다.
/// (학생 이름에서 배운 것과 같다: 선택 기능이 핵심 경로를 막으면 안 된다.)
class DictationSpeaker {
  DictationSpeaker({TtsEngine? engine}) : _tts = engine ?? FlutterTtsEngine();

  final TtsEngine _tts;

  bool _ready = false;
  bool _available = true;
  bool _speaking = false;

  /// 엔진이 쓸 만한가. 한 번이라도 실패하면 false 가 되고 UI 가 버튼을 감춘다.
  bool get isAvailable => _available;
  bool get isSpeaking => _speaking;

  /// 우리 척도 0.0(아주 느리게) ~ 1.0(보통 속도보다 빠르게). 기본은 또박또박.
  static const double defaultRate = 0.35;

  /// 초등 받아쓰기에서 쓸 만한 단계. 화면에 그대로 노출한다.
  static const Map<String, double> presets = {
    '아주 느리게': 0.2,
    '천천히': 0.35,
    '보통': 0.55,
  };

  /// 우리 척도(0~1) → 플랫폼 `speechRate`.
  ///
  /// iOS 는 0.5 근방이 사람이 듣기에 "보통"이고 1.0 은 알아듣기 힘들 만큼 빠르다.
  /// Android 는 1.0 이 보통이다. 같은 숫자를 넘기면 두 기기에서 전혀 다르게 들린다.
  @visibleForTesting
  static double platformRate(double rate, {required bool isIOS}) {
    final r = rate.clamp(0.0, 1.0);
    return isIOS ? r * 0.6 : r * 1.6;
  }

  Future<void> _ensureReady(double rate) async {
    try {
      final isIOS = defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS;
      if (!_ready) {
        await _tts.setLanguage('ko-KR');
        // 읽기가 끝날 때까지 기다릴 수 있어야 "다시 듣기"가 겹치지 않는다.
        await _tts.awaitSpeakCompletion(true);
        _ready = true;
      }
      await _tts.setSpeechRate(platformRate(rate, isIOS: isIOS));
    } catch (_) {
      _available = false;
    }
  }

  /// 한 문장을 읽는다. 이미 읽는 중이면 **멈추고 새로 읽는다**
  /// (학생이 "다시" 를 연타해도 겹쳐 들리지 않는다).
  Future<void> speak(String text, {double rate = defaultRate}) async {
    final t = text.trim();
    if (t.isEmpty || !_available) return;
    await _ensureReady(rate);
    if (!_available) return;
    try {
      if (_speaking) await _tts.stop();
      _speaking = true;
      await _tts.speak(t);
    } catch (_) {
      _available = false;
    } finally {
      _speaking = false;
    }
  }

  Future<void> stop() async {
    if (!_available) return;
    try {
      await _tts.stop();
    } catch (_) {
      // 멈추기 실패는 무시한다 — 다음 speak 가 어차피 stop 을 먼저 부른다.
    } finally {
      _speaking = false;
    }
  }

  Future<void> dispose() => stop();
}


/// TTS 엔진의 최소 표면.
///
/// `FlutterTts` 는 구상 클래스라 **대역을 만들 수 없다.** 그런데 여기서 정말
/// 검증해야 하는 것은 "엔진이 없을 때 앱이 멈추지 않는가"이고, 그건 실패하는
/// 엔진을 끼워야 확인된다 — 그래서 얇은 인터페이스를 하나 둔다.
abstract class TtsEngine {
  Future<void> setLanguage(String language);
  Future<void> setSpeechRate(double rate);
  Future<void> awaitSpeakCompletion(bool await_);
  Future<void> speak(String text);
  Future<void> stop();
}

/// 실제 엔진 어댑터. 로직은 담지 않는다 — 담으면 테스트가 못 닿는 곳이 생긴다.
class FlutterTtsEngine implements TtsEngine {
  FlutterTtsEngine([FlutterTts? tts]) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;

  @override
  Future<void> setLanguage(String language) async =>
      _tts.setLanguage(language);

  @override
  Future<void> setSpeechRate(double rate) async => _tts.setSpeechRate(rate);

  @override
  Future<void> awaitSpeakCompletion(bool await_) async =>
      _tts.awaitSpeakCompletion(await_);

  @override
  Future<void> speak(String text) async => _tts.speak(text);

  @override
  Future<void> stop() async => _tts.stop();
}
