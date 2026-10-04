// Dashboard shell: openclaw-style sidebar navigation + content area.
//
// The sidebar holds Dashboard, Chat, Activity, and Settings. The top bar
// keeps the connection chip and pairing actions visible from every view.

import 'dart:async';

import 'package:flutter/material.dart' hide ConnectionState;

import '../app/chat.dart';
import '../app/log_buffer.dart';
import '../app/model.dart';
import '../app/storage.dart';
import '../src/gadget/service.dart';
import 'views/activity_view.dart';
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
  });

  final GadgetService service;
  final PresentationState presentation;
  final SettingsStore settings;
  final ChatHistory chat;
  final SecureSdkTokenStore sdkTokens;
  final SecurePairingStore pairingStore;
  final LogBuffer log;

  void dispose() {
    service.stop();
    chat.close();
    presentation.close();
    log.close();
  }
}

enum AppView { dashboard, chat, activity, settings }

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

  @override
  void initState() {
    super.initState();
    _linkSub = widget.ctx.service.onStateChanged.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
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
      widget.ctx.log.add('pairing', 'Pairing token saved — connecting…');
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
      widget.ctx.log.add('pairing', 'Unpaired.');
      widget.ctx.presentation.applyPlaceholder();
      widget.ctx.presentation.applyStatus('');
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final connection = widget.ctx.service.connectionState;
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Sidebar(
            view: _view,
            collapsed: _collapsed,
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
    );
  }

  Widget _buildView() {
    return switch (_view) {
      AppView.dashboard => DashboardView(ctx: widget.ctx),
      AppView.chat => ChatView(ctx: widget.ctx),
      AppView.activity => ActivityView(ctx: widget.ctx),
      AppView.settings => SettingsView(ctx: widget.ctx),
    };
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.view,
    required this.collapsed,
    required this.onSelect,
    required this.onToggleCollapse,
  });

  final AppView view;
  final bool collapsed;
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
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

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
                Icon(selected ? activeIcon : icon, color: color, size: 20),
                if (!collapsed) ...[
                  const SizedBox(width: 12),
                  Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: color,
                      fontWeight: selected
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
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
