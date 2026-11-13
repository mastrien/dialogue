import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// In-app Android updater (outside Play Store): queries the latest GitHub release,
/// verifies the SHA-256 digest when provided, downloads the APK with progress, and
/// launches the Android package installer.
class AppUpdate {
  final String currentVersion;
  final String version;
  final String releaseNotes;
  final String apkUrl;
  final String? sha256;

  AppUpdate({
    required this.currentVersion,
    required this.version,
    required this.releaseNotes,
    required this.apkUrl,
    this.sha256,
  });

  static const _latestUrl =
      'https://api.github.com/repos/mastrien/dialogue/releases/latest';

  static Future<AppUpdate?> check() async {
    if (!Platform.isAndroid) return null;
    try {
      final response = await http
          .get(
            Uri.parse(_latestUrl),
            headers: const {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;

      final release = jsonDecode(response.body) as Map<String, dynamic>;
      final latest =
          (release['tag_name'] as String).trim().replaceFirst(RegExp(r'^v'), '');
      final current = (await PackageInfo.fromPlatform()).version;
      if (!isNewerVersion(latest, current)) return null;

      final apk = (release['assets'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .where((a) => (a['name'] as String).endsWith('.apk'))
          .firstOrNull;
      if (apk == null) return null;

      final digest = apk['digest'] as String?;
      return AppUpdate(
        currentVersion: current,
        version: latest,
        releaseNotes: (release['body'] as String?) ?? '',
        apkUrl: apk['browser_download_url'] as String,
        sha256: digest != null && digest.startsWith('sha256:')
            ? digest.substring(7)
            : null,
      );
    } catch (_) {
      return null;
    }
  }

  Stream<OtaEvent> install() => OtaUpdate().execute(
        apkUrl,
        destinationFilename: 'dialogue-$version.apk',
        sha256checksum: sha256 ?? '',
      );
}

bool isNewerVersion(String candidate, String current) {
  List<int> parts(String v) => v
      .split('-')
      .first
      .split('.')
      .map((p) => int.tryParse(p) ?? 0)
      .toList();

  final a = parts(candidate);
  final b = parts(current);
  for (var i = 0; i < 3; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}
