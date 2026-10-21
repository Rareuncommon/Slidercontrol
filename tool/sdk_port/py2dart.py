"""Transpiles the edelkrone SDK's generated protocol codecs from Python to Dart.

The SDK's `protocol/_generated/*.py` files are themselves a mechanical
transliteration of Dart (the official app's protocol library): they model
Dart's 64-bit integers with `i64`/`shl`/`ushr`, Dart division with `dart_div`,
Dart enums with `DartEnum`, and so on. This turns them back into Dart.

It handles exactly the restricted subset those files use and refuses anything
else, loudly, rather than guessing. The output is then checked byte for byte
against the Python originals by `test/sdk/codec_vectors_test.dart`, using
vectors that `gen_vectors.py` produces by running the Python SDK itself.

Typing is the one thing Python leaves implicit and Dart does not. A small
inference pass assigns every expression `int`, `double`, `bool`, an enum or
class name, or a list type, from the annotations in the source. An int-typed
value stored into a double-typed slot is widened with `.toDouble()`; a
double-typed value stored into an int-typed slot is refused, because in
Python that would silently store a float and in Dart it cannot.

Usage:
    python3 -I py2dart.py <out_dir> <module.py>...

Not part of the app. Run by hand when the SDK is updated.
"""

from __future__ import annotations

import ast
import keyword
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

INT, DOUBLE, BOOL, STRING, VOID, DYN = "int", "double", "bool", "String", "void", "dynamic"

DART_RESERVED = {
    "abstract", "as", "assert", "async", "await", "break", "case", "catch",
    "class", "const", "continue", "covariant", "default", "deferred", "do",
    "dynamic", "else", "enum", "export", "extends", "extension", "external",
    "factory", "false", "final", "finally", "for", "Function", "get", "hide",
    "if", "implements", "import", "in", "interface", "is", "late", "library",
    "mixin", "new", "null", "on", "operator", "part", "required", "rethrow",
    "return", "set", "show", "static", "super", "switch", "sync", "this",
    "throw", "true", "try", "typedef", "var", "void", "while", "with",
    "yield",
}


class Refused(Exception):
    pass


def camel(name: str) -> str:
    """snake_case -> lowerCamelCase, preserving a leading underscore."""
    lead = "_" if name.startswith("_") else ""
    parts = [p for p in name.strip("_").split("_") if p != ""]
    if not parts:
        return name
    out = parts[0] + "".join(p[:1].upper() + p[1:] for p in parts[1:])
    out = lead + out
    if out in DART_RESERVED:
        out += "_"
    return out


def list_of(t: str) -> str | None:
    m = re.fullmatch(r"List<(.+)>", t)
    return m.group(1) if m else None


@dataclass
class ClassInfo:
    name: str
    is_enum: bool = False
    members: dict[str, int] = field(default_factory=dict)  # enum constants
    fields: dict[str, str] = field(default_factory=dict)  # py name -> dart type
    ctor_params: list[tuple[str, str]] = field(default_factory=list)
    methods: dict[str, "FuncInfo"] = field(default_factory=dict)
    module: str = ""


@dataclass
class FuncInfo:
    name: str
    params: list[tuple[str, str]]
    returns: str
    static: bool


class Types:
    """Everything known about every class and global across all inputs."""

    def __init__(self) -> None:
        self.classes: dict[str, ClassInfo] = {}
        self.globals: dict[str, str] = {}

    def ann(self, node: ast.expr | None) -> str:
        if node is None:
            return VOID
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            return self.ann(ast.parse(node.value, mode="eval").body)
        if isinstance(node, ast.Constant) and node.value is None:
            return VOID
        if isinstance(node, ast.Name):
            return {"int": INT, "float": DOUBLE, "bool": BOOL, "str": STRING, "None": VOID}.get(
                node.id, node.id
            )
        if isinstance(node, ast.Subscript) and isinstance(node.value, ast.Name) and node.value.id == "list":
            return f"List<{self.ann(node.slice)}>"
        raise Refused(f"annotation {ast.unparse(node)}")


