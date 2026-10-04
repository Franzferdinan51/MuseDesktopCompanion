// Tests for chat history JSON serialization + restore.

import 'package:flutter_test/flutter_test.dart';
import 'package:muse_desktop_companion/app/chat.dart';

void main() {
  group('ChatMessage JSON', () {
    test('round-trips through toJson/fromJson', () {
      final original = ChatMessage(
        id: 7,
        text: 'Hello **world**',
        sentAt: DateTime.utc(2026, 10, 3, 12, 0, 0),
        status: ChatStatus.sending,
        role: ChatRole.assistant,
        streaming: true,
        serverId: 'srv-1',
      );
      final restored = ChatMessage.fromJson(original.toJson());
      expect(restored, isNotNull);
      expect(restored!.text, 'Hello **world**');
      expect(restored.sentAt, original.sentAt);
      expect(restored.role, ChatRole.assistant);
      expect(restored.serverId, 'srv-1');
      // Restored messages are always finished bubbles.
      expect(restored.streaming, isFalse);
      expect(restored.status, ChatStatus.sent);
    });

    test('corrupt entries return null', () {
      expect(ChatMessage.fromJson(const {}), isNull);
      expect(
        ChatMessage.fromJson(const {'text': 'x'}),
        isNull,
      );
      expect(
        ChatMessage.fromJson(const {'text': 'x', 'sentAt': 'not-a-date'}),
        isNull,
      );
      expect(
        ChatMessage.fromJson(const {'text': 42, 'sentAt': '2026-01-01'}),
        isNull,
      );
    });

    test('unknown role defaults to user', () {
      final restored = ChatMessage.fromJson(const {
        'text': 'hi',
        'sentAt': '2026-01-01T00:00:00.000Z',
        'role': 'system',
      });
      expect(restored, isNotNull);
      expect(restored!.role, ChatRole.user);
    });
  });

  group('ChatHistory.restoreMessages', () {
    test('reassigns ids and keeps order', () {
      final chat = ChatHistory();
      final id = chat.addSending('first');
      expect(id, 1);
      final loaded = [
        ChatMessage(
          id: 0,
          text: 'old one',
          sentAt: DateTime.utc(2026, 1, 1),
          status: ChatStatus.sent,
          role: ChatRole.user,
        ),
        ChatMessage(
          id: 0,
          text: 'old two',
          sentAt: DateTime.utc(2026, 1, 2),
          status: ChatStatus.sent,
          role: ChatRole.assistant,
        ),
      ];
      chat.restoreMessages(loaded);
      final messages = chat.messages;
      expect(messages.length, 3);
      expect(messages[0].text, 'first');
      expect(messages[1].text, 'old one');
      expect(messages[2].text, 'old two');
      // Ids stay unique.
      final ids = messages.map((m) => m.id).toSet();
      expect(ids.length, 3);
    });

    test('respects maxMessages bound', () {
      final chat = ChatHistory(maxMessages: 2);
      chat.restoreMessages([
        ChatMessage(
          id: 0,
          text: 'a',
          sentAt: DateTime.utc(2026, 1, 1),
          status: ChatStatus.sent,
          role: ChatRole.user,
        ),
        ChatMessage(
          id: 0,
          text: 'b',
          sentAt: DateTime.utc(2026, 1, 2),
          status: ChatStatus.sent,
          role: ChatRole.user,
        ),
        ChatMessage(
          id: 0,
          text: 'c',
          sentAt: DateTime.utc(2026, 1, 3),
          status: ChatStatus.sent,
          role: ChatRole.user,
        ),
      ]);
      expect(chat.messages.length, 2);
      expect(chat.messages.last.text, 'c');
    });
  });
}
