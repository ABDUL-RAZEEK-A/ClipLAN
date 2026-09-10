import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/device_info.dart';
import '../models/transfer_item.dart';

typedef TransferApprovalCallback = Future<bool> Function(TransferItem transfer);
typedef TransferUpdateCallback = void Function(TransferItem transfer);

final int _optimalBufferSize = _calculateOptimalBufferSize();

int getOptimalBufferSize() => _optimalBufferSize;

int _calculateOptimalBufferSize() {
  return 128 *
      1024 *
      1024; // 128MB buffer prevents TCP Window Collapse on fast Wi-Fi
}

// ---------------------------------------------------------
// ISOLATE MESSAGE DEFINITIONS
// ---------------------------------------------------------

class ServerIsolateStartConfig {
  final SendPort mainSendPort;
  final int port;
  final String savePath;
  ServerIsolateStartConfig(this.mainSendPort, this.port, this.savePath);
}

class SenderIsolateStartConfig {
  final SendPort mainSendPort;
  final String transferId;
  final String targetIp;
  final int targetPort;
  final Map<String, dynamic> metadata;
  final List<Map<String, dynamic>> files;
  final int speedLimitMBps;
  SenderIsolateStartConfig(
    this.mainSendPort,
    this.transferId,
    this.targetIp,
    this.targetPort,
    this.metadata,
    this.files,
    this.speedLimitMBps,
  );
}

/// High-performance buffered socket reader using Queue for O(1) dequeue.
/// Modeled after LocalSend's chunked TCP reader with backpressure.
class ConnectionReader {
  final Socket _socket;
  final Queue<Uint8List> _chunks = Queue<Uint8List>();
  int _bufferLength = 0;
  StreamSubscription<Uint8List>? _subscription;
  Completer<void>? _dataReadyCompleter;
  bool _isClosed = false;

  ConnectionReader(this._socket) {
    _subscription = _socket.listen(
      (data) {
        _chunks.addLast(data);
        _bufferLength += data.length;
        if (!(_dataReadyCompleter?.isCompleted ?? true)) {
          _dataReadyCompleter!.complete();
        }
        // Backpressure: pause socket if internal buffer exceeds optimal size
        if (_bufferLength > getOptimalBufferSize()) {
          _subscription?.pause();
        }
      },
      onError: (e) {
        _isClosed = true;
        if (!(_dataReadyCompleter?.isCompleted ?? true)) {
          _dataReadyCompleter!.completeError(e);
        }
      },
      onDone: () {
        _isClosed = true;
        if (!(_dataReadyCompleter?.isCompleted ?? true)) {
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
        if (_bufferLength < count) return null;
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
        _chunks.removeFirst(); // O(1) instead of O(n) removeAt(0)
      } else {
        final remaining = count - offset;
        result.setAll(offset, Uint8List.sublistView(chunk, 0, remaining));
        _chunks.removeFirst();
        _chunks.addFirst(Uint8List.sublistView(chunk, remaining));
        offset += remaining;
      }
    }
    _bufferLength -= count;

    // Resume socket if buffer drained below half the optimal size
    if (_bufferLength < getOptimalBufferSize() ~/ 2 &&
        (_subscription?.isPaused ?? false)) {
      _subscription?.resume();
    }
    if (_bufferLength == 0 &&
        !_isClosed &&
        (_dataReadyCompleter?.isCompleted ?? false)) {
      _dataReadyCompleter = Completer<void>();
    }
    return result;
  }

  /// Stream bytes directly to an IOSink.
  /// Returns 'disabled' for compatibility.
  Future<String> streamBytesToWithHash(
    int count,
    IOSink sink, {
    void Function(int)? onProgress,
    int speedLimitMBps = 0,
  }) async {
    int getDynamicChunkSize() {
      if (speedLimitMBps <= 0) return 25 * 1024 * 1024; // 25MB for unlimited
      int targetMB = (speedLimitMBps / 2).floor();
      if (targetMB < 1) targetMB = 1;
      if (targetMB > 10) targetMB = 10;
      return targetMB * 1024 * 1024;
    }

    final int dynamicChunkSize = getDynamicChunkSize();

    Stream<Uint8List> generateStream() async* {
      int remaining = count;
      final writeBuffer = BytesBuilder(copy: false);

      while (remaining > 0) {
        if (_isClosed && _bufferLength == 0) {
          throw Exception('Connection closed prematurely');
        }
        if (_bufferLength == 0) {
          if (_subscription?.isPaused ?? false) _subscription?.resume();
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
            writeBuffer.add(chunk);
            amountRead = chunk.length;
            _chunks.removeFirst(); // O(1)
          } else {
            final sub = Uint8List.sublistView(chunk, 0, remaining);
            writeBuffer.add(sub);
            _chunks.removeFirst();
            _chunks.addFirst(Uint8List.sublistView(chunk, remaining));
            amountRead = remaining;
          }
          remaining -= amountRead;
          _bufferLength -= amountRead;

          onProgress?.call(amountRead);

          if (writeBuffer.length >= dynamicChunkSize) {
            yield writeBuffer.takeBytes();
          }

          if (_bufferLength < getOptimalBufferSize() ~/ 2 &&
              (_subscription?.isPaused ?? false)) {
            _subscription?.resume();
          }
        }
        if (_bufferLength == 0 &&
            !_isClosed &&
            (_dataReadyCompleter?.isCompleted ?? false)) {
          _dataReadyCompleter = Completer<void>();
        }
      }

      if (writeBuffer.isNotEmpty) {
        yield writeBuffer.takeBytes();
      }
    }

    await sink.addStream(generateStream());
    return 'disabled';
  }