def collect(types: Types, module: str, tree: ast.Module) -> None:
    for node in tree.body:
        if isinstance(node, ast.ClassDef):
            info = ClassInfo(node.name, module=module)
            info.is_enum = any(ast.unparse(b) == "DartEnum" for b in node.bases)
            for item in node.body:
                if isinstance(item, ast.Assign) and info.is_enum:
                    info.members[item.targets[0].id] = ast.literal_eval(item.value)
                elif isinstance(item, ast.FunctionDef):
                    if item.name == "__init__":
                        for a in item.args.args[1:]:
                            info.ctor_params.append((a.arg, types.ann(a.annotation)))
                        for st in item.body:
                            if isinstance(st, ast.AnnAssign):
                                info.fields[st.target.attr] = types.ann(st.annotation)
                            elif isinstance(st, ast.Assign):
                                tgt = st.targets[0]
                                if isinstance(tgt, ast.Attribute):
                                    # Typed by its constructor parameter.
                                    p = dict(info.ctor_params).get(
                                        st.value.id if isinstance(st.value, ast.Name) else ""
                                    )
                                    if p is None:
                                        raise Refused(f"untyped field {node.name}.{tgt.attr}")
                                    info.fields[tgt.attr] = p
                    else:
                        static = any(
                            ast.unparse(d) in ("staticmethod", "classmethod") for d in item.decorator_list
                        )
                        args = item.args.args
                        if not static or any(ast.unparse(d) == "classmethod" for d in item.decorator_list):
                            args = args[1:]
                        params = [(a.arg, types.ann(a.annotation)) for a in args]
                        rtype = types.ann(item.returns)
                        if rtype in ("cls",):
                            rtype = node.name
                        info.methods[item.name] = FuncInfo(item.name, params, rtype, static)
            types.classes[node.name] = info
        elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
            types.globals[node.target.id] = types.ann(node.annotation)


HELPER_INT = {"i64", "idx", "shl", "ushr", "to_int", "dart_round", "to_signed", "length"}


