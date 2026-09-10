import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/app_role.dart';

/// 이 빌드가 학생용인가 교사용인가. `bootstrap(AppRole)` 이 덮어쓴다.
///
/// ## 기본값이 학생인 이유 — 잊었을 때 **닫히는 쪽**으로 떨어진다
///
/// 예전에는 override 가 없으면 던졌다. 그러면 bootstrap 실수를 잡을 수 있지만,
/// 역할을 보는 화면이 **테스트에서 통째로 못 뜨는** 부작용이 있었다.
///
/// 학생을 기본으로 두면 안전하다 — 학생 쪽이 **더 제한적**이기 때문이다
/// (외부 전송 없음, jammin 갱신 버튼 없음). 교사 엔트리는 항상 덮어쓰고,
/// 만에 하나 덮어쓰지 못하면 교사가 학생 화면을 보게 되므로 **눈에 띄게 틀린다**
/// — 조용히 권한이 넓어지는 것보다 낫다.
final appRoleProvider = Provider<AppRole>((ref) => AppRole.student);
