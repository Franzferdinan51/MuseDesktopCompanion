// Window bounds persistence: default size, minimum size, and remembering
// the window position/size across restarts via shared_preferences.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

/// Default and minimum window sizes for the dashboard.
const Size kDefaultWindowSize = Size(1200, 800);
const Size kMinimumWindowSize = Size(900, 600);

const String _kWidth = 'window_width';
const String _kHeight = 'window_height';
const String _kX = 'window_x';
const String _kY = 'window_y';

/// Call once in main(), before runApp().
Future<void> initWindowBounds() async {
  await windowManager.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await windowManager.setMinimumSize(kMinimumWindowSize);
  final width = prefs.getDouble(_kWidth) ?? kDefaultWindowSize.width;
  final height = prefs.getDouble(_kHeight) ?? kDefaultWindowSize.height;
  await windowManager.setSize(Size(width, height));
  final x = prefs.getDouble(_kX);
  final y = prefs.getDouble(_kY);
  if (x != null && y != null) {
    await windowManager.setPosition(Offset(x, y));
  }
}

/// Listens for window move/resize and persists the bounds (debounced).
class WindowBoundsSaver with WindowListener {
  WindowBoundsSaver();

  Timer? _debounce;

  void attach() {
    windowManager.addListener(this);
  }

  void detach() {
    _debounce?.cancel();
    windowManager.removeListener(this);
  }

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _save);
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bounds = await windowManager.getBounds();
      await prefs.setDouble(_kWidth, bounds.width);
      await prefs.setDouble(_kHeight, bounds.height);
      await prefs.setDouble(_kX, bounds.left);
      await prefs.setDouble(_kY, bounds.top);
    } catch (_) {
      // Bounds persistence is best-effort; never break the app over it.
    }
  }

  @override
  void onWindowResized() => _scheduleSave();

  @override
  void onWindowMoved() => _scheduleSave();
}
