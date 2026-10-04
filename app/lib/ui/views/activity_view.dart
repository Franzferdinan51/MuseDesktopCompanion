// Activity view: diagnostics log — connection events, remote commands,
// and gadget service logs. Newest at the bottom, auto-scrolls.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/log_buffer.dart';
import '../app_shell.dart';

class ActivityView extends StatefulWidget {
  const ActivityView({super.key, required this.ctx});

  final DashboardContext ctx;

  @override
  State<ActivityView> createState() => _ActivityViewState();
}

class _ActivityViewState extends State<ActivityView> {
  final ScrollController _scroll = ScrollController();
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.ctx.log.stream.listen((_) {
      if (mounted) {
        setState(() {});
        _scrollToBottom();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.ctx.log.lines;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Diagnostics log',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Clear'),
                onPressed: () => widget.ctx.log.clear(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Card(
              child: lines.isEmpty
                  ? Center(
                      child: Text(
                        'No activity yet.',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(12),
                      itemCount: lines.length,
                      itemBuilder: (context, i) {
                        final line = lines[i];
                        return _LogRow(line: line);
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.line});

  final LogLine line;

  Color _tagColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (line.tag) {
      'link' => Colors.green,
      'command' => scheme.primary,
      'pairing' => Colors.orange,
      'chat' => Colors.purple,
      'error' => scheme.error,
      _ => Colors.grey,
    };
  }

  @override
  Widget build(BuildContext context) {
    final time = line.time;
    final stamp =
        '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: SelectableText.rich(
        TextSpan(
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontFamilyFallback: const ['Menlo', 'Consolas', 'monospace'],
              ),
          children: [
            TextSpan(
              text: '$stamp ',
              style: const TextStyle(color: Colors.grey),
            ),
            TextSpan(
              text: '[${line.tag}] ',
              style: TextStyle(
                color: _tagColor(context),
                fontWeight: FontWeight.bold,
              ),
            ),
            TextSpan(text: line.message),
          ],
        ),
      ),
    );
  }
}