  Future<Map<String, dynamic>?> readMessage() async {
    final lengthBytes = await readExact(4);
    if (lengthBytes == null) return null;
    final length = ByteData.sublistView(lengthBytes).getUint32(0, Endian.big);
    if (length == 0 || length > 20 * 1024 * 1024) return null;
    final jsonBytes = await readExact(length);
    if (jsonBytes == null) return null;
    try {
      return jsonDecode(utf8.decode(jsonBytes));
    } catch (_) {
      return null;
    }
  }

  Future<void> close() async {
    _isClosed = true;
    await _subscription?.cancel();
    _socket.destroy();
  }
}

Future<void> _sendMessage(Socket socket, Map<String, dynamic> message) async {
  final jsonStr = jsonEncode(message);
  final bytes = utf8.encode(jsonStr);
  final lengthBytes = ByteData(4)..setUint32(0, bytes.length, Endian.big);
  socket.add(lengthBytes.buffer.asUint8List());
  socket.add(bytes);
  await socket.flush(); // Ensure message is flushed for reliability
}

// ---------------------------------------------------------
// RECEIVER ISOLATE
// ---------------------------------------------------------
Future<void> _serverIsolateEntryPoint(ServerIsolateStartConfig config) async {
  final receivePort = ReceivePort();
  config.mainSendPort.send({'type': 'init', 'sendPort': receivePort.sendPort});

  ServerSocket? server;
  try {
    server = await ServerSocket.bind(InternetAddress.anyIPv4, config.port);
  } catch (_) {
    try {
      server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    } catch (e) {
      config.mainSendPort.send({'type': 'error', 'msg': e.toString()});
      return;
    }
  }

  config.mainSendPort.send({'type': 'listening', 'port': server.port});

  final Map<String, Completer<bool>> pendingApprovals = {};
  final Map<String, Socket> activeSockets = {};

  receivePort.listen((msg) {
    if (msg is Map) {
      if (msg['type'] == 'approval_result') {
        final id = msg['id'];
        pendingApprovals[id]?.complete(msg['approved']);
        pendingApprovals.remove(id);
      } else if (msg['type'] == 'cancel_transfer') {
        final id = msg['transferId'];
        activeSockets[id]?.destroy();
        activeSockets.remove(id);
      } else if (msg['type'] == 'shutdown') {
        server?.close();
        for (final socket in activeSockets.values) {
          socket.destroy();
        }
        activeSockets.clear();
        receivePort.close();
      }
    }
  });

  server.listen((Socket socket) async {
    socket.setOption(SocketOption.tcpNoDelay, true);
    final reader = ConnectionReader(socket);
    String? currentTransferId;
    try {
      final request = await reader.readMessage();
      if (request == null) throw Exception('Invalid request');

      if (request['type'] == 'clipboard') {
        config.mainSendPort.send({'type': 'clipboard', 'data': request});
        await reader.close();
        return;
      }

      if (request['type'] != 'transfer_request') {
        throw Exception('Unknown request type');
      }

      currentTransferId = request['id'];
      final transferId = request['id'];
      final senderSpeedLimitMBps = request['speedLimitMBps'] ?? 0;

      activeSockets[transferId] = socket;
      final completer = Completer<bool>();
      pendingApprovals[transferId] = completer;

      // Ask main isolate for approval
      config.mainSendPort.send({
        'type': 'request_approval',
        'transferId': transferId,
        'metadata': request,
      });

      final approved = await completer.future;
      if (!approved) {
        await _sendMessage(socket, {'type': 'transfer_rejected'});
        await reader.close();
        return;
      }

      await _sendMessage(socket, {'type': 'transfer_accepted'});

      final files = List<Map<String, dynamic>>.from(request['files']);

      for (int fileIndex = 0; fileIndex < files.length; fileIndex++) {
        final fileMetadata = files[fileIndex];
        final fileName = fileMetadata['name'];
        final fileSize = fileMetadata['size'];
        final filePath = "${config.savePath}/$fileName";
        final file = File(filePath);
        final sink = file.openWrite();

        DateTime lastUpdate = DateTime.now();
        int bytesSinceUpdate = 0;

        // Stream file data
        await reader.streamBytesToWithHash(
          fileSize,
          sink,
          speedLimitMBps: senderSpeedLimitMBps,
          onProgress: (read) {
            bytesSinceUpdate += read;
            // Send progress every 1MB to avoid DateTime sys-calls in tight loop
            if (bytesSinceUpdate > 1024 * 1024) {
              config.mainSendPort.send({
                'type': 'progress',
                'transferId': transferId,
                'bytes': bytesSinceUpdate,
                'isUpdateOnly': true,
              });
              bytesSinceUpdate = 0;
            }
          },
        );

        // Send any remaining progress updates for this file
        if (bytesSinceUpdate > 0) {
          config.mainSendPort.send({
            'type': 'progress',
            'transferId': transferId,
            'bytes': bytesSinceUpdate,
            'isUpdateOnly': true,
          });
        }

        await sink.flush();
        await sink.close();

        // Verify file size
        final downloadedSize = await file.length();
        if (downloadedSize != fileSize) {
          throw Exception(
            'File size mismatch for $fileName. Expected $fileSize, got $downloadedSize.',
          );
        }

        // Read sender's hash message
        final hashMsg = await reader.readMessage();
        bool checksumValid = true;
        if (hashMsg != null && hashMsg['type'] == 'file_hash') {
          // Fast mode: assume valid
          checksumValid = true;
        }

        // Send per-file acknowledgment back to sender
        await _sendMessage(socket, {
          'type': 'file_ack',
          'fileName': fileName,
          'checksumValid': checksumValid,
        });

        config.mainSendPort.send({
          'type': 'file_completed',
          'transferId': transferId,
          'fileName': fileName,
          'path': filePath,
          'fileIndex': fileIndex,
          'checksumValid': null, // Fast mode
        });
      }

      config.mainSendPort.send({
        'type': 'transfer_completed',
        'transferId': transferId,
        'checksumValid': null, // Fast mode
        'savePath': config.savePath,
      });
    } catch (e) {
      config.mainSendPort.send({
        'type': 'transfer_failed',
        'transferId': currentTransferId,
        'msg': e.toString(),
      });
    } finally {
      if (currentTransferId != null) activeSockets.remove(currentTransferId);
      await reader.close();
    }
  });
}

