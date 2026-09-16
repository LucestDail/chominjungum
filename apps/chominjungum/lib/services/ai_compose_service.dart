import 'dart:convert';

import 'package:http/http.dart' as http;

import 'dictation_composer.dart';

/// AI 출제 — **받아쓰기 문장을 만들어 준다**(2026-09-16 결정: `osh-ai-gateway` 경유).
///
/// ## 🔴 이 파일은 외부로 나간다. 그래서 규칙이 셋이다.
///
///  1. **허브 기기에서만.** 학생 단말은 외부로 아무것도 보내지 않는다 —
///     호출 전에 `AppRole.canEnableAi` 와 `AiConsent.isEnabled()` 를 모두 통과해야 한다.
///  2. **학생 데이터는 절대 안 보낸다.** 보내는 것은 교사가 고른 **학년·주제**뿐이다.
///     답안·이름·기기 ID 는 이 파일을 지나가지 않는다.
///  3. **결과를 그대로 믿지 않는다.** 모델이 무엇을 주든 `DictationComposer` 의
///     제약(16글자·20줄)을 통과한 것만 남긴다 — jammin 과 같은 규칙이다.
///
/// ## 왜 게이트웨이인가
///
/// 홈랩 서비스의 LLM 호출은 `osh-ai-gateway` 경유가 표준이다. 키가 게이트웨이에만
/// 있고 비용·모델을 한 곳에서 갈아끼운다. ⚠️앱에 모델 키를 두면 그 둘을 다 잃는다.
///
/// ## ⚠️ 이것 없이도 앱은 완결된다
///
/// AI 는 **선택**이다. 꺼져 있으면 교사가 직접 타이핑하는 기존 경로가 그대로 돈다.
/// 네트워크가 없는 교실에서 이 기능이 실패해도 수업은 진행된다 —
/// 09-07 에 출제가 원격 서버에 묶여 통째로 실패한 적이 있어 그 선을 지킨다.
class AiComposeService {
  AiComposeService({http.Client? client, Duration? timeout})
      : _client = client ?? http.Client(),
        _timeout = timeout ?? const Duration(seconds: 25);

  final http.Client _client;

  /// ⚠️ 상한이 없으면 교실에서 **교사가 무한정 기다린다.** 기본값을 둔다.
  final Duration _timeout;

  /// 모델에게 주는 규칙 — **jammin 제약을 말로 옮긴 것**.
  ///
  /// ⚠️ 말로 시켰다고 지켜지는 것이 아니다. 그래서 받은 뒤에도
  /// [DictationComposer] 로 **다시 거른다**(아래 `_accept`).
  static const _system = '''
너는 초등학교 받아쓰기 문제를 만드는 도우미다. 규칙:
- 한 줄에 한 문항, 다른 말은 쓰지 마라(번호·따옴표·설명 금지)
- 각 문항은 16글자 이하
- 한글과 기본 문장부호만 사용한다
- 요청한 개수만큼만 낸다''';

  /// @param gradeLabel 학년 (예: "초등 2학년")
  /// @param topic 주제 (예: "받침이 있는 낱말")
  /// @param count 문항 수
  /// @param baseUrl `osh-ai-gateway` 주소
  /// @param apiKey `AiConsent` 가 Secure Storage 에서 꺼내 준 값
  Future<AiComposeResult> compose({
    required String baseUrl,
    required String apiKey,
    required String gradeLabel,
    required String topic,
    int count = 10,
  }) async {
    // ⚠️ 보내는 것에 학생 데이터가 섞이지 않도록 **여기서 조립한다.**
    //    호출자가 문자열을 만들어 넘기게 하면 언젠가 답안이 섞인다.
    final user = '$gradeLabel 학생을 위한 "$topic" 받아쓰기 문항 $count개를 만들어라.';

    final uri = Uri.parse('${_stripSlash(baseUrl)}/chat/completions');
    try {
      final res = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode({
              'messages': [
                {'role': 'system', 'content': _system},
                {'role': 'user', 'content': user},
              ],
              'temperature': 0.7,
              'max_tokens': 512,
            }),
          )
          .timeout(_timeout);

      if (res.statusCode ~/ 100 != 2) {
        // 🔴 본문을 그대로 보여 주지 않는다 — 키가 에코되는 게이트웨이가 있다
        return AiComposeResult.failure('AI 서버가 ${res.statusCode} 을 냈습니다');
      }

      final text = _extractText(utf8.decode(res.bodyBytes));
      if (text == null || text.trim().isEmpty) {
        return AiComposeResult.failure('AI 응답을 읽지 못했습니다');
      }
      return AiComposeResult.success(_accept(text, count));
    } catch (e) {
      // ⚠️ 실패해도 수업은 계속된다 — 교사가 직접 입력하면 된다
      return AiComposeResult.failure('AI 출제에 실패했습니다 (직접 입력으로 계속할 수 있습니다)');
    }
  }

  void close() => _client.close();

  static String _stripSlash(String s) =>
      s.endsWith('/') ? s.substring(0, s.length - 1) : s;

  /// OpenAI 호환 응답에서 본문만.
  static String? _extractText(String body) {
    try {
      final root = jsonDecode(body);
      if (root is! Map) return null;
      final choices = root['choices'];
      if (choices is! List || choices.isEmpty) return null;
      final msg = (choices.first as Map)['message'];
      if (msg is! Map) return null;
      final c = msg['content'];
      return c is String ? c : null;
    } catch (_) {
      return null;
    }
  }

  /// 🔴 **모델이 무엇을 주든 규칙을 통과한 것만 남긴다.**
  ///
  /// 모델은 번호를 붙이거나("1. 나비") 16글자를 넘기거나 설명을 덧붙인다.
  /// 그대로 학습지에 넣으면 jammin 제약을 깨고 렌더가 어긋난다.
  static List<String> _accept(String raw, int count) {
    final out = <String>[];
    for (var line in raw.split('\n')) {
      line = line.trim();
      if (line.isEmpty) continue;
      // "1. ", "1) ", "- ", "• " 같은 머리표 제거
      line = line.replaceFirst(RegExp(r'^\s*(\d+\s*[.)]|[-•*])\s*'), '').trim();
      // 따옴표 제거
      line = line.replaceAll(RegExp(r'^["“”\x27]+|["“”\x27]+$'), '').trim();
      if (line.isEmpty) continue;
      // 🔴 이름을 지어내지 않는다 — 실제 API 는 `isComposable`(한글·16글자 이하)
      if (!DictationComposer.isComposable(line)) continue;
      out.add(line);
      if (out.length >= count) break;
    }
    return out;
  }
}

/// 결과 — **성공/실패를 예외가 아니라 값으로** 낸다. 교실에서 예외가 화면을 덮으면 안 된다.
class AiComposeResult {
  const AiComposeResult._(this.items, this.error);

  factory AiComposeResult.success(List<String> items) =>
      AiComposeResult._(items, null);
  factory AiComposeResult.failure(String message) =>
      AiComposeResult._(const [], message);

  final List<String> items;
  final String? error;

  bool get ok => error == null;

  /// ⚠️ **응답은 왔는데 규칙을 통과한 문항이 0개**일 수 있다.
  /// 그걸 성공으로 보여 주면 교사는 빈 화면을 보고 이유를 모른다.
  bool get isEmptyAfterFilter => ok && items.isEmpty;
}
