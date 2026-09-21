import 'package:uuid/uuid.dart';

/// Data model representing a clipboard text snippet.
class ClipboardItem {
  final String id;
  final String text;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? senderName;
  final bool isShared;

  ClipboardItem({
    required this.id,
    required this.text,
    required this.createdAt,
    this.updatedAt,
    this.senderName,
    this.isShared = false,
  });

  factory ClipboardItem.create(
    String text, {
    String? senderName,
    bool isShared = false,
  }) {
    return ClipboardItem(
      id: const Uuid().v4(),
      text: text,
      createdAt: DateTime.now(),
      senderName: senderName,
      isShared: isShared,
    );
  }

  ClipboardItem copyWith({
    String? text,
    DateTime? updatedAt,
    String? senderName,
    bool? isShared,
  }) {
    return ClipboardItem(
      id: id,
      text: text ?? this.text,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      senderName: senderName ?? this.senderName,
      isShared: isShared ?? this.isShared,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'senderName': senderName,
      'isShared': isShared,
    };
  }

  factory ClipboardItem.fromJson(Map<String, dynamic> json) {
    return ClipboardItem(
      id: json['id'] as String? ?? const Uuid().v4(),
      text: json['text'] as String? ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
      senderName: json['senderName'] as String?,
      isShared: json['isShared'] as bool? ?? false,
    );
  }
}
