import 'package:flutter/foundation.dart';

enum DevicePlatform { android, windows, unsupported }

abstract interface class DeviceService {
  DevicePlatform get platform;
}

class FlutterDeviceService implements DeviceService {
  const FlutterDeviceService();

  @override
  DevicePlatform get platform => switch (defaultTargetPlatform) {
        TargetPlatform.android => DevicePlatform.android,
        TargetPlatform.windows => DevicePlatform.windows,
        _ => DevicePlatform.unsupported,
      };
}