// ---------------------------------------------------------
// SENDER ISOLATE
// ---------------------------------------------------------
Future<void> _senderIsolateEntryPoint(SenderIsolateStartConfig config) async {
  try {
    final socket = await Socket.connect(
      config.targetIp,
      config.targetPort,
      timeout: const Duration(seconds: 10),
    );
    socket.setOption(SocketOption.tcpNoDelay, true);

    await _sendMessage(socket, config.metadata);

    final reader = ConnectionReader(socket);
    final response = await reader.readMessage();
    if (response == null || response['type'] != 'transfer_accepted') {
      throw Exception('Transfer rejected by receiver');
    }

    config.mainSendPort.send({
      'type': 'transfer_accepted',
      'transferId': config.transferId,
    });

    for (final fileMeta in config.files) {
      final file = File(fileMeta['path']);

      int bytesSinceUpdate = 0;

      Stream<Uint8List> generateSenderStream() async* {
        final raf = await file.open(mode: FileMode.read);
        try {
          final length = await raf.length();
          final stopwatch = Stopwatch()..start();
          int bytesSentThisSecond = 0;

          int getDynamicChunkSize() {
            if (config.speedLimitMBps <= 0)
              return 25 * 1024 * 1024; // 25MB for unlimited (Unstable)
            int targetMB = (config.speedLimitMBps / 2).floor();
            if (targetMB < 1) targetMB = 1;
            if (targetMB > 10) targetMB = 10;
            return targetMB * 1024 * 1024;
          }

          final int dynamicChunkSize = getDynamicChunkSize();

          while (await raf.position() < length) {
            final chunk = await raf.read(dynamicChunkSize);

            if (config.speedLimitMBps > 0) {
              bytesSentThisSecond += chunk.length;
              final targetBytesPerSec = config.speedLimitMBps * 1024 * 1024;

              if (bytesSentThisSecond >= targetBytesPerSec) {
                final elapsed = stopwatch.elapsedMilliseconds;
                if (elapsed < 1000) {
                  await Future.delayed(Duration(milliseconds: 1000 - elapsed));
                }
                stopwatch.reset();
                bytesSentThisSecond = 0;
              }
            }

            yield chunk;
          }
        } finally {
          await raf.close();
        }
      }

      final stream = generateSenderStream().map((chunk) {
        bytesSinceUpdate += chunk.length;
        if (bytesSinceUpdate > 1024 * 1024) {
          config.mainSendPort.send({
            'type': 'progress',
            'transferId': config.transferId,
            'bytes': bytesSinceUpdate,
            'isUpdateOnly': true,
          });
          bytesSinceUpdate = 0;
        }
        return chunk;
      });

      await socket.addStream(stream);

      // Send any remaining progress
      if (bytesSinceUpdate > 0) {
        config.mainSendPort.send({
          'type': 'progress',
          'transferId': config.transferId,
          'bytes': bytesSinceUpdate,
          'isUpdateOnly': true,
        });
      }

      // No hashing, send dummy hash to maintain protocol compatibility
      await _sendMessage(socket, {'type': 'file_hash', 'hash': 'disabled'});

      // Wait for receiver's per-file acknowledgment
      final ackMsg = await reader.readMessage();
      if (ackMsg != null && ackMsg['type'] == 'file_ack') {
        // Fast mode: ignore checksum result
      }

      config.mainSendPort.send({
        'type': 'file_completed',
        'transferId': config.transferId,
        'fileIndex': config.files.indexOf(fileMeta),
        'path': fileMeta['path'],
      });
    }

    await socket.flush();
    await socket.close();
    config.mainSendPort.send({
      'type': 'transfer_completed',
      'transferId': config.transferId,
      'checksumValid': null, // Fast mode
    });
  } catch (e) {
    config.mainSendPort.send({
      'type': 'transfer_failed',
      'transferId': config.transferId,
      'msg': e.toString(),
    });
  }
}

