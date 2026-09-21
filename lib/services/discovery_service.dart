import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import '../models/device_info.dart';

// ---------------------------------------------------------
// ISOLATE MESSAGING PROTOCOL
// ---------------------------------------------------------
abstract class DiscoveryMessage {}
class DevicesUpdateMessage extends DiscoveryMessage {
  final List<DeviceInfo> devices;
  DevicesUpdateMessage(this.devices);
}
class ClipboardMessage extends DiscoveryMessage {
  final Map<String, dynamic> data;
  ClipboardMessage(this.data);
}
class LocalIpUpdateMessage extends DiscoveryMessage {
  final String? ip;
  LocalIpUpdateMessage(this.ip);
}
class LogMessage extends DiscoveryMessage {
  final String message;
  LogMessage(this.message);
}

abstract class DiscoveryCommand {}
class UpdateConfigCommand extends DiscoveryCommand {
  final String deviceName;
  final String username;
  UpdateConfigCommand(this.deviceName, this.username);
}
class BroadcastCommand extends DiscoveryCommand {}
class BroadcastClipboardCommand extends DiscoveryCommand {
  final String text;
  BroadcastClipboardCommand(this.text);
}
class RefreshCommand extends DiscoveryCommand {}
class StopCommand extends DiscoveryCommand {}

class _IsolateConfig {
  final SendPort sendPort;
  final String deviceName;
  final String username;
  final String os;
  final String hardwareName;
  final String deviceId;
  final int serverPort;
  final bool isAndroid;
  final bool isIOS;
  final bool isMacOS;
  final bool isWindows;
  final bool isLinux;

  _IsolateConfig({
    required this.sendPort,
    required this.deviceName,
    required this.username,
    required this.os,
    required this.hardwareName,
    required this.deviceId,
    required this.serverPort,
    required this.isAndroid,
    required this.isIOS,
    required this.isMacOS,
    required this.isWindows,
    required this.isLinux,
  });
}

// ---------------------------------------------------------
// MAIN SERVICE (PROXY)
// ---------------------------------------------------------
/// UDP-based local network device discovery service.
/// Uses a background isolate to prevent UI thread lockups during network transitions.
class DiscoveryService {
  static const int discoveryPort = 53317;
  static const int staleTimeoutSeconds = 15;

  final StreamController<List<DeviceInfo>> _devicesController = StreamController<List<DeviceInfo>>.broadcast();
  final StreamController<Map<String, dynamic>> _clipboardController = StreamController<Map<String, dynamic>>.broadcast();

  String _deviceName;
  String _username;
  final String _os;
  final String _hardwareName;
  final String _deviceId;
  final int _serverPort;
  
  String? _localIp;
  List<DeviceInfo> _devices = [];
  
  Isolate? _isolate;
  SendPort? _isolateSendPort;
  ReceivePort? _receivePort;

  String? get localIp => _localIp;
  Stream<List<DeviceInfo>> get devicesStream => _devicesController.stream;
  Stream<Map<String, dynamic>> get clipboardStream => _clipboardController.stream;
  List<DeviceInfo> get devices => _devices;

  DiscoveryService({
    required String deviceName,
    required String username,
    required String os,
    required String hardwareName,
    required String deviceId,
    required int serverPort,
  }) : _deviceName = deviceName,
       _username = username,
       _os = os,
       _hardwareName = hardwareName,
       _deviceId = deviceId,
       _serverPort = serverPort;

  void updateDeviceName(String name) {
    _deviceName = name;
    _isolateSendPort?.send(UpdateConfigCommand(_deviceName, _username));
  }

  void updateUsername(String name) {
    _username = name;
    _isolateSendPort?.send(UpdateConfigCommand(_deviceName, _username));
  }

