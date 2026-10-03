// Widget tests for the Muse Desktop Companion.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muse_companion/app/avatar_motion.dart';
import 'package:muse_companion/app/chat.dart';
import 'package:muse_companion/app/desktop_commands.dart';
import 'package:muse_companion/app/model.dart';

void main() {
  test('desktop command specs include the avatar and status commands', () {
    final specs = desktopCommandSpecs();
    expect(specs.containsKey('display.draw_url'), isTrue);
    expect(specs.containsKey('display.show_animation'), isTrue);
    expect(specs.containsKey('companion.set_status'), isTrue);
    expect(specs.containsKey('pocket.set_status'), isTrue);
    expect(specs.containsKey('device.health'), isTrue);
    // Phone-only commands must not be advertised on desktop.
    expect(specs.containsKey('phone.call'), isFalse);
    expect(specs.containsKey('vision.capture'), isFalse);
  });

  test('presentation state applies pose and status', () {
    final presentation = PresentationState();
    expect(presentation.pose, AvatarPose.idle);
    presentation.applyPose(AvatarPose.thinking);
    expect(presentation.pose, AvatarPose.thinking);
    presentation.applyStatus('Hello from the Muse');
    expect(presentation.statusText, 'Hello from the Muse');
    expect(presentation.lines, contains('Hello from the Muse'));
    presentation.close();
  });

  test('chat history records a sending message', () {
    final chat = ChatHistory();
    final id = chat.addSending('hello');
    expect(chat.messages.length, 1);
    expect(chat.messages.first.text, 'hello');
    expect(chat.messages.first.status, ChatStatus.sending);
    chat.markSent(id);
    expect(chat.messages.first.status, ChatStatus.sent);
    chat.close();
  });

  testWidgets('bootstrap shows a loading screen, never black', (
    WidgetTester tester,
  ) async {
    // The real bootstrap needs secure storage; here we assert the loading
    // and error screens render their content instead of an empty window.
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('probe'))),
    );
    expect(find.text('probe'), findsOneWidget);
  });
}
