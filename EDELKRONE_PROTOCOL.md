# edelkrone BLE protocol

Reverse-engineered from a SliderPLUS v6 and a HeadONE, by capturing the official
app with PacketLogger on macOS and by direct experiment over `bleak`.

Everything here is verified against captured bytes unless explicitly marked
UNVERIFIED. The Python reference implementation (`ek_drive.py`) has a `selftest`
command that regenerates every frame below and compares it to the capture.

---

## 1. Transport

Both devices are BLE peripherals. They advertise as:

| Device | Advertised name |
|---|---|
| SliderPLUS v6 | `SldrPlsV1` |
| HeadONE | `HeadOneFM` |

The `V1` in the slider's name is a protocol/advertising version, not the product
generation — a v6 slider still advertises `SldrPlsV1`.

### GATT layout

Both devices expose the same characteristics. Only the service UUID differs, in
its last four hex digits:

| | UUID |
|---|---|
| Service (slider) | `4baee7eb-2122-4502-98e9-1ee792bd5603` |
| Service (head) | `4baee7eb-2122-4502-98e9-1ee792bd5594` |
| Write (commands) | `5a861ccb-687b-459a-af01-347792f07a0c` |
| Notify (telemetry) | `c2720639-bdfc-4b8e-896d-b5bea0479976` |
| Write (secondary, unused) | `7da5b2e6-071c-4601-9fde-ecaf291d0a04` |
| Notify (secondary, unused) | `eaa8212a-3551-4e98-adeb-0b68957a215a` |

No characteristic is readable. All state arrives via notifications, and **only in
response to a poll** — subscribe alone yields one frame and then silence.

Commands are written with a Write Request (expecting a response), not
Write Without Response.

---

## 2. Framing

Every frame, in both directions, has the same shape:

```
[len] [opcode] [payload ...] [checksum_hi] [checksum_lo]
```

- `len` — the number of bytes before the checksum, i.e. `2 + len(payload)`.
  Note this counts the `len` byte itself and the opcode.
- `checksum` — a big-endian 16-bit **sum of every byte before it**. Not CRC,
  not XOR. Plain addition, truncated to 16 bits.

Worked example, the slider keepalive `02 0F 00 11`:
`0x02 + 0x0F = 0x11`, which is the trailing checksum.

In notification frames the first byte is a **message type**, not a length.
Slider telemetry starts `0x02`; the head emits `0x02`, `0x04`, and others.
The checksum rule still holds: sum of all bytes before the final two.

Multi-byte numeric fields are **big-endian**.

---

## 3. Slider commands

Written to the write characteristic.

| Purpose | Frame | Cadence |
|---|---|---|
| Keepalive / poll | `02 0F 0011` | every 250 ms |
| Velocity (jog) | `06 0D <vel:i16> 70 80 <sum>` | every 100 ms while moving |
| Save pose | `07 07 <slot> 00 00 30 39 <sum>` | once |
| Recall pose | `0D 0B 00 <extra:u32> <speed:u16> <accel:u16> FF <slot> <sum>` | once |
| Loop | `0D 0B 01 <extra:u32> <speed:u16> <accel:u16> 00 <slot> <sum>` | once |
| Stop | `02 0C 000E` | once |

### Notes

**Velocity** is a signed 16-bit big-endian value in encoder counts per second,
very close to 1:1 (commanding ±31,846 measured ±30,789 counts/sec). Full stick
in the app is about ±31,900. Zero means stop. `70 80` was constant in every
captured frame; its meaning is unknown.

**Save** captures the device's *current* position into the slot — the frame
carries no position. `30 39` (12345) appears to be a magic constant; it was
identical in every capture.

**Recall**: the target slot is the **last** payload byte, not the first. The
first payload byte is the loop flag.

**Loop** differs from a recall in exactly two bytes: payload byte 0 goes
`00`→`01`, and the byte before the slot goes `FF`→`00`.

