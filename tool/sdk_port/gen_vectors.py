"""Generates differential test vectors for the transpiled protocol codecs.

Runs every function and method of the Python SDK's generated codecs — the
real ones, imported from the installed `edelkrone` package — over a seeded
spread of arguments, and records what each call wrote and returned. It also
writes the Dart side of the harness: a dispatch table that makes the same call
against `lib/sdk/protocol/generated/` and serialises the result the same way.

`test/sdk/codec_vectors_test.dart` then demands the two agree exactly: every
byte a builder writes, every field a parser fills in, every exception.

Usage (from the repo root, with the SDK installed in a venv):
    <venv>/bin/python -I tool/sdk_port/gen_vectors.py <generated_py_dir>

Not part of the app. Re-run whenever the SDK or the transpiler changes.
"""

from __future__ import annotations

import ast
import importlib
import json
import math
import random
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import py2dart  # noqa: E402

ROOT = HERE.parent.parent
MODULES = ["moco", "head_module_util", "slide_module_util", "head_module", "slide_module"]
CASES_PER_FUNCTION = 48
BUFFER = 200

INTS = [0, 1, 2, 3, 5, 7, 11, 15, 16, 31, 100, 127, 128, 200, 254, 255, 256, 1000, 4095, 12345, 32767, 65535, 70000, -1, -100]
SMALL_INTS = [0, 1, 2, 3, 5, 7, 9, 11, 12, 15]
DOUBLES = [-1.0, -0.73, -0.5, -0.01, 0.0, 0.004, 0.25, 0.5, 0.999, 1.0, 1.7, 12.34, -45.6, 90.0, 180.0, 359.9, 1234.5678]

INDEX_NAMES = {"ind", "index", "keyp_index", "slot", "offset", "base", "bit", "len", "width"}


def is_parse(name: str) -> bool:
    return "parse" in name or name.startswith("make") or name in ("checksum_control", "check_bit", "adv_parse")


class Sampler:
    def __init__(self, types: py2dart.Types, mods: dict[str, object], rng: random.Random) -> None:
        self.types = types
        self.mods = mods
        self.rng = rng

    def cls(self, name: str):
        info = self.types.classes[name]
        return getattr(self.mods[info.module], name)

    def value(self, t: str, pname: str, method: str):
        """Returns (python value, json description)."""
        rng = self.rng
        inner = py2dart.list_of(t)
        if inner is not None:
            if pname in ("ptr", "data", "buffer", "adv_data") and inner == "int":
                if pname == "adv_data":
                    n = rng.choice([12, 13, 13, 13, 20])
                    raw = [rng.randrange(256) for _ in range(n)]
                elif is_parse(method):
                    raw = [rng.randrange(256) for _ in range(BUFFER)]
                    if rng.random() < 0.1:
                        raw = [rng.choice([0, 255])] * BUFFER
                else:
                    raw = [0] * 64
                return list(raw), {"t": "bytes", "v": raw}
            if inner == "int":
                if pname in ("mac", "pan_module_mac_address"):
                    raw = [rng.randrange(256) for _ in range(6)]
                else:
                    raw = [0, 0, 0]
                return list(raw), {"t": "ints", "v": raw}
            if inner == "double":
                return [0.0, 0.0, 0.0], {"t": "doubles", "v": 3}
            if inner in self.types.classes:
                obj, desc = self.value(inner, pname, method)
                return [obj], {"t": "objlist", "v": desc}
            raise py2dart.Refused(f"list type {t}")
        if t == "int":
            pool = SMALL_INTS if pname in INDEX_NAMES or "index" in pname else INTS
            if pname == "width":
                pool = [1, 4, 8, 12, 16, 24, 32]
            v = rng.choice(pool)
            return v, {"t": "int", "v": v}
        if t == "double":
            v = rng.choice(DOUBLES)
            return v, {"t": "double", "v": repr(v)}
        if t == "bool":
            v = rng.choice([True, False])
            return v, {"t": "bool", "v": v}
        if t in self.types.classes:
            info = self.types.classes[t]
            pycls = self.cls(t)
            if info.is_enum:
                m = rng.choice(list(info.members))
                return getattr(pycls, m), {"t": "enum", "c": t, "v": m}
            # A data class: build it, then randomise every scalar field.
            if info.ctor_params:
                kwargs = {}
                fields = {}
                for n, ft in info.ctor_params:
                    pv, pd = self.value(ft, n, "parse")
                    kwargs[n] = pv
                    fields[n] = pd
                return pycls(**kwargs), {"t": "obj", "c": t, "ctor": fields}
            obj = pycls()
            fields = {}
            for fname, ft in info.fields.items():
                if ft in ("int", "double", "bool") or (ft in self.types.classes and self.types.classes[ft].is_enum):
                    fv, fd = self.value(ft, fname, "parse")
                    setattr(obj, fname, fv)
                    fields[fname] = fd
            return obj, {"t": "obj", "c": t, "fields": fields}
        raise py2dart.Refused(f"type {t} for {pname}")


