import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/app_role.dart';
import '../../providers/app_role_provider.dart';
import '../../providers/dictation_providers.dart';
import '../../theme/jammin_tokens.dart';
import '../../widgets/jammin/jammin_brand_title.dart';
import '../../widgets/jammin/jammin_scaffold.dart';
import '../../widgets/jammin/jammin_section.dart';

/// 설정 — 기기 정보와 라이선스 고지.
///
/// ## 왜 탭이 아니라 화면 하나인가
///
/// PLAN 은 하단 Navigation Bar(홈/받아쓰기/시험·자료/설정)를 말하지만,
/// 이 앱은 **역할별로 엔트리가 갈려 있다**(`main.dart`=학생 / `main_teacher.dart`=교사).
/// 교사는 허브·출제·성적을, 학생은 응시·이력을 본다 — 같은 탭 구성을 쓸 이유가 없고,
/// 역할별 탭을 만드는 것은 앱 골격 재설계에 가깝다. "시험·자료"는 지금 담을 내용도 없다.
///
/// 그래서 방향성 결정과 무관하게 값이 있는 **설정 화면 하나**만 먼저 둔다.
/// 여기가 두 가지의 제자리다:
/// - **기기 ID** — 화면 여기저기에 흘리지 않고 필요할 때만 찾아본다(PLAN 1.3 "설정으로 이동")
/// - **폰트 라이선스 고지** — OFL 은 사본 동봉을 요구한다. 번들에 넣는 것으로 충족되지만
///   사람이 볼 수 있으면 더 낫다
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const fontLicenseAsset = 'assets/fonts/KCCDodamdodam-LICENSE.txt';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(appRoleProvider);
    final deviceId = ref.watch(deviceBindingIdProvider);

    return JamminScaffold(
      titleWidget: const JamminBrandTitle(subtitle: '설정'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          const JamminSectionHeader(
            heading: '이 기기',
            subheading: '교사가 학생 명단과 연결할 때 쓰는 값입니다.',
            center: false,
          ),
          const SizedBox(height: 12),
          _Row(label: '역할', value: role == AppRole.teacher ? '교사' : '학생'),
          const SizedBox(height: 8),
          deviceId.when(
            data: (id) => _DeviceIdTile(deviceId: id),
            loading: () => const _Row(label: '기기 ID', value: '불러오는 중…'),
            error: (e, _) => _Row(label: '기기 ID', value: '읽을 수 없습니다'),
          ),

          const SizedBox(height: 32),
          const JamminSectionHeader(
            heading: '글꼴',
            subheading: 'KCC도담도담체를 씁니다.',
            center: false,
          ),
          const SizedBox(height: 12),
          const _FontLicense(),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 84,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: JamminTokens.textMuted,
                ),
          ),
        ),
        Expanded(child: Text(value, style: Theme.of(context).textTheme.bodyMedium)),
      ],
    );
  }
}

/// 기기 ID 는 길어서(UUID) 접어 두고, 필요할 때 펼치거나 복사한다.
class _DeviceIdTile extends StatefulWidget {
  const _DeviceIdTile({required this.deviceId});

  final String deviceId;

  @override
  State<_DeviceIdTile> createState() => _DeviceIdTileState();
}

class _DeviceIdTileState extends State<_DeviceIdTile> {
  bool _full = false;

  String get _short =>
      widget.deviceId.length <= 8 ? widget.deviceId : '${widget.deviceId.substring(0, 8)}…';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Row(label: '기기 ID', value: _full ? widget.deviceId : _short),
        const SizedBox(height: 4),
        Row(
          children: [
            const SizedBox(width: 84),
            TextButton(
              onPressed: () => setState(() => _full = !_full),
              child: Text(_full ? '접기' : '전체 보기'),
            ),
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: widget.deviceId));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('기기 ID를 복사했습니다.')),
                );
              },
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('복사'),
            ),
          ],
        ),
      ],
    );
  }
}

/// 공유마당이 준 고지 원문은 **HTML 조각**이라 그대로 띄우면 태그가 보인다.
/// 태그를 걷어내는 부분만 떼어 두어 테스트할 수 있게 한다
/// (파일 자체는 앱 번들에 그대로 들어 있다 — 그게 OFL 이 요구하는 사본 동봉이다).
class FontLicenseText {
  FontLicenseText._();

  static final _tag = RegExp(r'<[^>]*>');
  static final _blankLines = RegExp(r'\n{2,}');

  static String plainText(String raw) {
    return raw
        .replaceAll(_tag, '')
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .join('\n')
        .replaceAll(_blankLines, '\n');
  }
}

/// 번들된 OFL 고지를 읽어 보여준다.
class _FontLicense extends StatelessWidget {
  const _FontLicense();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: rootBundle.loadString(SettingsScreen.fontLicenseAsset),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          // 고지를 못 읽어도 앱은 계속 돈다 — 사본은 번들에 들어 있다.
          return Text(
            'KCC도담도담체 · 한국저작권위원회 · 공유마당 · SIL Open Font License',
            style: Theme.of(context).textTheme.bodySmall,
          );
        }
        if (!snapshot.hasData) {
          return const SizedBox(height: 20);
        }
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: JamminTokens.surface,
            borderRadius: BorderRadius.circular(JamminTokens.radiusSm),
          ),
          child: SelectableText(
            FontLicenseText.plainText(snapshot.data!),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        );
      },
    );
  }
}