class Emitter:
    def __init__(self, types: Types, module: str, source: str) -> None:
        self.types = types
        self.module = module
        self.source = source
        self.out: list[str] = []
        self.indent = 0
        self.locals: dict[str, str] = {}
        self.declared: set[str] = set()
        self.cls: ClassInfo | None = None
        self.used_log = False

    # -- output ---------------------------------------------------------------

    def line(self, text: str = "") -> None:
        self.out.append(("  " * self.indent + text) if text else "")

    # -- types ----------------------------------------------------------------

    def type_of(self, e: ast.expr) -> str:
        t = self.types
        if isinstance(e, ast.Constant):
            if isinstance(e.value, bool):
                return BOOL
            if isinstance(e.value, int):
                return INT
            if isinstance(e.value, float):
                return DOUBLE
            if isinstance(e.value, str):
                return STRING
            if e.value is None:
                return VOID
        if isinstance(e, ast.JoinedStr):
            return STRING
        if isinstance(e, ast.Name):
            if e.id in ("True", "False"):
                return BOOL
            if e.id == "cls" and self.cls is not None:
                return "type:" + self.cls.name
            if e.id == "self" and self.cls is not None:
                return self.cls.name
            if e.id in self.locals:
                return self.locals[e.id]
            if e.id in t.globals:
                return t.globals[e.id]
            if e.id in t.classes:
                return "type:" + e.id
            raise Refused(f"unknown name {e.id}")
        if isinstance(e, ast.Attribute):
            base = self.type_of(e.value)
            if base.startswith("type:"):
                cls = t.classes[base[5:]]
                if cls.is_enum and e.attr in cls.members:
                    return cls.name
                if e.attr in cls.methods:
                    return "method:" + cls.name + "." + e.attr
                raise Refused(f"unknown attribute {ast.unparse(e)}")
            if base in t.classes:
                cls = t.classes[base]
                if cls.is_enum:
                    if e.attr == "value":
                        return INT
                    if e.attr == "index":
                        return INT
                    if e.attr == "name":
                        return STRING
                if e.attr in cls.fields:
                    return cls.fields[e.attr]
                if e.attr in cls.methods:
                    return "method:" + cls.name + "." + e.attr
            raise Refused(f"cannot type attribute {ast.unparse(e)} on {base}")
        if isinstance(e, ast.Subscript):
            base = self.type_of(e.value)
            inner = list_of(base)
            if inner is None:
                raise Refused(f"subscript on {base}: {ast.unparse(e)}")
            return inner
        if isinstance(e, ast.BinOp):
            a, b = self.type_of(e.left), self.type_of(e.right)
            if isinstance(e.op, (ast.BitAnd, ast.BitOr, ast.BitXor, ast.RShift, ast.LShift)):
                if a != INT or b != INT:
                    raise Refused(f"bitwise on {a},{b}: {ast.unparse(e)}")
                return INT
            if isinstance(e.op, ast.Div):
                raise Refused(f"bare / (should be dart_div): {ast.unparse(e)}")
            if isinstance(e.op, (ast.Add, ast.Sub, ast.Mult)):
                if a == STRING and b == STRING and isinstance(e.op, ast.Add):
                    return STRING
                if a not in (INT, DOUBLE) or b not in (INT, DOUBLE):
                    raise Refused(f"arithmetic on {a},{b}: {ast.unparse(e)}")
                return DOUBLE if DOUBLE in (a, b) else INT
            raise Refused(f"operator {type(e.op).__name__}")
        if isinstance(e, ast.UnaryOp):
            if isinstance(e.op, ast.Not):
                return BOOL
            return self.type_of(e.operand)
        if isinstance(e, (ast.Compare, ast.BoolOp)):
            return BOOL
        if isinstance(e, ast.IfExp):
            a, b = self.type_of(e.body), self.type_of(e.orelse)
            if a == b:
                return a
            if {a, b} == {INT, DOUBLE}:
                return DOUBLE
            raise Refused(f"ifexp {a}/{b}: {ast.unparse(e)}")
        if isinstance(e, ast.Call):
            return self.call_type(e)
        if isinstance(e, ast.List):
            if not e.elts:
                raise Refused("empty list literal")
            return f"List<{self.type_of(e.elts[0])}>"
        if isinstance(e, ast.Lambda):
            return "lambda"
        raise Refused(f"cannot type {type(e).__name__}: {ast.unparse(e)}")

    def call_type(self, e: ast.Call) -> str:
        f = e.func
        if isinstance(f, ast.Name):
            n = f.id
            if n in HELPER_INT:
                return INT
            if n == "dart_div" or n == "float":
                return DOUBLE
            if n == "dart_abs":
                return self.type_of(e.args[0])
            if n == "list":
                inner = self.type_of(e.args[0])
                if inner.startswith("type:"):
                    return f"List<{inner[5:]}>"
                raise Refused(f"list({inner})")
            if n == "list_filled":
                return f"List<{self.type_of(e.args[1])}>"
            if n == "list_generate":
                lam = e.args[1]
                return f"List<{self.lambda_body_type(lam)}>"
            if n == "sublist":
                return self.type_of(e.args[0])
            if n == "first_where":
                inner = list_of(self.type_of(e.args[0]))
                if inner is None:
                    raise Refused("first_where over non-list")
                return inner
            if n in ("put16b", "make16b"):
                return VOID if n == "put16b" else INT
            if n == "ValueError":
                return "ValueError"
            if n in self.types.classes:
                return n
            if n == "range":
                return "range"
            raise Refused(f"unknown function {n}")
        if isinstance(f, ast.Attribute):
            if isinstance(f.value, ast.Name) and f.value.id == "EdelkroneLog":
                return VOID
            mt = self.type_of(f)
            if mt.startswith("method:"):
                cname, mname = mt[7:].split(".")
                fi = self.types.classes[cname].methods[mname]
                return fi.returns
        raise Refused(f"cannot type call {ast.unparse(e)}")

    def lambda_body_type(self, lam: ast.Lambda) -> str:
        saved = dict(self.locals)
        for a in lam.args.args:
            self.locals[a.arg] = INT
        try:
            return self.type_of(lam.body)
        finally:
            self.locals = saved

    # -- expressions ----------------------------------------------------------

    def src(self, e: ast.AST) -> str:
        seg = ast.get_source_segment(self.source, e)
        return seg if seg is not None else ast.unparse(e)

    def expr(self, e: ast.expr, want: str | None = None) -> str:
        """Emits [e]; widens an int to double when [want] is double."""
        if (
            want is not None
            and list_of(want) == DOUBLE
            and isinstance(e, ast.Call)
            and isinstance(e.func, ast.Name)
            and e.func.id == "list_filled"
            and self.type_of(e.args[1]) == INT
        ):
            # Python stores int zeros in a list annotated float; Dart cannot.
            return f"List<double>.filled({self._expr(e.args[0])}, {self.expr(e.args[1], DOUBLE)})"
        text = self._expr(e)
        if want is not None:
            have = self.type_of(e)
            if want == DOUBLE and have == INT:
                if isinstance(e, ast.Constant):
                    return f"{e.value}.0" if "x" not in self.src(e).lower() else f"({text}).toDouble()"
                return f"({text}).toDouble()"
            if want == INT and have == DOUBLE:
                raise Refused(f"double stored into int: {ast.unparse(e)}")
        return text

    def _expr(self, e: ast.expr) -> str:
        if isinstance(e, ast.Constant):
            if isinstance(e.value, bool):
                return "true" if e.value else "false"
            if e.value is None:
                return "null"
            if isinstance(e.value, str):
                return repr(e.value).replace("$", r"\$")
            return self.src(e)
        if isinstance(e, ast.JoinedStr):
            parts = []
            for v in e.values:
                if isinstance(v, ast.Constant):
                    parts.append(v.value.replace("\\", "\\\\").replace("'", "\\'").replace("$", r"\$"))
                elif isinstance(v, ast.FormattedValue):
                    if v.format_spec is not None or v.conversion != -1:
                        raise Refused("f-string format spec")
                    parts.append("${" + self._expr(v.value) + "}")
            return "'" + "".join(parts) + "'"
        if isinstance(e, ast.Name):
            if e.id == "True":
                return "true"
            if e.id == "False":
                return "false"
            if e.id in self.types.classes:
                return e.id
            return camel(e.id)
        if isinstance(e, ast.Attribute):
            base_t = self.type_of(e.value)
            if base_t.startswith("type:"):
                cls = self.types.classes[base_t[5:]]
                if cls.is_enum and e.attr in cls.members:
                    return f"{cls.name}.{e.attr}"
                if e.attr in cls.methods:
                    return f"{cls.name}.{camel(e.attr)}"
            if isinstance(e.value, ast.Name) and e.value.id == "self":
                return camel(e.attr)
            if isinstance(e.value, ast.Name) and e.value.id == "cls":
                return e.attr
            return f"{self._expr(e.value)}.{camel(e.attr) if e.attr not in ('value', 'index', 'name') else e.attr}"
        if isinstance(e, ast.Subscript):
            return f"{self._expr(e.value)}[{self._expr(e.slice)}]"
        if isinstance(e, ast.BinOp):
            op = {
                ast.Add: "+", ast.Sub: "-", ast.Mult: "*", ast.BitAnd: "&",
                ast.BitOr: "|", ast.BitXor: "^", ast.RShift: ">>", ast.LShift: "<<",
            }[type(e.op)]
            return f"({self._expr(e.left)} {op} {self._expr(e.right)})"
        if isinstance(e, ast.UnaryOp):
            if isinstance(e.op, ast.Not):
                if self.type_of(e.operand) != BOOL:
                    raise Refused(f"not on non-bool: {ast.unparse(e)}")
                return f"!{self._expr(e.operand)}"
            if isinstance(e.op, ast.USub):
                return f"-{self._expr(e.operand)}"
            raise Refused("unary op")
        if isinstance(e, ast.Compare):
            if len(e.ops) != 1:
                raise Refused(f"chained compare {ast.unparse(e)}")
            op = {
                ast.Eq: "==", ast.NotEq: "!=", ast.Gt: ">", ast.GtE: ">=",
                ast.Lt: "<", ast.LtE: "<=", ast.Is: "==", ast.IsNot: "!=",
            }.get(type(e.ops[0]))
            if op is None:
                raise Refused(f"compare op {type(e.ops[0]).__name__}")
            return f"({self._expr(e.left)} {op} {self._expr(e.comparators[0])})"
        if isinstance(e, ast.BoolOp):
            for v in e.values:
                if self.type_of(v) != BOOL:
                    raise Refused(f"boolop on non-bool: {ast.unparse(e)}")
            op = " && " if isinstance(e.op, ast.And) else " || "
            return "(" + op.join(self._expr(v) for v in e.values) + ")"
        if isinstance(e, ast.IfExp):
            t = self.type_of(e)
            return f"({self.cond(e.test)} ? {self.expr(e.body, t)} : {self.expr(e.orelse, t)})"
        if isinstance(e, ast.Call):
            return self.call(e)
        if isinstance(e, ast.List):
            inner = self.type_of(e)
            return "<" + list_of(inner) + ">[" + ", ".join(self._expr(x) for x in e.elts) + "]"
        if isinstance(e, ast.Lambda):
            args = ", ".join(camel(a.arg) for a in e.args.args)
            saved = dict(self.locals)
            for a in e.args.args:
                self.locals.setdefault(a.arg, DYN)
            try:
                return f"({args}) => {self._expr(e.body)}"
            finally:
                self.locals = saved
        raise Refused(f"expression {type(e).__name__}: {ast.unparse(e)}")

    def cond(self, e: ast.expr) -> str:
        t = self.type_of(e)
        if t == BOOL:
            return self._expr(e)
        if t == INT:
            return f"({self._expr(e)} != 0)"
        raise Refused(f"condition of type {t}: {ast.unparse(e)}")

    def call(self, e: ast.Call) -> str:
        f = e.func
        if e.keywords and not (isinstance(f, ast.Name) and f.id in self.types.classes):
            raise Refused(f"keyword args: {ast.unparse(e)}")
        a = e.args
        if isinstance(f, ast.Name):
            n = f.id
            if n in ("i64", "idx"):
                return self._expr(a[0])
            if n == "shl":
                return f"({self._expr(a[0])} << {self._expr(a[1])})"
            if n == "ushr":
                return f"({self._expr(a[0])} >>> {self._expr(a[1])})"
            if n == "dart_div":
                return f"({self.expr(a[0], DOUBLE)} / {self.expr(a[1], DOUBLE)})"
            if n == "to_int":
                if self.type_of(a[0]) == INT:
                    return self._expr(a[0])
                return f"({self._expr(a[0])}).toInt()"
            if n == "dart_round":
                if self.type_of(a[0]) == INT:
                    return self._expr(a[0])
                return f"({self._expr(a[0])}).round()"
            if n == "dart_abs":
                return f"({self._expr(a[0])}).abs()"
            if n == "to_signed":
                return f"({self._expr(a[0])}).toSigned({self._expr(a[1])})"
            if n == "float":
                return f"({self._expr(a[0])}).toDouble()"
            if n == "length":
                return f"{self._expr(a[0])}.length"
            if n == "sublist":
                end = f", {self._expr(a[2])}" if len(a) > 2 else ""
                return f"{self._expr(a[0])}.sublist({self._expr(a[1])}{end})"
            if n == "list":
                return f"{self._expr(a[0])}.values"
            if n == "list_filled":
                return f"List<{list_of(self.type_of(e))}>.filled({self._expr(a[0])}, {self._expr(a[1])})"
            if n == "list_generate":
                return f"List<{list_of(self.type_of(e))}>.generate({self._expr(a[0])}, {self._expr(a[1])})"
            if n == "first_where":
                inner = list_of(self.type_of(a[0]))
                saved = dict(self.locals)
                lam = a[1]
                for p in lam.args.args:
                    self.locals[p.arg] = inner
                try:
                    test = self._expr(lam)
                finally:
                    self.locals = saved
                if len(a) > 2:
                    return f"{self._expr(a[0])}.firstWhere({test}, orElse: {self._expr(a[2])})"
                return f"{self._expr(a[0])}.firstWhere({test})"
            if n == "ValueError":
                return f"ArgumentError({self._expr(a[0])})"
            if n in ("put16b", "make16b"):
                return f"{camel(n)}({', '.join(self._expr(x) for x in a)})"
            if n in self.types.classes:
                cls = self.types.classes[n]
                if e.args:
                    raise Refused(f"positional ctor args: {ast.unparse(e)}")
                kw = dict(cls.ctor_params)
                parts = [f"{camel(k.arg)}: {self.expr(k.value, kw.get(k.arg))}" for k in e.keywords]
                return f"{n}({', '.join(parts)})"
            raise Refused(f"call {n}")
        if isinstance(f, ast.Attribute):
            if isinstance(f.value, ast.Name) and f.value.id == "EdelkroneLog":
                self.used_log = True
                return f"EdelkroneLog.{f.attr}({', '.join(self._expr(x) for x in a)})"
            mt = self.type_of(f)
            if mt.startswith("method:"):
                cname, mname = mt[7:].split(".")
                fi = self.types.classes[cname].methods[mname]
                if len(a) != len(fi.params):
                    raise Refused(f"arity {ast.unparse(e)}")
                args = ", ".join(self.expr(x, pt) for x, (_, pt) in zip(a, fi.params))
                return f"{self._expr(f)}({args})"
        raise Refused(f"call {ast.unparse(e)}")

    # -- statements -------------------------------------------------------------

    def infer_locals(self, body: list[ast.stmt], params: dict[str, str]) -> dict[str, str]:
        """Unifies every assignment to each local, so a variable that is ever a
        double is declared a double."""
        found: dict[str, str] = dict(params)
        names: list[str] = []
        self.loop_vars: set[str] = set()

        def visit(stmts: list[ast.stmt]) -> None:
            for st in stmts:
                if isinstance(st, (ast.Assign, ast.AnnAssign)):
                    tgt = st.targets[0] if isinstance(st, ast.Assign) else st.target
                    if isinstance(tgt, ast.Name) and tgt.id not in self.types.globals:
                        self.locals = found
                        if isinstance(st, ast.AnnAssign):
                            t = self.types.ann(st.annotation)
                        else:
                            t = self.type_of(st.value)
                        prev = found.get(tgt.id)
                        if prev is None:
                            found[tgt.id] = t
                            names.append(tgt.id)
                        elif prev != t:
                            if {prev, t} == {INT, DOUBLE}:
                                found[tgt.id] = DOUBLE
                            else:
                                raise Refused(f"local {tgt.id} is {prev} and {t}")
                elif isinstance(st, ast.For):
                    found.setdefault(st.target.id, INT)
                    self.loop_vars.add(st.target.id)
                    visit(st.body)
                elif isinstance(st, ast.If):
                    visit(st.body)
                    visit(st.orelse)

        # Two passes, so a later double reaches an earlier int.
        visit(body)
        visit(body)
        return found

    def function(self, fn: ast.FunctionDef, info: FuncInfo, owner: ClassInfo | None) -> None:
        params = dict(info.params)
        self.locals = self.infer_locals(fn.body, params)
        self.declared = set(params)
        self.returns = info.returns
        sig = ", ".join(f"{t} {camel(n)}" for n, t in info.params)
        static = "static " if (owner is not None and info.static) else ""
        name = "fromValue" if fn.name == "from_value" else camel(fn.name)
        self.line(f"{static}{info.returns} {name}({sig}) {{")
        self.indent += 1
        # Python scopes a local to the whole function; Dart to its block. A
        # variable first assigned inside one loop and read in the next is
        # legal Python and a compile error in Dart, so declare them all here.
        for local, t in self.locals.items():
            if local in params or local in self.loop_vars or local in self.types.globals:
                continue
            self.line(f"late {t} {camel(local)};")
            self.declared.add(local)
        self.block(fn.body)
        self.indent -= 1
        self.line("}")

    def block(self, stmts: list[ast.stmt]) -> None:
        for st in stmts:
            self.stmt(st)

    def target(self, tgt: ast.expr) -> tuple[str, str]:
        """Returns (dart lvalue, its type)."""
        if isinstance(tgt, ast.Name):
            return camel(tgt.id), self.locals.get(tgt.id) or self.types.globals[tgt.id]
        if isinstance(tgt, ast.Attribute):
            return self._expr(tgt), self.type_of(tgt)
        if isinstance(tgt, ast.Subscript):
            return self._expr(tgt), self.type_of(tgt)
        raise Refused(f"target {ast.unparse(tgt)}")

    def stmt(self, st: ast.stmt) -> None:
        if isinstance(st, ast.Expr):
            if isinstance(st.value, ast.Constant) and isinstance(st.value.value, str):
                return  # docstring
            self.line(self._expr(st.value) + ";")
            return
        if isinstance(st, ast.Global):
            return
        if isinstance(st, ast.Pass):
            return
        if isinstance(st, (ast.Assign, ast.AnnAssign)):
            tgt = st.targets[0] if isinstance(st, ast.Assign) else st.target
            if isinstance(st, ast.Assign) and len(st.targets) != 1:
                raise Refused("multiple targets")
            lv, t = self.target(tgt)
            rv = self.expr(st.value, t)
            if isinstance(tgt, ast.Name) and tgt.id not in self.declared and tgt.id not in self.types.globals:
                self.declared.add(tgt.id)
                self.line(f"{t} {lv} = {rv};")
            else:
                self.line(f"{lv} = {rv};")
            return
        if isinstance(st, ast.Return):
            if st.value is None:
                self.line("return;")
            else:
                self.line(f"return {self.expr(st.value, self.returns if self.returns in (INT, DOUBLE) else None)};")
            return
        if isinstance(st, ast.If):
            self.line(f"if ({self.cond(st.test)}) {{")
            self.indent += 1
            self.block(st.body)
            self.indent -= 1
            orelse = st.orelse
            while len(orelse) == 1 and isinstance(orelse[0], ast.If):
                inner = orelse[0]
                self.line(f"}} else if ({self.cond(inner.test)}) {{")
                self.indent += 1
                self.block(inner.body)
                self.indent -= 1
                orelse = inner.orelse
            if orelse:
                self.line("} else {")
                self.indent += 1
                self.block(orelse)
                self.indent -= 1
            self.line("}")
            return
        if isinstance(st, ast.For):
            it = st.iter
            if not (isinstance(it, ast.Call) and isinstance(it.func, ast.Name) and it.func.id == "range"):
                raise Refused(f"for over {ast.unparse(it)}")
            a = it.args
            start, stop, step = ("0", a[0], None) if len(a) == 1 else (self._expr(a[0]), a[1], a[2] if len(a) > 2 else None)
            v = camel(st.target.id)
            self.declared.add(st.target.id)
            if step is None:
                self.line(f"for (var {v} = {start}; {v} < {self._expr(stop)}; {v}++) {{")
            else:
                s = self._expr(step)
                cmp = ">" if s.startswith("-") else "<"
                self.line(f"for (var {v} = {start}; {v} {cmp} {self._expr(stop)}; {v} += {s}) {{")
            self.indent += 1
            self.block(st.body)
            self.indent -= 1
            self.line("}")
            return
        if isinstance(st, ast.Continue):
            self.line("continue;")
            return
        if isinstance(st, ast.Raise):
            self.line(f"throw {self._expr(st.exc)};")
            return
        raise Refused(f"statement {type(st).__name__}: {ast.unparse(st)[:80]}")

    # -- top level ----------------------------------------------------------------

    def enum(self, c: ClassInfo, node: ast.ClassDef) -> None:
        doc = ast.get_docstring(node)
        if doc:
            self.line(f"/// {doc}")
        self.line(f"enum {c.name} {{")
        self.indent += 1
        items = list(c.members.items())
        for i, (k, v) in enumerate(items):
            end = "," if i < len(items) - 1 else ";"
            self.line(f"{k}({self._literal(node, k)}){end}")
        self.line()
        self.line(f"const {c.name}(this.value);")
        self.line("final int value;")
        for item in node.body:
            if isinstance(item, ast.FunctionDef):
                self.line()
                self.cls = c
                self.function(item, c.methods[item.name], c)
        self.indent -= 1
        self.line("}")

    def _literal(self, node: ast.ClassDef, member: str) -> str:
        for item in node.body:
            if isinstance(item, ast.Assign) and item.targets[0].id == member:
                return self.src(item.value)
        raise Refused(member)

    def data_class(self, c: ClassInfo, node: ast.ClassDef) -> None:
        self.line(f"class {c.name} {{")
        self.indent += 1
        init = next((i for i in node.body if isinstance(i, ast.FunctionDef) and i.name == "__init__"), None)
        if c.ctor_params:
            params = ", ".join(f"required this.{camel(n)}" for n, _ in c.ctor_params)
            self.line(f"{c.name}({{{params}}});")
            self.line()
            for n, t in c.ctor_params:
                self.line(f"{t} {camel(n)};")
        elif init is not None:
            self.locals = {}
            for st in init.body:
                if isinstance(st, ast.AnnAssign):
                    t = self.types.ann(st.annotation)
                    self.line(f"{t} {camel(st.target.attr)} = {self.expr(st.value, t)};")
                elif isinstance(st, ast.Expr):
                    continue
                elif isinstance(st, ast.Pass):
                    continue
                else:
                    raise Refused(f"__init__ statement {ast.unparse(st)[:80]}")
        for item in node.body:
            if isinstance(item, ast.FunctionDef) and item.name != "__init__":
                self.line()
                self.cls = c
                self.function(item, c.methods[item.name], c)
        self.indent -= 1
        self.line("}")

    def module_body(self, tree: ast.Module) -> None:
        for node in tree.body:
            if isinstance(node, (ast.ImportFrom, ast.Import)):
                continue
            if isinstance(node, ast.Expr):
                continue
            if isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
                t = self.types.ann(node.annotation)
                self.locals = {}
                self.line(f"{t} {camel(node.target.id)} = {self.expr(node.value, t)};")
                self.line()
                continue
            if isinstance(node, ast.ClassDef):
                c = self.types.classes[node.name]
                if c.is_enum:
                    self.enum(c, node)
                else:
                    self.data_class(c, node)
                self.line()
                continue
            if isinstance(node, ast.FunctionDef):
                params = [(a.arg, self.types.ann(a.annotation)) for a in node.args.args]
                info = FuncInfo(node.name, params, self.types.ann(node.returns), False)
                self.function(node, info, None)
                self.line()
                continue
            raise Refused(f"top-level {type(node).__name__}")


