import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/device_info.dart';
import '../models/transfer_item.dart';
import 'rate_limiter.dart';

typedef TransferApprovalCallback = Future<bool> Function(TransferItem transfer);
typedef TransferUpdateCallback = void Function(TransferItem transfer);

// A simple buffered reader to safely read exact bytes from a TCP socket
class ConnectionReader {
  final Socket _socket;
  final List<Uint8List> _chunks = [];
  int _bufferLength = 0;
  StreamSubscription<Uint8List>? _subscription;
  Completer<void>? _dataReadyCompleter;
  bool _isClosed = false;

  ConnectionReader(this._socket) {
    _subscription = _socket.listen(
      (data) {
        _chunks.add(data);
        _bufferLength += data.length;
        if (!_dataReadyCompleter!.isCompleted) {
          _dataReadyCompleter!.complete();
        }

        // Prevent OOM by pausing when buffer gets too large (4MB)
        if (_bufferLength > 4 * 1024 * 1024) {
          _subscription?.pause();
        }
      },
      onError: (e) {
        debugPrint('[ConnectionReader] Socket error: $e');
        _isClosed = true;
        if (!_dataReadyCompleter!.isCompleted) {
          _dataReadyCompleter!.completeError(e);
        }
      },
      onDone: () {
        _isClosed = true;
        if (!_dataReadyCompleter!.isCompleted) {
          _dataReadyCompleter!.complete();
        }
      },
      cancelOnError: true,
    );
    _dataReadyCompleter = Completer<void>();
  }

  Future<Uint8List?> readExact(int count) async {
    while (_bufferLength < count) {
      if (_isClosed) {
        if (_bufferLength < count) return null; // EOF
        break;
      }
      try {
        await _dataReadyCompleter!.future;
        if (!_isClosed && _bufferLength < count) {
          _dataReadyCompleter = Completer<void>();
        }
      } catch (e) {
        return null;
      }
    }

    if (_bufferLength < count) return null;

    final result = Uint8List(count);
    int offset = 0;
    while (offset < count) {
      final chunk = _chunks.first;
      if (offset + chunk.length <= count) {
        result.setAll(offset, chunk);
        offset += chunk.length;
        _chunks.removeAt(0);
      } else {
        final remaining = count - offset;
        result.setAll(offset, chunk.sublist(0, remaining));
        _chunks[0] = chunk.sublist(remaining);
        offset += remaining;
      }
    }
    _bufferLength -= count;

    // Resume reading if buffer drains (under 2MB)
    if (_bufferLength < 2 * 1024 * 1024 && (_subscription?.isPaused ?? false)) {
      _subscription?.resume();
    }

    if (_bufferLength == 0 && !_isClosed && _dataReadyCompleter!.isCompleted) {
      _dataReadyCompleter = Completer<void>();
    }

    return result;
  }

  /// Streams exactly [count] bytes directly to the provided [sink], bypassing memory allocation.
  /// Extremely fast for large file transfers.
  Future<void> streamBytesTo(
    int count,
    IOSink sink, {
    void Function(int)? onProgress,
    void Function(Uint8List)? onChunk,
  }) async {
    int remaining = count;

    int bytesSinceFlush = 0;
    while (remaining > 0) {
      if (_isClosed && _bufferLength == 0) {
        throw Exception('Connection closed prematurely');
      }

      if (_bufferLength == 0) {
        // Resume if paused to get more data
        if (_subscription?.isPaused ?? false) {
          _subscription?.resume();
        }
        try {
          await _dataReadyCompleter!.future;
          if (!_isClosed && _bufferLength == 0) {
            _dataReadyCompleter = Completer<void>();
            continue;
          }
        } catch (e) {
          throw Exception('Connection lost');
        }
      }

      while (remaining > 0 && _chunks.isNotEmpty) {
        final chunk = _chunks.first;
        final int amountRead;
        if (chunk.length <= remaining) {
          sink.add(chunk);
          onChunk?.call(chunk);
          amountRead = chunk.length;
          _chunks.removeAt(0);
        } else {
          final sub = chunk.sublist(0, remaining);
          sink.add(sub);
          onChunk?.call(sub);
          _chunks[0] = chunk.sublist(remaining);
          amountRead = remaining;
        }

        remaining -= amountRead;
        _bufferLength -= amountRead;
        bytesSinceFlush += amountRead;

        // Resume reading if buffer drains (under 2MB)
        if (_bufferLength < 2 * 1024 * 1024 &&
            (_subscription?.isPaused ?? false)) {
          _subscription?.resume();
        }

        onProgress?.call(amountRead);

        if (bytesSinceFlush >= 1024 * 1024 * 10) {
          await sink.flush();
          bytesSinceFlush = 0;
        }
      }

      if (_bufferLength == 0 &&
          !_isClosed &&
          _dataReadyCompleter!.isCompleted) {
        _dataReadyCompleter = Completer<void>();
      }
    }
  }

