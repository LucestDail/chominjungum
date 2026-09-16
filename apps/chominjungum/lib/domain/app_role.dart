/// 빌드/실행 시 역할.
///
/// - [teacher] 교실 허브 — 출제·수신·채점·학급 관리·서버 업싱크
/// - [parent]  **집 허브** — 교사와 같은 기계를 쓰되 학교 것은 없다(2026-09-16 결정)
/// - [student] 수신·학습
enum AppRole { teacher, parent, student }

/// 역할이 무엇을 할 수 있는지 — **한 곳에 모은다.**
///
/// ## 왜 확장으로 빼나
///
/// 부모 모드를 넣기 전까지 화면들은 `role == AppRole.teacher` 를 직접 봤다.
/// 역할이 셋이 되면 그 비교가 **전부 틀린 질문**이 된다 — 묻고 싶은 것은
/// "교사인가" 가 아니라 **"허브인가"**, **"외부로 보낼 수 있는가"** 이기 때문이다.
///
/// 🔴 화면마다 `teacher || parent` 를 적으면 **언젠가 한 곳이 빠진다.**
/// 그게 이 워크스페이스가 반복해 기록한 모양이라, 판정을 여기로 모으고
/// 아래 규칙을 테스트로 잠근다.
extension AppRoleRules on AppRole {
  /// 이 기기가 **허브**인가 — 출제하고 학생 기기를 받는 쪽.
  bool get isHub => this == AppRole.teacher || this == AppRole.parent;

  /// 학교 서버로 제출을 **올릴 수 있는가**.
  ///
  /// 🔴 부모는 안 된다. 2026-09-16 결정이 *"집에서 부모 기기가 허브 —
  /// 오프라인 번들로 이미 되고 **서버가 필요 없다**"* 였다. 집 기기에 학교 토큰과
  /// 학급 ID 를 넣게 만들면 그 결정을 되돌리는 것이고, **자녀 답안이 학교 서버로
  /// 나가는 길**을 여는 것이다.
  bool get canUpsync => this == AppRole.teacher;

  /// 외부(jammin 등)에서 콘텐츠를 **당겨올 수 있는가**.
  ///
  /// ⚠️ 학생 기기에서는 절대 안 된다("중앙 서버 없음" 전제). 부모는 집 인터넷이
  /// 있으므로 허용한다 — 다만 이것도 **선택**이고 없어도 오프라인 번들로 동작한다.
  bool get canFetchContent => isHub;

  /// AI 기능(출제·글씨 교정)을 **켤 수 있는가**.
  ///
  /// ⚠️ 학생 단말은 외부로 아무것도 보내지 않는다. 허브만 켤 수 있다.
  bool get canEnableAi => isHub;

  /// 화면에 쓰는 이 역할의 이름.
  String get displayName => switch (this) {
        AppRole.teacher => '교사',
        AppRole.parent => '부모',
        AppRole.student => '학생',
      };

  /// 이 역할이 돌보는 무리의 이름 — 교사는 "학급", 부모는 "자녀".
  String get groupName => switch (this) {
        AppRole.teacher => '학급',
        AppRole.parent => '자녀',
        AppRole.student => '학급',
      };

  /// 허브가 스스로를 학생 목록에 보일 때 쓰는 이름.
  String get hostDisplayName => displayName;
}