**The device's loop mode stops after roughly one round trip.** Do not rely on
it. Supervise from the host: recall a pose, wait for the move to complete, then
recall the other one. See §7.

**Poses are volatile.** They survive a BLE disconnect and a client restart, but
are lost when the device is powered off.

---

## 4. HeadONE commands

Same framing, different opcodes.

| Purpose | Frame | Cadence |
|---|---|---|
| Keepalive / poll | `02 01 0003` | every 250 ms |
| Velocity (pan) | `06 0A <vel:i16> 00 00 <sum>` | every 100 ms while moving |
| Save pose | `07 05 <slot> 00 00 30 39 <sum>` | once |
| Recall pose | `11 07 FF <slot> 00 <speed:u16> <accel:u16> <extra:u32> FFFFFC18 <sum>` | once |
| Loop | `11 07 00 <slot> 01 <speed:u16> <accel:u16> <extra:u32> FFFFFC18 <sum>` | once |
| Stop | `02 09 000B` | once |

### Notes

Sending the **slider's** velocity opcode (`0x0D`) to the head returns a 20-byte
frame containing an ASCII identifier and produces no motion. The opcode sets are
not interchangeable.

Positive velocity pans right, negative left — same sign convention as the
slider.

In the head's recall frame the varying bytes are payload byte 0 (`FF` single /
`00` loop), byte 1 (slot), and byte 2 (`00` single / `01` loop). The tail
`0494 0494 00 E6741A FFFFFC18` was byte-identical across every captured frame.
`FFFFFC18` reads as signed 32-bit −1000. Meaning unknown.

Polling `0x0F` returns `04 FFFFFFFF 00 01 02 ... 0C <sum>` — an ascending run
that looks like a list of the 13 valid opcodes (`0x00`–`0x0C`).

---

## 5. Telemetry

### Slider

27-byte frames, first byte `0x02`.

| Offset | Meaning |
|---|---|
| 0 | message type, `0x02` |
| 1 | state — see below |
| 2 | battery percent |
| 8–9 | position, **uint16, wraps** |
| 25–26 | checksum |

State byte:

| Value | Meaning |
|---|---|
| `0x00` | idle |
| `0x02` | executing a pose move |
| `0x0E` | manual jog |
| `0xFF` | an ack with a different layout — skip it, the position bytes are not valid |

**The position counter is only 16 bits and wraps.** It must be unwrapped in
software: track the previous raw value, and treat a jump of more than +32768 as
a wrap downward and less than −32768 as a wrap upward. Telemetry arrives at
roughly 3.3 Hz, so per-sample motion stays well under the ±32,768 ambiguity
limit even at full speed (~9,000 counts/sample). Hand-pushing reaches ~60,000
counts/sec, which is still safe at that sample rate but leaves less margin.

The absolute value is arbitrary — it is not preserved across sessions and has no
fixed relationship to any physical point on the rail.

### HeadONE

122-byte frames, first byte `0x02`, checksum in bytes 120–121. Byte 89 is
battery percent.

**The head does not report live position** on its own connection. All 13 poll
opcodes return either static blobs or identifier frames, and nothing changes
during commanded motion. Two bytes change once at connect and then never again.

A 16-byte message type with byte 1 = `0x05` was observed carrying a steadily
incrementing byte during a pose recall — that is likely progress or angle, but
it was truncated in capture and has not been decoded. UNVERIFIED.

---

## 6. Measured physical constants

For this specific rig. Re-measure for different hardware.

| Quantity | Value |
|---|---|
| Slider rail travel | ~481,000 counts (powered); ~475,458 measured by hand |
| Slider full-stick speed | ~30,500 counts/sec |
| Slider pose-recall speed | ~16,600 counts/sec (with `0494` speed/accel) |
| Slider full-rail traverse | ~29 s at recall speed |
| Head rotation rate | ~1.2°/sec at velocity 2000, so ~20°/sec at full stick |

The powered and hand measurements differ by 1.2% because the motor presses
slightly further into the end stops than a hand does. Use the powered figure —
every move that consumes it is also powered.