def ser(types: py2dart.Types, v):
    if isinstance(v, bool):
        return v
    if hasattr(v, "name") and hasattr(v, "value") and type(v).__name__ in types.classes:
        return {"e": v.name}
    if isinstance(v, int):
        return v
    if isinstance(v, float):
        if math.isnan(v):
            return {"f": "NaN"}
        if math.isinf(v):
            return {"f": "Infinity" if v > 0 else "-Infinity"}
        return {"f": repr(v)}
    if isinstance(v, list):
        return [ser(types, x) for x in v]
    if v is None:
        return None
    name = type(v).__name__
    if name in types.classes:
        info = types.classes[name]
        keys = [k for k, _ in info.ctor_params] if info.ctor_params else list(info.fields)
        return {"o": name, **{py2dart.camel(k): ser(types, getattr(v, k)) for k in keys}}
    raise TypeError(f"cannot serialise {type(v)}")


def main() -> None:
    gen_dir = Path(sys.argv[1])
    types = py2dart.Types()
    trees = {}
    for m in MODULES:
        p = gen_dir / f"{m}.py"
        trees[m] = ast.parse(p.read_text())
        py2dart.collect(types, m, trees[m])

    mods = {m: importlib.import_module(f"edelkrone.protocol._generated.{m}") for m in MODULES}
    rng = random.Random(20261020)
    sampler = Sampler(types, mods, rng)

    cases = []
    dispatch = []  # (key, dart lambda body)
    for m in MODULES:
        for node in trees[m].body:
            funcs = []
            if isinstance(node, ast.ClassDef):
                info = types.classes[node.name]
                if info.is_enum:
                    continue
                for mname, fi in info.methods.items():
                    funcs.append((node.name, mname, fi))
            elif isinstance(node, ast.FunctionDef):
                params = [(a.arg, types.ann(a.annotation)) for a in node.args.args]
                funcs.append((None, node.name, py2dart.FuncInfo(node.name, params, types.ann(node.returns), True)))
            for owner, mname, fi in funcs:
                key = f"{m}:{owner or ''}.{mname}"
                pyowner = getattr(mods[m], owner) if owner else None
                for _ in range(CASES_PER_FUNCTION):
                    args, descs = [], []
                    for pname, pt in fi.params:
                        pv, pd = sampler.value(pt, pname, mname)
                        args.append(pv)
                        descs.append(pd)
                    if owner is None:
                        fn = getattr(mods[m], mname)
                    elif fi.static:
                        fn = getattr(pyowner, mname)
                    else:
                        fn = getattr(pyowner(), mname)
                    try:
                        ret = fn(*args)
                        out = {"ret": ser(types, ret), "args": [ser(types, a) for a in args]}
                    except Exception as exc:  # noqa: BLE001
                        out = {"throws": type(exc).__name__}
                    cases.append({"k": key, "in": descs, "out": out})
                dispatch.append((key, owner, mname, fi, m))

    vec_dir = ROOT / "test" / "sdk" / "vectors"
    vec_dir.mkdir(parents=True, exist_ok=True)
    (vec_dir / "codec_vectors.json").write_text(json.dumps(cases, separators=(",", ":")))
    print(f"{len(cases)} cases over {len(dispatch)} functions")

    write_dispatch(types, dispatch)


