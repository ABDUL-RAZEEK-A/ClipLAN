import 'package:hive_flutter/hive_flutter.dart';
import '../models/transfer_item.dart';
import '../models/clipboard_item.dart';

/// Hive-backed persistence for settings, transfer history, and My Clipboard.
class StorageService {
  static const String _settingsBox = 'settings';
  static const String _historyBox = 'history';
  static const String _clipboardBox = 'my_clipboard';

  late Box<dynamic> _settings;
  late Box<dynamic> _history;
  late Box<dynamic> _clipboard;

  Future<void> init() async {
    _settings = await Hive.openBox(_settingsBox);
    _history = await Hive.openBox(_historyBox);
    _clipboard = await Hive.openBox(_clipboardBox);
  }

  // ---- Settings -----------------------------------------------------------

  String get deviceName =>
      _settings.get('deviceName', defaultValue: 'My Device') as String;
  set deviceName(String v) => _settings.put('deviceName', v);

  String get deviceId => _settings.get('deviceId', defaultValue: '') as String;
  set deviceId(String v) => _settings.put('deviceId', v);

  String get savePath => _settings.get('savePath', defaultValue: '') as String;
  set savePath(String v) => _settings.put('savePath', v);

  bool get requireApproval =>
      _settings.get('requireApproval', defaultValue: false) as bool;
  set requireApproval(bool v) => _settings.put('requireApproval', v);

  String get username => _settings.get('username', defaultValue: '') as String;
  set username(String v) => _settings.put('username', v);

  String get os => _settings.get('os', defaultValue: '') as String;
  set os(String v) => _settings.put('os', v);

  String get hardwareName =>
      _settings.get('hardwareName', defaultValue: '') as String;
  set hardwareName(String v) => _settings.put('hardwareName', v);

  String get avatarBase64 =>
      _settings.get('avatarBase64', defaultValue: '') as String;
  set avatarBase64(String v) => _settings.put('avatarBase64', v);

  bool get showDeviceIp =>
      _settings.get('showDeviceIp', defaultValue: false) as bool;
  set showDeviceIp(bool v) => _settings.put('showDeviceIp', v);

  /// Whether the user has completed the initial setup (device name).
  /// Modeled after the reference repo's `haveUser()` check.
  bool get hasCompletedSetup =>
      _settings.get('hasCompletedSetup', defaultValue: false) as bool;
  set hasCompletedSetup(bool v) => _settings.put('hasCompletedSetup', v);

  // ---- History ------------------------------------------------------------

  List<TransferItem> getHistory() {
    final items = <TransferItem>[];
    for (var i = 0; i < _history.length; i++) {
      try {
        final raw = _history.getAt(i);
        if (raw is Map) {
          items.add(
            TransferItem.fromHistoryJson(Map<String, dynamic>.from(raw)),
          );
        }
      } catch (_) {
        // skip corrupt entries
      }
    }
    items.sort((a, b) => b.startTime.compareTo(a.startTime));
    return items;
  }

  Future<void> addToHistory(TransferItem item) async {
    await _history.add(item.toHistoryJson());
  }

  Future<void> clearHistory() async {
    await _history.clear();
  }

  // ---- My Clipboard -------------------------------------------------------

  List<ClipboardItem> getMyClipboard() {
    final items = <ClipboardItem>[];
    for (var i = 0; i < _clipboard.length; i++) {
      try {
        final raw = _clipboard.getAt(i);
        if (raw is Map) {
          items.add(ClipboardItem.fromJson(Map<String, dynamic>.from(raw)));
        }
      } catch (_) {
        // skip corrupt entries
      }
    }
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  Future<void> saveMyClipboardItem(ClipboardItem item) async {
    final rawList = _clipboard.values.toList();
    int existingIndex = -1;
    for (int i = 0; i < rawList.length; i++) {
      if (rawList[i] is Map && rawList[i]['id'] == item.id) {
        existingIndex = i;
        break;
      }
    }

    if (existingIndex >= 0) {
      await _clipboard.putAt(existingIndex, item.toJson());
    } else {
      await _clipboard.add(item.toJson());
    }
  }

  Future<void> deleteMyClipboardItem(String id) async {
    final rawList = _clipboard.values.toList();
    for (int i = 0; i < rawList.length; i++) {
      if (rawList[i] is Map && rawList[i]['id'] == id) {
        await _clipboard.deleteAt(i);
        break;
      }
    }
  }

  Future<void> clearMyClipboard() async {
    await _clipboard.clear();
  }
}
