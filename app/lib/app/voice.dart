// Voice output: text-to-speech for assistant replies.
//
// [TtsEngine] abstracts the platform TTS so the service is unit-testable;
// [FlutterTtsEngine] is the real implementation backed by flutter_tts.

import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

/// Minimal TTS surface used by [VoiceService].
abstract class TtsEngine {
  Future<void> speak(String text);
  Future<void> stop();
  void setCompletionHandler(void Function() handler);
  Future<void> setVolume(double volume);
  Future<void> setSpeechRate(double rate);
}

/// flutter_tts-backed engine.
class FlutterTtsEngine implements TtsEngine {
  FlutterTtsEngine() : _tts = FlutterTts();

  final FlutterTts _tts;

  @override
  Future<void> speak(String text) => _tts.speak(text);

  @override
  Future<void> stop() => _tts.stop();

  @override
  void setCompletionHandler(void Function() handler) {
    _tts.setCompletionHandler(handler);
  }

  @override
  Future<void> setVolume(double volume) => _tts.setVolume(volume);

  @override
  Future<void> setSpeechRate(double rate) => _tts.setSpeechRate(rate);
}

/// Speaks assistant replies when enabled. Emits [speaking] so the UI can
/// show a stop button while audio is playing.
class VoiceService {
  VoiceService({TtsEngine? engine}) : _engine = engine ?? FlutterTtsEngine() {
    _engine.setCompletionHandler(() => _setSpeaking(false));
  }

  final TtsEngine _engine;
  final StreamController<bool> _speaking = StreamController<bool>.broadcast();
  bool _isSpeaking = false;

  /// Fires true when speech starts, false when it stops or completes.
  Stream<bool> get speakingStream => _speaking.stream;

  bool get isSpeaking => _isSpeaking;

  /// Speak [text] aloud, stopping any in-progress speech first.
  Future<void> speak(String text, {double volume = 0.8}) async {
    final clean = text.trim();
    if (clean.isEmpty) return;
    await stop();
    await _engine.setVolume(volume.clamp(0.0, 1.0));
    await _engine.setSpeechRate(0.95);
    _setSpeaking(true);
    try {
      await _engine.speak(clean);
    } catch (_) {
      _setSpeaking(false);
    }
  }

  /// Stop any in-progress speech.
  Future<void> stop() async {
    try {
      await _engine.stop();
    } finally {
      _setSpeaking(false);
    }
  }

  void _setSpeaking(bool value) {
    if (_isSpeaking == value) return;
    _isSpeaking = value;
    if (!_speaking.isClosed) _speaking.add(value);
  }

  void dispose() {
    if (!_speaking.isClosed) _speaking.close();
  }
}
