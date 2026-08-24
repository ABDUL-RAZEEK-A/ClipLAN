import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/device_info.dart';

/// UDP-based local network device discovery service.
///
/// Broadcasts presence announcements and listens for other devices
/// on the same Wi-Fi network. Enhanced with targeted unicast responses,
/// multi-subnet broadcasts, dynamic IP refresh, and reliable stale timeouts.
class DiscoveryService {
  static const int discoveryPort = 53317;
  static const int staleTimeoutSeconds =
      15; // Increased to 15s to prevent Wi-Fi drop flicker

  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;
  Timer? _cleanupTimer;
  final Map<String, DeviceInfo> _devices = {};
  final StreamController<List<DeviceInfo>> _devicesController =
      StreamController<List<DeviceInfo>>.broadcast();
  final StreamController<Map<String, dynamic>> _clipboardController =
      StreamController<Map<String, dynamic>>.broadcast();

  String _deviceName;
  String _username;
  String _os;
  String _hardwareName;
  String _avatarBase64;
  final String _deviceId;
  final int _serverPort;
  String? _localIp;
  Set<String> _localIps = {};

  String? get localIp => _localIp;
  Stream<List<DeviceInfo>> get devicesStream => _devicesController.stream;
  Stream<Map<String, dynamic>> get clipboardStream =>
      _clipboardController.stream;
  List<DeviceInfo> get devices => _devices.values.toList();

  DiscoveryService({
    required String deviceName,
    required String username,
    required String os,
    required String hardwareName,
    required String avatarBase64,
    required String deviceId,
    required int serverPort,
  }) : _deviceName = deviceName,
       _username = username,
       _os = os,
       _hardwareName = hardwareName,
       _avatarBase64 = avatarBase64,
       _deviceId = deviceId,
       _serverPort = serverPort;

  void updateDeviceName(String name) {
    _deviceName = name;
    _broadcast();
  }

  void updateUsername(String name) {
    _username = name;
    _broadcast();
  }

  void updateAvatarBase64(String avatar) => _avatarBase64 = avatar;

  Future<void> start() async {
    await _findLocalIps();

    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
        reuseAddress: true,
        reusePort: true,
      );

      _socket!.broadcastEnabled = true;
      _socket!.multicastLoopback = false;

      try {
        _socket!.joinMulticast(InternetAddress('224.0.0.1'));
        _socket!.joinMulticast(InternetAddress('224.0.0.251'));
      } catch (_) {}

      _socket!.listen(
        _handleDatagram,
        onError: (dynamic error) {
          debugPrint('[DiscoveryService] UDP Socket error: $error');
          _rebindSocket();
        },
        onDone: () {
          debugPrint('[DiscoveryService] UDP Socket closed');
        },
      );

