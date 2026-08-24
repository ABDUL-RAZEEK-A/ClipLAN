import 'package:flutter_test/flutter_test.dart';
import 'package:cliplan/models/clipboard_item.dart';

void main() {
  test('ClipboardItem model serialization', () {
    final item = ClipboardItem.create(
      'Hello world snippet',
      senderName: 'Device A',
      isShared: true,
    );
    final json = item.toJson();

    expect(json['text'], 'Hello world snippet');
    expect(json['senderName'], 'Device A');
    expect(json['isShared'], isTrue);

    final restored = ClipboardItem.fromJson(json);
    expect(restored.id, item.id);
    expect(restored.text, 'Hello world snippet');
    expect(restored.senderName, 'Device A');
    expect(restored.isShared, isTrue);
  });

  test('ClipboardItem copyWith text update', () {
    final item = ClipboardItem.create('Original Text');
    final updated = item.copyWith(text: 'Updated Text');

    expect(updated.id, item.id);
    expect(updated.text, 'Updated Text');
    expect(updated.createdAt, item.createdAt);
  });
}
