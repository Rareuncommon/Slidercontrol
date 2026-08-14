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
- **Never home the head.** It has no end stops. There is no homing anywhere in
  this codebase, for either device. If any is ever added, its stall detection
  must use net progress over a ~0.5 s window, not per-tick deltas — against a
  hard stop the encoder dithers by hundreds of counts (§7).
- **The slider has no soft limits.** It will drive into its mechanical stops and
  grind indefinitely.
- Unattended motion uses pose recalls, never streamed velocity. A recall is one
  command the device finishes on its own, so a dropped link ends stopped.
  Streamed velocity keeps running if the host vanishes — which is why jogging is
  hold-to-move only.

## Layout

| Path | What it is |
|---|---|
| `lib/ek_protocol.dart` | Framing, opcodes, telemetry, position unwrapping. Pure Dart. **Ground truth — do not edit.** |
| `lib/ble/ek_names.dart` | Advertised-name recognition. Pure. |
| `lib/ble/ek_snapshot.dart` | Device state and the `EkMotionTarget` interface. Pure. |
| `lib/ble/ek_scanner.dart` | Scanning, matched on advertised name. |
| `lib/ble/ek_connection.dart` | One connection: discovery, 250 ms keepalive, serialised writes, telemetry. |
| `lib/control/motion_settings.dart` | Speed/acceleration percentages → wire values. |
| `lib/control/jog.dart` | Streamed velocity while held. |
| `lib/control/ping_pong.dart` | Host-supervised loop between two poses. |
| `lib/ui/`, `lib/main.dart` | Device list and per-device controls. |

Everything above `ek_connection.dart` depends on the `EkMotionTarget` interface
rather than on BLE, so the motion logic is unit-tested against a fake device.

## Tests

```
flutter pub get
dart test
```

70 tests, no hardware and no Flutter binding required. They cover the protocol
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
  finish. The slider is properly supervised. Decoding the head's 16-byte
  `0x05` message would fix this.
- **Speed vs acceleration is unestablished** (§7b). The two `u16` slots are
  symmetric in every captured frame and were always set together, so independent
  sliders rest on an assumption. Setting both to the same value reproduces
  exactly what was captured; the UI says so when they differ.
- **Only 1% and 100% were measured.** Everything between is modelled.
- Coordinated slider + head moves and Point Tracking are not implemented (§8).

## Licence note

`flutter_blue_plus` 2.x is not BSD. `connect()` requires declaring
`License.nonprofit` or `License.commercial`; this project declares `nonprofit`,
which covers personal and educational use. Commercial distribution needs a paid
licence.