      // Broadcast presence every 1 second
      _broadcastTimer?.cancel();
      _broadcastTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _broadcast(),
      );

      // Remove stale devices every 3 seconds (15s tolerance)
      _cleanupTimer?.cancel();
      _cleanupTimer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => _cleanupStaleDevices(),
      );

      // Initial broadcast burst
      _broadcast();
      Future.delayed(const Duration(milliseconds: 200), _broadcast);
      Future.delayed(const Duration(milliseconds: 500), _broadcast);
      Future.delayed(const Duration(milliseconds: 800), _broadcast);
    } catch (e) {
      debugPrint('[DiscoveryService] Failed to start UDP socket: $e');
    }
  }

  Future<void> _rebindSocket() async {
    try {
      _socket?.close();
      _socket = null;
      await Future.delayed(const Duration(seconds: 1));
      await start();
    } catch (_) {}
  }

  Future<void> _findLocalIps() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      final ips = <String>{};
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
            ips.add(addr.address);
          }
        }
      }

      _localIps = ips;
      if (ips.isNotEmpty) {
        _localIp = ips.first;
      }
    } catch (_) {}
  }

  Future<void> _broadcast({String? targetIp}) async {
    if (_socket == null) return;

    // Periodically refresh IP set if empty
    if (_localIps.isEmpty) {
      await _findLocalIps();
      if (_localIp == null) return;
    }

    final message = jsonEncode({
      'type': 'announce',
      'id': _deviceId,
      'name': _deviceName,
      'username': _username,
      'os': _os,
      'hardwareName': _hardwareName,
      'ip': _localIp ?? '',
      'port': _serverPort,
      'platform': Platform.isAndroid
          ? 'android'
          : (Platform.isIOS ? 'ios' : 'unknown'),
    });

    final data = utf8.encode(message);

    try {
      // If a specific target IP is provided (unicast response), send directly to target
      if (targetIp != null && targetIp.isNotEmpty) {
        try {
          _socket!.send(data, InternetAddress(targetIp), discoveryPort);
        } catch (_) {}
        return;
      }

      // 1. Global Broadcast
      _socket!.send(data, InternetAddress('255.255.255.255'), discoveryPort);

      // 2. Multicast Groups
      _socket!.send(data, InternetAddress('224.0.0.1'), discoveryPort);
      _socket!.send(data, InternetAddress('224.0.0.251'), discoveryPort);

      // 3. Subnet Broadcasts for all active interface IPs
      for (final ip in _localIps) {
        final parts = ip.split('.');
        if (parts.length == 4) {
          final subnetBroadcast = '${parts[0]}.${parts[1]}.${parts[2]}.255';
          _socket!.send(data, InternetAddress(subnetBroadcast), discoveryPort);
        }
      }

      // 4. Direct unicast heartbeats to all previously discovered active peers
      for (final device in _devices.values) {
        if (device.ip.isNotEmpty && !_localIps.contains(device.ip)) {
          try {
            _socket!.send(data, InternetAddress(device.ip), discoveryPort);
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('[DiscoveryService] Broadcast error: $e');
    }
  }

  void broadcastClipboard(String text) {
    if (_socket == null) return;

    final message = jsonEncode({
      'type': 'clipboard',
      'id': _deviceId,
      'name': _deviceName,
      'text': text,
    });

    final data = utf8.encode(message);

    // Skip UDP broadcast if the payload is too large (prevents OS Error 40: Message too long)
    // Most standard MTUs are 1500 bytes. We use a conservative 4096 byte limit for UDP.
    // Large clipboard data will still be reliably delivered via TCP in AppState.
    if (data.length > 4096) {
      debugPrint(
        '[DiscoveryService] Clipboard text too large for UDP (${data.length} bytes), relying on TCP fallback.',
      );
      return;
    }

    try {
      _socket!.send(data, InternetAddress('255.255.255.255'), discoveryPort);
      _socket!.send(data, InternetAddress('224.0.0.1'), discoveryPort);
      _socket!.send(data, InternetAddress('224.0.0.251'), discoveryPort);

      for (final ip in _localIps) {
        final parts = ip.split('.');
        if (parts.length == 4) {
          final subnetBroadcast = '${parts[0]}.${parts[1]}.${parts[2]}.255';
          _socket!.send(data, InternetAddress(subnetBroadcast), discoveryPort);
        }
      }

      for (final device in _devices.values) {
        if (device.ip.isNotEmpty) {
          try {
            _socket!.send(data, InternetAddress(device.ip), discoveryPort);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  void _handleDatagram(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;

    final datagram = _socket?.receive();
    if (datagram == null) return;

    try {
      final senderIp = datagram.address.address;

      // Ignore packets sent by ourselves (matching our own local IPs)
      if (_localIps.contains(senderIp)) return;

      final message =
          jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;
      final remoteDeviceId = message['id'] as String?;

      if (remoteDeviceId == null || remoteDeviceId == _deviceId) return;

      if (message['type'] == 'announce') {
        final device = DeviceInfo.fromJson(message);

        // Fallback to datagram's sender IP if missing in payload
        if (device.ip.isEmpty) {
          device.ip = senderIp;
        }

        final isNewDevice = !_devices.containsKey(device.id);
        device.lastSeen = DateTime.now();
        _devices[device.id] = device;
        _devicesController.add(devices);

        // Instant Handshake: If we just discovered a new peer or updated it,
        // send an immediate unicast presence announcement directly back to the sender's IP.
        if (isNewDevice) {
          _broadcast(targetIp: senderIp);
        }
      } else if (message['type'] == 'clipboard') {
        final text = message['text'] as String?;
        if (text != null && text.isNotEmpty) {
          _clipboardController.add({
            'text': text,
            'senderName': message['name'] ?? 'Unknown Device',
            'senderId': remoteDeviceId,
            'timestamp': DateTime.now().toIso8601String(),
          });
        }
      }
    } catch (_) {
      // Ignore malformed packets
    }
  }

  void _cleanupStaleDevices() {
    final now = DateTime.now();
    final staleIds = <String>[];

    for (final entry in _devices.entries) {
      if (now.difference(entry.value.lastSeen).inSeconds >
          staleTimeoutSeconds) {
        staleIds.add(entry.key);
      }
    }

    if (staleIds.isNotEmpty) {
      for (final id in staleIds) {
        _devices.remove(id);
      }
      _devicesController.add(devices);
    }
  }

  Future<void> refresh() async {
    _devices.clear();
    _devicesController.add([]);
    await _findLocalIps();
    _broadcast();
    Future.delayed(const Duration(milliseconds: 200), _broadcast);
    Future.delayed(const Duration(milliseconds: 500), _broadcast);
    Future.delayed(const Duration(milliseconds: 800), _broadcast);
  }

  void stop() {
    _broadcastTimer?.cancel();
    _cleanupTimer?.cancel();
    _socket?.close();
    _socket = null;
    _devices.clear();
    _devicesController.add([]);
  }

  void dispose() {
    stop();
    _devicesController.close();
    _clipboardController.close();
  }
}
