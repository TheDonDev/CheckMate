// lib/services/remote_config_service.dart
import 'dart:convert';

class RemoteConfigService {
  Future<void> initialize() async {}

  bool get maintenanceMode => false;
  String get appVersion => '1.0.0';
  String get minRequiredVersion => '1.0.0';

  Map<String, dynamic> get featureFlags => {};
}
