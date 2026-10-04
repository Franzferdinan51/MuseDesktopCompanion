// Command palette: Cmd+K / Ctrl+K quick actions.
//
// Overlay dialog with a filter field and a flat list of commands:
// view navigation plus common actions (Reconnect, Unpair, Clear chat,
// Toggle theme). Filtering is a case-insensitive substring match over
// the label and keywords.

import 'package:flutter/material.dart';

/// One entry in the palette.
class PaletteCommand {
  const PaletteCommand({
    required this.label,
    required this.hint,
    this.keywords = '',
    required this.action,
  });

  final String label;
  final String hint;
  final String keywords;
  final VoidCallback action;
}

/// Case-insensitive substring match over label + keywords.
List<PaletteCommand> filterPaletteCommands(
  List<PaletteCommand> commands,
  String query,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return List<PaletteCommand>.from(commands);
  return commands.where((command) {
    final haystack = '${command.label} ${command.keywords}'.toLowerCase();
    return haystack.contains(q);
  }).toList();
}

/// Show the palette dialog. Call [onNavigate]/actions are wired by the
/// caller through the [commands] list.
Future<void> showCommandPalette(
  BuildContext context,
  List<PaletteCommand> commands,
) {
  return showDialog<void>(
    context: context,
    builder: (context) => _CommandPaletteDialog(commands: commands),
  );
}

class _CommandPaletteDialog extends StatefulWidget {
  const _CommandPaletteDialog({required this.commands});

  final List<PaletteCommand> commands;

  @override
  State<_CommandPaletteDialog> createState() => _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends State<_CommandPaletteDialog> {
  final TextEditingController _filter = TextEditingController();
  int _selected = 0;

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  void _run(PaletteCommand command) {
    Navigator.of(context).pop();
    command.action();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = filterPaletteCommands(widget.commands, _filter.text);
    if (_selected >= filtered.length) _selected = 0;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _filter,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Type a command…',
                  prefixIcon: Icon(Icons.search, size: 18),
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                onChanged: (_) => setState(() => _selected = 0),
                onSubmitted: (_) {
                  if (filtered.isNotEmpty) _run(filtered[_selected]);
                },
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: filtered.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No matching commands.'),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final command = filtered[i];
                        final selected = i == _selected;
                        return ListTile(
                          dense: true,
                          selected: selected,
                          selectedTileColor: Theme.of(
                            context,
                          ).colorScheme.primaryContainer.withValues(alpha: 0.4),
                          title: Text(command.label),
                          subtitle: Text(command.hint),
                          onTap: () => _run(command),
                          onFocusChange: (focused) {
                            if (focused) setState(() => _selected = i);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
