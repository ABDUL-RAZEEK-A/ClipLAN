import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:isolate';
import 'dart:ui';
import '../services/notification_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import '../models/device_info.dart';
import '../models/transfer_item.dart';
import '../models/clipboard_item.dart';
import '../services/discovery_service.dart';
import '../services/transfer_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

/// Central application state — manages discovery, transfers, history, clipboard, and settings.
class AppState extends ChangeNotifier with WidgetsBindingObserver {
  final StorageService storage;
  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
  DiscoveryService? _discovery;
  TransferService? _transfer;

  List<DeviceInfo> _devices = [];
  final List<TransferItem> _activeTransfers = [];
  List<TransferItem> _history = [];
  List<ClipboardItem> _myClipboard = [];
  final List<Map<String, dynamic>> _sharedClipboards = [];
  bool _isDiscovering = false;
  bool _isInForeground = true; // Track app lifecycle for notification optimization

  // Rate limiter (0.0 = unlimited, > 0 = Mbps)
  double _transferSpeedLimitMbps = 0.0; // Default to unlimited for maximum speed

  /// Timers that must be cancelled on dispose to prevent setState-after-dispose crashes.
  final List<Timer> _pendingTimers = [];

  /// Throttle UI rebuilds during high-frequency transfer progress updates.
  Timer? _progressThrottleTimer;
  bool _progressDirty = false;

  /// Set by the HomeScreen to display approval bottom-sheets.
  Future<bool> Function(TransferItem)? showApprovalDialog;

  /// Set by the UI to display clipboard approval dialogs.
  Future<bool> Function(Map<String, dynamic>)? onClipboardReceived;

  // ---- Getters ------------------------------------------------------------

  List<DeviceInfo> get devices => List.unmodifiable(_devices);
  List<TransferItem> get activeTransfers => List.unmodifiable(_activeTransfers);
  List<TransferItem> get history => List.unmodifiable(_history);
  List<ClipboardItem> get myClipboard => List.unmodifiable(_myClipboard);
  List<Map<String, dynamic>> get sharedClipboards =>
      List.unmodifiable(_sharedClipboards);
  bool get isDiscovering => _isDiscovering;
  bool get isServerRunning => _transfer != null;
  String? get localIp => _discovery?.localIp;
  bool get isOnline => localIp != null && localIp!.isNotEmpty && localIp != '127.0.0.1' && localIp != '0.0.0.0';
  int get serverPort => _transfer?.port ?? 53318;
  String get deviceId => storage.deviceId;
  String get deviceName => storage.deviceName;
  String get username => storage.username;
  String get avatarBase64 => storage.avatarBase64;
  String get os => storage.os;
  String get hardwareName => storage.hardwareName;
  String get savePath => storage.savePath;
  bool get requireApproval => storage.requireApproval;
  double get transferSpeedLimit => _transferSpeedLimitMbps;
  bool get showDeviceIp => storage.showDeviceIp;

  /// Whether the first-launch setup has been completed (device name set).
  /// Modeled after reference repo's `haveUser()`.
  bool get hasCompletedSetup => storage.hasCompletedSetup;

  /// Mark setup as done and persist. Called after username dialog.
  void completeSetup(String name) {
    storage.username = name;
    storage.deviceName = name;
    storage.hasCompletedSetup = true;
    _discovery?.updateUsername(name);
    _discovery?.updateDeviceName(name);
    _transfer?.updateDeviceName(name);
    notifyListeners();
  }

  // ---- Lifecycle ----------------------------------------------------------

  AppState(this.storage) {
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _init();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    _isInForeground = (state == AppLifecycleState.resumed);
    
    if (state == AppLifecycleState.resumed) {
      // Clear any lingering progress notification when re-entering app
      NotificationService().cancelNotification(888);
      // startServer is now guarded against redundant restarts internally
      _discovery?.start();
      _transfer?.startServer(savePath: storage.savePath);
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _discovery?.stop();
      // Only stop server if no active transfers to prevent data loss
      if (_activeTransfers.isEmpty) {
        _transfer?.stopServer();
      }
    }
  }

  Future<void> refreshDevices() async {
    _discovery?.refresh();
  }

