// Chat history persistence: JSON file in the app documents directory.
//
// The history is saved (debounced) whenever it changes and restored at
// startup, keeping the last [kPersistedChatMessages] messages. The Clear
// chat button in Settings wipes both the in-memory history and this file.

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'chat.dart';

/// Maximum messages kept in the persisted file (matches ChatHistory bound).
const int kPersistedChatMessages = 200;

/// File holding the persisted chat history.
Future<File> chatHistoryFile() async {
  final dir = await getApplicationDocumentsDirectory();
  final appDir = Directory('${dir.path}/muse_desktop_companion');
  if (!await appDir.exists()) {
    await appDir.create(recursive: true);
  }
  return File('${appDir.path}/chat_history.json');
}

/// Write the current history to disk. Streaming flags are normalized so a
/// restored history never shows a half-streamed bubble.
Future<void> saveChatHistory(ChatHistory chat) async {
  final file = await chatHistoryFile();
  final payload = {
    'version': 1,
    'messages': chat.messages.map((m) => m.toJson()).toList(),
  };
  await file.writeAsString(jsonEncode(payload));
}

/// Read the persisted history, or an empty list when there is none / it is
/// corrupt. Never throws.
Future<List<ChatMessage>> loadChatHistory() async {
  try {
    final file = await chatHistoryFile();
    if (!await file.exists()) return <ChatMessage>[];
    final raw = await file.readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) return <ChatMessage>[];
    final messages = decoded['messages'];
    if (messages is! List) return <ChatMessage>[];
    final restored = <ChatMessage>[];
    for (final item in messages) {
      if (item is Map<String, Object?>) {
        final message = ChatMessage.fromJson(item);
        if (message != null) restored.add(message);
      }
    }
    return restored;
  } catch (_) {
    return <ChatMessage>[];
  }
}

/// Delete the persisted history file, if it exists. Never throws.
Future<void> clearChatHistoryFile() async {
  try {
    final file = await chatHistoryFile();
    if (await file.exists()) await file.delete();
  } catch (_) {
    // Best effort: the in-memory clear already happened.
  }
}