  Future<Map<String, dynamic>?> readMessage() async {
    final lengthBytes = await readExact(4);
    if (lengthBytes == null) return null;
    final length = ByteData.sublistView(lengthBytes).getUint32(0, Endian.big);

    // Protect against absurdly large messages
    if (length == 0 || length > 20 * 1024 * 1024) return null;

    final jsonBytes = await readExact(length);
    if (jsonBytes == null) return null;

    try {
      final jsonString = utf8.decode(jsonBytes);
      return jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[ConnectionReader] Failed to parse message: $e');
      return null;
    }
  }

  void dispose() {
    _subscription?.cancel();
    if (!_dataReadyCompleter!.isCompleted) {
      _dataReadyCompleter!.complete();
    }
  }
}

class TransferService {
  static const int defaultPort = 53318;
  static const int chunkSize = 1024 * 1024; // 1 MB chunk sizes

  ServerSocket? _server;
  int _port = defaultPort;
  String? _savePath;
  int _activeTransferCount = 0;
  String _deviceName = 'ClipLAN Device';

  double _speedLimitMbps = 0.0;
  RateLimiter? _rateLimiter;

  TransferApprovalCallback? onApprovalRequired;
  TransferUpdateCallback? onTransferUpdate;
  Function(Map<String, dynamic>)? onClipboardData;

  int get port => _port;

  void updateDeviceName(String name) => _deviceName = name;
  void updateSavePath(String path) => _savePath = path;

  void updateSpeedLimit(double mbps) {
    _speedLimitMbps = mbps;
    if (mbps > 0) {
      // Convert Mbps to Bytes per second: (Mbps * 1,000,000) / 8
      _rateLimiter = RateLimiter((mbps * 1000000 / 8).round());
    } else {
      _rateLimiter = null;
    }
  }

  // ---------------------------------------------------------------------------
  // Messaging Helpers
  // ---------------------------------------------------------------------------
  Future<void> _sendMessage(Socket socket, Map<String, dynamic> msg) async {
    try {
      final jsonBytes = utf8.encode(jsonEncode(msg));
      final header = ByteData(4)..setUint32(0, jsonBytes.length, Endian.big);
      socket.add(header.buffer.asUint8List());
      socket.add(jsonBytes);
      await socket.flush();
    } catch (e) {
      debugPrint('[TransferService] Failed to send message: $e');
      throw Exception('Socket disconnected while sending message');
    }
  }

