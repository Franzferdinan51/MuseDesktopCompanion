// In-memory diagnostics log for the Activity view.
//
// The gadget service logger, connection-state changes, and received remote
// commands all write here. The Activity view subscribes to [stream] and
// auto-scrolls as lines arrive. Ring buffer: old lines fall off the top.

import 'dart:async';

/// One timestamped diagnostics line.
class LogLine {
  const LogLine(this.time, this.tag, this.message);

  final DateTime time;
  final String tag;
  final String message;
}

/// Bounded in-memory log with a broadcast stream for live views.
class LogBuffer {
  LogBuffer({this.capacity = 500});

  final int capacity;
  final List<LogLine> _lines = <LogLine>[];
  final StreamController<void> _controller =
      StreamController<void>.broadcast();

  /// Fires whenever lines are added or cleared.
  Stream<void> get stream => _controller.stream;

  List<LogLine> get lines => List.unmodifiable(_lines);

  void add(String tag, String message) {
    _lines.add(LogLine(DateTime.now(), tag, message));
    if (_lines.length > capacity) {
      _lines.removeRange(0, _lines.length - capacity);
    }
    if (!_controller.isClosed) _controller.add(null);
  }

  void clear() {
    _lines.clear();
    if (!_controller.isClosed) _controller.add(null);
  }

  void close() {
    if (!_controller.isClosed) _controller.close();
  }
}
