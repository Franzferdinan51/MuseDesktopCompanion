// Desktop command set for the Muse Desktop Companion.
//
// A subset of the phone companion's commands: avatar display, status
// captions, and health. Phone-only commands (camera, calls, SMS,
// flashlight, notifications) are not registered — Muse sees only what
// this device can actually do.

import 'dart:io';
import 'dart:typed_data';

import 'package:battery_plus/battery_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;

import '../src/gadget/commands.dart' show maxStatusChars;
import 'version.dart';

/// Command specs advertised in `link.register`, sized for the desktop.
Map<String, Object?> desktopCommandSpecs() {
  Map<String, Object?> stringParam(String description) => {
    'type': 'string',
    'description': description,
  };

  return {
    'display.draw_url': {
      'description':
          'Download an image and draw it as the companion avatar on the '
          'desktop dashboard. Takes an http:// or https:// URL of a JPEG, '
          'PNG, WebP or GIF. The dashboard cover-crops a square around the '
          'subject and animates idle, listening, thinking, and speaking. '
          'Prefer a sharp picture of your own Muse. The character stays '
          'visible until replaced or cleared with display.show_animation.',
      'required': {'url': stringParam('http:// or https:// URL of the image.')},
      'optional': <String, Object?>{},
    },
    'display.show_animation': {
      'description':
          'Clear the character image and bring back the neutral placeholder. '
          'The caption is kept.',
      'required': <String, Object?>{},
      'optional': <String, Object?>{},
    },
    'companion.set_status': {
      'description':
          'Update the caption below the character. The character remains '
          'visible. Send meaningful updates when your activity changes; keep '
          'them short (one or two lines). Up to $maxStatusChars characters.',
      'required': {
        'text': stringParam(
          'Current activity or status, up to $maxStatusChars characters.',
        ),
      },
      'optional': <String, Object?>{},
    },
    'pocket.set_status': {
      'description': 'Compatibility alias of companion.set_status.',
      'required': {
        'text': stringParam('Current activity or status.'),
      },
      'optional': <String, Object?>{},
    },
    'companion.set_display': {
      'description':
          'Adjust the companion display preferences. All parameters are '
          'optional and applied together; omitted ones are left unchanged.',
      'required': <String, Object?>{},
      'optional': {
        'theme': stringParam('Color theme: "light", "dark" or "system".'),
      },
    },
    'device.health': {
      'description':
          'Report companion health: battery level (percent), whether it is '
          'charging, device model, OS version and app version.',
      'required': <String, Object?>{},
      'optional': <String, Object?>{},
    },
  };
}

/// Download character image bytes from a URL. Returns null on failure.
Future<Uint8List?> downloadCharacterBytes(String url) async {
  try {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    final response = await http
        .get(uri, headers: {'User-Agent': 'muse-desktop-companion/$kAppVersion'})
        .timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) return null;
    if (response.bodyBytes.isEmpty) return null;
    return response.bodyBytes;
  } catch (_) {
    return null;
  }
}

/// Real desktop device health for `device.health`.
///
/// Battery level/charging come from battery_plus (null on desktops without
/// a battery or when the query fails). Model and OS version come from
/// device_info_plus, with Platform.operatingSystem as the fallback.
Future<Map<String, Object?>> desktopDeviceHealth(String appVersion) async {
  int? batteryLevel;
  bool? charging;
  try {
    final battery = Battery();
    batteryLevel = await battery.batteryLevel;
    final state = await battery.batteryState;
    charging =
        state == BatteryState.charging || state == BatteryState.full;
  } catch (_) {
    // No battery or query failed — leave the fields null.
  }

  var model = 'Desktop';
  var os = Platform.operatingSystem;
  var osVersion = '';
  try {
    final info = DeviceInfoPlugin();
    if (Platform.isMacOS) {
      final mac = await info.macOsInfo;
      if (mac.model.isNotEmpty) model = mac.model;
      os = 'macOS';
      osVersion = mac.osRelease;
    } else if (Platform.isWindows) {
      final win = await info.windowsInfo;
      if (win.productName.isNotEmpty) model = win.productName;
      os = 'Windows';
      osVersion = win.displayVersion;
    } else if (Platform.isLinux) {
      final linux = await info.linuxInfo;
      if (linux.prettyName.isNotEmpty) model = linux.prettyName;
      os = 'Linux';
      osVersion = linux.version ?? '';
    }
  } catch (_) {
    // Keep the fallbacks.
  }

  return {
    'ok': true,
    'battery_level': batteryLevel,
    'charging': charging,
    'model': model,
    'os': os,
    'os_version': osVersion,
    'app_version': appVersion,
  };
}
