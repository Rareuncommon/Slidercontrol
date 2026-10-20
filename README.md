# Slidercontrol

Flutter BLE control for an edelkrone **SliderPLUS v6** and **HeadONE**, on
Android, iOS and macOS.

The app is built on **edelkrone's own SDK** (`edelkrone` 0.1.0 on PyPI, MIT),
ported to Dart in `lib/sdk/`. The earlier reverse-engineered client
(`lib/ek_protocol.dart`, `EDELKRONE_PROTOCOL.md`) is kept in the repository,
untouched, as the capture record — the app no longer uses it.

## Safety

A motor is attached to a camera.

- **Take the camera off the rig before testing anything that moves.**
- **The app sends a stop before it disconnects, and whenever it is
  backgrounded, hidden or closed.** The SDK's stop goes to the front of the
  command queue, ahead of any polling, and never throws.
- **STOP ALL** on the control page and **Escape** on any screen stop
  everything, through `StopRegistry`: the joystick, a recall, and the device's
  own loop.
- **Nothing is homed.** The head has no end stops and is never driven to find
  one. The slider references itself after power-on; the app never drives it
  into its stops on purpose. The old homing code is gone.
- **Pose recalls, not streamed velocity, for anything unattended.** The
  ping-pong loop with no dwell is the device's own loop: one command the head
  runs until stopped, so nothing depends on the app between legs. Jogging is
  hold-to-move only, and the device stops by itself 1.5 s after the last
  joystick command.
- **Refuses to move with an unlearnt focus motor.** If the head reports a
  focus module whose lens has not been learnt, motion commands are refused, as
  the SDK does. Learn the lens in the edelkrone app first.

## Why a Dart port, and not the SDK itself

The SDK is Python (≥ 3.11, over `bleak`) and runs on macOS, Windows and Linux.
It cannot run inside an iOS or Android app. So the parts this app needs are
ported:

| Layer | How it was ported | How it is checked |
|---|---|---|
| Protocol codecs (`lib/sdk/protocol/generated/`) | Mechanically, by `tool/sdk_port/py2dart.py`. The SDK's codecs are themselves a transliteration of the official app's Dart library, so they go back to Dart cleanly. The transpiler refuses any construct it does not understand rather than guessing. | `test/sdk/codec_vectors_test.dart`: 5,808 calls across 121 functions, recorded by running the real Python SDK, replayed in order. Every byte written, every field parsed, every return value and every throw must agree exactly. |
| Device table (`lib/sdk/devices/models.dart`) | Generated from the SDK's model definitions by `gen_models.py`. | Part of the session vectors. |
| Session, devices, motion, API (`lib/sdk/session`, `devices/registry.dart`, `motion`, `api`) | By hand, following the SDK's structure and names. | `test/sdk/session_vectors_test.dart`: every command encoding, 898 layout decisions, 300 rig groupings and 600 status frames against the Python SDK. `test/sdk/session_behaviour_test.dart`: queue priority, stop order, joins, poses and loops against a simulated HeadONE + slider. |
| Transport (`lib/sdk/transport/`) | New: `FlutterBlueTransport` implements the SDK's transport interface over flutter_blue_plus. Recognition goes through the same `DeviceBook` as the SDK's desktop transport. | — (radio) |

The vector tests were checked by deliberately breaking the port (a wrong scale
factor, a shifted byte offset, the wrong channel, the wrong tilt rule) and
confirming each break fails them.

Only the HeadONE and slider families are drivable; that is all this app uses.
Numeric drive-to-coordinate is not ported, because SDK 0.1 does not offer it.

### What about the edelkrone MCP?

edelkrone's MCP server (`https://connect.edelkrone.com/mcp`) is a connector for
Claude and ChatGPT that answers questions about the SDK and your account. It
does not drive hardware and the app does not talk to it. To use it from
claude.ai, add it under **Settings → Connectors**.

## How the app works

1. **Scan.** Units are grouped into rigs the way the SDK groups them.
2. **Join.** Pick the HeadONE and tick the slider. The app forms a wireless
   layout, as the official app does: the head keeps its group, takes the
   layout configuration, adds the slider as a peer, and the app adopts the
   setup the head then reports. An upright head becomes PAN_AND_SLIDE; a tilted
   one TILT_AND_SLIDE. To undo a layout, power the units off and on.
3. **Control.** One non-scrolling page, portrait or landscape: live positions,
   a jog pad per axis, twelve pose tiles, speed / acceleration / jog sliders,
   loop and STOP ALL. The SDK log is one tap away.

