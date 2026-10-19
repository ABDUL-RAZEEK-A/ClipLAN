import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// High-performance zero-copy File & Media Picker for Android.
/// Bypasses FilePicker's slow cache-copying behavior on Android,
/// resolving 3GB+ files directly to disk paths in <1ms.
class NativePickerService {
  static const MethodChannel _channel = MethodChannel('com.cliplan/nativePicker');

  static bool get isSupported => Platform.isAndroid;

  /// Picks files or media directly from the Android system / gallery.
  /// [type] can be 'any', 'media', 'image', or 'video'.
  static Future<List<PlatformFile>?> pickFiles({
    bool allowMultiple = true,
    String type = 'any',
  }) async {
    if (!Platform.isAndroid) return null;

    try {
      final List<dynamic>? rawResults = await _channel.invokeMethod('pickFiles', {
        'allowMultiple': allowMultiple,
        'type': type,
      });

      if (rawResults == null || rawResults.isEmpty) return null;

      final files = <PlatformFile>[];
      for (final item in rawResults) {
        if (item is Map) {
          final map = Map<String, dynamic>.from(item);
          final path = map['path']?.toString() ?? '';
          final name = map['name']?.toString() ?? path.split(Platform.pathSeparator).last;
          final size = (map['size'] as num?)?.toInt() ?? 0;

          if (path.isNotEmpty) {
            files.add(PlatformFile(
              path: path,
              name: name,
              size: size,
            ));
          }
        }
      }
      return files.isNotEmpty ? files : null;
    } catch (e) {
      debugPrint('[NativePickerService] Error picking files: $e');
      return null;
    }
  }
}