  // ---------------------------------------------------------------------------
  // Server implementation
  // ---------------------------------------------------------------------------
  Future<void> startServer({String? savePath}) async {
    if (savePath != null) _savePath = savePath;
    if (_savePath == null || _savePath!.isEmpty) {
      final dir = await getApplicationDocumentsDirectory();
      _savePath = '${dir.path}/ClipLAN';
    }

    final saveDir = Directory(_savePath!);
    if (!await saveDir.exists()) {
      await saveDir.create(recursive: true);
    }

    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, _port);
    } catch (_) {
      // Fallback to random port if default is busy
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      _port = _server!.port;
    }

    _server!.listen(_handleIncomingConnection);
    debugPrint('[TransferService] Listening on port $_port');
  }

  Future<void> stopServer() async {
    await _server?.close();
    _server = null;
  }

  Future<void> _handleIncomingConnection(Socket socket) async {
    socket.setOption(SocketOption.tcpNoDelay, true);
    final reader = ConnectionReader(socket);
    TransferItem? transfer;

    try {
      final request = await reader.readMessage();
      if (request == null) {
        socket.destroy();
        return;
      }

      // Handle Clipboard
      if (request['type'] == 'clipboard') {
        final data = {
          'text': request['text'] ?? '',
          'senderName': request['senderName'] ?? 'Unknown Device',
          'senderId': request['id'] ?? '',
          'timestamp': DateTime.now().toIso8601String(),
        };
        onClipboardData?.call(data);
        socket.destroy();
        return;
      }

      // Handle File Transfer
      if (request['type'] == 'transfer_request') {
        final filesJson = request['files'] as List;
        final files = filesJson
            .map((f) => FileItem.fromJson(f as Map<String, dynamic>))
            .toList();

        _activeTransferCount++;
        if (_activeTransferCount == 1) WakelockPlus.enable();

        transfer = TransferItem(
          id: request['id'] as String,
          deviceName: request['senderName'] as String,
          deviceIp: socket.remoteAddress.address,
          direction: TransferDirection.receiving,
          files: files,
          status: TransferStatus.waitingApproval,
          socket: socket,
        );
        onTransferUpdate?.call(transfer);

        // Ask for permission
        final approved = await onApprovalRequired?.call(transfer) ?? false;

        await _sendMessage(socket, {
          'type': 'transfer_response',
          'id': transfer.id,
          'accepted': approved,
        });

        if (!approved) {
          transfer.status = TransferStatus.cancelled;
          onTransferUpdate?.call(transfer);
          socket.destroy();
          return;
        }

        transfer.status = TransferStatus.transferring;
        onTransferUpdate?.call(transfer);

        // Receive files one by one
        for (int i = 0; i < files.length; i++) {
          final fileInfo = await reader.readMessage();
          if (fileInfo == null || fileInfo['type'] == 'cancel') {
            throw Exception('Sender cancelled transfer');
          }

          if (fileInfo['type'] != 'file_start') {
            throw Exception('Protocol error: expected file_start');
          }

          transfer.currentFileIndex = i;
          final fileName = fileInfo['name'] as String;
          final fileSize = fileInfo['size'] as int;

          final filePath = _getUniqueFilePath('$_savePath/$fileName');
          transfer!.files[i].path = filePath;
          final file = File(filePath);
          final sink = file.openWrite();

          final hashEnabled = fileInfo['hashEnabled'] == true;

          int bytesReceived = 0;
          final sha256Sink = hashEnabled ? AccumulatorSink<Digest>() : null;
          final sha256Input = hashEnabled
              ? sha256.startChunkedConversion(sha256Sink!)
              : null;

          DateTime lastUpdate = DateTime.now();

          await reader.streamBytesTo(
            fileSize,
            sink,
            onChunk: (chunk) {
              if (hashEnabled) sha256Input?.add(chunk);
            },
            onProgress: (amountRead) {
              if (transfer!.status == TransferStatus.failed ||
                  transfer.status == TransferStatus.cancelled) {
                throw Exception('Transfer cancelled');
              }

              transfer.bytesTransferred += amountRead;
              final now = DateTime.now();
              if (now.difference(lastUpdate).inMilliseconds > 50) {
                onTransferUpdate?.call(transfer);
                lastUpdate = now;
              }
            },
          );

          onTransferUpdate?.call(transfer!);

          await sink.flush();
          await sink.close();
          sha256Input?.close();

          final actualHash = hashEnabled
              ? sha256Sink!.events.single.toString()
              : null;
          final fileEnd = await reader.readMessage();

          if (fileEnd == null || fileEnd['type'] != 'file_end') {
            throw Exception('Protocol error: expected file_end');
          }

          final expectedHash = fileEnd['checksum'] as String?;
          final hashValid =
              !hashEnabled ||
              (expectedHash == null) ||
              (actualHash == expectedHash);
          transfer!.files[i].checksum = actualHash;

          // Send ACK for this file
          await _sendMessage(socket, {
            'type': 'ack',
            'fileIndex': i,
            'checksumValid': hashValid,
          });

          if (!hashValid) {
            transfer!.checksumValid = false;
          }
        }

        // Wait for final completion signal
        final completeMsg = await reader.readMessage();
        if (completeMsg != null && completeMsg['type'] == 'transfer_complete') {
          transfer!.status = TransferStatus.completed;
        } else {
          transfer!.status = TransferStatus.failed;
          transfer!.errorMessage = 'Did not receive transfer_complete';
        }

        transfer!.endTime = DateTime.now();
        onTransferUpdate?.call(transfer!);
      } else {
        socket.destroy();
      }
    } catch (e) {
      if (transfer != null) {
        if (transfer.status != TransferStatus.failed &&
            transfer.status != TransferStatus.cancelled) {
          transfer.status = TransferStatus.failed;
          transfer.errorMessage = e.toString();
        }
        onTransferUpdate?.call(transfer);
      }
    } finally {
      _activeTransferCount--;
      if (_activeTransferCount <= 0) {
        _activeTransferCount = 0;
        WakelockPlus.disable();
      }
      reader.dispose();
      socket.destroy();
    }
  }

  // ---------------------------------------------------------------------------
  // Client implementation
  // ---------------------------------------------------------------------------
  Future<bool> sendClipboard(String text, DeviceInfo device) async {
    const int maxRetries = 3;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final socket = await Socket.connect(
          device.ip,
          device.port,
          timeout: const Duration(seconds: 5),
        );
        await _sendMessage(socket, {
          'type': 'clipboard',
          'id': 'clip-${DateTime.now().millisecondsSinceEpoch}',
          'senderName': _deviceName,
          'text': text,
        });
        await socket.flush();
        await socket.close();
        return true; // Success
      } catch (e) {
        debugPrint(
          '[TransferService] Clipboard attempt $attempt failed to ${device.ip}: $e',
        );
        if (attempt < maxRetries) {
          await Future.delayed(const Duration(seconds: 1)); // Wait before retry
        }
      }
    }
    return false; // Failed all retries
  }

  Future<TransferItem> sendFiles({
    required String transferId,
    required DeviceInfo device,
    required List<FileItem> files,
    required TransferUpdateCallback onUpdate,
    bool enableHashing = true,
  }) async {
    final transfer = TransferItem(
      id: transferId,
      deviceName: device.name,
      deviceIp: device.ip,
      direction: TransferDirection.sending,
      files: files,
      status: TransferStatus.pending,
    );

    _activeTransferCount++;
    if (_activeTransferCount == 1) WakelockPlus.enable();

    try {
      final socket = await Socket.connect(
        device.ip,
        device.port,
        timeout: const Duration(seconds: 10),
      );
      socket.setOption(SocketOption.tcpNoDelay, true);
      transfer.socket = socket;
      final reader = ConnectionReader(socket);

      transfer.status = TransferStatus.waitingApproval;
      onUpdate(transfer);

      // Send Request
      await _sendMessage(socket, {
        'type': 'transfer_request',
        'id': transferId,
        'senderName': _deviceName,
        'files': files.map((f) => f.toJson()).toList(),
      });

      // Wait for response
      final response = await reader.readMessage();
      if (response == null || response['accepted'] != true) {
        transfer.status = TransferStatus.cancelled;
        transfer.errorMessage = 'Transfer rejected by receiver';
        onUpdate(transfer);
        socket.destroy();
        return transfer;
      }

      transfer.status = TransferStatus.transferring;
      onUpdate(transfer);

      // Send each file
      for (int i = 0; i < files.length; i++) {
        final f = files[i];
        if (f.path == null || !await File(f.path!).exists()) {
          await _sendMessage(socket, {'type': 'cancel', 'id': transferId});
          throw Exception('File not found: ${f.name}');
        }

        transfer.currentFileIndex = i;
        final file = File(f.path!);
        final fileSize = await file.length();

        await _sendMessage(socket, {
          'type': 'file_start',
          'id': transferId,
          'fileIndex': i,
          'name': f.name,
          'size': fileSize,
          'hashEnabled': enableHashing,
        });

        int bytesSent = 0;
        final sha256Sink = AccumulatorSink<Digest>();
        final sha256Input = enableHashing
            ? sha256.startChunkedConversion(sha256Sink)
            : null;

        DateTime lastUpdate = DateTime.now();

        // Use addStream for proper backpressure to avoid OOM on sender side
        final fileStream = file.openRead().asyncMap((chunk) async {
          if (transfer.status == TransferStatus.failed ||
              transfer.status == TransferStatus.cancelled) {
            throw Exception('Transfer cancelled');
          }
          if (enableHashing) {
            sha256Input?.add(chunk);
          }
          bytesSent += chunk.length;
          transfer.bytesTransferred += chunk.length;

          final now = DateTime.now();
          if (now.difference(lastUpdate).inMilliseconds > 50) {
            onUpdate(transfer);
            lastUpdate = now;
          }
          return chunk;
        });

        await socket.addStream(fileStream);
        onUpdate(transfer);

        await socket.flush();

        if (enableHashing) {
          sha256Input?.close();
          f.checksum = sha256Sink.events.single.toString();
        }

        await _sendMessage(socket, {
          'type': 'file_end',
          'id': transferId,
          'fileIndex': i,
          'checksum': f.checksum,
        });

        // Wait for ACK
        final ack = await reader.readMessage();
        if (ack != null && ack['checksumValid'] == false) {
          transfer.checksumValid = false;
        }
      }

      if (transfer.status == TransferStatus.failed ||
          transfer.status == TransferStatus.cancelled) {
        throw Exception('Transfer cancelled');
      }

      // Complete transfer
      await _sendMessage(socket, {
        'type': 'transfer_complete',
        'id': transferId,
      });

      transfer.status = TransferStatus.completed;
      transfer.endTime = DateTime.now();
      onUpdate(transfer);

      reader.dispose();
      await socket.close();
    } catch (e) {
      if (transfer.status != TransferStatus.failed &&
          transfer.status != TransferStatus.cancelled) {
        transfer.status = TransferStatus.failed;
        transfer.errorMessage = e.toString();
      }
      onUpdate(transfer);
    } finally {
      _activeTransferCount--;
      if (_activeTransferCount <= 0) {
        _activeTransferCount = 0;
        WakelockPlus.disable();
      }
    }

    return transfer;
  }

  void cancelTransfer(TransferItem transfer) {
    transfer.status = TransferStatus.failed;
    transfer.errorMessage = 'Transfer cancelled';
    transfer.socket?.destroy();
    onTransferUpdate?.call(transfer);
  }

  void dispose() {
    stopServer();
  }

  // ---------------------------------------------------------------------------
  // Utilities
  // ---------------------------------------------------------------------------
  String _getUniqueFilePath(String basePath) {
    var file = File(basePath);
    if (!file.existsSync()) return basePath;

    final dotIndex = basePath.lastIndexOf('.');
    final dirAndName = dotIndex != -1
        ? basePath.substring(0, dotIndex)
        : basePath;
    final ext = dotIndex != -1 ? basePath.substring(dotIndex) : '';

    int counter = 1;
    while (file.existsSync()) {
      file = File('$dirAndName ($counter)$ext');
      counter++;
    }
    return file.path;
  }
}

// Minimal sink for crypto hashes
class AccumulatorSink<T> implements Sink<T> {
  final List<T> events = [];
  @override
  void add(T event) => events.add(event);
  @override
  void close() {}
}