def module_level_functions(types: Types, tree: ast.Module) -> None:
    """Registers module-level helpers (moco's put16b/make16b) as known calls."""
    # Handled by name in Emitter.call; nothing to record.


HEADER = """// GENERATED FILE — do not edit by hand.
//
// Transpiled from the edelkrone Python SDK {version} ({src}) by
// tool/sdk_port/py2dart.py. That file is itself a transliteration of the
// official edelkrone app's Dart protocol library, so this is a round trip back
// to Dart. Verified byte for byte against the Python original by
// test/sdk/codec_vectors_test.dart.
//
// Copyright (c) 2026 edelkrone. MIT licensed; see lib/sdk/LICENSE.
//
// ignore_for_file: constant_identifier_names, non_constant_identifier_names, unnecessary_parenthesis, prefer_final_locals, unused_local_variable, prefer_const_constructors, unnecessary_this, prefer_initializing_formals, unused_import, curly_braces_in_flow_control_structures, unnecessary_brace_in_string_interps, dead_code
"""


def main() -> None:
    out_dir = Path(sys.argv[1])
    version = sys.argv[2]
    paths = [Path(p) for p in sys.argv[3:]]
    types = Types()
    trees = {}
    for p in paths:
        src = p.read_text()
        tree = ast.parse(src)
        trees[p] = (src, tree)
        collect(types, p.stem, tree)

    imports = {
        "moco": [],
        "head_module_util": [],
        "slide_module_util": [],
        "head_module": ["moco.dart", "head_module_util.dart", "../../log.dart"],
        "slide_module": ["moco.dart", "slide_module_util.dart", "../../log.dart"],
    }
    failures = 0
    for p, (src, tree) in trees.items():
        em = Emitter(types, p.stem, src)
        try:
            em.module_body(tree)
        except Refused as exc:
            print(f"REFUSED {p.name}: {exc}", file=sys.stderr)
            failures += 1
            continue
        head = HEADER.format(version=version, src=f"protocol/_generated/{p.name}")
        imp = "".join(f"import '{i}';\n" for i in imports.get(p.stem, []))
        body = "\n".join(em.out).rstrip() + "\n"
        body = re.sub(r"\n{3,}", "\n\n", body)
        (out_dir / f"{p.stem}.dart").write_text(head + "\n" + imp + ("\n" if imp else "") + body)
        print(f"wrote {p.stem}.dart ({len(em.out)} lines)")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