**The head and slider start and stop together because the device does it.**
In a joined layout, the head stores both axes in each pose and plans every
recall so all axes arrive at the same moment. There is no host-side timing,
streaming or speed solving any more; that is why the synchronised-move code,
the head-timing settings and homing are gone.

Things to know before shooting:

- A recall moves the head **through every pose stored between** the current
  slot and the target. An empty slot in between stops it, so the app warns
  before leaving a gap.
- **Poses live on the head and are deleted when the layout dissolves.**
- Arrival is verified against the reported position (0.25° / 0.25 cm).
- Pose names are stored in the app per rig; the poses themselves are on the
  device.

## Where the spec and the SDK disagree

The captures were right about the wire: framing (`[len][opcode][payload][sum16]`),
the GATT UUIDs and write-with-response all match the SDK. These are the places
where the conclusions drawn from them were not:

- **The HeadONE does report its position** (§5). The status frame carries none,
  as captured, but a separate numeric readout (opcode 83, index 255) gives pan,
  tilt and slide.
- **The "unused" second characteristic pair is the IO-control channel.** It
  carries the layout join (group id, peer add).
- **Coordinated moves** (§8) are the layout join plus ordinary keyposes.
- **Streamed velocity does not run indefinitely** (§7): the device stops 1.5 s
  after the last joystick command.
- **Speed and acceleration** (§7b) are not a "period pair". A keypose move
  (opcode 7) carries start slot (255 = current), target slot, loop flag,
  acceleration-in and acceleration-out as u16 × 32000, speed as u32 ×
  1000 × 32000, and a fixed duration in ms where −1 means "use the speed".
  That −1000 is the `FF FF FC 18` at the end of the captured head frame. Reading
  the acceleration bytes as part of a speed period is the likely reason the old
  acceleration slider did nothing.

## Tests

```
flutter pub get
dart test                 # SDK port, controller, stop registry, old protocol
flutter test test_widget  # control page at six phone, tablet and desktop sizes
```

No hardware needed. To regenerate after an SDK update, install the SDK in a
virtualenv and, with `G` pointing at its `edelkrone/protocol/_generated/`:

```
python3 -I tool/sdk_port/py2dart.py lib/sdk/protocol/generated <sdk-version> \
  $G/moco.py $G/head_module_util.py $G/slide_module_util.py $G/head_module.py $G/slide_module.py
python3 -I tool/sdk_port/gen_models.py
python3 -I tool/sdk_port/gen_vectors.py $G
python3 -I tool/sdk_port/gen_session_vectors.py
```

## Layout

| Path | What it is |
|---|---|
| `lib/sdk/` | The Dart port of the edelkrone SDK (see above). |
| `lib/app/rig_controller.dart` | App state: scan, join, jog, poses, loop, stop. Pure Dart, tested against the simulated rig. |
| `lib/app/flutter_support.dart` | Pose-name persistence and the in-app log buffer. |
| `lib/app/permissions.dart` | Runtime Bluetooth permission. |
| `lib/control/stop_registry.dart` | Every way to stop everything. |
| `lib/main.dart` | Scan page, join sheet, lifecycle stop. |
| `lib/ui/rig_page.dart` | The control page. |
| `lib/ui/jog_pad.dart`, `emergency_stop.dart`, `ui_scale.dart` | Shared widgets. |
| `lib/ek_protocol.dart`, `EDELKRONE_PROTOCOL.md` | The reverse-engineered client and spec. Kept as the record; unused. |
| `tool/sdk_port/` | Transpiler and vector generators. |

## Platform notes

- **Android** — `BLUETOOTH_SCAN` / `BLUETOOTH_CONNECT`, plus legacy permissions
  and location below API 31, requested at runtime.
- **macOS** — the Bluetooth entitlement must be in both `DebugProfile` and
  `Release` entitlements, and `NSBluetoothAlwaysUsageDescription` in
  `Info.plist`.
- **iOS** — `NSBluetoothAlwaysUsageDescription` in `Info.plist`.
- macOS and iOS need full Xcode and CocoaPods.

## Licences

- `lib/sdk/` is derived from the edelkrone SDK, MIT licensed; see
  `lib/sdk/LICENSE`.
- `flutter_blue_plus` 2.x requires declaring a licence on connect. This project
  declares `License.nonprofit` (personal and educational use). Commercial
  distribution needs a paid licence.
