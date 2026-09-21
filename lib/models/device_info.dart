/// Represents a discovered device on the local network.
class DeviceInfo {
  final String id;
  final String name;
  final String? username;
  final String? os;
  final String? hardwareName;
  final String? avatarBase64;
  String ip;
  final int port;
  final String platform;
  DateTime lastSeen;

  DeviceInfo({
    required this.id,
    required this.name,
    this.username,
    this.os,
    this.hardwareName,
    this.avatarBase64,
    required this.ip,
    required this.port,
    required this.platform,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      username: json['username'] as String?,
      os: json['os'] as String?,
      hardwareName: json['hardwareName'] as String?,
      avatarBase64: json['avatarBase64'] as String?,
      ip: json['ip'] as String,
      port: json['port'] as int,
      platform: json['platform'] as String? ?? 'unknown',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'username': username,
    'os': os,
    'hardwareName': hardwareName,
    'avatarBase64': avatarBase64,
    'ip': ip,
    'port': port,
    'platform': platform,
  };

  @override
  bool operator ==(Object other) => other is DeviceInfo && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
