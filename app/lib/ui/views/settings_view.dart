// Settings view: theme, avatar override, connection, and app info.

import 'dart:async';

import 'package:flutter/material.dart' hide ConnectionState;

import '../../app/chat_persistence.dart';
import '../../app/desktop_commands.dart';
import '../../app/model.dart';
import '../../app/version.dart';
import '../app_shell.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key, required this.ctx});

  final DashboardContext ctx;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final TextEditingController _avatarUrl = TextEditingController();
  bool _applyingAvatar = false;

  @override
  void dispose() {
    _avatarUrl.dispose();
    super.dispose();
  }

  Future<void> _setTheme(String theme) async {
    final ctx = widget.ctx;
    final updated = ctx.presentation.settings.copyWith(theme: theme);
    ctx.presentation.applySettings(updated);
    unawaited(ctx.settings.saveSettings(updated));
    ctx.log.add('settings', 'Theme set to $theme.');
    setState(() {});
  }

  Future<void> _setSpeakReplies(bool value) async {
    final ctx = widget.ctx;
    final updated = ctx.presentation.settings.copyWith(speakReplies: value);
    ctx.presentation.applySettings(updated);
    await ctx.settings.saveSettings(updated);
    if (!value) {
      // Stop anything currently playing when the user turns speech off.
      await ctx.voice.stop();
    }
    ctx.log.add('settings', 'Speak replies ${value ? 'on' : 'off'}.');
    if (mounted) setState(() {});
  }

  Future<void> _applyAvatarUrl() async {
    final url = _avatarUrl.text.trim();
    if (url.isEmpty || _applyingAvatar) return;
    setState(() => _applyingAvatar = true);
    try {
      final bytes = await downloadCharacterBytes(url);
      if (bytes != null) {
        widget.ctx.presentation.applyCharacter(bytes);
        widget.ctx.log.add('settings', 'Avatar applied from URL.');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Avatar updated.')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not download that image.')),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _applyingAvatar = false);
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
      widget.ctx.log.add('pairing', 'Unpaired from Settings.');
      widget.ctx.presentation.applyPlaceholder();
      widget.ctx.presentation.applyStatus('');
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctx = widget.ctx;
    final theme = ctx.presentation.settings.theme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Section(
            title: 'Appearance',
            child: Row(
              children: [
                const Text('Theme'),
                const Spacer(),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'light',
                      label: Text('Light'),
                      icon: Icon(Icons.light_mode, size: 16),
                    ),
                    ButtonSegment(
                      value: 'dark',
                      label: Text('Dark'),
                      icon: Icon(Icons.dark_mode, size: 16),
                    ),
                    ButtonSegment(
                      value: 'system',
                      label: Text('System'),
                      icon: Icon(Icons.settings_suggest, size: 16),
                    ),
                  ],
                  selected: {theme},
                  onSelectionChanged: (selected) =>
                      _setTheme(selected.first),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Section(
            title: 'Avatar',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _avatarUrl,
                        decoration: const InputDecoration(
                          labelText: 'Avatar image URL',
                          hintText: 'https://…/avatar.png',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _applyAvatarUrl(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed:
                          _applyingAvatar ? null : _applyAvatarUrl,
                      child: _applyingAvatar
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Text('Apply'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.image_not_supported, size: 16),
                  label: const Text('Clear custom avatar'),
                  onPressed: () {
                    ctx.presentation.applyPlaceholder();
                    ctx.log.add('settings', 'Avatar cleared.');
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Section(
            title: 'Connection',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _InfoRow(
                  label: 'Link',
                  value: connectionStatusLabel(
                    ctx.service.connectionState,
                  ),
                ),
                if (ctx.service.agentName != null)
                  _InfoRow(
                    label: 'Agent',
                    value: ctx.service.agentName!,
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Reconnect'),
                        onPressed: () {
                          ctx.service.wake();
                          ctx.log.add('link', 'Manual reconnect requested.');
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.link_off, size: 16),
                        label: const Text('Unpair'),
                        onPressed: _unpair,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Section(
            title: 'Voice',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Speak assistant replies'),
                          SizedBox(height: 2),
                          Text(
                            'Read Muse\u2019s replies aloud on this device.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: ctx.presentation.settings.speakReplies,
                      onChanged: _setSpeakReplies,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.stop, size: 16),
                  label: const Text('Stop speaking now'),
                  onPressed: () => ctx.voice.stop(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Section(
            title: 'Chat',
            child: OutlinedButton.icon(
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('Clear chat history'),
              onPressed: () async {
                ctx.chat.clear();
                await clearChatHistoryFile();
                ctx.log.add('settings', 'Chat history cleared.');
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Chat history cleared.'),
                    ),
                  );
                }
              },
            ),
          ),
          const SizedBox(height: 12),
          _Section(
            title: 'About',
            child: const _InfoRow(
              label: 'Version',
              value: kAppVersion,
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
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
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