---

## 7. Behaviour any client must implement

These are not protocol details but they are not optional.

**Poll or get nothing.** No telemetry arrives without the keepalive at 250 ms.

**Supervise the loop.** Device loop mode stops after about one round trip.
Recall a pose, wait for state to return to `0x00` and stay there ~0.6 s, then
recall the other. Do not simply fire the loop command and walk away.

**Unwrap the slider position** as described in §5. Failing to do this yields
counts that bear no relation to distance travelled.

**The slider has no soft limits.** It will drive into its mechanical stops and
grind indefinitely. If a client implements homing it must detect the stall
itself, using *net progress over a window* (~0.5 s) rather than per-tick deltas —
against a hard stop the encoder dithers by hundreds of counts, which defeats any
fixed per-tick threshold. Confirm a suspected stop by backing off and
re-approaching; the SliderPLUS has a mid-rail mechanism transition that pauses
progress and imitates an end stop convincingly.

**Send the stop command before exiting.** If the process dies mid-move the
device keeps executing and holds torque, leaving the carriage locked and
unmovable by hand. On POSIX, install a SIGINT handler that sets a flag the
motion loop polls, so cleanup runs on a live event loop — cancelling the task
outright kills the cleanup before the stop write goes out.

**Prefer pose recalls to streamed velocity for unattended operation.** A recall
is one command the device completes on its own, so a dropped BLE link ends with
the device stopping. Streamed velocity keeps running if the host disappears.

---

## 7b. Speed and acceleration

Captured with the app's speed/acceleration sliders at 1% and at 100%:

| Setting | `speed`/`accel` pair | slider `extra` | head `extra` |
|---|---|---|---|
| 1% | `0x7BC3` = 31,683 | 20 | 320,000 |
| 100% | `0x0140` = 320 | 1,080 | 32,000,000 |
| (app default seen earlier) | `0x0494` = 1,172 | 515 | 15,102,490 |

**The pair is a period, not a speed — larger means slower.** It is identical on
both devices at the same percentage, so that field is device-independent. The
`extra` field is device-specific and scales the opposite way; the head's is
exactly `320,000 × percent` at both measured points.

Both `extra` fields independently place the earlier default at about 47%, which
is a useful cross-check that the two encodings are being read correctly.

Modelling percentage in between (reciprocal for the pair, linear for `extra`)
reproduces both endpoints within 1%. **Only the two endpoints are measured** —
two points define a line but say nothing about the shape between them. Capture a
mid-range setting before trusting intermediate values.

Speed and acceleration were set together in both captures, so which of the two
`u16` slots is speed and which is acceleration is not established — they are
symmetric in every frame seen.

Manual jogging has no speed field: the velocity value *is* the speed. To make a
speed control apply to manual movement as well, scale the commanded velocity by
the same percentage host-side.

---

## 8. Not yet decoded
- The constant `70 80` in the slider velocity frame.
- The tail `00 E6741A FFFFFC18` in the head's recall frame.
- Head position reporting (§5).
- Whether any command releases motor holding torque, or whether a power cycle is
  the only way.
- Coordinated slider + head moves. The app pairs the two and captures both axes
  in one keypose; that path has not been captured.
- Point Tracking. Requires reimplementing edelkrone's inverse kinematics, not
  just the protocol.

---

## 9. Porting notes

The framing, opcodes, and behaviour above are the whole protocol. A port needs:

1. A frame builder — length byte, opcode, payload, 16-bit sum checksum.
2. A device profile selecting the opcode set from the advertised name.
3. A 250 ms keepalive timer per connection.
4. A notification parser with the wrap-unwrapping in §5.
5. The supervised ping-pong in §7.

BLE APIs differ but the sequence does not: scan → connect → discover services →
subscribe to the notify characteristic → start polling → write commands.

On macOS/iOS, CoreBluetooth hides MAC addresses and gives per-host UUIDs
instead, so a device identifier from one machine will not match another. Match
on advertised name for anything portable.
