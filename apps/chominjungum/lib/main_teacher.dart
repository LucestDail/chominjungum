import 'bootstrap.dart';
import 'domain/app_role.dart';

Future<void> main() async {
  await bootstrap(AppRole.teacher);
}
