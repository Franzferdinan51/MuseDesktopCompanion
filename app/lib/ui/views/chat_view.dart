// Chat view: message list with markdown rendering + input.
//
// The input bar has push-to-talk voice input (hold the mic button) and a
// stop button while assistant speech is playing.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../app/avatar_motion.dart';
import '../../app/chat.dart';
import '../../app/chat_persistence.dart';
import '../../src/gadget/chat_events.dart';
import '../../src/gadget/service.dart';
import '../app_shell.dart';

class ChatView extends StatefulWidget {
  const ChatView({super.key, required this.ctx});

  final DashboardContext ctx;

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  StreamSubscription<void>? _chatSub;
  StreamSubscription<bool>? _speakingSub;
  bool _sending = false;

  // Push-to-talk recording state.
  final AudioRecorder _recorder = AudioRecorder();
  bool _recording = false;
  Duration _recordElapsed = Duration.zero;
  Timer? _recordTimer;
  DateTime? _recordStartedAt;

  bool _speaking = false;

  @override
  void initState() {
    super.initState();
    _chatSub = widget.ctx.chat.stream.listen((_) {
      if (mounted) {
        setState(() {});
        _scrollToBottom();
      }
    });
    _speakingSub = widget.ctx.voice.speakingStream.listen((speaking) {
      if (mounted) setState(() => _speaking = speaking);
    });
    _speaking = widget.ctx.voice.isSpeaking;
    // Scroll to the latest message once the view first lays out.
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    _chatSub?.cancel();
    _speakingSub?.cancel();
    _recordTimer?.cancel();
    _recorder.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    _input.clear();
    await _sendMessage(text, const []);
  }

  Future<void> _sendMessage(
    String text,
    List<ChatAttachment> attachments,
  ) async {
    if (_sending) return;
    setState(() => _sending = true);
    final id = widget.ctx.chat.addSending(text);
    // Persist the outgoing message right away; assistant replies persist
    // through the debounced saver in main.dart.
    unawaited(saveChatHistory(widget.ctx.chat));
    try {
      final result = await widget.ctx.service.sendChat(text, null, attachments);
      if (result['ok'] == true) {
        widget.ctx.chat.markSent(id);
        widget.ctx.presentation.applyPose(AvatarPose.thinking);
      } else {
        widget.ctx.chat.markFailed(id, '${result['error'] ?? 'failed'}');
      }
    } catch (e) {
      widget.ctx.chat.markFailed(id, e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Push-to-talk: start recording while the mic button is held.
  Future<void> _startRecording() async {
    if (_recording || _sending) return;
    final connected =
        widget.ctx.service.connectionState == ConnectionState.connected;
    if (!connected) return;
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Microphone permission denied. Enable it in System Settings '
                '→ Privacy & Security → Microphone.',
              ),
            ),
          );
        }
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/voice_note_${DateTime.now().millisecondsSinceEpoch}.wav';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.wav),
        path: path,
      );
      setState(() {
        _recording = true;
        _recordElapsed = Duration.zero;
        _recordStartedAt = DateTime.now();
      });
      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!mounted || _recordStartedAt == null) return;
        setState(() {
          _recordElapsed = DateTime.now().difference(_recordStartedAt!);
        });
      });
      widget.ctx.presentation.applyPose(AvatarPose.listening);
    } catch (e) {
      widget.ctx.log.add('voice', 'Recording failed to start: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not start recording: $e')));
      }
    }
  }

  /// Mic released: stop, send the WAV as a voice note attachment.
  Future<void> _stopRecordingAndSend() async {
    if (!_recording) return;
    _recordTimer?.cancel();
    setState(() => _recording = false);
    widget.ctx.presentation.applyPose(AvatarPose.thinking);
    String? path;
    try {
      path = await _recorder.stop();
    } catch (e) {
      widget.ctx.log.add('voice', 'Recording stop failed: $e');
    }
    if (path == null) return;
    try {
      final bytes = await File(path).readAsBytes();
      if (bytes.isEmpty) return;
      await _sendMessage('🎤 Voice note', [
        ChatAttachment(
          mimeType: 'audio/wav',
          filename: 'voice_note.wav',
          bytes: bytes,
        ),
      ]);
    } catch (e) {
      widget.ctx.log.add('voice', 'Voice note send failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Voice note failed: $e')));
      }
    } finally {
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }

  String get _recordLabel {
    final s = _recordElapsed.inSeconds;
    final mm = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final connected =
        widget.ctx.service.connectionState == ConnectionState.connected;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            child: _ChatList(chat: widget.ctx.chat, scroll: _scroll),
          ),
          if (_recording) ...[
            const SizedBox(height: 8),
            _RecordingIndicator(elapsed: _recordLabel),
          ],
          const SizedBox(height: 8),
          _ChatInput(
            controller: _input,
            sending: _sending,
            enabled: connected,
            recording: _recording,
            speaking: _speaking,
            onSend: _send,
            onRecordStart: _startRecording,
            onRecordEnd: _stopRecordingAndSend,
            onStopSpeaking: () => widget.ctx.voice.stop(),
          ),
        ],
      ),
    );
  }
}

