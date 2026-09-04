import 'dart:io';

import 'package:chominjungum/services/local_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// Hive 는 앱에서 `initFlutter()` 로 경로를 잡지만(path_provider 플러그인 필요),
/// 테스트에서는 임시 디렉토리로 직접 초기화한다.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('cjm_store_test');
    LocalStore.initAt(dir.path);
    await LocalStore.open();
  });

  tearDown(() async {
    await LocalStore.deleteAllFromDisk();
    await LocalStore.closeAll();
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });

  test('저장한 값을 그대로 다시 읽는다', () async {
    await LocalStore.put(LocalStore.itemsBox, 'a1', {
      'id': 'a1',
      'expectedText': '학교에 갔다.',
      'count': 7,
    });

    final loaded = LocalStore.get(LocalStore.itemsBox, 'a1');
    expect(loaded, isNotNull);
    expect(loaded!['expectedText'], '학교에 갔다.');
    expect(loaded['count'], 7);
  });

  test('Box 를 닫고 다시 열어도 남아 있다', () async {
    await LocalStore.put(LocalStore.attemptsBox, 'k1', {'rawAnswer': '학교에 갓다.'});

    await LocalStore.closeAll();
    LocalStore.initAt(dir.path);
    await LocalStore.open();

    expect(LocalStore.get(LocalStore.attemptsBox, 'k1')!['rawAnswer'], '학교에 갓다.');
  });

  test('없는 키는 null', () {
    expect(LocalStore.get(LocalStore.itemsBox, 'nope'), isNull);
  });

  test('values 는 저장한 것을 모두 돌려준다', () async {
    await LocalStore.put(LocalStore.attemptsBox, 'k1', {'i': 1});
    await LocalStore.put(LocalStore.attemptsBox, 'k2', {'i': 2});

    final all = LocalStore.values(LocalStore.attemptsBox);
    expect(all.length, 2);
    expect(all.map((e) => e['i']).toSet(), {1, 2});
  });

  test('손상된 기록은 화면을 막지 않고 건너뛴다', () async {
    await LocalStore.put(LocalStore.attemptsBox, 'ok', {'i': 1});
    // 형식이 바뀐 옛 데이터를 흉내낸다
    await LocalStore.box(LocalStore.attemptsBox).put('broken', '{이건 JSON 이 아니다');

    expect(LocalStore.get(LocalStore.attemptsBox, 'broken'), isNull);
    expect(LocalStore.values(LocalStore.attemptsBox).length, 1);
  });

  test('delete 와 clearAll', () async {
    await LocalStore.put(LocalStore.itemsBox, 'a', {'i': 1});
    await LocalStore.put(LocalStore.sessionsBox, 'b', {'i': 2});

    await LocalStore.delete(LocalStore.itemsBox, 'a');
    expect(LocalStore.get(LocalStore.itemsBox, 'a'), isNull);
    expect(LocalStore.get(LocalStore.sessionsBox, 'b'), isNotNull);

    await LocalStore.clearAll();
    expect(LocalStore.values(LocalStore.sessionsBox), isEmpty);
  });

  test('open 을 두 번 불러도 안전하다', () async {
    await LocalStore.put(LocalStore.itemsBox, 'a', {'i': 1});
    await LocalStore.open();
    expect(LocalStore.get(LocalStore.itemsBox, 'a')!['i'], 1);
  });
}
