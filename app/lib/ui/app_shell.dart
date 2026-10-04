// Dashboard shell: openclaw-style sidebar navigation + content area.
//
// The sidebar holds Dashboard, Chat, Activity, and Settings. The top bar
// keeps the connection chip and pairing actions visible from every view.

import 'dart:async';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/services.dart';

import '../app/approvals.dart';
import '../app/chat.dart';
import '../app/chat_persistence.dart';
import '../app/log_buffer.dart';
import '../app/model.dart';
import '../app/storage.dart';
import '../app/voice.dart';
import '../src/gadget/service.dart';
import 'command_palette.dart';
import 'views/activity_view.dart';
import 'views/approvals_view.dart';
import 'views/chat_view.dart';
import 'views/dashboard_view.dart';
import 'views/settings_view.dart';

/// Passed from main.dart; everything the dashboard needs.
class DashboardContext {
  DashboardContext({
    required this.service,
    required this.presentation,
    required this.settings,
    required this.chat,
    required this.sdkTokens,
    required this.pairingStore,
    required this.log,
    required this.approvals,
    required this.voice,
  });

  final GadgetService service;
  final PresentationState presentation;
  final SettingsStore settings;
  final ChatHistory chat;
  final SecureSdkTokenStore sdkTokens;
  final SecurePairingStore pairingStore;
  final LogBuffer log;
  final ApprovalQueue approvals;
  final VoiceService voice;

  void dispose() {
    service.stop();
    chat.close();
    presentation.close();
    log.close();
    approvals.close();
    voice.dispose();
  }
}

