import re

with open('lib/providers/app_state.dart', 'r') as f:
    content = f.read()

# Add imports
content = content.replace(
    "import '../services/background_service.dart';",
    "import '../services/background_service.dart';\nimport '../services/notification_service.dart';\nimport 'dart:isolate';\nimport 'dart:ui';"
)

# Initialize NotificationService and listen to IsolateNameServer
init_replacement = '''
      final storageService = StorageService();
      // ... handled elsewhere, we are inside AppState._init()
'''
# Actually let's just patch _init() inside app_state.dart.
# Find: `await Permission.manageExternalStorage.request();`
# Replace with that plus initialization.

content = content.replace(
'''      if (Platform.isAndroid) {
        await Permission.nearbyWifiDevices.request();
        await Permission.storage.request();
        await Permission.manageExternalStorage.request();
      }''',
'''      if (Platform.isAndroid) {
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
          _transfer?.cancelTransfer(message);
        }
      });
'''
)

# Modify _handleTransferUpdate
content = content.replace(
'''    if (_isTerminal(transfer.status)) {
      storage.addToHistory(transfer);
      _history = storage.getHistory();
      // Terminal state changes must update UI immediately
      notifyListeners();
      return;
    }''',
'''    if (_isTerminal(transfer.status)) {
      storage.addToHistory(transfer);
      _history = storage.getHistory();
      
      // Clear progress notification and show completion
      NotificationService().cancelNotification(888);
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
      
      // Terminal state changes must update UI immediately
      notifyListeners();
      return;
    }'''
)

# Modify _handleTransferUpdate for progress
content = content.replace(
'''    // Throttle progress-only updates to max 2 rebuilds/sec to prevent UI jank
    if (transfer.status == TransferStatus.transferring) {
      _progressDirty = true;
      _progressThrottleTimer ??= Timer.periodic(
        const Duration(milliseconds: 500),
        (_) {
          if (_progressDirty) {
            _progressDirty = false;
            notifyListeners();
          } else {
            _progressThrottleTimer?.cancel();
            _progressThrottleTimer = null;
          }
        },
      );
    }''',
'''    // Throttle progress-only updates to max 2 rebuilds/sec to prevent UI jank
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
              progressPercent = ((transfer.transferredBytes / transfer.totalSize) * 100).toInt();
            }
            
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
          } else {
            _progressThrottleTimer?.cancel();
            _progressThrottleTimer = null;
          }
        },
      );
    }'''
)

with open('lib/providers/app_state.dart', 'w') as f:
    f.write(content)
