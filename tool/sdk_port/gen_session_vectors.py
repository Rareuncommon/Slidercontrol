"""Differential vectors for the hand-ported layers above the codec.

The codec is proven by gen_vectors.py. This proves the layers written by
hand on top of it, against the Python SDK's own versions of them:

  commands  — CommandSet: every command this port sends, for the HeadONE and
              the SliderPLUS. Bytes, channel and expected reply type.
  layouts   — prepare_setup: which units form which layout, who leads, and in
              what order the modules are listed. Includes upright and tilted
              HeadONEs, which resolve to different layouts.
  rigs      — group_into_rigs: grouping a scan into rigs.
  status    — DeviceStatus: what a status frame plus a position readout mean,
              in degrees, centimetres and percent.

Usage (from the repo root, with the SDK installed in a venv):
    <venv>/bin/python -I tool/sdk_port/gen_session_vectors.py
"""

from __future__ import annotations

import gzip
import itertools
import json
import math
import random
from pathlib import Path

from edelkrone.api.status import DeviceStatus
from edelkrone.devices import models
from edelkrone.devices.registry import EdelkroneDevice, prepare_setup
from edelkrone.devices.rig import group_into_rigs
from edelkrone.protocol.moco import EdlDevice, EdlSetup, EspWifiState, LibEdelkroneMocoAdvData
from edelkrone.session.command import ResponseFrame
from edelkrone.session.command_set import CommandSet, MoveRequest
from edelkrone.session.family import DeviceLibraries
from edelkrone.session.responses import FamilyCodec, ParseContext
from edelkrone.session.state import DeviceState
from edelkrone.transport import Channel

ROOT = Path(__file__).resolve().parent.parent.parent
rng = random.Random(1020)


def f(v):
    if v is None:
        return None
    if isinstance(v, bool):
        return v
    if isinstance(v, float):
        if math.isnan(v):
            return {"f": "NaN"}
        return {"f": repr(v)}
    return v


# -- commands ------------------------------------------------------------------


def commands():
    out = []
    for key, model in (("head", models.HEAD_ONE_FM), ("slide", models.SLIDER_PLUS_V1)):
        cs = CommandSet(DeviceLibraries.of(model))
        calls = [("status_get", ()), ("version_get", ()), ("settings_get", ()), ("motion_abort", ())]
        calls += [("keypose_store", (i,)) for i in (0, 1, 5, 11)]
        calls += [("keypose_delete", (i,)) for i in (0, 3, 11)]
        calls += [("numeric_position_read", (i,)) for i in (0, 7, 255)]
        for s in (-1.0, -0.37, 0.0, 0.004, 0.5, 1.0, 1.4, -2.0):
            calls.append(("manual_slide", (s,)))
        for b in (True, False):
            calls.append(("buzzer", (b,)))
        for _ in range(12):
            calls.append(
                (
                    "keypose_move",
                    (
                        rng.randrange(12),
                        rng.choice([-1, 0, 1, 4]),
                        rng.choice([True, False]),
                        rng.choice([0.01, 0.15, 0.5, 1.0]),
                        rng.choice([0.0, 0.25, 0.4, 1.0]),
                    ),
                )
            )
        if key == "head":
            calls += [("remote_version_get", ()), ("keypose_move_duration_get", ())]
            for p, t in ((0.0, 0.0), (0.3, -0.1), (-1.0, 1.0), (1.2, 0.0), (0.0123, -0.987)):
                calls.append(("manual_pan_tilt", (p, t)))
                calls.append(("manual_jib_pan_tilt", (p, t)))
            for setup in (EdlSetup.PAN_ONLY, EdlSetup.PAN_AND_SLIDE, EdlSetup.TILT_AND_SLIDE, EdlSetup.NONE):
                calls.append(("configuration", (setup.name,)))
        else:
            calls.append(("configuration", ("SLIDE_ONLY",)))
        calls += [("ioctl_status_get", ()), ("canbus_info_get", ()), ("canbus_auto_pair", ())]
        for g in (0, 0x1234, 0xFFFF):
            calls.append(("group_id_self_set", (g,)))
            calls.append(("add_peer", ([0xA4, 0xC1, 0x38, 0x5E, 0x7B, 0x2D], "SLIDER_PLUS_V1", g)))

        for name, args in calls:
            if name == "keypose_move":
                aim, start, loop, speed, accel = args
                cmd = cs.keypose_move(
                    MoveRequest(
                        aim_index=aim,
                        start_index=start,
                        loop=loop,
                        relative_speed=speed,
                        accel_in_ratio=accel,
                        accel_out_ratio=accel,
                    )
                )
            elif name == "buzzer":
                cmd = cs.settings.buzzer_muted(args[0])
            elif name == "configuration":
                setup = EdlSetup[args[0]]
                if key == "slide":
                    from edelkrone.protocol._generated.slide_module import LibSlideModuleEdlSetup

                    cmd = cs.settings.configuration_slide(LibSlideModuleEdlSetup[args[0]])
                else:
                    cmd = cs.settings.configuration(setup)
            elif name == "add_peer":
                cmd = cs.add_peer(mac=args[0], device_type=EdlDevice[args[1]], group_id=args[2])
            else:
                cmd = getattr(cs, name)(*args)
            out.append(
                {
                    "fam": key,
                    "cmd": name,
                    "args": [f(a) if not isinstance(a, list) else a for a in args],
                    "bytes": list(cmd.encode()),
                    "channel": cmd.channel.value,
                    "expects": cmd.expects,
                }
            )
    return out