  void addManualDevice(DeviceInfo device) {
    if (!_devices.any((d) => d.id == device.id)) {
      device.lastSeen = DateTime.now();
      _devices.add(device);
      notifyListeners();
    }
  }

  Future<void> broadcastClipboard(String text) async {
    // 1. Try UDP broadcast (fast, works on home networks)
    _discovery?.broadcastClipboard(text);

    // 2. Try TCP unicast to all known devices (works on restricted college networks)
    bool anySuccess = false;
    for (final device in _devices) {
      if (device.ip.isNotEmpty) {
        final success = await sendText(device, text);
        if (success) anySuccess = true;
      }
    }

    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(
          anySuccess
              ? 'Clipboard securely shared to network'
              : 'Failed to reach devices directly, sent via UDP.',
        ),
        backgroundColor: anySuccess ? AppColors.success : AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _init() async {
    try {
      debugPrint('[ClipLAN] _init started');

      // Ensure a persistent device ID
      if (storage.deviceId.isEmpty) {
        storage.deviceId = const Uuid().v4();
      }
      debugPrint('[ClipLAN] Device ID: ${storage.deviceId}');

      // Ensure save path
      if (storage.savePath.isEmpty) {
        if (Platform.isAndroid) {
          storage.savePath = '/storage/emulated/0/Download/ClipLAN';
        } else {
          final dir = await getApplicationDocumentsDirectory();
          storage.savePath = '${dir.path}/ClipLAN';
        }
      }
      debugPrint('[ClipLAN] Save path: ${storage.savePath}');

      final saveDir = Directory(storage.savePath);
      if (!await saveDir.exists()) {
        await saveDir.create(recursive: true);
      }
      debugPrint('[ClipLAN] Save directory ready');

      // Load history and My Clipboard
      _history = storage.getHistory();
      _myClipboard = storage.getMyClipboard();
      debugPrint('[ClipLAN] History loaded: ${_history.length} items');
      debugPrint('[ClipLAN] Clipboard loaded: ${_myClipboard.length} items');

      // Fetch Device Info if not set
      final deviceInfoPlugin = DeviceInfoPlugin();
      if (storage.os.isEmpty || storage.hardwareName.isEmpty) {
        if (Platform.isAndroid) {
          final info = await deviceInfoPlugin.androidInfo;
          storage.os = 'Android';
          storage.hardwareName = '${info.brand} ${info.model}';
        } else if (Platform.isIOS) {
          final info = await deviceInfoPlugin.iosInfo;
          storage.os = 'iOS';
          storage.hardwareName = info.utsname.machine;
        } else if (Platform.isMacOS) {
          final info = await deviceInfoPlugin.macOsInfo;
          storage.os = 'macOS';
          storage.hardwareName = info.model;
        } else if (Platform.isWindows) {
          storage.os = 'Windows';
          storage.hardwareName = 'PC';
        }
      }

      // Initialize Share Intent (Mobile Only)
      if (Platform.isAndroid || Platform.isIOS) {
        ReceiveSharingIntent.instance.getMediaStream().listen(
          (List<SharedMediaFile> value) {
            for (var file in value) {
              _handleSharedFile(file.path);
            }
          },
          onError: (err) {
            debugPrint("getIntentDataStream error: $err");
          },
        );
        ReceiveSharingIntent.instance.getInitialMedia().then((
          List<SharedMediaFile> value,
        ) {
          for (var file in value) {
            _handleSharedFile(file.path);
          }
          ReceiveSharingIntent.instance.reset();
        });
      }

      // Request permissions on Android
      if (Platform.isAndroid) {
        await Permission.nearbyWifiDevices.request();
        await Permission.storage.request();
        await Permission.manageExternalStorage.request();
        // Request notification permission for Android 13+
        await Permission.notification.request();
      }

      await NotificationService().init();

      // Listen for cancel events from the notification center
      final ReceivePort cancelPort = ReceivePort();
      IsolateNameServer.removePortNameMapping(kCancelPortName);
      IsolateNameServer.registerPortWithName(cancelPort.sendPort, kCancelPortName);
      cancelPort.listen((message) {
        if (message is String) {
          debugPrint('[AppState] Received cancel action from notification for transfer: $message');
          try {
            final t = _activeTransfers.firstWhere((t) => t.id == message);
            _transfer?.cancelTransfer(t);
          } catch (e) {
            debugPrint('[AppState] Could not find transfer to cancel: $e');
          }
        }
      });


      // Start transfer server
      final transfer = TransferService()
        ..updateDeviceName(storage.deviceName)
        ..updateSavePath(storage.savePath);
      _transfer = transfer;

      transfer.onApprovalRequired = _handleApproval;
      transfer.onTransferUpdate = _handleTransferUpdate;
      transfer.onClipboardData = _handleClipboardData;

      try {
        await transfer.startServer(savePath: storage.savePath);
        debugPrint(
          '[ClipLAN] Transfer server started on port ${transfer.port}',
        );
      } catch (e) {
        debugPrint('[ClipLAN] Transfer server failed: $e');
      }

      // Request iOS local network permission by triggering a network operation.
      // iOS only shows the Local Network permission dialog when the app first
      // attempts to use the local network, not at install time.
      if (Platform.isIOS) {
        await _triggerIosLocalNetworkPermission();
      }

      // Start discovery
      final discovery = DiscoveryService(
        deviceName: storage.deviceName,
        username: storage.username,
        os: storage.os,
        hardwareName: storage.hardwareName,
        deviceId: storage.deviceId,
        serverPort: transfer.port,
      );
      _discovery = discovery;

      discovery.devicesStream.listen((devices) {
        _devices = devices;
        notifyListeners();
      });

      discovery.clipboardStream.listen((data) {
        _handleClipboardData(data);
      });

      try {
        await discovery.start();
        _isDiscovering = true;
        debugPrint('[ClipLAN] Discovery started');
      } catch (e) {
        debugPrint('[ClipLAN] Discovery failed: $e');
      }

      // On iOS, the IP may become available after the user grants permission.
      // Re-check and notify UI periodically for the first 30 seconds.
      if (Platform.isIOS && !isOnline) {
        debugPrint('[ClipLAN] iOS: IP not available yet, starting retry loop...');
        for (int i = 0; i < 10; i++) {
          final timer = Timer(Duration(seconds: 3 * (i + 1)), () async {
            if (isOnline) return; // Already online, skip
            await _discovery?.refresh();
            notifyListeners();
            if (isOnline) {
              debugPrint('[ClipLAN] iOS: Now online after retry ${i + 1}');
            }
          });
          _pendingTimers.add(timer);
        }
      }

      debugPrint('[ClipLAN] _init completed successfully');
      notifyListeners();
    } catch (e, stackTrace) {
      debugPrint('[ClipLAN] _init FATAL ERROR: $e');
      debugPrint('[ClipLAN] Stack trace: $stackTrace');
      // Don't rethrow — let the app display the UI even if networking fails
      notifyListeners();
    }
  }

  // ---- Clipboard deduplication & handling ---------------------------------

  String? _lastClipboardHash;
  DateTime? _lastClipboardTime;
  bool _isShowingClipboardDialog = false;

  void _handleClipboardData(Map<String, dynamic> data) async {
    final text = data['text'] as String?;
    if (text == null) return;

    // Deduplicate identical incoming clipboard events within 2 seconds
    final hash = text + (data['senderId'] ?? '');
    final now = DateTime.now();
    if (_lastClipboardHash == hash &&
        _lastClipboardTime != null &&
        now.difference(_lastClipboardTime!).inSeconds < 2) {
      return;
    }
    _lastClipboardHash = hash;
    _lastClipboardTime = now;

    // Prevent stacking multiple dialogs
    if (_isShowingClipboardDialog) return;

    if (onClipboardReceived != null) {
      _isShowingClipboardDialog = true;
      final accepted = await onClipboardReceived!(data);
      _isShowingClipboardDialog = false;

      if (accepted) {
        _sharedClipboards.insert(0, data);
        notifyListeners();
        await Clipboard.setData(ClipboardData(text: data['text']));
        scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: const Text('Copied to clipboard'),
            backgroundColor: const Color(0xFF1F2937),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  // ---- Approval callback --------------------------------------------------

  Future<bool> _handleApproval(TransferItem transfer) async {
    _addOrUpdateTransfer(transfer);
    notifyListeners();

    // Guard: if the widget that owns the callback was unmounted, fall through
    // to auto-accept logic instead of calling a stale BuildContext.
    if (showApprovalDialog != null) {
      try {
        return await showApprovalDialog!(transfer);
      } catch (e) {
        debugPrint(
          '[AppState] showApprovalDialog threw (widget disposed?): $e',
        );
      }
    }
    
    // If we reach here, UI is likely backgrounded or detached. Show a notification.
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
            FlutterLocalNotificationsPlugin();
        await flutterLocalNotificationsPlugin.show(
          transfer.id.hashCode,
          'Incoming File',
          '${transfer.deviceName} wants to send you ${transfer.files.length} files.',
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'cliplan_foreground',
              'ClipLAN Service',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
        );
      } catch (e) {
        debugPrint('[AppState] Failed to show notification: $e');
      }
    }
    
    return !storage.requireApproval; // auto-accept if approval disabled
  }

  // ---- Transfer state updates ---------------------------------------------

  void setTransferSpeedLimit(double mbps) {
    _transferSpeedLimitMbps = mbps;
    if (_transfer != null) {
      _transfer!.updateSpeedLimit(mbps);
    }
    notifyListeners();
  }

  void _manageBackgroundService() async {
    if (!Platform.isAndroid) return;
    
    final hasActive = _activeTransfers.any((t) => !_isTerminal(t.status));
    final service = FlutterBackgroundService();
    if (hasActive) {
      if (!(await service.isRunning())) {
        await service.startService();
      }
    } else {
      if (await service.isRunning()) {
        service.invoke('stopService');
      }
    }
  }

  void _handleTransferUpdate(TransferItem transfer) {
    _addOrUpdateTransfer(transfer);

    if (_isTerminal(transfer.status)) {
      storage.addToHistory(transfer);
      _history = storage.getHistory();
      
      // Clear progress notification and show completion
      NotificationService().cancelNotification(888);
      
      if (!_isInForeground) {
        if (transfer.status == TransferStatus.completed) {
          NotificationService().showCompletionNotification(
            id: transfer.id.hashCode,
            title: 'Transfer Complete',
            body: '${transfer.deviceName} - ${transfer.files.length} file(s) transferred successfully.',
          );
        } else if (transfer.status == TransferStatus.failed) {
          NotificationService().showCompletionNotification(
            id: transfer.id.hashCode,
            title: 'Transfer Failed',
            body: 'Transfer with ${transfer.deviceName} failed.',
          );
        }
      }
      
      // Terminal state changes must update UI immediately
      notifyListeners();
      return;
    }

    // Throttle progress-only updates to max 2 rebuilds/sec to prevent UI jank
    if (transfer.status == TransferStatus.transferring) {
      _progressDirty = true;
      _progressThrottleTimer ??= Timer.periodic(
        const Duration(milliseconds: 500),
        (_) {
          if (_progressDirty) {
            _progressDirty = false;
            notifyListeners();
            
            // Update notification
            int progressPercent = 0;
            if (transfer.totalSize > 0) {
              progressPercent = ((transfer.bytesTransferred / transfer.totalSize) * 100).toInt();
            }
            
            if (!_isInForeground) {
              NotificationService().showProgressNotification(
                id: 888, // Foreground service notification ID
                title: transfer.direction == TransferDirection.receiving 
                    ? 'Receiving from ${transfer.deviceName}' 
                    : 'Sending to ${transfer.deviceName}',
                body: 'Transferring ${transfer.files.length} file(s)...',
                progress: progressPercent,
                maxProgress: 100,
                payload: transfer.id,
              );
            }
          } else {
            _progressThrottleTimer?.cancel();
            _progressThrottleTimer = null;
          }
        },
      );
    } else {
      // Status changes (waitingApproval, etc.) update immediately
      notifyListeners();
    }
  }

  void _addOrUpdateTransfer(TransferItem t) {
    final idx = _activeTransfers.indexWhere((a) => a.id == t.id);
    if (idx >= 0) {
      _activeTransfers[idx] = t;
    } else {
      _activeTransfers.add(t);
    }
    _manageBackgroundService();
  }

  void dismissTransfer(String transferId) {
    _activeTransfers.removeWhere((t) => t.id == transferId);
    _manageBackgroundService();
    notifyListeners();
  }

  void clearTerminalTransfers() {
    _activeTransfers.removeWhere((t) => _isTerminal(t.status));
    _manageBackgroundService();
    notifyListeners();
  }

  bool _isTerminal(TransferStatus s) =>
      s == TransferStatus.completed ||
      s == TransferStatus.failed ||
      s == TransferStatus.cancelled;

  // ---- Send files ---------------------------------------------------------

  Future<void> sendFiles(
    DeviceInfo device,
    List<PlatformFile> files, {
    bool enableHashing = false,
  }) async {
    final fileItems = files
        .map(
          (f) => FileItem(
            name: f.name,
            size: f.size,
            path: f.path,
            mime: _guessMime(f.name),
          ),
        )
        .toList();

    final transferId = const Uuid().v4();

    await _transfer?.sendFiles(
      transferId: transferId,
      device: device,
      files: fileItems,
      onUpdate: _handleTransferUpdate,
      enableHashing: enableHashing,
      speedLimitMBps: _transferSpeedLimitMbps.toInt(),
    );
  }

  /// Send raw text as a direct TCP clipboard share instead of a text file.
  Future<bool> sendText(DeviceInfo device, String text) async {
    try {
      final success = await _transfer?.sendClipboard(text, device);
      return success ?? false;
    } catch (e) {
      debugPrint('[AppState] Failed to send TCP clipboard: $e');
      return false;
    }
  }

  // ---- Transfer controls --------------------------------------------------

  void cancelTransfer(TransferItem transfer) {
    _transfer?.cancelTransfer(transfer);
  }

  Future<void> retryTransfer(TransferItem transfer) async {
    if (transfer.direction != TransferDirection.sending) return;

    final device = _devices.firstWhere(
      (d) => d.ip == transfer.deviceIp,
      orElse: () => DeviceInfo(
        id: '',
        name: transfer.deviceName,
        ip: transfer.deviceIp,
        port: TransferService.defaultPort,
        platform: 'unknown',
      ),
    );

    final fileItems = transfer.files
        .map(
          (f) =>
              FileItem(name: f.name, size: f.size, path: f.path, mime: f.mime),
        )
        .toList();

    await _transfer?.sendFiles(
      transferId: const Uuid().v4(),
      device: device,
      files: fileItems,
      onUpdate: _handleTransferUpdate,
      speedLimitMBps: _transferSpeedLimitMbps.toInt(),
    );
  }

  // ---- Settings -----------------------------------------------------------

  void updateDeviceName(String name) {
    storage.deviceName = name;
    _discovery?.updateDeviceName(name);
    _transfer?.updateDeviceName(name);
    notifyListeners();
  }

  void updateUsername(String name) {
    storage.username = name;
    _discovery?.updateUsername(name);
    notifyListeners();
  }

  void updateAvatarBase64(String b64) {
    storage.avatarBase64 = b64;
    notifyListeners();
  }

  final List<String> _pendingSharedFiles = [];
  List<String> get pendingSharedFiles => List.unmodifiable(_pendingSharedFiles);

  void _handleSharedFile(String path) {
    debugPrint('[ClipLAN] Received shared file: $path');
    _pendingSharedFiles.add(path);
    notifyListeners();
  }

  void consumeSharedFiles() {
    _pendingSharedFiles.clear();
    notifyListeners();
  }

  void updateSavePath(String path) {
    storage.savePath = path;
    _transfer?.updateSavePath(path);
    notifyListeners();
  }

  void updateRequireApproval(bool value) {
    storage.requireApproval = value;
    notifyListeners();
  }

  void updateShowDeviceIp(bool value) {
    storage.showDeviceIp = value;
    notifyListeners();
  }

  Future<void> clearHistory() async {
    await storage.clearHistory();
    _history = [];
    notifyListeners();
  }

  // ---- Clipboard Management -----------------------------------------------

  Future<void> addMyClipboardText(String text) async {
    if (text.trim().isEmpty) return;
    final item = ClipboardItem.create(text.trim());
    await storage.saveMyClipboardItem(item);
    _myClipboard = storage.getMyClipboard();
    notifyListeners();
  }

  Future<void> updateMyClipboardItem(String id, String text) async {
    if (text.trim().isEmpty) return;
    final index = _myClipboard.indexWhere((item) => item.id == id);
    if (index >= 0) {
      final updated = _myClipboard[index].copyWith(text: text.trim());
      await storage.saveMyClipboardItem(updated);
      _myClipboard = storage.getMyClipboard();
      notifyListeners();
    }
  }

  Future<void> deleteMyClipboardItem(String id) async {
    await storage.deleteMyClipboardItem(id);
    _myClipboard = storage.getMyClipboard();
    notifyListeners();
  }

  Future<void> clearMyClipboard() async {
    await storage.clearMyClipboard();
    _myClipboard = [];
    notifyListeners();
  }

  Future<void> acceptSharedClipboard(Map<String, dynamic> sharedData) async {
    final text = sharedData['text'] as String? ?? '';
    final senderName =
        sharedData['deviceName'] as String? ??
        sharedData['senderName'] as String?;
    if (text.trim().isEmpty) return;

    final item = ClipboardItem.create(
      text.trim(),
      senderName: senderName,
      isShared: true,
    );
    await storage.saveMyClipboardItem(item);
    _myClipboard = storage.getMyClipboard();

    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: const Text('Saved to My Clipboard!'),
        backgroundColor: const Color(0xFF1F2937),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    notifyListeners();
  }

  void dismissSharedClipboard(int index) {
    if (index >= 0 && index < _sharedClipboards.length) {
      _sharedClipboards.removeAt(index);
      notifyListeners();
    }
  }

  // ---- Helpers ------------------------------------------------------------

  /// Trigger the iOS Local Network permission dialog by performing a network
  /// operation that requires local network access. iOS lazily shows this dialog
  /// only on the first LAN operation, so we fire a dummy multicast/broadcast
  /// to prompt it during app init.
  Future<void> _triggerIosLocalNetworkPermission() async {
    try {
      debugPrint('[ClipLAN] iOS: Triggering local network permission...');
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
      );
      socket.broadcastEnabled = true;
      // Send a tiny packet to the broadcast address — this is what triggers
      // the iOS "allow local network access" system dialog
      socket.send(
        [0x43, 0x4C], // "CL" bytes
        InternetAddress('255.255.255.255'),
        53317,
      );
      await Future.delayed(const Duration(milliseconds: 500));
      socket.close();
      debugPrint('[ClipLAN] iOS: Local network permission trigger sent');
    } catch (e) {
      debugPrint('[ClipLAN] iOS: Local network permission trigger failed: $e');
    }
  }

  String _guessMime(String name) {
    final ext = name.split('.').last.toLowerCase();
    const map = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'svg': 'image/svg+xml',
      'mp4': 'video/mp4',
      'mov': 'video/quicktime',
      'avi': 'video/x-msvideo',
      'mp3': 'audio/mpeg',
      'wav': 'audio/wav',
      'aac': 'audio/aac',
      'pdf': 'application/pdf',
      'doc': 'application/msword',
      'docx':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'txt': 'text/plain',
      'csv': 'text/csv',
      'json': 'application/json',
      'zip': 'application/zip',
      'rar': 'application/x-rar-compressed',
      'apk': 'application/vnd.android.package-archive',
    };
    return map[ext] ?? 'application/octet-stream';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Cancel all pending timers so they don't call notifyListeners after disposal.
    _progressThrottleTimer?.cancel();
    _progressThrottleTimer = null;
    for (final t in _pendingTimers) {
      t.cancel();
    }
    _pendingTimers.clear();
    // Nullify UI callbacks to release BuildContext references held by widgets.
    showApprovalDialog = null;
    onClipboardReceived = null;
    _discovery?.dispose();
    _transfer?.dispose();
    super.dispose();
  }
}
