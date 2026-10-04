// Tests for VoiceService with a fake TTS engine.

import 'package:flutter_test/flutter_test.dart';
import 'package:muse_desktop_companion/app/voice.dart';

class FakeTtsEngine implements TtsEngine {
  final List<String> spoken = [];
  void Function()? _onComplete;
  bool stopped = false;

  @override
  Future<void> speak(String text) async {
    spoken.add(text);
  }

  @override
  Future<void> stop() async {
    stopped = true;
  }

  @override
  void setCompletionHandler(void Function() handler) {
    _onComplete = handler;
  }

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setSpeechRate(double rate) async {}

  void complete() => _onComplete?.call();
}

void main() {
  group('VoiceService', () {
    test('speak marks speaking true, completion clears it', () async {
      final engine = FakeTtsEngine();
      final voice = VoiceService(engine: engine);
      final states = <bool>[];
      voice.speakingStream.listen(states.add);

      await voice.speak('Hello there');
      expect(engine.spoken, ['Hello there']);
      expect(voice.isSpeaking, isTrue);

      engine.complete();
      await Future<void>.delayed(Duration.zero);
      expect(voice.isSpeaking, isFalse);
      expect(states, [true, false]);
      voice.dispose();
    });

    test('blank text is not spoken', () async {
      final engine = FakeTtsEngine();
      final voice = VoiceService(engine: engine);
      await voice.speak('   ');
      expect(engine.spoken, isEmpty);
      expect(voice.isSpeaking, isFalse);
      voice.dispose();
    });

    test('stop clears speaking state', () async {
      final engine = FakeTtsEngine();
      final voice = VoiceService(engine: engine);
      await voice.speak('Hello');
      expect(voice.isSpeaking, isTrue);
      await voice.stop();
      expect(engine.stopped, isTrue);
      expect(voice.isSpeaking, isFalse);
      voice.dispose();
    });

    test('speak stops previous speech first', () async {
      final engine = FakeTtsEngine();
      final voice = VoiceService(engine: engine);
      await voice.speak('one');
      await voice.speak('two');
      expect(engine.stopped, isTrue);
      expect(engine.spoken, ['one', 'two']);
      voice.dispose();
    });
  });
}
