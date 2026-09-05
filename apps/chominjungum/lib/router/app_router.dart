import 'package:go_router/go_router.dart';

import '../domain/app_role.dart';
import '../features/dictation/dictation_practice_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/student/student_home_screen.dart';
import '../features/teacher/teacher_home_screen.dart';

GoRouter createRouter(AppRole role) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) =>
            role == AppRole.teacher ? const TeacherHomeScreen() : const StudentHomeScreen(),
      ),
      GoRoute(
        path: '/practice',
        builder: (context, state) => const DictationPracticeScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
}
