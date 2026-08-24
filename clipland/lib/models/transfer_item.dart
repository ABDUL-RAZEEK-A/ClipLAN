import 'dart:io';

/// Status of a file transfer operation.
enum TransferStatus {
  pending,
  waitingApproval,
  transferring,
  verifying,
  completed,
  failed,
  cancelled,
}

/// Direction of a transfer from this device's perspective.
enum TransferDirection { sending, receiving }

/// Represents a single file within a transfer.
class FileItem {
  final String name;
  final int size;
  final String? mime;
  String? path;
  String? checksum;

  FileItem({
    required this.name,
    required this.size,
    this.mime,
    this.path,
    this.checksum,
  });

  factory FileItem.fromJson(Map<String, dynamic> json) {
    return FileItem(
      name: json['name'] as String,
      size: json['size'] as int,
      mime: json['mime'] as String?,
      path: json['path'] as String?,
      checksum: json['checksum'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'size': size,
    if (mime != null) 'mime': mime,
    if (path != null) 'path': path,
    if (checksum != null) 'checksum': checksum,
  };

  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// Represents a complete transfer session (one or more files).
class TransferItem {
  final String id;
  final String deviceName;
  final String deviceIp;
  final TransferDirection direction;
  final List<FileItem> files;
  TransferStatus status;
  int currentFileIndex;
  int bytesTransferred;
  String? errorMessage;
  DateTime startTime;
  DateTime? endTime;
  Socket? socket;
  bool? checksumValid;

  TransferItem({
    required this.id,
    required this.deviceName,
    required this.deviceIp,
    required this.direction,
    required this.files,
    this.status = TransferStatus.pending,
    this.currentFileIndex = 0,
    this.bytesTransferred = 0,
    this.errorMessage,
    DateTime? startTime,
    this.endTime,
    this.socket,
    this.checksumValid,
  }) : startTime = startTime ?? DateTime.now();

  int get totalSize => files.fold(0, (sum, f) => sum + f.size);

  double get progress {
    if (totalSize == 0) return 0;
    return (bytesTransferred / totalSize).clamp(0.0, 1.0);
  }

  String get formattedTotalSize {
    final s = totalSize;
    if (s < 1024) return '$s B';
    if (s < 1024 * 1024) return '${(s / 1024).toStringAsFixed(1)} KB';
    if (s < 1024 * 1024 * 1024) {
      return '${(s / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(s / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String get statusLabel {
    switch (status) {
      case TransferStatus.pending:
        return 'Pending';
      case TransferStatus.waitingApproval:
        return 'Waiting';
      case TransferStatus.transferring:
        return 'Transferring';
      case TransferStatus.verifying:
        return 'Verifying';
      case TransferStatus.completed:
        return 'Completed';
      case TransferStatus.failed:
        return 'Failed';
      case TransferStatus.cancelled:
        return 'Cancelled';
    }
  }

  Map<String, dynamic> toHistoryJson() => {
    'id': id,
    'deviceName': deviceName,
    'deviceIp': deviceIp,
    'direction': direction.name,
    'files': files.map((f) => f.toJson()).toList(),
    'status': status.name,
    'bytesTransferred': bytesTransferred,
    'startTime': startTime.toIso8601String(),
    'endTime': endTime?.toIso8601String(),
    'checksumValid': checksumValid,
  };

  factory TransferItem.fromHistoryJson(Map<String, dynamic> json) {
    return TransferItem(
      id: json['id'] as String,
      deviceName: json['deviceName'] as String,
      deviceIp: json['deviceIp'] as String,
      direction: TransferDirection.values.byName(json['direction'] as String),
      files: (json['files'] as List)
          .map((f) => FileItem.fromJson(Map<String, dynamic>.from(f as Map)))
          .toList(),
      status: TransferStatus.values.byName(json['status'] as String),
      bytesTransferred: json['bytesTransferred'] as int,
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: json['endTime'] != null
          ? DateTime.parse(json['endTime'] as String)
          : null,
      checksumValid: json['checksumValid'] as bool? ?? true,
    );
  }
}
