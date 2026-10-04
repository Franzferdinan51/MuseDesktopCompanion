// Approvals view: pending Muse command confirmations.
//
// Commands gated by [ApprovalQueue.requiresApproval] wait here instead of
// running immediately. Each card shows the command name, its parameters,
// and Allow / Deny buttons. The sidebar shows a badge with the pending
// count while any are waiting.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/approvals.dart';
import '../app_shell.dart';

class ApprovalsView extends StatefulWidget {
  const ApprovalsView({super.key, required this.ctx});

  final DashboardContext ctx;

  @override
  State<ApprovalsView> createState() => _ApprovalsViewState();
}

class _ApprovalsViewState extends State<ApprovalsView> {
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.ctx.approvals.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pending = widget.ctx.approvals.pending;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Approvals',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            'Muse asks here before running sensitive commands. '
            'Nothing runs until you allow it.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: pending.isEmpty
                ? Center(
                    child: Text(
                      'Nothing waiting for approval.',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: pending.length,
                    itemBuilder: (context, i) =>
                        _ApprovalCard(approval: pending[i], ctx: widget.ctx),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({required this.approval, required this.ctx});

  final PendingApproval approval;
  final DashboardContext ctx;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final params = approval.params.entries.toList();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.shield_outlined,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    approval.command,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (params.isEmpty)
              Text(
                'No parameters.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.grey,
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final entry in params)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: RichText(
                          text: TextSpan(
                            style: theme.textTheme.bodySmall,
                            children: [
                              TextSpan(
                                text: '${entry.key}: ',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              TextSpan(text: '${entry.value}'),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Deny'),
                  onPressed: () {
                    ctx.approvals.deny(approval.id);
                    ctx.log.add(
                      'approvals',
                      'Denied ${approval.command}.',
                    );
                  },
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Allow'),
                  onPressed: () {
                    ctx.approvals.approve(approval.id);
                    ctx.log.add(
                      'approvals',
                      'Approved ${approval.command}.',
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
