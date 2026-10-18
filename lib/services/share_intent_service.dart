import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef SharedFilesCallback = void Function(List<String> paths);

/// High-performance zero-copy Share Intent service.
/// Receives resolved absolute file paths directly from Android Intent
/// in <1ms without duplicating or copying multi-gigabyte files.
class ShareIntentService {
  static const MethodChannel _channel = MethodChannel('com.cliplan/shareIntent');
  static SharedFilesCallback? _onFilesReceived;

  static void init({required SharedFilesCallback onReceived}) {
    _onFilesReceived = onReceived;

    if (!Platform.isAndroid) return;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onSharedFiles') {
        final List<dynamic>? rawPaths = call.arguments as List<dynamic>?;
        if (rawPaths != null && rawPaths.isNotEmpty) {
          final paths = rawPaths.map((p) => p.toString()).toList();
          debugPrint('[ShareIntentService] onSharedFiles received ${paths.length} file(s)');
          _onFilesReceived?.call(paths);
        }
      }
    });

    // Fetch any files that launched the app from the share sheet
    _channel.invokeMethod<List<dynamic>>('getInitialSharedFiles').then((rawPaths) {
      if (rawPaths != null && rawPaths.isNotEmpty) {
        final paths = rawPaths.map((p) => p.toString()).toList();
        debugPrint('[ShareIntentService] getInitialSharedFiles received ${paths.length} file(s)');
        _onFilesReceived?.call(paths);
      }
    }).catchError((e) {
      debugPrint('[ShareIntentService] Error fetching initial shared files: $e');
    });
  }
}
