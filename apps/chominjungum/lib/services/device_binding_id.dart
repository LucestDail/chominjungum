import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

const _kDeviceBinding = 'device_binding_id_v1';

/// 설치·기기 단위 안정 ID (jammin 연계 저장소 파티션 키로 사용).
class DeviceBindingId {
  DeviceBindingId._();

  static const _storage = FlutterSecureStorage();
  static const _uuid = Uuid();

  static Future<String> getOrCreate() async {
    final existing = await _storage.read(key: _kDeviceBinding);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final id = _uuid.v4();
    await _storage.write(key: _kDeviceBinding, value: id);
    return id;
  }
}
