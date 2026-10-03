// The desktop dashboard: mission control for the Muse companion.
//
// Layout:
//   +------------------+-------------------------------------------+
//   | Avatar card      | Chat panel                                |
//   | (PixelStage)     | [messages scroll]                         |
//   | Caption          | [input........................] [Send]     |
//   +------------------+-------------------------------------------+
//   | Status card: link state, agent, version, quick actions       |
//   +-------------------------------------------------------------+
//
// Not a phone UI clone: this is a computer-style dashboard window with
// the avatar front and center, a full chat panel beside it, and the
// connection state always visible.

import 'dart:async';

import 'package:flutter/material.dart' hide ConnectionState;

import '../app/chat.dart';
import '../app/avatar_motion.dart';
import '../app/model.dart';
import '../app/pixel_avatar.dart';
import '../app/storage.dart';
import '../src/gadget/service.dart';
import 'pixel_stage.dart';

/// Passed from main.dart; everything the dashboard needs.
class DashboardContext {
  DashboardContext({
    required this.service,
    required this.presentation,
    required this.settings,
    required this.chat,
    required this.sdkTokens,
    required this.pairingStore,
  });

  final GadgetService service;
  final PresentationState presentation;
  final SettingsStore settings;
  final ChatHistory chat;
  final SecureSdkTokenStore sdkTokens;
  final SecurePairingStore pairingStore;

  void dispose() {
    service.stop();
    chat.close();
    presentation.close();
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.ctx});

  final DashboardContext ctx;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  StreamSubscription<void>? _chatSub;
  StreamSubscription<void>? _presentationSub;
  StreamSubscription<ConnectionState>? _linkSub;
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
    _presentationSub = widget.ctx.presentation.stream.listen((_) {
      if (mounted) setState(() {});
    });
    _linkSub = widget.ctx.service.onStateChanged.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _chatSub?.cancel();
    _presentationSub?.cancel();
    _linkSub?.cancel();
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

  Future<void> _showPairingDialog() async {
    final controller = TextEditingController();
    final token = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pair with Muse'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Paste your Muse device token below. You can find it in the '
              'Muse developer settings or copy it from another paired device.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Device token',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              minLines: 1,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Pair'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (token == null || token.isEmpty) return;
    try {
      await widget.ctx.pairingStore.save({'access_token': token});
      widget.ctx.service.wake();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pairing saved — connecting…')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Pairing failed: $e')),
        );
      }
    }
  }

  Future<void> _unpair() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unpair this device?'),
        content: const Text(
          'The saved pairing will be removed. You can pair again at any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Unpair'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await widget.ctx.service.unpair();
      widget.ctx.presentation.applyPlaceholder();
      widget.ctx.presentation.applyStatus('');
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final presentation = widget.ctx.presentation;
    final connection = widget.ctx.service.connectionState;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Muse Companion'),
        actions: [
          _ConnectionChip(connection: connection),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.link),
            tooltip: 'Pair with Muse',
            onPressed: _showPairingDialog,
          ),
          IconButton(
            icon: const Icon(Icons.link_off),
            tooltip: 'Unpair',
            onPressed: _unpair,
          ),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left: avatar + status.
          SizedBox(
            width: 320,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _AvatarCard(presentation: presentation),
                  const SizedBox(height: 12),
                  _StatusCard(ctx: widget.ctx),
                ],
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          // Right: chat.
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Expanded(
                      child: _ChatList(
                          chat: widget.ctx.chat, scroll: _scroll)),
                  const SizedBox(height: 8),
                  _ChatInput(
                    controller: _input,
                    sending: _sending,
                    enabled:
                        widget.ctx.service.connectionState ==
                        ConnectionState.connected,
                    onSend: _send,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionChip extends StatelessWidget {
  const _ConnectionChip({required this.connection});

  final ConnectionState connection;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (connection) {
      ConnectionState.connected => ('Connected', Colors.green),
      ConnectionState.connecting => ('Connecting…', Colors.orange),
      ConnectionState.waiting => ('Retrying', Colors.orange),
      ConnectionState.unpaired => ('Not paired', Colors.grey),
      ConnectionState.stopped => ('Stopped', Colors.red),
    };
    return Chip(
      avatar: Icon(Icons.circle, size: 12, color: color),
      label: Text(label),
    );
  }
}

class _AvatarCard extends StatelessWidget {
  const _AvatarCard({required this.presentation});

  final PresentationState presentation;

  @override
  Widget build(BuildContext context) {
    final caption = presentation.statusText;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: PixelStage(
                pose: presentation.pose,
                bytes: presentation.character,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              avatarStateLabel(presentation.pose),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    letterSpacing: 2,
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
            if (caption.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                caption,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.ctx});

  final DashboardContext ctx;

  @override
  Widget build(BuildContext context) {
    final service = ctx.service;
    final presentation = ctx.presentation;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Status',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            _StatusRow(
              label: 'Link',
              value: connectionStatusLabel(service.connectionState),
            ),
            if (service.statusDetail.isNotEmpty)
              _StatusRow(label: 'Detail', value: service.statusDetail),
            if (service.agentName != null)
              _StatusRow(label: 'Agent', value: service.agentName!),
            if (presentation.name != null)
              _StatusRow(label: 'Name', value: presentation.name!),
            const _StatusRow(label: 'Version', value: '0.1.0'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Reconnect'),
                    onPressed: () => service.wake(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.image_not_supported, size: 16),
                    label: const Text('Clear avatar'),
                    onPressed: () => presentation.applyPlaceholder(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
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
        constraints: const BoxConstraints(maxWidth: 480),
        decoration: BoxDecoration(
          color: isUser
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message.text),
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
