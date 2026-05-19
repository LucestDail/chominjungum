import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('32.svg and 4352.svg load', () async {
    for (final path in ['assets/hangul/32.svg', 'assets/hangul/4352.svg']) {
      final loader = SvgAssetLoader(path);
      final bytes = await rootBundle.load(path);
      expect(bytes.lengthInBytes, greaterThan(0));
      final picture = await svg.cache.putIfAbsent(
        loader.cacheKey(null),
        () => loader.loadBytes(null),
      );
      expect(picture, isNotNull, reason: path);
    }
  });

  testWidgets('glyph svg renders with size', (tester) async {
    await tester.pumpWidget(
      Center(
        child: SvgPicture.asset(
          'assets/hangul/4352.svg',
          width: 80,
          height: 40,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final box = tester.renderObject<RenderBox>(find.byType(SvgPicture));
    expect(box.size.width, greaterThan(1));
  });
}
