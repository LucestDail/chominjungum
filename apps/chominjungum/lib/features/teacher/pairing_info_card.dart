import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sync_protocol/sync_protocol.dart';

import '../../theme/jammin_tokens.dart';
import '../../widgets/jammin/jammin_status_banner.dart';

/// 학생이 스캔할 QR 과, QR 을 못 읽을 때 쓰는 연결 문자열.
///
/// ## 왜 문자열을 기본으로 감추나
///
/// [SessionPairingPayload.encode] 결과에는 **세션 키가 들어 있다**
/// (`publicKeyB64` — 이름과 달리 대칭 키다). 교실에서는 교사 화면을 프로젝터에
/// 띄우거나 학생이 어깨너머로 보는 일이 흔해서, 그대로 두면 아무나 키를 적어
/// 갈 수 있다. QR 은 스캔하는 학생만 보면 되므로 그대로 두고, 사람이 읽을 수 있는
/// 문자열만 감춘다.
///
/// 없애지 않는 이유: QR 카메라가 없거나 스캔이 안 되는 기기를 위한 **유일한 대체
/// 경로**다(학생 화면의 "페이로드 붙여넣기"). 교사가 필요할 때 펼치게 한다.
///
/// 세션이 바뀌면 펼친 상태가 유지되면 안 된다 — 호출하는 쪽에서
/// `key: ValueKey(sessionId)` 를 주면 새 위젯이 되어 자동으로 접힌다.
class PairingInfoCard extends StatefulWidget {
  const PairingInfoCard({super.key, required this.pairing});

  final SessionPairingPayload pairing;

  @override
  State<PairingInfoCard> createState() => _PairingInfoCardState();
}

class _PairingInfoCardState extends State<PairingInfoCard> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final encoded = widget.pairing.encode();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              '학생 스캔용 QR',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            QrImageView(
              data: encoded,
              version: QrVersions.auto,
              size: 220,
              backgroundColor: JamminTokens.surfaceElevated,
            ),
            const SizedBox(height: 12),
            if (!_revealed)
              TextButton.icon(
                onPressed: () => setState(() => _revealed = true),
                icon: const Icon(Icons.visibility_off_outlined, size: 18),
                label: const Text('연결 정보 보기 (QR을 못 읽을 때)'),
              )
            else ...[
              const JamminStatusBanner(
                message: '이 정보에는 접속 키가 들어 있습니다. 학생 기기에만 보여주세요.',
                tone: JamminStatusTone.info,
              ),
              const SizedBox(height: 8),
              SelectableText(
                encoded,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              TextButton.icon(
                onPressed: () => setState(() => _revealed = false),
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: const Text('숨기기'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