# -- layouts and rigs ---------------------------------------------------------


class Handle:
    def __init__(self, i):
        self.id = f"dev{i}"
        self.name = ""


def adv(i, setup=EdlSetup.NONE, group=0xFFFF, tilted=False):
    mac = [0xC8, 0xF0, 0x9E, 0x10, 0x20, i & 0xFF]
    return LibEdelkroneMocoAdvData(
        mac=mac,
        group_id=group,
        setup=setup,
        wifi_channel=0,
        wifi_state=EspWifiState.NONE,
        is_tilted=tilted,
        old_slide_module_connected=False,
        esp32_firmware_version_minor=34,
        esp32_firmware_version_major=0,
        device_firmware_version_minor=1,
        device_firmware_version_major=1,
        canbus_pairing_active=False,
    )


POOL = [
    "HEAD_ONE",
    "HEAD_ONE_FM",
    "SLIDER_PLUS_V1",
    "SLIDER_ONE",
    "SLIDER_ONE_FM",
    "SLIDE_MODULE_V3",
    "HEAD_PLUS_V3",
    "DOLLY_PLUS_V2",
    "JIB_PLUS_V3",
    "HEAD_PLUS_PRO_V3",
]


def unit(i, name, **kw):
    return EdelkroneDevice(ble_device=Handle(i), model=getattr(models, name), adv_data=adv(i, **kw), rssi=-40 - i)


def desc(i, name, **kw):
    return {"i": i, "model": name, **{k: (v.name if hasattr(v, "name") else v) for k, v in kw.items()}}


def layouts():
    cases = []
    combos = [[a] for a in POOL] + [list(p) for p in itertools.product(POOL, repeat=2)]
    combos += [[rng.choice(POOL) for _ in range(3)] for _ in range(250)]
    for combo in combos:
        for tilts in itertools.product([False, True], repeat=len(combo)):
            if len(combo) == 3 and rng.random() < 0.75:
                continue
            units = [unit(i, n, tilted=t) for i, (n, t) in enumerate(zip(combo, tilts))]
            r = prepare_setup(units)
            result = None
            if r is not None:
                result = {
                    "setup": r.setup_type.name,
                    "master": units.index(r.master_device),
                    "slaves": [units.index(s) for s in r.slave_devices],
                }
            cases.append({"units": [desc(i, n, tilted=t) for i, (n, t) in enumerate(zip(combo, tilts))], "out": result})
    return cases