def write_dispatch(types: py2dart.Types, dispatch) -> None:
    lines = [
        "// GENERATED by tool/sdk_port/gen_vectors.py — do not edit.",
        "//",
        "// Replays each recorded call against the Dart port. Paired with",
        "// vectors/codec_vectors.json, which the Python SDK produced.",
        "//",
        "// ignore_for_file: prefer_const_constructors, unnecessary_lambdas, avoid_dynamic_calls, unused_local_variable",
        "",
        "import '../../lib/sdk/protocol/generated/moco.dart';",
        "import '../../lib/sdk/protocol/generated/head_module.dart';",
        "import '../../lib/sdk/protocol/generated/head_module_util.dart';",
        "import '../../lib/sdk/protocol/generated/slide_module.dart';",
        "import '../../lib/sdk/protocol/generated/slide_module_util.dart';",
        "",
        "typedef Decoder = Object? Function(Map<String, dynamic> desc);",
        "",
        "/// Builds an enum value from its name.",
        "Object enumByName(String cls, String name) => enumValues[cls]!.firstWhere((e) => (e as Enum).name == name);",
        "",
        "final Map<String, List<Object>> enumValues = {",
    ]
    for name, info in types.classes.items():
        if info.is_enum:
            lines.append(f"  '{name}': {name}.values,")
    lines += ["};", "", "/// Builds a data class, with its scalar fields set.", "Object makeObject(String cls, Map<String, dynamic> desc, Object? Function(Map<String, dynamic>) decode) {", "  switch (cls) {"]
    for name, info in types.classes.items():
        if info.is_enum:
            continue
        lines.append(f"    case '{name}':")
        if info.ctor_params:
            args = ", ".join(
                py2dart.camel(n) + ": " + cast(types, t, "decode(desc['ctor']['" + n + "'])")
                for n, t in info.ctor_params
            )
            lines.append(f"      return {name}({args});")
        else:
            lines.append(f"      final o = {name}();")
            lines.append("      final f = (desc['fields'] as Map<String, dynamic>?) ?? const {};")
            for fname, ft in info.fields.items():
                if ft in ("int", "double", "bool") or (ft in types.classes and types.classes[ft].is_enum):
                    value = cast(types, ft, "decode(f['" + fname + "'])")
                    lines.append(f"      if (f.containsKey('{fname}')) o.{py2dart.camel(fname)} = {value};")
            lines.append("      return o;")
    lines += ["  }", "  throw ArgumentError(cls);", "}", "", "/// Serialises a result the way gen_vectors.py does.", "Object? ser(Object? v) {",
              "  if (v == null || v is bool || v is int) return v;",
              "  if (v is double) {",
              "    if (v.isNaN) return {'f': 'NaN'};",
              "    if (v.isInfinite) return {'f': v > 0 ? 'Infinity' : '-Infinity'};",
              "    return {'f': v};",
              "  }",
              "  if (v is Enum) return {'e': v.name};",
              "  if (v is List) return [for (final x in v) ser(x)];",
              "  switch (v) {"]
    for name, info in types.classes.items():
        if info.is_enum:
            continue
        keys = [k for k, _ in info.ctor_params] if info.ctor_params else list(info.fields)
        body = ", ".join(f"'{py2dart.camel(k)}': ser(v.{py2dart.camel(k)})" for k in keys)
        lines.append(f"    case {name}(): return {{'o': '{name}', {body}}};")
    lines += ["  }", "  throw ArgumentError('cannot serialise ${v.runtimeType}');", "}", "",
              "typedef Call = Object? Function(List<Object?> a);", "", "final Map<String, Call> calls = {"]
    for key, owner, mname, fi, m in dispatch:
        dname = "fromValue" if mname == "from_value" else py2dart.camel(mname)
        args = ", ".join(cast(types, t, f"a[{i}]") for i, (_, t) in enumerate(fi.params))
        if owner is None:
            target = dname
        elif fi.static:
            target = f"{owner}.{dname}"
        else:
            target = f"{owner}().{dname}"
        lines.append(f"  '{key}': (a) => {target}({args}),")
    lines += ["};", ""]
    out = ROOT / "test" / "sdk" / "codec_dispatch.g.dart"
    out.write_text("\n".join(lines))
    print(f"wrote {out.relative_to(ROOT)}")


def cast(types: py2dart.Types, t: str, expr: str) -> str:
    inner = py2dart.list_of(t)
    if inner is not None:
        return f"({expr} as List).cast<{inner}>()"
    return f"{expr} as {t}"


if __name__ == "__main__":
    main()