enum AppView { dashboard, chat, approvals, activity, settings }

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.ctx});

  final DashboardContext ctx;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppView _view = AppView.dashboard;
  bool _collapsed = false;
  StreamSubscription<ConnectionState>? _linkSub;
  StreamSubscription<void>? _approvalsSub;

  @override
  void initState() {
    super.initState();
    _linkSub = widget.ctx.service.onStateChanged.listen((_) {
      if (mounted) setState(() {});
    });
    _approvalsSub = widget.ctx.approvals.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    _approvalsSub?.cancel();
    super.dispose();
  }

  /// Jump to the Approvals view when a new request arrives while the user
  /// is elsewhere? No — just badge it. This switches views on demand.
  void _goToApprovals() {
    setState(() => _view = AppView.approvals);
  }

  void _openPalette() {
    final ctx = widget.ctx;
    showCommandPalette(context, [
      PaletteCommand(
        label: 'Go to Dashboard',
        hint: 'Switch to the Dashboard view',
        keywords: 'navigate view home',
        action: () => setState(() => _view = AppView.dashboard),
      ),
      PaletteCommand(
        label: 'Go to Chat',
        hint: 'Switch to the Chat view',
        keywords: 'navigate view messages talk',
        action: () => setState(() => _view = AppView.chat),
      ),
      PaletteCommand(
        label: 'Go to Approvals',
        hint: 'Review pending command approvals',
        keywords: 'navigate view allow deny permissions queue',
        action: _goToApprovals,
      ),
      PaletteCommand(
        label: 'Go to Activity',
        hint: 'Switch to the Activity view',
        keywords: 'navigate view log terminal',
        action: () => setState(() => _view = AppView.activity),
      ),
      PaletteCommand(
        label: 'Go to Settings',
        hint: 'Switch to the Settings view',
        keywords: 'navigate view preferences options',
        action: () => setState(() => _view = AppView.settings),
      ),
      PaletteCommand(
        label: 'Reconnect',
        hint: 'Drop the link and reconnect to the Muse',
        keywords: 'link refresh retry connection',
        action: () {
          ctx.service.wake();
          ctx.log.add('link', 'Manual reconnect requested (palette).');
        },
      ),
      PaletteCommand(
        label: 'Unpair',
        hint: 'Remove the saved pairing from this device',
        keywords: 'disconnect forget remove link',
        action: _unpair,
      ),
      PaletteCommand(
        label: 'Clear chat',
        hint: 'Delete the chat history (also clears the saved file)',
        keywords: 'delete wipe messages history',
        action: () {
          ctx.chat.clear();
          unawaited(clearChatHistoryFile());
          ctx.log.add('settings', 'Chat history cleared (palette).');
        },
      ),
      PaletteCommand(
        label: 'Toggle theme',
        hint: 'Cycle light → dark → system',
        keywords: 'appearance dark light mode',
        action: () => _cycleTheme(),
      ),
    ]);
  }

  Future<void> _cycleTheme() async {
    final ctx = widget.ctx;
    final current = ctx.presentation.settings.theme;
    final next = switch (current) {
      'light' => 'dark',
      'dark' => 'system',
      _ => 'light',
    };
    final updated = ctx.presentation.settings.copyWith(theme: next);
    ctx.presentation.applySettings(updated);
    await ctx.settings.saveSettings(updated);
    ctx.log.add('settings', 'Theme set to $next (palette).');
    if (mounted) setState(() {});
  }

  Future<void> _showPairingDialog() async {
    final controller = TextEditingController();
    final nodeId = widget.ctx.service.identity.nodeId;
    final token = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pair with Muse'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Where to find your token:\n'
                '• Muse app → Settings → Devices → Developer mode → SDK tokens\n'
                '• or gadgets.muse.ai → Account → SDK tokens\n'
                '• or copy it from another paired device.',
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'This desktop appears as:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    const Text('Muse Desktop'),
                    SelectableText(
                      nodeId,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ],
                ),
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
      widget.ctx.log.add('pairing', 'Pairing token saved — connecting…');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pairing saved — connecting…')),
        );
      }
    } catch (e) {
      final detail = e.toString();
      widget.ctx.log.add('pairing', 'Pairing failed: $detail');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Pairing failed: $detail'),
            duration: const Duration(seconds: 6),
          ),
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
      widget.ctx.log.add('pairing', 'Unpaired.');
      widget.ctx.presentation.applyPlaceholder();
      widget.ctx.presentation.applyStatus('');
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final connection = widget.ctx.service.connectionState;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            _openPalette,
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _openPalette,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Sidebar(
                view: _view,
                collapsed: _collapsed,
                pendingApprovals: widget.ctx.approvals.pendingCount,
                onSelect: (view) => setState(() => _view = view),
                onToggleCollapse: () =>
                    setState(() => _collapsed = !_collapsed),
              ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TopBar(
                  view: _view,
                  connection: connection,
                  onPair: _showPairingDialog,
                  onUnpair: _unpair,
                ),
                Expanded(child: _buildView()),
              ],
            ),
          ),
        ],
      ),
        ),
      ),
    );
  }

  Widget _buildView() {
    return switch (_view) {
      AppView.dashboard => DashboardView(ctx: widget.ctx),
      AppView.chat => ChatView(ctx: widget.ctx),
      AppView.approvals => ApprovalsView(ctx: widget.ctx),
      AppView.activity => ActivityView(ctx: widget.ctx),
      AppView.settings => SettingsView(ctx: widget.ctx),
    };
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.view,
    required this.collapsed,
    required this.pendingApprovals,
    required this.onSelect,
    required this.onToggleCollapse,
  });

  final AppView view;
  final bool collapsed;
  final int pendingApprovals;
  final ValueChanged<AppView> onSelect;
  final VoidCallback onToggleCollapse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = collapsed ? 64.0 : 216.0;
    return Container(
      width: width,
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  Icons.smart_toy_outlined,
                  color: theme.colorScheme.primary,
                ),
                if (!collapsed) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Muse',
                      style: theme.textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _NavItem(
                  icon: Icons.dashboard_outlined,
                  activeIcon: Icons.dashboard,
                  label: 'Dashboard',
                  selected: view == AppView.dashboard,
                  collapsed: collapsed,
                  onTap: () => onSelect(AppView.dashboard),
                ),
                _NavItem(
                  icon: Icons.chat_bubble_outline,
                  activeIcon: Icons.chat_bubble,
                  label: 'Chat',
                  selected: view == AppView.chat,
                  collapsed: collapsed,
                  onTap: () => onSelect(AppView.chat),
                ),
                _NavItem(
                  icon: Icons.shield_outlined,
                  activeIcon: Icons.shield,
                  label: 'Approvals',
                  selected: view == AppView.approvals,
                  collapsed: collapsed,
                  badge: pendingApprovals,
                  onTap: () => onSelect(AppView.approvals),
                ),
                _NavItem(
                  icon: Icons.terminal_outlined,
                  activeIcon: Icons.terminal,
                  label: 'Activity',
                  selected: view == AppView.activity,
                  collapsed: collapsed,
                  onTap: () => onSelect(AppView.activity),
                ),
                _NavItem(
                  icon: Icons.settings_outlined,
                  activeIcon: Icons.settings,
                  label: 'Settings',
                  selected: view == AppView.settings,
                  collapsed: collapsed,
                  onTap: () => onSelect(AppView.settings),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          _NavItem(
            icon: collapsed
                ? Icons.chevron_right
                : Icons.chevron_left,
            activeIcon: collapsed
                ? Icons.chevron_right
                : Icons.chevron_left,
            label: 'Collapse',
            selected: false,
            collapsed: collapsed,
            onTap: onToggleCollapse,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.collapsed,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  /// Pending count shown as a badge; 0 hides it.
  final int badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: selected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            child: Row(
              children: [
                _BadgeIcon(
                  icon: Icon(
                    selected ? activeIcon : icon,
                    color: color,
                    size: 20,
                  ),
                  badge: badge,
                  collapsed: collapsed,
                ),
                if (!collapsed) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: color,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (badge > 0) ...[
                    const SizedBox(width: 8),
                    _CountBadge(count: badge),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small count pill shown next to a nav label.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.error,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$count',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onError,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Nav icon with a dot badge when collapsed and count > 0.
class _BadgeIcon extends StatelessWidget {
  const _BadgeIcon({
    required this.icon,
    required this.badge,
    required this.collapsed,
  });

  final Widget icon;
  final int badge;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    if (badge <= 0 || !collapsed) return icon;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          right: -4,
          top: -4,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.error,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.view,
    required this.connection,
    required this.onPair,
    required this.onUnpair,
  });

  final AppView view;
  final ConnectionState connection;
  final VoidCallback onPair;
  final VoidCallback onUnpair;

  String get _title => switch (view) {
    AppView.dashboard => 'Dashboard',
    AppView.chat => 'Chat',
    AppView.approvals => 'Approvals',
    AppView.activity => 'Activity',
    AppView.settings => 'Settings',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            _title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Spacer(),
          _ConnectionChip(connection: connection),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.link),
            tooltip: 'Pair with Muse',
            onPressed: onPair,
          ),
          IconButton(
            icon: const Icon(Icons.link_off),
            tooltip: 'Unpair',
            onPressed: onUnpair,
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
