import 'package:sync_protocol/sync_protocol.dart';

import '../domain/dictation_models.dart';
import 'mistake_analysis.dart';

/// 한 학생의 응시 현황.
class StudentProgress {
  const StudentProgress({
    required this.deviceBindingId,
    required this.displayName,
    required this.submitted,
    required this.total,
    required this.correctCount,
    required this.gradedCount,
    required this.lastSubmittedAtMs,
  });

  final String deviceBindingId;

  /// 학생이 적은 이름. 없으면 기기 ID 축약(`학생 a3f2`).
  final String displayName;

  /// 낸 문제 중 제출한 개수 / 전체.
  final int submitted;
  final int total;

  /// 맞은 글자 수 / 채점된 글자 수.
  final int correctCount;
  final int gradedCount;

  final int? lastSubmittedAtMs;

  bool get isDone => total > 0 && submitted >= total;
  double get progress => total == 0 ? 0 : submitted / total;
  double get accuracy => gradedCount == 0 ? 0 : correctCount / gradedCount;
  bool get hasStarted => submitted > 0;
}

/// 교실 한 수업의 현황판 — **순수 계산**이다.
///
/// ## 왜 계산으로 두나
///
/// 교사 화면이 상태를 직접 주무르면 테스트가 닿지 않는다(교사 화면은
/// `NetworkInfo` 플러그인에 묶여 위젯 테스트가 아예 안 된다). 그래서 화면은
/// 이 결과를 **그리기만** 하고, 판단은 전부 여기서 한다.
///
/// ## 서버 없이 성립한다
///
/// 학급 명단이 따로 없다. 교사 기기가 이번 수업에서 **본 것**으로 명단을 만든다:
/// 접속한 기기, 제출한 답안, 거기 실린 이름. 서버 쪽 `chominjungum-web` 이
/// 학급을 관리하지만 그건 선택이고, 교실에서는 이것만으로 한 사이클이 돈다.
class ClassroomBoard {
  const ClassroomBoard({
    required this.students,
    required this.itemCount,
    required this.submittedCount,
    required this.averageAccuracy,
    required this.weakness,
  });

  /// 이름 순이 아니라 **진도 순**(덜 낸 학생이 위). 교사가 볼 이유가 그것이다.
  final List<StudentProgress> students;

  final int itemCount;
  final int submittedCount;

  /// 학급 평균 정답률(글자 기준). 채점된 답안이 없으면 0.
  final double averageAccuracy;

  /// 학급 전체의 취약 자모. 개인이 아니라 **다음 수업에 뭘 더 볼지**를 위한 것.
  final MistakeAnalysis weakness;

  bool get isEmpty => students.isEmpty;

  /// 전원이 다 냈는가 — 교사가 다음으로 넘어가도 되는 신호.
  bool get allDone =>
      students.isNotEmpty && students.every((s) => s.isDone);

  int get doneCount => students.where((s) => s.isDone).length;

  /// [attempts] 는 이번 수업에서 받은 답안, [items] 는 낸 문제.
  ///
  /// [connectedDeviceIds] 는 **아직 아무것도 안 낸 학생**을 명단에 넣기 위한 것이다.
  /// 제출로만 명단을 만들면 "접속은 했는데 한 문제도 안 푼 학생"이 안 보인다 —
  /// 교사가 가장 알고 싶은 것이 그것이다.
  static ClassroomBoard of({
    required List<AttemptSubmitPayload> attempts,
    required List<DictationItem> items,
    Set<String> connectedDeviceIds = const {},
    Map<String, String> knownNames = const {},
  }) {
    final byDevice = <String, List<AttemptSubmitPayload>>{};
    for (final a in attempts) {
      byDevice.putIfAbsent(a.deviceBindingId, () => []).add(a);
    }
    for (final id in connectedDeviceIds) {
      byDevice.putIfAbsent(id, () => []);
    }

    final students = <StudentProgress>[];
    var totalCorrect = 0;
    var totalGraded = 0;

    for (final entry in byDevice.entries) {
      final list = entry.value;
      // 같은 문항을 다시 냈으면 **최신 것만** 센다(재제출은 새 제출이 아니다).
      final latest = <String, AttemptSubmitPayload>{};
      for (final a in list) {
        final prev = latest[a.itemId];
        if (prev == null || a.submittedAtMs >= prev.submittedAtMs) {
          latest[a.itemId] = a;
        }
      }

      var correct = 0;
      var graded = 0;
      int? last;
      for (final a in latest.values) {
        correct += a.correctCount;
        graded += a.totalCount;
        if (last == null || a.submittedAtMs > last) last = a.submittedAtMs;
      }
      totalCorrect += correct;
      totalGraded += graded;

      students.add(
        StudentProgress(
          deviceBindingId: entry.key,
          displayName: _nameFor(entry.key, list, knownNames),
          submitted: latest.length,
          total: items.length,
          correctCount: correct,
          gradedCount: graded,
          lastSubmittedAtMs: last,
        ),
      );
    }

    // 덜 낸 학생이 위로. 같으면 정답률 낮은 순 — 교사가 도와줄 순서다.
    students.sort((a, b) {
      final p = a.progress.compareTo(b.progress);
      if (p != 0) return p;
      final acc = a.accuracy.compareTo(b.accuracy);
      if (acc != 0) return acc;
      return a.displayName.compareTo(b.displayName);
    });

    return ClassroomBoard(
      students: students,
      itemCount: items.length,
      submittedCount: students.fold(0, (n, s) => n + s.submitted),
      averageAccuracy: totalGraded == 0 ? 0 : totalCorrect / totalGraded,
      weakness: MistakeAnalysis.of(
        attempts: [for (final a in attempts) _toLocalAttempt(a)],
        items: items,
      ),
    );
  }

  /// 이름은 **가장 최근 제출**의 것을 쓴다. 학생이 도중에 바꿔 적을 수 있다.
  static String _nameFor(
    String deviceId,
    List<AttemptSubmitPayload> attempts,
    Map<String, String> knownNames,
  ) {
    final sorted = [...attempts]
      ..sort((a, b) => b.submittedAtMs.compareTo(a.submittedAtMs));
    for (final a in sorted) {
      final n = a.studentName?.trim();
      if (n != null && n.isNotEmpty) return n;
    }
    final known = knownNames[deviceId]?.trim();
    if (known != null && known.isNotEmpty) return known;
    return '학생 ${_shortId(deviceId)}';
  }

  static String _shortId(String id) =>
      id.length <= 4 ? id : id.substring(0, 4);

  /// 취약 자모 분석은 로컬 이력 타입을 받는다. 프로토콜 타입을 그쪽에 맞춰 준다.
  static DictationAttempt _toLocalAttempt(AttemptSubmitPayload a) =>
      DictationAttempt(
        id: a.attemptId,
        itemId: a.itemId,
        deviceBindingId: a.deviceBindingId,
        rawAnswer: a.rawAnswer,
        inputKind: AttemptInputKind.keyboard,
        createdAtMs: a.submittedAtMs,
        correctCount: a.correctCount,
        totalCount: a.totalCount,
        submittedAtMs: a.submittedAtMs,
        matchesJson: a.matches == null
            ? null
            : _encodeMatches(a.matches!),
      );

  static String _encodeMatches(List<GlyphMatchSummary> ms) {
    final buf = StringBuffer('[');
    for (var i = 0; i < ms.length; i++) {
      if (i > 0) buf.write(',');
      buf.write('{"i":${ms[i].index},"ok":${ms[i].ok}}');
    }
    buf.write(']');
    return buf.toString();
  }
}