SETUPS = [EdlSetup.NONE, EdlSetup.GROUP_MEMBER, EdlSetup.PAN_AND_SLIDE, EdlSetup.SLIDE_ONLY, EdlSetup.PAN_ONLY, EdlSetup.TILT_AND_SLIDE]


def rigs():
    cases = []
    for _ in range(300):
        n = rng.randint(1, 4)
        spec = [
            (rng.choice(POOL), rng.choice(SETUPS), rng.choice([0x0101, 0x0202, 0xFFFF]), rng.choice([False, True]))
            for _ in range(n)
        ]
        units = [unit(i, m, setup=s, group=g, tilted=t) for i, (m, s, g, t) in enumerate(spec)]
        out = []
        for r in group_into_rigs(units):
            out.append(
                {
                    "master": units.index(r.master),
                    "slaves": [units.index(s) for s in r.slaves],
                    "ordered": [units.index(s) for s in r.ordered_slaves],
                    "setup": r.setup.name,
                    "recognised": r.is_recognised,
                }
            )
        cases.append(
            {"units": [desc(i, m, setup=s, group=g, tilted=t) for i, (m, s, g, t) in enumerate(spec)], "out": out}
        )
    return cases


# -- status ------------------------------------------------------------------


def frame(type_byte, length):
    v = [rng.randrange(256) for _ in range(length)]
    v[0] = type_byte
    return v


def status_cases():
    cases = []
    for key, model, status_type, numeric_type, lengths in (
        ("head", models.HEAD_ONE_FM, 2, 18, (122, 130, 140)),
        ("slide", models.SLIDER_PLUS_V1, 2, 9, (27, 40)),
    ):
        libs = DeviceLibraries.of(model)
        codec = FamilyCodec.for_family(libs.family)
        ctx = ParseContext(libs=libs, has_live_mode=True)
        for _ in range(300):
            state = DeviceState.for_family(libs)
            frames = [frame(status_type, rng.choice(lengths))]
            if rng.random() < 0.8:
                nf = frame(numeric_type, 34)
                nf[1] = rng.choice([255, 255, 255, 3])
                # Plausible readouts: small signed thousandths, sometimes "not fitted".
                for off in (2, 6, 10, 14, 18, 22):
                    val = rng.choice([rng.randint(-360000, 360000), -1000, 0])
                    nf[off : off + 4] = list(val.to_bytes(4, "big", signed=True))
                frames.append(nf)
            try:
                for fr in frames:
                    codec.apply(ResponseFrame(Channel.DATA, bytes(fr)), state, ctx)
                s = DeviceStatus._from_state(state).to_dict()
                pose = s["pose"]
                out = {
                    "activity": s["activity"],
                    "pose": {k: f(v) for k, v in pose.items()},
                    "slide_fraction": f(s["slide_fraction"]),
                    "battery_percent": f(s["battery_percent"]),
                    "is_calibrated": s["is_calibrated"],
                    "has_focus_motor": s["has_focus_motor"],
                    "layout": s["layout"],
                    "stored_pose_slots": s["stored_pose_slots"],
                    "modules_responding": s["modules_responding"],
                    "move_progress": f(s["move_progress"]),
                    "position_is_trusted": s["position_is_trusted"],
                    "has_status_frame": s["has_status_frame"],
                    "tilt_deg": f(s["tilt_deg"]),
                    "is_level": s["is_level"],
                    "orientation_warning": s["orientation_warning"],
                    "accel": [f(s["accel_x_ms2"]), f(s["accel_y_ms2"]), f(s["accel_z_ms2"])],
                }
            except Exception as exc:  # noqa: BLE001
                out = {"throws": type(exc).__name__}
            cases.append({"fam": key, "frames": frames, "out": out})
    return cases


def main():
    data = {"commands": commands(), "layouts": layouts(), "rigs": rigs(), "status": status_cases()}
    path = ROOT / "test" / "sdk" / "vectors" / "session_vectors.json.gz"
    path.write_bytes(gzip.compress(json.dumps(data, separators=(",", ":")).encode(), 9))
    print({k: len(v) for k, v in data.items()}, path.stat().st_size, "bytes")


if __name__ == "__main__":
    main()
