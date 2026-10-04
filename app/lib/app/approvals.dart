// Approvals queue: user confirmation gate for sensitive Muse commands.
//
// Commands that reach the desktop gadget through `device.invoke` are
// executed by [_runCommand] in main.dart. Anything matching
// [requiresApproval] is queued here instead of running immediately; the
// Approvals view shows each pending request with Allow / Deny buttons.
// Approved commands run right away; denied ones return an error to Muse.

import 'dart:async';

/// One command waiting for the user to allow or deny it.
class PendingApproval {
  PendingApproval({
    required this.id,
    required this.command,
    required this.params,
    required this.requestedAt,
  });

  final String id;
  final String command;
  final Map<String, Object?> params;
  final DateTime requestedAt;
}

/// Queue of commands awaiting user confirmation.
///
/// [request] suspends the invoke handler until the user decides. Call from
/// the UI thread side via [approve]/[deny].
class ApprovalQueue {
  final List<PendingApproval> _pending = <PendingApproval>[];
  final Map<String, Completer<bool>> _completers = <String, Completer<bool>>{};
  final StreamController<void> _changes = StreamController<void>.broadcast();
  int _nextId = 1;

  /// Fires whenever the pending list changes.
  Stream<void> get changes => _changes.stream;

  /// Snapshot of currently pending approvals, oldest first.
  List<PendingApproval> get pending => List.unmodifiable(_pending);

  int get pendingCount => _pending.length;

  /// Whether [command] needs user confirmation before it may run.
  ///
  /// Currently: anything under `device.*` (hardware-adjacent) and
  /// `display.draw_url` (fetches a remote URL).
  static bool requiresApproval(String command) {
    return command.startsWith('device.') || command == 'display.draw_url';
  }

  /// Queue [command] and wait for the user. Returns true when approved.
  Future<bool> request(
    String command,
    Map<String, Object?> params,
  ) {
    final approval = PendingApproval(
      id: 'approval-${_nextId++}',
      command: command,
      params: Map<String, Object?>.unmodifiable(params),
      requestedAt: DateTime.now(),
    );
    final completer = Completer<bool>();
    _pending.add(approval);
    _completers[approval.id] = completer;
    _emit();
    return completer.future;
  }

  /// Approve a pending request; its invoke handler resumes and runs.
  void approve(String id) => _decide(id, true);

  /// Deny a pending request; its invoke handler returns an error to Muse.
  void deny(String id) => _decide(id, false);

  /// Deny everything still pending (e.g. on unpair or shutdown).
  void denyAll() {
    for (final approval in List<PendingApproval>.from(_pending)) {
      _decide(approval.id, false);
    }
  }

  void _decide(String id, bool approved) {
    final completer = _completers.remove(id);
    _pending.removeWhere((approval) => approval.id == id);
    if (completer != null && !completer.isCompleted) {
      completer.complete(approved);
    }
    _emit();
  }

  void _emit() {
    if (!_changes.isClosed) _changes.add(null);
  }

  void close() {
    denyAll();
    if (!_changes.isClosed) _changes.close();
  }
}
