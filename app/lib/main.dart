// Muse Desktop Companion — entry point.
//
// A desktop dashboard for the Muse companion: the pixel avatar front and
// center, chat panel, status area, and connection info — mission control
// for talking to your Muse, not a phone UI clone.
//
// Startup is bulletproof by design: runApp() fires immediately with a
// loading shell, async initialization happens inside it, and any failure
// shows an error screen with retry — never a black window.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app/captions.dart';
import 'app/chat.dart';
import 'app/desktop_commands.dart';
import 'app/log_buffer.dart';
import 'app/model.dart';
import 'app/avatar_motion.dart';
import 'app/storage.dart';
import 'app/version.dart';
import 'app/window_bounds.dart';
import 'src/gadget/chat_events.dart';
import 'src/gadget/service.dart';
import 'ui/app_shell.dart';
import 'ui/muse_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initWindowBounds();
  runApp(const _BootstrapApp());
}

/// Shows loading, then the dashboard, then an error screen on failure.
/// Nothing in the init path can leave the window black.
class _BootstrapApp extends StatefulWidget {
  const _BootstrapApp();

  @override
  State<_BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<_BootstrapApp> {
  _InitState _state = _InitState.loading;
  String _error = '';
  DashboardContext? _ctx;
  StreamSubscription<void>? _presentationSub;
  final WindowBoundsSaver _boundsSaver = WindowBoundsSaver();

  @override
  void initState() {
    super.initState();
    _boundsSaver.attach();
    _init();
  }

  Future<void> _init() async {
    try {
      final ctx = await _buildContext();
      if (!mounted) {
        ctx.dispose();
        return;
      }
      // Rebuild the MaterialApp when presentation settings change so the
      // theme toggle takes effect immediately.
      _presentationSub = ctx.presentation.stream.listen((_) {
        if (mounted) setState(() {});
      });
      setState(() {
        _ctx = ctx;
        _state = _InitState.ready;
      });
    } catch (e) {
      debugPrint('[muse] startup failed: $e');
      if (!mounted) return;
      setState(() {
        _state = _InitState.error;
        _error = e.toString();
      });
    }
  }

  Future<DashboardContext> _buildContext() async {
    final storage = const FlutterSecureStorage();
    final identity = await PersistentIdentity.loadOrCreate(storage);
    final settings = await SettingsStore.init();
    final presentation = PresentationState(
      settings: settings.loadSettings(),
    );
    final savedStatus = settings.loadStatus();
    if (savedStatus.isNotEmpty) {
      presentation.applyStatus(savedStatus);
    }

    final pairingStore = SecurePairingStore(storage);
    final sdkTokens = SecureSdkTokenStore(storage);
    final savedSdkToken = await sdkTokens.load();
    final log = LogBuffer();

    // Desktop command set: avatar, status, and chat. Phone-only commands
    // (camera, calls, SMS, flashlight) are not registered here.
    final service = GadgetService(
      identity: identity.identity,
      commands: desktopCommandSpecs(),
      runCommand: _runCommand,
      pairingStore: pairingStore,
      version: kAppVersion,
      sdkToken: savedSdkToken?.isEmpty == true ? null : savedSdkToken,
      displayName: 'Muse Desktop',
      logger: (message) {
        debugPrint('[muse] $message');
        log.add('service', message);
      },
      introSent: settings.loadIntroSent(),
      persistIntro: settings.saveIntroSent,
      onCharacterUrl: (url) async {
        if (url.isNotEmpty) {
          log.add('avatar', 'Server pushed character URL.');
          await _drawChatCharacter(presentation, url);
        }
      },
    );

    service.onStateChanged.listen((state) {
      log.add('link', 'Link state: ${state.name}');
    });

    final chat = ChatHistory();
    service.onChatEvent.listen((event) {
      chat.applyServerEvent(event.event, event.payload);
    });
    chat.onCaption = (text) {
      final caption = captionFromReply(text);
      if (caption.isNotEmpty) presentation.applyStatus(caption);
      if (captionSetsThinking(
        streaming: chat.assistantStreaming,
        pose: presentation.pose,
      )) {
        presentation.applyPose(AvatarPose.thinking);
      }
    };
    chat.onActivity = (code) {
      final line = activityCaption(code);
      if (line != null) presentation.applyStatus(line);
      if (activitySetsPose(code, streaming: chat.assistantStreaming)) {
        presentation.applyPose(poseForActivity(code));
      }
    };
    chat.onAssistantDone = (text) {
      final image = httpsImageUrlInReply(text);
      if (image != null) {
        unawaited(_drawChatCharacter(presentation, image));
      }
      final caption = captionFromReply(text);
      if (caption.isNotEmpty) {
        presentation.applyStatus(caption);
        unawaited(settings.saveStatus(caption));
      }
      presentation.applyPose(AvatarPose.idle);
    };

    service.start();
    log.add('link', 'Service started.');
    return DashboardContext(
      service: service,
      presentation: presentation,
      settings: settings,
      chat: chat,
      sdkTokens: sdkTokens,
      pairingStore: pairingStore,
      log: log,
    );
  }

  /// Desktop command implementations. The avatar and status commands drive
  /// the presentation state; everything else reports unsupported.
  Future<Map<String, Object?>> _runCommand(
    String command,
    Map<String, Object?> params,
    int? timeoutMs,
  ) async {
    final ctx = _ctx;
    ctx?.log.add('command', '$command ${params.keys.join(',')}');
    switch (command) {
      case 'companion.set_status':
      case 'pocket.set_status':
        final text = params['text'];
        if (text is String && ctx != null) {
          ctx.presentation.applyStatus(text);
          unawaited(ctx.settings.saveStatus(text));
        }
        return {'ok': true};
      case 'display.draw_url':
        final url = params['url'];
        if (url is String && ctx != null) {
          final result = await downloadCharacterBytes(url);
          if (result != null) {
            ctx.presentation.applyCharacter(result);
            ctx.log.add('avatar', 'Avatar drawn from URL.');
            return {'ok': true};
          }
          return {'ok': false, 'error': 'download failed'};
        }
        return {'ok': false, 'error': 'missing url'};
      case 'display.show_animation':
        ctx?.presentation.applyPlaceholder();
        return {'ok': true};
      case 'companion.set_display':
        final theme = params['theme'];
        if (theme is String &&
            CompanionSettings.themeOptions.contains(theme) &&
            ctx != null) {
          final updated =
              ctx.presentation.settings.copyWith(theme: theme);
          ctx.presentation.applySettings(updated);
          unawaited(ctx.settings.saveSettings(updated));
          ctx.log.add('settings', 'Theme set to $theme by Muse.');
        }
        return {'ok': true};
      case 'device.health':
        return desktopDeviceHealth(kAppVersion);
      default:
        return {'ok': false, 'error': 'unsupported on desktop'};
    }
  }

  ThemeMode _themeMode() {
    return switch (_ctx?.presentation.settings.theme) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  @override
  void dispose() {
    _presentationSub?.cancel();
    _boundsSaver.detach();
    _ctx?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Muse Companion',
      debugShowCheckedModeBanner: false,
      theme: museTheme(Brightness.light),
      darkTheme: museTheme(Brightness.dark),
      themeMode: _themeMode(),
      home: switch (_state) {
        _InitState.loading => const _LoadingScreen(),
        _InitState.error => _ErrorScreen(
            error: _error,
            onRetry: () {
              setState(() {
                _state = _InitState.loading;
                _error = '';
              });
              _init();
            },
          ),
        _InitState.ready => AppShell(ctx: _ctx!),
      },
    );
  }
}

enum _InitState { loading, ready, error }

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Starting Muse Companion…'),
          ],
        ),
      ),
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                'Muse Companion could not start',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(error, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      ),
    );
  }
}

/// Draw a portrait Muse linked in a finished chat reply.
Future<void> _drawChatCharacter(
  PresentationState presentation,
  String url,
) async {
  try {
    final bytes = await downloadCharacterBytes(url);
    if (bytes != null) {
      presentation.applyCharacter(bytes);
      debugPrint('[muse] chat character drawn');
    }
  } catch (e) {
    debugPrint('[muse] chat character was not drawn: $e');
  }
}