class _RecordingIndicator extends StatelessWidget {
  const _RecordingIndicator({required this.elapsed});

  final String elapsed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Recording $elapsed — release to send',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onErrorContainer,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatList extends StatelessWidget {
  const _ChatList({required this.chat, required this.scroll});

  final ChatHistory chat;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final messages = chat.messages;
    if (messages.isEmpty) {
      return Center(
        child: Text(
          'No messages yet.\nPair with Muse, then say hello.',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
        ),
      );
    }
    return ListView.builder(
      controller: scroll,
      itemCount: messages.length,
      itemBuilder: (context, i) => _ChatBubble(message: messages[i]),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatRole.user;
    final theme = Theme.of(context);
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 560),
        decoration: BoxDecoration(
          color: isUser
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MarkdownBody(
              data: message.text,
              selectable: true,
              styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                p: theme.textTheme.bodyMedium,
              ),
            ),
            if (message.status == ChatStatus.failed)
              Text(
                'Failed: ${message.error}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            if (message.streaming)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '…',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChatInput extends StatelessWidget {
  const _ChatInput({
    required this.controller,
    required this.sending,
    required this.enabled,
    required this.recording,
    required this.speaking,
    required this.onSend,
    required this.onRecordStart,
    required this.onRecordEnd,
    required this.onStopSpeaking,
  });

  final TextEditingController controller;
  final bool sending;
  final bool enabled;
  final bool recording;
  final bool speaking;
  final VoidCallback onSend;
  final VoidCallback onRecordStart;
  final VoidCallback onRecordEnd;
  final VoidCallback onStopSpeaking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            enabled: enabled && !sending && !recording,
            decoration: InputDecoration(
              hintText: enabled
                  ? 'Message your Muse…'
                  : 'Pair with Muse to start chatting',
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
            ),
            onSubmitted: (_) => onSend(),
          ),
        ),
        const SizedBox(width: 8),
        // Push-to-talk: hold to record, release to send.
        GestureDetector(
          onLongPressStart: (_) => onRecordStart(),
          onLongPressEnd: (_) => onRecordEnd(),
          // A quick tap also toggles recording for accessibility.
          onTap: recording ? onRecordEnd : null,
          child: Container(
            decoration: BoxDecoration(
              color: recording
                  ? theme.colorScheme.error
                  : theme.colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(12),
            child: Icon(
              recording ? Icons.mic : Icons.mic_none,
              size: 20,
              color: recording
                  ? theme.colorScheme.onError
                  : (enabled
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.disabledColor),
            ),
          ),
        ),
        if (speaking) ...[
          const SizedBox(width: 8),
          IconButton.filledTonal(
            icon: const Icon(Icons.stop, size: 20),
            tooltip: 'Stop speaking',
            onPressed: onStopSpeaking,
          ),
        ],
        const SizedBox(width: 8),
        FilledButton.icon(
          icon: sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send, size: 16),
          label: const Text('Send'),
          onPressed: enabled && !sending && !recording ? onSend : null,
        ),
      ],
    );
  }
}