  Future<void> start() async {
    if (_isolate != null) return;
    
    _receivePort?.close();
    _receivePort = ReceivePort();
    
    _receivePort!.listen((message) {
      if (message is SendPort) {
        _isolateSendPort = message;
      } else if (message is DevicesUpdateMessage) {
        _devices = message.devices;
        _devicesController.add(_devices);
      } else if (message is ClipboardMessage) {
        _clipboardController.add(message.data);
      } else if (message is LocalIpUpdateMessage) {
        _localIp = message.ip;
      } else if (message is LogMessage) {
        debugPrint(message.message);
      }
    });

    final config = _IsolateConfig(
      sendPort: _receivePort!.sendPort,
      deviceName: _deviceName,
      username: _username,
      os: _os,
      hardwareName: _hardwareName,
      deviceId: _deviceId,
      serverPort: _serverPort,
      isAndroid: Platform.isAndroid,
      isIOS: Platform.isIOS,
      isMacOS: Platform.isMacOS,
      isWindows: Platform.isWindows,
      isLinux: Platform.isLinux,
    );

    _isolate = await Isolate.spawn(_discoveryIsolateEntryPoint, config);
  }

  void broadcastClipboard(String text) {
    _isolateSendPort?.send(BroadcastClipboardCommand(text));
  }

  Future<void> refresh() async {
    _isolateSendPort?.send(RefreshCommand());
  }

  void stop() {
    _isolateSendPort?.send(StopCommand());
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _isolateSendPort = null;
    
    _receivePort?.close();
    _receivePort = null;
    
    _devices.clear();
    _devicesController.add([]);
  }

  void dispose() {
    stop();
    _devicesController.close();
    _clipboardController.close();
  }
}

