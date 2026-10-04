// Dashboard view: avatar card + status card, the mission-control home.

import 'package:flutter/material.dart' hide ConnectionState;

import '../../app/model.dart';
import '../../app/pixel_avatar.dart';
import '../../app/version.dart';
import '../app_shell.dart';
import '../pixel_stage.dart';

class DashboardView extends StatelessWidget {
  const DashboardView({super.key, required this.ctx});

  final DashboardContext ctx;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: _AvatarCard(presentation: ctx.presentation),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: _StatusCard(ctx: ctx),
          ),
        ],
      ),
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
            const _StatusRow(label: 'Version', value: kAppVersion),
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