// ---------------------------------------------------------
// MAIN SERVICE
// ---------------------------------------------------------

class TransferService {
  static const int defaultPort = 53318;
  int _port = defaultPort;
  int get port => _port;

  String _deviceName = 'ClipLAN Device';
  String? _savePath;
  int _activeTransferCount = 0;
  bool _isServerRunning = false;

  TransferApprovalCallback? onApprovalRequired;
  TransferUpdateCallback? onTransferUpdate;
  void Function(Map<String, dynamic>)? onClipboardData;

  Isolate? _serverIsolate;
  SendPort? _serverSendPort;
  final Map<String, TransferItem> _activeTransfers = {};
  final Map<String, Isolate> _senderIsolates = {};

  TransferService();

  void updateDeviceName(String name) => _deviceName = name;

  void updateSavePath(String path) => _savePath = path;

  void updateSpeedLimit(double mbps) {
    // Unsupported in isolate architecture natively, reserved for API compatibility
  }

  void dispose() {
    stopServer();
  }

  Future<void> startServer({String? savePath}) async {
    if (savePath != null) _savePath = savePath;

    // Guard: prevent redundant server restarts
    if (_isServerRunning && _serverSendPort != null) return;

    // Clean up any stale state
    await stopServer();

    final receivePort = ReceivePort();

    _serverIsolate = await Isolate.spawn(
      _serverIsolateEntryPoint,
      ServerIsolateStartConfig(receivePort.sendPort, _port, _savePath ?? ''),
    );

    receivePort.listen((msg) async {
      if (msg is Map) {
        final type = msg['type'];
        if (type == 'init') {
          _serverSendPort = msg['sendPort'];
          _isServerRunning = true;
        } else if (type == 'listening') {
          _port = msg['port'];
        } else if (type == 'clipboard') {
          onClipboardData?.call(msg['data']);
        } else if (type == 'request_approval') {
          final transferId = msg['transferId'];
          final request = msg['metadata'];

          final files = (request['files'] as List)
              .map((f) => FileItem(name: f['name'], size: f['size'], path: ''))
              .toList();

          final transfer = TransferItem(
            id: transferId,
            deviceName: request['senderName'] ?? 'Unknown',
            deviceIp: '',
            direction: TransferDirection.receiving,
            files: files,
            status: TransferStatus.waitingApproval,
            savedPath: _savePath,
          );

          _activeTransfers[transferId] = transfer;
          onTransferUpdate?.call(transfer);

          final approved = await onApprovalRequired?.call(transfer) ?? false;
          _serverSendPort?.send({
            'type': 'approval_result',
            'id': transferId,
            'approved': approved,
          });

          if (approved) {
            transfer.status = TransferStatus.transferring;
            _activeTransferCount++;
            if (_activeTransferCount == 1) WakelockPlus.enable();
            onTransferUpdate?.call(transfer);
          } else {
            transfer.status = TransferStatus.cancelled;
            _activeTransfers.remove(transferId);
            onTransferUpdate?.call(transfer);
          }
        } else if (type == 'progress') {
          final id = msg['transferId'];
          final transfer = _activeTransfers[id];
          if (transfer != null) {
            transfer.bytesTransferred += (msg['bytes'] as int);
            onTransferUpdate?.call(transfer);
          }
        } else if (type == 'file_completed') {
          final id = msg['transferId'];
          final transfer = _activeTransfers[id];
          if (transfer != null) {
            // Update file path so Open/Show Folder works
            final fileIndex = msg['fileIndex'] as int?;
            final filePath = msg['path'] as String?;
            if (fileIndex != null &&
                fileIndex < transfer.files.length &&
                filePath != null) {
              transfer.files[fileIndex].path = filePath;
              transfer.currentFileIndex = fileIndex + 1;
              onTransferUpdate?.call(transfer);
            }
          }
        } else if (type == 'transfer_completed') {
          final id = msg['transferId'];
          final transfer = _activeTransfers[id];
          if (transfer != null) {
            transfer.bytesTransferred = transfer.totalSize;
            transfer.status = TransferStatus.completed;
            transfer.checksumValid = msg['checksumValid'] as bool?;
            transfer.savedPath = msg['savePath'] as String?;
            onTransferUpdate?.call(transfer);
            _activeTransfers.remove(id);
            _checkWakelock();
          }
        } else if (type == 'transfer_failed') {
          final id = msg['transferId'];
          final transfer = _activeTransfers[id];
          if (transfer != null) {
            transfer.status = TransferStatus.failed;
            transfer.errorMessage = msg['msg'];
            onTransferUpdate?.call(transfer);
            _activeTransfers.remove(id);
            _checkWakelock();
          }
        }
      }
    });
  }

