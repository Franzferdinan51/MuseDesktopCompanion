# Muse Desktop Companion

A desktop dashboard for your Muse — the pixel avatar front and center, a
full chat panel beside it, and the link status always visible. Mission
control for talking to your Muse, not a phone UI clone.

Built with Flutter. Targets macOS primarily; Windows and Linux follow
from the same codebase.

## What it does

- **Pixel avatar** — the 2D Waveshare-style avatar renderer ported from
  the Android companion: 64×64 hard-pixel stage with idle, listening,
  thinking, speaking, error, boot, and off poses, plus blinking, gaze
  wandering, and per-mode color schemes.
- **Chat** — send and receive text with your Muse. Replies stream into
  the chat panel; captions appear under the avatar.
- **Link** — the full Muse gadget protocol: P-256 identity, Noise XX
  handshake, WebSocket link to your leased VM. Pair by pasting a device
  token; the app handles VM lookup, registration, and reconnects.
- **Dashboard** — avatar card, status card (link state, agent, version),
  and quick actions (reconnect, clear avatar, pair/unpair) in one window.

Phone-only features (camera, calls, SMS, flashlight, BLE peripheral)
are intentionally not included — Muse only sees commands this device
can actually run.

## Pairing

The desktop app cannot do BLE provisioning like the phone app. Instead:

1. Open the app — it shows "Not paired".
2. Click the link icon in the top bar.
3. Paste your Muse device token (from the Muse developer settings or
   copied from another paired device).
4. The app saves the pairing, fetches your VMs, and connects.

To unpair, click the unlink icon. The identity key is kept; only the
pairing is removed.

## Project layout

```
app/lib/
  main.dart              Bulletproof startup: loading shell first, then
                         the dashboard; errors show a retry screen.
  app/
    avatar_life.dart     Avatar life-cycle (blink/gaze/palette clocks).
    avatar_motion.dart   Pose motion curves (bob, lean, rings…).
    captions.dart        Caption derivation from chat replies.
    chat.dart            Chat history state.
    desktop_commands.dart  Command specs advertised to the Muse.
    model.dart           PresentationState: everything the UI renders.
    pixel_avatar.dart    Pixel-stage math (grid, accents, labels).
    storage.dart         Secure identity/pairing/token storage.
  src/gadget/            The Muse gadget protocol stack, shared with
                         the Android companion (identity, Noise XX,
                         link client, pairing, service…).
  ui/
    dashboard_screen.dart  The mission-control layout.
    muse_theme.dart        Muse color theme.
    pixel_stage.dart       The animated avatar widget.
```

## Building

```sh
cd app
flutter pub get
flutter analyze   # must be clean
flutter test      # must pass
flutter run -d macos
```

To build a release `.app`:

```sh
flutter build macos --release
```

The output lands in `build/macos/Build/Products/Release/`.

## Status

Early but working: the dashboard renders, the avatar animates, chat
flows through the link once paired. The black-screen startup bug is
fixed by construction — `runApp()` fires immediately and every failure
mode shows a real screen.
