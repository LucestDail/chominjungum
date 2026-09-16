import 'bootstrap.dart';
import 'domain/app_role.dart';

/// 부모 엔트리 — **집에서 부모 기기가 허브**(2026-09-16 결정).
///
/// 교사 앱과 같은 기계를 쓴다. 다른 것은 **학교 것이 없다는 점**뿐이다:
/// 서버 업싱크·학급 토큰이 빠지고, 라벨이 "학급" 대신 "자녀" 다.
///
/// 🔴 그래서 **서버도 새 프로토콜도 필요 없다.** 오프라인 번들로 이미 되고,
/// 이 앱의 전제("중앙 서버 없음")가 집에서도 그대로 유지된다.
Future<void> main() async {
  await bootstrap(AppRole.parent);
}