// ---------------------------------------------------------
// BACKGROUND ISOLATE ENTRY POINT
// ---------------------------------------------------------
Future<void> _discoveryIsolateEntryPoint(_IsolateConfig config) async {
  final receivePort = ReceivePort();
  config.sendPort.send(receivePort.sendPort);

  String deviceName = config.deviceName;
  String username = config.username;
  final String platformStr = config.isAndroid ? 'android' : (config.isIOS ? 'ios' : (config.isMacOS ? 'macos' : (config.isWindows ? 'windows' : (config.isLinux ? 'linux' : 'unknown'))));

  RawDatagramSocket? socket;
  Timer? broadcastTimer;
  Timer? cleanupTimer;
  Timer? ipRefreshTimer;
  
  final Map<String, DeviceInfo> devices = {};
  String? localIp;
  Set<String> localIps = {};
  bool isBroadcasting = false;
  bool isRebinding = false;

  void log(String message) {
    config.sendPort.send(LogMessage(message));
  }

  Future<String?> getLocalIpViaSocket() async {
    RawDatagramSocket? probe;
    try {
      probe = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      probe.send([0], InternetAddress('8.8.8.8'), 53);
      await Future.delayed(const Duration(milliseconds: 50));
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLinkLocal: false);
      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        if (name.startsWith('pdp_ip') || name.startsWith('rmnet') || name.startsWith('utun') || name.startsWith('tun') || name.startsWith('tap')) continue;
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) return addr.address;
        }
      }
      try {
        final tcpSocket = await Socket.connect('8.8.8.8', 53, timeout: const Duration(seconds: 2));
        final ip = tcpSocket.address.address;
        tcpSocket.destroy();
        if (ip != '0.0.0.0' && ip != '127.0.0.1') return ip;
      } catch (_) {}
      return null;
    } catch (e) {
      log('[DiscoveryIsolate] getLocalIpViaSocket error: $e');
      return null;
    } finally {
      probe?.close();
    }
  }

  Future<void> findLocalIps() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLinkLocal: false);
      final ips = <String>{};
      String? wifiIp;
      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        if (name.startsWith('rmnet') || name.startsWith('ccmni') || name.startsWith('pdp_ip') || name.startsWith('tun') || name.startsWith('tap') || name.startsWith('utun') || name.startsWith('tailscale') || name.startsWith('wg')) {
          continue;
        }
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
            ips.add(addr.address);
            if (name.startsWith('wlan') || name.startsWith('en')) wifiIp ??= addr.address;
          }
        }
      }

      if (ips.isEmpty && config.isIOS) {
        final fallbackIp = await getLocalIpViaSocket();
        if (fallbackIp != null) {
          ips.add(fallbackIp);
          wifiIp = fallbackIp;
        }
      }

      localIps = ips;
      if (ips.isNotEmpty) {
        final newIp = wifiIp ?? ips.first;
        if (localIp != newIp) {
          localIp = newIp;
          config.sendPort.send(LocalIpUpdateMessage(localIp));
        }
      }
    } catch (e) {
      log('[DiscoveryIsolate] findLocalIps error: $e');
    }
  }

  Future<void> broadcast({String? targetIp}) async {
    if (socket == null || isBroadcasting) return;
    isBroadcasting = true;

    try {
      if (localIps.isEmpty) {
        await findLocalIps();
        if (localIp == null) return;
      }

      final message = jsonEncode({
        'type': 'announce',
        'id': config.deviceId,
        'name': deviceName,
        'username': username,
        'os': config.os,
        'hardwareName': config.hardwareName,
        'ip': localIp ?? '',
        'port': config.serverPort,
        'platform': platformStr,
      });

      final data = utf8.encode(message);

      try {
        if (targetIp != null && targetIp.isNotEmpty) {
          try {
            socket!.send(data, InternetAddress(targetIp), DiscoveryService.discoveryPort);
          } catch (_) {}
          return;
        }
        socket!.send(data, InternetAddress('255.255.255.255'), DiscoveryService.discoveryPort);
        socket!.send(data, InternetAddress('224.0.0.1'), DiscoveryService.discoveryPort);
        socket!.send(data, InternetAddress('224.0.0.251'), DiscoveryService.discoveryPort);

        for (final ip in localIps) {
          final parts = ip.split('.');
          if (parts.length == 4) {
            final subnetBroadcast = '${parts[0]}.${parts[1]}.${parts[2]}.255';
            socket!.send(data, InternetAddress(subnetBroadcast), DiscoveryService.discoveryPort);
          }
        }
        for (final device in devices.values) {
          if (device.ip.isNotEmpty && !localIps.contains(device.ip)) {
            try {
              socket!.send(data, InternetAddress(device.ip), DiscoveryService.discoveryPort);
            } catch (_) {}
          }
        }
      } catch (e) {
        log('[DiscoveryIsolate] Broadcast error: $e');
      }
    } finally {
      isBroadcasting = false;
    }
  }

  void cleanupStaleDevices() {
    final now = DateTime.now();
    final staleIds = <String>[];
    for (final entry in devices.entries) {
      if (now.difference(entry.value.lastSeen).inSeconds > DiscoveryService.staleTimeoutSeconds) {
        staleIds.add(entry.key);
      }
    }
    if (staleIds.isNotEmpty) {
      for (final id in staleIds) {
        devices.remove(id);
      }
      config.sendPort.send(DevicesUpdateMessage(devices.values.toList()));
    }
  }

  void handleDatagram(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = socket?.receive();
    if (datagram == null) return;
    try {
      final senderIp = datagram.address.address;
      if (localIps.contains(senderIp)) return;
      final message = jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;
      final remoteDeviceId = message['id'] as String?;
      if (remoteDeviceId == null || remoteDeviceId == config.deviceId) return;

      if (message['type'] == 'announce') {
        final device = DeviceInfo.fromJson(message);
        if (device.ip.isEmpty) device.ip = senderIp;

        final isNewDevice = !devices.containsKey(device.id);
        final existingDevice = devices[device.id];
        bool needsUiUpdate = isNewDevice || (existingDevice != null && (existingDevice.name != device.name || existingDevice.ip != device.ip));
        
        device.lastSeen = DateTime.now();
        devices[device.id] = device;
        
        if (needsUiUpdate) {
          config.sendPort.send(DevicesUpdateMessage(devices.values.toList()));
        }
        if (isNewDevice) {
          broadcast(targetIp: senderIp);
        }
      } else if (message['type'] == 'clipboard') {
        final text = message['text'] as String?;
        if (text != null && text.isNotEmpty) {
          config.sendPort.send(ClipboardMessage({
            'text': text,
            'senderName': message['name'] ?? 'Unknown Device',
            'senderId': remoteDeviceId,
            'timestamp': DateTime.now().toIso8601String(),
          }));
        }
      }
    } catch (_) {}
  }

  Future<void> bindSocket() async {
    if (isRebinding) return;
    isRebinding = true;
    try {
      socket?.close();
      socket = null;
      
      await findLocalIps();
      if (localIps.isEmpty && config.isIOS) {
        await Future.delayed(const Duration(seconds: 2));
        await findLocalIps();
      }

      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        DiscoveryService.discoveryPort,
        reuseAddress: true,
        reusePort: true,
      );
      socket!.broadcastEnabled = true;
      socket!.multicastLoopback = false;

      try {
        socket!.joinMulticast(InternetAddress('224.0.0.1'));
      } catch (_) {}
      try {
        socket!.joinMulticast(InternetAddress('224.0.0.251'));
      } catch (_) {}

      socket!.listen(
        handleDatagram,
        onError: (dynamic error) {
          log('[DiscoveryIsolate] UDP Socket error: $error');
          if (error is SocketException) {
            final code = error.osError?.errorCode;
            if (code == 65 || code == 51 || code == 50 || code == 64) return;
          }
          Future.delayed(const Duration(seconds: 1), bindSocket);
        },
      );

      broadcastTimer?.cancel();
      broadcastTimer = Timer.periodic(const Duration(seconds: 3), (_) => broadcast());

      cleanupTimer?.cancel();
      cleanupTimer = Timer.periodic(const Duration(seconds: 3), (_) => cleanupStaleDevices());

      ipRefreshTimer?.cancel();
      ipRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) => findLocalIps());

      broadcast();
      Future.delayed(const Duration(milliseconds: 200), broadcast);
      Future.delayed(const Duration(milliseconds: 500), broadcast);
    } catch (e) {
      log('[DiscoveryIsolate] Failed to bind: $e');
    } finally {
      isRebinding = false;
    }
  }

  void stop() {
    broadcastTimer?.cancel();
    cleanupTimer?.cancel();
    ipRefreshTimer?.cancel();
    socket?.close();
    socket = null;
    devices.clear();
  }

  receivePort.listen((msg) async {
    if (msg is UpdateConfigCommand) {
      deviceName = msg.deviceName;
      username = msg.username;
      broadcast();
    } else if (msg is BroadcastClipboardCommand) {
      if (socket == null) return;
      final data = utf8.encode(jsonEncode({
        'type': 'clipboard',
        'id': config.deviceId,
        'name': deviceName,
        'text': msg.text,
      }));
      if (data.length > 4096) return;
      try {
        socket!.send(data, InternetAddress('255.255.255.255'), DiscoveryService.discoveryPort);
        socket!.send(data, InternetAddress('224.0.0.1'), DiscoveryService.discoveryPort);
        socket!.send(data, InternetAddress('224.0.0.251'), DiscoveryService.discoveryPort);
        for (final ip in localIps) {
          final parts = ip.split('.');
          if (parts.length == 4) {
            socket!.send(data, InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255'), DiscoveryService.discoveryPort);
          }
        }
        for (final device in devices.values) {
          if (device.ip.isNotEmpty) {
            try {
              socket!.send(data, InternetAddress(device.ip), DiscoveryService.discoveryPort);
            } catch (_) {}
          }
        }
      } catch (_) {}
    } else if (msg is RefreshCommand) {
      devices.clear();
      config.sendPort.send(DevicesUpdateMessage([]));
      await findLocalIps();
      broadcast();
      Future.delayed(const Duration(milliseconds: 200), broadcast);
      Future.delayed(const Duration(milliseconds: 500), broadcast);
    } else if (msg is StopCommand) {
      stop();
    }
  });

  await bindSocket();
}
