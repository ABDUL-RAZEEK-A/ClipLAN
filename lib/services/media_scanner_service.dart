import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service to notify the host OS (especially Android MediaStore)
/// to immediately index newly received files so they appear in
/// Gallery, Downloads, and File managers without any delay.
class MediaScannerService {
  static const MethodChannel _channel = MethodChannel('com.cliplan/mediaScanner');

  /// Requests the OS to immediately scan and index the given file path.
  static Future<void> scanFile(String filePath) async {
    if (!Platform.isAndroid || filePath.isEmpty) return;
    try {
      await _channel.invokeMethod('scanFile', {'path': filePath});
      debugPrint('[MediaScanner] Scanned file: $filePath');
    } catch (e) {
      debugPrint('[MediaScanner] Failed to scan file $filePath: $e');
    }
  }

  /// Batch scans multiple files immediately.
  static Future<void> scanFiles(List<String> filePaths) async {
    if (!Platform.isAndroid || filePaths.isEmpty) return;
    try {
      final validPaths = filePaths.where((p) => p.isNotEmpty).toList();
      if (validPaths.isEmpty) return;
      await _channel.invokeMethod('scanFiles', {'paths': validPaths});
      debugPrint('[MediaScanner] Batch scanned ${validPaths.length} files');
    } catch (e) {
      debugPrint('[MediaScanner] Failed to scan files: $e');
    }
  }
}
