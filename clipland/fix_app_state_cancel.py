import re

with open('lib/providers/app_state.dart', 'r') as f:
    content = f.read()

# Fix cancelTransfer(message) -> cancelTransfer(transfer)
content = content.replace('''      cancelPort.listen((message) {
        if (message is String) {
          debugPrint('[AppState] Received cancel action from notification for transfer: $message');
          _transfer?.cancelTransfer(message);
        }
      });''', '''      cancelPort.listen((message) {
        if (message is String) {
          debugPrint('[AppState] Received cancel action from notification for transfer: $message');
          try {
            final t = _activeTransfers.firstWhere((t) => t.id == message);
            _transfer?.cancelTransfer(t);
          } catch (e) {
            debugPrint('[AppState] Could not find transfer to cancel: $e');
          }
        }
      });''')

with open('lib/providers/app_state.dart', 'w') as f:
    f.write(content)
