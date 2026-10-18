import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Service to dynamically reflect the application version defined in `pubspec.yaml`.
class AppVersionService {
  static String version = '4.3.0';
  static String buildNumber = '6';

  static String get badgeVersion => 'v$version';
  static String get fullVersion => '$version+$buildNumber';
  static String get displayVersion => '$version (Build $buildNumber)';

  static Future<void> init() async {
    // 1. Check PackageInfo (native build metadata)
    try {
      final info = await PackageInfo.fromPlatform();
      if (info.version.isNotEmpty && info.version != '1.0.0') {
        version = info.version;
        if (info.buildNumber.isNotEmpty) {
          buildNumber = info.buildNumber;
        }
      }
    } catch (_) {}

    // 2. Direct sync from bundled pubspec.yaml asset
    try {
      final yamlContent = await rootBundle.loadString('pubspec.yaml');
      final match = RegExp(r'^version:\s*([^\s\r\n]+)', multiLine: true).firstMatch(yamlContent);
      if (match != null) {
        final raw = match.group(1)!;
        final parts = raw.split('+');
        if (parts.isNotEmpty && parts[0].isNotEmpty) {
          version = parts[0];
        }
        if (parts.length > 1 && parts[1].isNotEmpty) {
          buildNumber = parts[1];
        }
      }
    } catch (_) {}
  }
}
