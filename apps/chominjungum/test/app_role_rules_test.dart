import 'package:chominjungum/domain/app_role.dart';
import 'package:flutter_test/flutter_test.dart';

/// 역할 규칙 — **부모 모드를 넣으면서 가장 위험한 것은 "학교 것이 집으로 새는 것"** 이다.
///
/// 2026-09-16 결정: *"집에서 부모 기기가 허브 — 오프라인 번들로 이미 되고 **서버가 필요 없다**"*.
/// 그 결정을 코드가 지키는지 여기서 잠근다.
void main() {
  group('허브 판정', () {
    test('교사와 부모가 허브다 — 학생은 아니다', () {
      expect(AppRole.teacher.isHub, isTrue);
      expect(AppRole.parent.isHub, isTrue);
      expect(AppRole.student.isHub, isFalse);
    });

    test('★ 자의 판별력 — 모든 역할에 참을 내지 않는다', () {
      final hubs = AppRole.values.where((r) => r.isHub).toList();
      expect(hubs, hasLength(2));
      expect(hubs, isNot(containsAll(AppRole.values)));
    });
  });

  group('🔴 부모는 학교 서버로 올릴 수 없다', () {
    test('업싱크는 교사만', () {
      expect(AppRole.teacher.canUpsync, isTrue);
      expect(AppRole.parent.canUpsync, isFalse,
          reason: '집 기기에 학급 토큰을 넣게 만들면 "서버가 필요 없다" 는 결정을 되돌리는 것이고, '
              '자녀 답안이 학교 서버로 나가는 길을 여는 것이다');
      expect(AppRole.student.canUpsync, isFalse);
    });

    test('⚠️ 허브라고 해서 전부 올릴 수 있는 것은 아니다 (isHub 와 canUpsync 는 다른 질문)', () {
      expect(AppRole.parent.isHub && !AppRole.parent.canUpsync, isTrue);
    });
  });

  group('학생 단말은 외부로 아무것도 보내지 않는다 — 이 앱의 전제', () {
    test('AI 를 켤 수 없다', () {
      expect(AppRole.student.canEnableAi, isFalse);
      expect(AppRole.teacher.canEnableAi, isTrue);
      expect(AppRole.parent.canEnableAi, isTrue);
    });

    test('콘텐츠를 외부에서 당겨올 수 없다', () {
      // 🔴 09-07 에 출제가 원격 서버에 묶여 통째로 실패한 적이 있다
      expect(AppRole.student.canFetchContent, isFalse);
      expect(AppRole.teacher.canFetchContent, isTrue);
      expect(AppRole.parent.canFetchContent, isTrue);
    });

    test('학생에게 열린 외부 경로가 하나도 없다', () {
      const s = AppRole.student;
      expect([s.canUpsync, s.canEnableAi, s.canFetchContent], everyElement(isFalse));
    });
  });

  group('이름', () {
    test('역할마다 다른 이름을 쓴다', () {
      final names = AppRole.values.map((r) => r.displayName).toSet();
      expect(names, hasLength(AppRole.values.length));
      expect(AppRole.parent.displayName, '부모');
    });

    test('부모에게는 "학급" 이 아니라 "자녀" 다', () {
      expect(AppRole.parent.groupName, '자녀');
      expect(AppRole.teacher.groupName, '학급');
    });

    test('빈 이름이 없다 (화면에 빈칸이 뜨면 안 된다)', () {
      for (final r in AppRole.values) {
        expect(r.displayName, isNotEmpty, reason: '$r');
        expect(r.groupName, isNotEmpty, reason: '$r');
        expect(r.hostDisplayName, isNotEmpty, reason: '$r');
      }
    });
  });

  group('⚠️ 새 역할이 생기면 여기서 멈춘다', () {
    test('모든 역할이 세 능력에 대해 명시적으로 답한다', () {
      // 🔴 `switch` 가 아니라 확장 게터라 새 역할이 생겨도 컴파일은 통과한다.
      //    그래서 **개수**로 잠근다 — 늘어나면 이 테스트가 먼저 깨지고,
      //    그때 "새 역할은 무엇을 할 수 있는가" 를 반드시 정하게 된다.
      expect(AppRole.values, hasLength(3),
          reason: '역할을 추가했다면 canUpsync·canEnableAi·canFetchContent 를 정하고 '
              '이 테스트의 기대값을 갱신하라');
    });
  });
}
