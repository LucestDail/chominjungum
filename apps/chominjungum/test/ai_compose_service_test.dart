import 'dart:convert';

import 'package:chominjungum/services/ai_compose_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 🔴 **가장 중요한 것은 "무엇이 나가는가" 다.**
///
/// 이 앱의 전제가 "중앙 서버 없음 · 학생 데이터는 교실을 안 나간다" 이고,
/// AI 출제는 그 전제에 **구멍을 낼 수 있는 유일한 경로**다. 그래서 기능이 되는지보다
/// **답안·이름·기기 ID 가 안 실리는지**를 먼저 잠근다.
void main() {
  /// 마지막으로 나간 요청을 붙잡아 두는 가짜 클라이언트.
  late String lastBody;
  late Uri lastUri;
  late Map<String, String> lastHeaders;

  http.Client fake(String responseText, {int status = 200}) {
    return MockClient((req) async {
      lastBody = req.body;
      lastUri = req.url;
      lastHeaders = req.headers;
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'content': responseText}
            }
          ]
        }),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
  }

  group('🔴 나가는 것에 학생 데이터가 없다', () {
    test('보내는 것은 학년·주제·개수뿐이다', () async {
      final svc = AiComposeService(client: fake('나비\n구름'));
      await svc.compose(
        baseUrl: 'https://gw.example/v1',
        apiKey: 'K',
        gradeLabel: '초등 2학년',
        topic: '받침이 있는 낱말',
        count: 3,
      );

      expect(lastBody, contains('초등 2학년'));
      expect(lastBody, contains('받침이 있는 낱말'));
      /*
       * 답안·이름·기기 ID 는 이 API 로 들어올 자리가 아예 없다 —
       * 호출자가 문자열을 만들어 넘기게 두지 않은 것이 그 이유다.
       *
       * ⚠️ 첫 판에서 `'학생'` 을 금지어에 넣었다가 **제 자가 틀렸다** —
       *    프롬프트 문구 "초등 2학년 **학생**을 위한" 이 걸렸다. 실제 유출이 아니다.
       *    ⇒ 금지어는 **데이터의 모양**으로 잡는다(식별자 키 이름·기기 ID 형식),
       *      한국어 낱말로 잡으면 정상 문구를 오답으로 찍는다.
       */
      for (final leaked in ['attemptId', 'deviceId', 'nickname', 'studentId', 'sessionKey']) {
        expect(lastBody, isNot(contains(leaked)), reason: '요청에 $leaked 가 실렸다');
      }
      // 그리고 **보내는 필드가 셋뿐**인지 구조로 확인한다 — 낱말 금지보다 이게 확실하다
      final sent = jsonDecode(lastBody) as Map<String, dynamic>;
      expect(sent.keys.toSet(), {'messages', 'temperature', 'max_tokens'});
      expect((sent['messages'] as List), hasLength(2));
    });

    test('게이트웨이 주소와 인증 헤더가 맞다', () async {
      final svc = AiComposeService(client: fake('나비'));
      await svc.compose(
        baseUrl: 'https://gw.example/v1/', // 끝 슬래시가 있어도
        apiKey: 'SECRET',
        gradeLabel: 'g',
        topic: 't',
      );
      expect(lastUri.toString(), 'https://gw.example/v1/chat/completions');
      expect(lastHeaders['Authorization'], 'Bearer SECRET');
    });
  });

  group('🔴 모델이 무엇을 주든 규칙을 통과한 것만 남긴다', () {
    test('번호·따옴표 머리표를 벗긴다', () async {
      final svc = AiComposeService(client: fake('1. 나비\n2) 구름\n- 하늘\n"바다"'));
      final r = await svc.compose(
          baseUrl: 'u', apiKey: 'k', gradeLabel: 'g', topic: 't', count: 10);
      expect(r.items, ['나비', '구름', '하늘', '바다']);
    });

    /// ⚠️ jammin 제약(16글자)을 모델이 어기는 일은 흔하다. 말로 시켰다고 지켜지지 않는다.
    test('16글자를 넘는 문항을 버린다', () async {
      final long = '가' * 17;
      final svc = AiComposeService(client: fake('나비\n$long\n구름'));
      final r = await svc.compose(
          baseUrl: 'u', apiKey: 'k', gradeLabel: 'g', topic: 't', count: 10);
      expect(r.items, ['나비', '구름']);
    });

    test('한글이 아닌 줄(설명·영문)을 버린다', () async {
      final svc = AiComposeService(
          client: fake('Here are the items:\n나비\nSure!\n구름'));
      final r = await svc.compose(
          baseUrl: 'u', apiKey: 'k', gradeLabel: 'g', topic: 't', count: 10);
      expect(r.items, ['나비', '구름']);
    });

    test('요청한 개수를 넘기지 않는다', () async {
      final svc = AiComposeService(client: fake('가\n나\n다\n라\n마'));
      final r = await svc.compose(
          baseUrl: 'u', apiKey: 'k', gradeLabel: 'g', topic: 't', count: 2);
      expect(r.items, hasLength(2));
    });

    test('★ 자의 판별력 — 전부 버리지도, 전부 받지도 않는다', () async {
      final svc = AiComposeService(client: fake('나비\nOK\n${'가' * 20}\n구름'));
      final r = await svc.compose(
          baseUrl: 'u', apiKey: 'k', gradeLabel: 'g', topic: 't', count: 10);
      expect(r.items, hasLength(2));
      expect(r.items, containsAll(['나비', '구름']));
    });
  });

  group('실패해도 수업은 계속된다', () {
    test('HTTP 오류를 값으로 낸다 (예외를 던지지 않는다)', () async {
      final svc = AiComposeService(client: fake('x', status: 500));
      final r = await svc.compose(
          baseUrl: 'u', apiKey: 'k', gradeLabel: 'g', topic: 't');
      expect(r.ok, isFalse);
      expect(r.error, isNotNull);
    });

    /// 🔴 게이트웨이가 본문에 키를 되비추는 경우가 있다. 오류 메시지에 본문을 넣지 않는다.
    test('오류 메시지에 응답 본문이나 키가 새지 않는다', () async {
      final svc = AiComposeService(
          client: MockClient((_) async => http.Response('{"key":"SECRET-abc"}', 401)));
      final r = await svc.compose(
          baseUrl: 'u', apiKey: 'SECRET-abc', gradeLabel: 'g', topic: 't');
      expect(r.error, isNot(contains('SECRET')));
    });

    test('망가진 응답에 터지지 않는다', () async {
      final svc =
          AiComposeService(client: MockClient((_) async => http.Response('not json', 200)));
      final r = await svc.compose(
          baseUrl: 'u', apiKey: 'k', gradeLabel: 'g', topic: 't');
      expect(r.ok, isFalse);
    });

    /// ⚠️ 상한이 없으면 교실에서 교사가 무한정 기다린다.
    test('응답이 안 오면 타임아웃으로 끝난다', () async {
      final svc = AiComposeService(
        client: MockClient((_) async {
          await Future<void>.delayed(const Duration(seconds: 2));
          return http.Response('{}', 200);
        }),
        timeout: const Duration(milliseconds: 80),
      );
      final r = await svc.compose(
          baseUrl: 'u', apiKey: 'k', gradeLabel: 'g', topic: 't');
      expect(r.ok, isFalse);
    });

    /// 🔴 응답은 왔는데 **통과한 문항이 0개**인 경우 — 성공으로 보이면 교사는 이유를 모른다.
    test('걸러서 0개가 된 것을 성공과 구분한다', () async {
      final svc = AiComposeService(client: fake('Sure, here you go!\nOK'));
      final r = await svc.compose(
          baseUrl: 'u', apiKey: 'k', gradeLabel: 'g', topic: 't');
      expect(r.ok, isTrue);
      expect(r.items, isEmpty);
      expect(r.isEmptyAfterFilter, isTrue);
    });
  });
}
