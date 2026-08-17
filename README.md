# Slidercontrol

Flutter BLE control for an edelkrone **SliderPLUS v6** and **HeadONE**, on
Android, iOS and macOS.

There is no public SDK for these devices. The protocol was reverse-engineered by
capturing the official app with PacketLogger; `EDELKRONE_PROTOCOL.md` is the
specification of record and `lib/ek_protocol.dart` is a byte-for-byte verified
implementation of it. **Section 8 of the spec lists what is still undecoded — if
something appears to be missing, it is genuinely missing, not an oversight.**

## Safety

A motor is attached to a camera. These are not theoretical.

- **Take the camera off the rig before testing anything that moves.**
- **The app always sends a stop before it disconnects or is backgrounded.** If a
  client dies mid-move the device keeps executing and holds torque, leaving the
  carriage locked and immovable by hand.
- **Never home the head.** It has no end stops. `Homing` refuses a head target
  at every entry point.
- **Homing drives the slider into its mechanical stops on purpose.** It is
  always an explicit, confirmed action behind a camera-off warning, with live
  progress and an abort — never something that happens quietly on connect. Each
  pass is bounded three ways: stall detection, a travel budget, and a timeout,
  and it aborts the moment the link drops.
- Stall detection uses **net progress over a ~0.5 s window**, not per-tick
  deltas — against a hard stop the encoder dithers by hundreds of counts — and a
  suspected stop is confirmed by backing off and re-approaching, because the
  SliderPLUS's mid-rail mechanism transition imitates an end stop (§7).
- **The slider has no soft limits.** It will drive into its mechanical stops and
  grind indefinitely.
- Unattended motion uses pose recalls, never streamed velocity. A recall is one
  command the device finishes on its own, so a dropped link ends stopped.
  Streamed velocity keeps running if the host vanishes — which is why jogging is
  hold-to-move only.
- **Escape stops everything, from any screen.** So does STOP ALL on the device
  list, and both go through `StopRegistry`, which tears down the ping-pong loop
  as well as writing the stop. Halting the motor while the loop still runs only
  pauses it — the next leg would start it again.
- Auto-reconnect restores the link and the keepalive after an unexpected drop.
  It never resumes motion. That is a safety improvement rather than a risk: a
  device that loses its link mid-recall keeps going, and until the link is back
  there is no way to send it a stop at all.

## Layout

| Path | What it is |
|---|---|
| `lib/ek_protocol.dart` | Framing, opcodes, telemetry, position unwrapping. Pure Dart. **Ground truth — do not edit.** |
| `lib/ble/ek_names.dart` | Advertised-name recognition. Pure. |
| `lib/ble/ek_snapshot.dart` | Device state and the `EkMotionTarget` interface. Pure. |
| `lib/ble/ek_scanner.dart` | Scanning, matched on advertised name. |
| `lib/ble/ek_connection.dart` | One connection: discovery, 250 ms keepalive, serialised writes, telemetry. |
| `lib/control/motion_settings.dart` | Speed/acceleration percentages → wire values. |
| `lib/control/panel_settings.dart` | Panel settings, clamped. Pure. |
| `lib/control/stop_registry.dart` | Every way to stop everything. Pure. |
| `lib/control/jog.dart` | Streamed velocity while held. |
| `lib/control/leg_supervisor.dart` | One leg of motion, supervised. Pure. Shared. |
| `lib/control/ping_pong.dart` | Host-supervised loop between two poses. |
| `lib/control/fleet.dart` | Several devices moving together. Pure. |
| `lib/control/homing.dart` | Homing, stall detection, closed-loop moves. Pure. |
| `lib/control/move_timing.dart` | Solving each axis's speed for a shared duration. Pure. |
| `lib/control/pose_store.dart` | Keypose slots and their persistence. Pure. |
| `lib/control/keypose_controller.dart` | Keyposes across every device. |
| `lib/ui/control_page.dart` | The single, non-scrolling control page. |
| `lib/ui/jog_pad.dart` | Circular proportional jog pad. |
| `lib/ui/keypose_tiles.dart` | Keypose tiles and the slider position track. |
| `lib/ui/homing_dialog.dart` | Homing and pose restore, with progress. |
| `lib/ui/ui_scale.dart` | Shared spacing, type and the Section/Caution widgets. |
| `lib/ui/frame_inspector.dart` | Raw notification frames, for decoding §8. |
| `lib/main.dart` | Device list (entry point only) and global stop. |

