import 'dart:convert';
import 'package:firebase_remote_config/firebase_remote_config.dart';

class RemoteConfigService {
  final FirebaseRemoteConfig _remoteConfig = FirebaseRemoteConfig.instance;

  Future<void> initialize() async {
    await _remoteConfig.setConfigSettings(RemoteConfigSettings(
      fetchTimeout: const Duration(minutes: 1),
      minimumFetchInterval: const Duration(hours: 1),
    ));

    await _remoteConfig.setDefaults(const {
      'feature_flags': '{}',
      'app_version': '1.0.0',
      'maintenance_mode': false,
      'min_required_version': '1.0.0'
    });

    await _remoteConfig.fetchAndActivate();
  }

  bool get maintenanceMode => _remoteConfig.getBool('maintenance_mode');
  String get appVersion => _remoteConfig.getString('app_version');
  String get minRequiredVersion => _remoteConfig.getString('min_required_version');
  
  Map<String, dynamic> get featureFlags {
    try {
      final flags = _remoteConfig.getString('feature_flags');
      return flags.isNotEmpty 
          ? Map<String, dynamic>.from(json.decode(flags))
          : {};
    } catch (e) {
      return {};
    }
  }
}