  Future<void> stopServer() async {
    _serverSendPort?.send({'type': 'shutdown'});
    _serverIsolate?.kill();
    _serverIsolate = null;
    _serverSendPort = null;
    _isServerRunning = false;
  }

  void _checkWakelock() {
    if (_activeTransferCount > 0) _activeTransferCount--;
    if (_activeTransferCount == 0) WakelockPlus.disable();
  }

  Future<TransferItem> sendFiles({
    required String transferId,
    required DeviceInfo device,
    required List<FileItem> files,
    required TransferUpdateCallback onUpdate,
    bool enableHashing = false,
    int speedLimitMBps = 0,
  }) async {
    final transfer = TransferItem(
      id: transferId,
      deviceName: device.name,
      deviceIp: device.ip,
      direction: TransferDirection.sending,
      files: files,
      status: TransferStatus.waitingApproval,
    );

    _activeTransfers[transferId] = transfer;
    onUpdate(transfer);

    _activeTransferCount++;
    if (_activeTransferCount == 1) WakelockPlus.enable();

    final metadata = {
      'type': 'transfer_request',
      'id': transferId,
      'senderName': _deviceName,
      'speedLimitMBps': speedLimitMBps,
      'files': files.map((f) => {'name': f.name, 'size': f.size}).toList(),
    };

    final fileMetaList = files
        .map((f) => {'path': f.path, 'size': f.size})
        .toList();

    final receivePort = ReceivePort();

    final isolate = await Isolate.spawn(
      _senderIsolateEntryPoint,
      SenderIsolateStartConfig(
        receivePort.sendPort,
        transferId,
        device.ip,
        device.port,
        metadata,
        fileMetaList,
        speedLimitMBps,
      ),
    );
    _senderIsolates[transferId] = isolate;

    receivePort.listen((msg) {
      if (msg is Map) {
        final type = msg['type'];
        if (type == 'transfer_accepted') {
          transfer.status = TransferStatus.transferring;
          onUpdate(transfer);
        } else if (type == 'progress') {
          transfer.bytesTransferred += (msg['bytes'] as int);
          onUpdate(transfer);
        } else if (type == 'transfer_completed') {
          transfer.bytesTransferred = transfer.totalSize;
          transfer.status = TransferStatus.completed;
          transfer.checksumValid = msg['checksumValid'] as bool?;
          onUpdate(transfer);
          _activeTransfers.remove(transferId);
          _senderIsolates.remove(transferId);
          _checkWakelock();
          receivePort.close();
        } else if (type == 'transfer_failed') {
          transfer.status = TransferStatus.failed;
          transfer.errorMessage = msg['msg'];
          onUpdate(transfer);
          _activeTransfers.remove(transferId);
          _senderIsolates.remove(transferId);
          _checkWakelock();
          receivePort.close();
        }
      }
    });

    return transfer;
  }

  Future<bool> sendClipboard(String text, DeviceInfo device) async {
    // Keep clipboard simple on main thread
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
      return true;
    } catch (e) {
      return false;
    }
  }

  void cancelTransfer(TransferItem transfer) {
    transfer.status = TransferStatus.cancelled;
    onTransferUpdate?.call(transfer);

    if (transfer.direction == TransferDirection.sending) {
      _senderIsolates[transfer.id]?.kill();
      _senderIsolates.remove(transfer.id);
      _checkWakelock();
    } else {
      _serverSendPort?.send({
        'type': 'cancel_transfer',
        'transferId': transfer.id,
      });
    }
    _activeTransfers.remove(transfer.id);
  }
}