Everything above `ek_connection.dart` depends on the `EkMotionTarget` interface
rather than on BLE, so the motion logic is unit-tested against a fake device.

## Tests

```
flutter pub get
dart test
```

145 tests, no hardware and no Flutter binding required. They cover the protocol
against the captured bytes, plus the motion logic — including that a stop goes
out on every exit path: normal completion, user stop, lost link, timed-out leg,
and a write that throws.

## Platform notes

- **Android** — `BLUETOOTH_SCAN` / `BLUETOOTH_CONNECT`, legacy permissions and
  location below API 31, requested at runtime via `permission_handler`.
- **macOS** — the Bluetooth entitlement is in **both** `DebugProfile.entitlements`
  and `Release.entitlements`. Missing either gives a silent no-results scan.
  `NSBluetoothAlwaysUsageDescription` is also required in `Info.plist` on
  macOS 11+.
- **iOS** — `NSBluetoothAlwaysUsageDescription` in `Info.plist`.
- macOS and iOS need full Xcode plus CocoaPods, not just the Command Line Tools.

CoreBluetooth hides MAC addresses and issues per-host UUIDs, so devices are
matched on advertised name (`SldrPlsV1`, `HeadOneFM`) rather than by identifier.

## Known gaps

These come from the spec, not from the implementation:

- **The HeadONE reports no motion state and no position** (§5). Ping-pong on the
  head therefore runs blind on a fixed timer instead of waiting for each move to
  finish (adjustable in the UI, since only you can see how long a leg really
  takes). The slider is properly supervised. Decoding the head's 16-byte
  `0x05` message would fix this — the **Raw frames** screen, reachable from the
  device panel, exists for exactly that: it logs every notification verbatim,
  can hide the routine telemetry, and copies to the clipboard.
- **Speed vs acceleration is unestablished** (§7b). The two `u16` slots are
  symmetric in every captured frame and were always set together, so independent
  sliders rest on an assumption. Setting both to the same value reproduces
  exactly what was captured; the UI says so when they differ.
- **Only 1% and 100% were measured.** Everything between is modelled.
- **Coordinated slider + head moves are not implemented** (§8). The official
  app pairs the units and captures both axes into a single keypose; that path
  was never captured, so nothing here reproduces it. "Move together" is
  host-side coordination instead: each device gets an ordinary pose recall at
  the same moment, and none starts its next leg until all have finished this
  one. Within a leg the axes run at their own rates and can drift — match their
  speeds if you need them to arrive together.
- Point Tracking is not implemented (§8); it needs edelkrone's inverse
  kinematics, not just the protocol.
- **The head's move duration cannot be measured.** It reports no position and
  no motion state (§5), so making both axes take the same time relies on a
  human timing one head move. That calibration is only valid for the poses it
  was taken between, because there is no way to know how far apart two head
  poses are. Decoding the 16-byte `0x05` frame §5 suspects carries head
  progress would remove the need entirely — **this is the single capture that
  would most improve the app.**
- **Head poses cannot be restored after a power cycle.** The head reports no
  position (§5), so there is nothing to record and nothing to verify arrival
  against. Jogging open-loop for a stored duration would drift with battery and
  load, silently, so the app does not do it — head poses are re-taught by hand
  each session, and the UI says so. Slider poses saved while homed are stored as
  a fraction of measured travel and **can** be restored.

## Licence note

`flutter_blue_plus` 2.x is not BSD. `connect()` requires declaring
`License.nonprofit` or `License.commercial`; this project declares `nonprofit`,
which covers personal and educational use. Commercial distribution needs a paid
licence.
