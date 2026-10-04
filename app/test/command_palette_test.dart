// Tests for the command palette filter.

import 'package:flutter_test/flutter_test.dart';
import 'package:muse_desktop_companion/ui/command_palette.dart';

void main() {
  List<PaletteCommand> commands() => [
    PaletteCommand(
      label: 'Go to Dashboard',
      hint: 'Switch to the Dashboard view',
      keywords: 'navigate view home',
      action: () {},
    ),
    PaletteCommand(
      label: 'Go to Chat',
      hint: 'Switch to the Chat view',
      keywords: 'navigate view messages',
      action: () {},
    ),
    PaletteCommand(
      label: 'Reconnect',
      hint: 'Reconnect to the Muse',
      keywords: 'link refresh',
      action: () {},
    ),
  ];

  test('empty query returns everything', () {
    final all = commands();
    expect(filterPaletteCommands(all, ''), hasLength(3));
    expect(filterPaletteCommands(all, '   '), hasLength(3));
  });

  test('matches label case-insensitively', () {
    final result = filterPaletteCommands(commands(), 'CHAT');
    expect(result, hasLength(1));
    expect(result.single.label, 'Go to Chat');
  });

  test('matches keywords', () {
    final result = filterPaletteCommands(commands(), 'navigate');
    expect(result, hasLength(2));
  });

  test('no match returns empty', () {
    expect(filterPaletteCommands(commands(), 'zzz'), isEmpty);
  });
}
