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
- Pose recalls are preferred over streamed velocity. A recall is one command the
  device finishes on its own, so a dropped link ends stopped. Streamed velocity
  keeps running if the host vanishes — which is why jogging is hold-to-move
  only. **Synchronised moves are the deliberate exception**: they stream
  velocity to the slider because that is the only way to impose an exact
  duration, so they are for attended shooting. Every exit path — completion,
  stop, lost link, a write that throws — stops every axis.
- **A homed reference survives an app restart but not a device power cycle.**
  The carriage is assumed not to have moved while the app was closed. The
  position counter restarts at an arbitrary value on power-up (§5), so the
  stored reference is checked against the live counter as soon as telemetry
  arrives, and discarded with a warning if the carriage now reads somewhere the
  rail does not reach.
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
| `lib/control/move_timing.dart` | Solving each axis's speed for a shared duration. Pure. Fallback only. |
| `lib/control/sync_move.dart` | One move, both axes driven from one host clock. Pure. |
| `lib/control/sync_ping_pong.dart` | Ping-pong where every leg is a synchronised move. Pure. |
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

186 tests, no hardware and no Flutter binding required. They cover the protocol
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

## Synchronised moves

Both axes start and stop at the same instant. That is the whole point of a
two-axis shot, and it is harder than it sounds.

**What does not work: solving for a speed percentage.** The obvious approach is
to predict how long each device's pose recall will take at a given speed and
pick percentages that make the two durations match. Two things defeat it. The
motor saturates — §6 measures a recall at ~16,600 counts/sec at roughly 47%,
while full-stick jog is only ~30,500 counts/sec, so a `duration ∝ 1/percent`
model would predict ~35,000 counts/sec at 100%, past what the hardware can do,
and nothing in the captures says where the curve flattens. And the head cannot
be measured at all (§5), so even a correct model could never be checked against
it. This was implemented, tested against the model, and did not work on
hardware. `move_timing.dart` is what remains of it; it is now only the fallback
for when the rail has not been homed.

**What works: imposing the duration.** `sync_move.dart` ticks one host clock and
commands every axis from it, so the moves begin and end together by
construction rather than by calculation:

- The **slider** is velocity-streamed closed loop against its reported position,
  following a smoothstep so it eases in and out. It arrives at a target count,
  at the requested time.
- The **head** gets its ordinary pose recall, issued on the same tick as the
  slider's first command and stopped on the same tick as its last. Its own
  profile runs in between. It has to be this way: with no position reported,
  the host cannot know which way to turn the head or how far.

Consequences worth knowing before you shoot:

- Asking for a shot shorter than the slider can physically manage **extends the
  leg** rather than letting it arrive short. The UI shows the duration that will
  actually be used.
- Asking for a shot shorter than the head needs **truncates the head**, because
  stopping together is the guarantee being kept. Time the shot against the
  slower axis.
- This streams velocity, which §7 warns keeps running if the host vanishes. It
  is for attended shooting. It requires a homed rail, and falls back to
  independent pose recalls when there is no homed target to steer to.

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
  was never captured, so nothing here reproduces it. What the app does instead
  is drive both axes from one host clock — see **Synchronised moves** below.
- Point Tracking is not implemented (§8); it needs edelkrone's inverse
  kinematics, not just the protocol.
- **The head's move duration cannot be measured.** It reports no position and
  no motion state (§5). The synchronised path does not need that measurement —
  it imposes the duration rather than predicting it — but it still cannot know
  how far the head has to travel, so a shot shorter than the head really needs
  truncates the head's move. Decoding the 16-byte `0x05` frame §5 suspects
  carries head progress would remove the limitation entirely — **this is the
  single capture that would most improve the app.**
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
