// Chat view: message list with markdown rendering + input.

import 'dart:async';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../app/avatar_motion.dart';
import '../../app/chat.dart';
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
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _chatSub = widget.ctx.chat.stream.listen((_) {
      if (mounted) {
        setState(() {});
        _scrollToBottom();
      }
    });
    // Scroll to the latest message once the view first lays out.
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    _chatSub?.cancel();
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
    setState(() => _sending = true);
    _input.clear();
    final id = widget.ctx.chat.addSending(text);
    try {
      final result = await widget.ctx.service.sendChat(text, null, const []);
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            child: _ChatList(chat: widget.ctx.chat, scroll: _scroll),
          ),
          const SizedBox(height: 8),
          _ChatInput(
            controller: _input,
            sending: _sending,
            enabled: widget.ctx.service.connectionState ==
                ConnectionState.connected,
            onSend: _send,
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
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final bool enabled;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            enabled: enabled && !sending,
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
        FilledButton.icon(
          icon: sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send, size: 16),
          label: const Text('Send'),
          onPressed: enabled && !sending ? onSend : null,
        ),
      ],
    );
  }
}
