"""Deterministic input generation, per-language drivers, output comparison.

Single implementation of the input generator lives here; Rails only sends a
seed and a case count. User code never runs in this process — only in a
per-case subprocess with a timeout, a stdout cap, an empty stdin and a
secret-free env. Real containment (non-root, no net, tmpfs, cgroups) comes
from the Docker image.
"""
import ast
import json
import os
import random
import re
import shutil
import subprocess
import sys
import textwrap

LANGUAGES = ("python", "javascript", "ruby")
STDOUT_CAP = 65536
SAFE_MAX = 2 ** 53 - 1  # cross-language integer safety bound (spec review focus)


def _version(cmd):
    try:
        proc = subprocess.run(cmd, capture_output=True, timeout=10, text=True)
        lines = ((proc.stdout or "") + "\n" + (proc.stderr or "")).strip().splitlines()
        return lines[0].strip() if lines else "unknown"
    except Exception:
        return "missing"


RUNTIMES = {
    "python": _version([sys.executable, "--version"]),
    "node": _version(["node", "--version"]),
    "ruby": _version(["ruby", "--version"]),
}

# Drivers are appended to the user program. They read one JSON arg-list from
# argv, call solve(*args) and emit exactly one OUT:<json> line. Anything else
# on stdout (user prints) is ignored by the parser but counts toward the cap.
# No solve / wrong arity / exception / bad output value => nonzero exit or no
# OUT line => the case fails (attempt) or the input is dropped (reference).
_PY_DRIVER = """
import json as __dr_json, sys as __dr_sys
import inspect as __dr_inspect, asyncio as __dr_asyncio
try:
    __dr_args = __dr_json.loads(__dr_sys.argv[1])
except Exception:
    __dr_sys.exit(2)
try:
    __dr_fn = solve
except NameError:
    print("ERR:NameError: solve is not defined", file=__dr_sys.stderr)
    __dr_sys.exit(3)
try:
    __dr_out = __dr_fn(*__dr_args)
    if __dr_inspect.isawaitable(__dr_out):
        __dr_out = __dr_asyncio.run(__dr_out)
    __dr_sys.stdout.write("OUT:" + __dr_json.dumps(__dr_out, allow_nan=False))
except SystemExit:
    raise
except BaseException as __dr_e:
    print("ERR:%s: %s" % (type(__dr_e).__name__, __dr_e), file=__dr_sys.stderr)
    __dr_sys.exit(1)
"""

_JS_DRIVER = """
(async () => {
const __dr_args = JSON.parse(process.argv[2]);
let __dr_out;
try { __dr_out = await solve(...__dr_args); }
catch (__dr_e) { process.stderr.write("ERR:" + ((__dr_e && __dr_e.name) || "Error")); process.exit(1); }
if (__dr_out === undefined) __dr_out = null;
process.stdout.write("OUT:" + JSON.stringify(__dr_out));
})();
"""

_RB_DRIVER = """
require "json"
begin
  __dr_args = JSON.parse(ARGV[0])
  __dr_out = solve(*__dr_args)
  STDOUT.write("OUT:" + JSON.generate(__dr_out))
rescue SystemExit
  raise
rescue Exception => __dr_e
  STDERR.write("ERR:#{__dr_e.class}: #{__dr_e.message}\n")
  exit(1)
end
"""

DRIVERS = {"python": _PY_DRIVER, "javascript": _JS_DRIVER, "ruby": _RB_DRIVER}
# Resolve interpreters once, with the startup PATH: ad-hoc toolchains
# (fnm/rbenv shims) live outside /usr/bin. Spawn env carries PATH only —
# no secrets — so shims keep working and no system-ruby fallback sneaks in.
SPAWN_ENV = {"PATH": os.environ.get("PATH", "/usr/bin:/bin:/usr/local/bin")}


def _interp(name, argv0):
    if argv0 is not None:
        return [argv0]
    found = shutil.which(name, path=SPAWN_ENV["PATH"])
    return [found] if found else None


INTERPS = {"python": [sys.executable],
           "javascript": _interp("node", None),
           "ruby": _interp("ruby", None)}
EXTS = {"python": "py", "javascript": "js", "ruby": "rb"}


def write_program(tmpdir, stem, language, code):
    """Write user code + driver sentinel to a file; return its path."""
    if language == "python":
        code = textwrap.dedent(code)
    path = os.path.join(tmpdir, "%s.%s" % (stem, EXTS[language]))  # noqa: path stem is server-chosen ('ref'/'att'), never user input
    try:
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(code)
            if not code.endswith("\n"):
                handle.write("\n")
            handle.write(DRIVERS[language])
    except OSError as exc:
        # Callers treat this as runner failure: 500, job retries, stays pending.
        raise RuntimeError(f"cannot write program file: {exc}") from exc
    return path


def _count_params(raw):
    raw = raw.strip()
    if not raw:
        return 0
    if "{" in raw or "[" in raw or "*" in raw or "&" in raw:
        return None  # destructuring/splat: arity unknowable, caller reviews
    return len([part for part in raw.split(",") if part.strip()])


def get_arity(language, code):
    """Number of solve() params, or None when the entrypoint is unusable."""
    if language == "python":
        # Pasted code often arrives uniformly indented; dedent is a no-op
        # for normally formatted programs and rescues indented pastes.
        code = textwrap.dedent(code)
        try:
            tree = ast.parse(code)
        except SyntaxError:
            return None
        for node in ast.walk(tree):
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) \
                    and node.name == "solve":
                args = node.args
                if args.vararg or args.kwonlyargs or args.kwarg:
                    return None
                return len(args.args)
        return None
    if language == "javascript":
        patterns = [
            r"function\s+solve\s*\(([^)]*)\)",
            r"(?:const|let|var)\s+solve\s*=\s*(?:async\s*)?\(([^)]*)\)\s*=>",
            r"(?:const|let|var)\s+solve\s*=\s*(?:async\s*)?function\s*\(([^)]*)\)",
        ]
        for pattern in patterns:
            match = re.search(pattern, code)
            if match:
                return _count_params(match.group(1))
        return None
    if language == "ruby":
        match = re.search(r"def\s+solve(?:\s*\(([^)]*)\)|\s+([^\n;#:]*))?", code)
        if not match:
            return None
        raw = match.group(1) if match.group(1) is not None else (match.group(2) or "")
        return _count_params(raw)
    return None


EDGE_INTS = [0, 1, -1, 2, -2, 10, -10, 100, -100, 1000, -1000,
             2 ** 31 - 1, -(2 ** 31), 2 ** 31, SAFE_MAX, -SAFE_MAX]


def _rand_int(rng):
    roll = rng.random()
    if roll < 0.6:
        return rng.randint(-1000, 1000)
    if roll < 0.85:
        return rng.randint(-1000000, 1000000)
    return rng.randint(-SAFE_MAX, SAFE_MAX)


def _rand_list(rng):
    return [rng.randint(-100, 100) for _ in range(rng.randint(0, 8))]


def _rand_str(rng):
    return "".join(rng.choice("abcxyz") for _ in range(rng.randint(0, 6)))


def _gen_value(rng):
    roll = rng.random()
    if roll < 0.60:
        return _rand_int(rng)
    if roll < 0.88:
        return _rand_list(rng)
    return _rand_str(rng)


def gen_inputs(seed, count, arity):
    """Seed -> up to `count` arg-lists: edge cases, then PRNG values by type.

    Deterministic in (seed, count, arity). Broad by type on purpose: inputs the
    reference crashes on are dropped reference-first by the caller, so tasks
    with narrow domains (int-only, list-only) still get a large valid set.
    """
    rng = random.Random(seed)
    cases = []  # type: list
    if arity == 1:
        # Round-robin across types from position 0: small-N consumers (like
        # the 10-case creation dry-run) must see every shape, not scalars only.
        scalars = [[value] for value in EDGE_INTS]
        singles = [[[value]] for value in EDGE_INTS]
        mixed = [[], [""], ["abc"], [[]], [[1, 2, 3]], [[-5, 0, 5]],
                 ["hello world"], [[0]], ["a"], ["x" * 100]]
        for i in range(max(len(scalars), len(singles), len(mixed))):
            for group in (scalars, singles, mixed):
                if i < len(group):
                    cases.append(group[i])
    elif arity == 2:
        intpairs = []
        for value in EDGE_INTS[:8]:
            intpairs += [[value, value], [0, value], [value, 0]]
        mixed2 = [[[1, 2, 3], 2], [[], 0], [[5], -1], [[0], [1]], [["a"], ["b"]]]
        for i in range(max(len(intpairs), len(mixed2))):
            for group in (intpairs, mixed2):
                if i < len(group):
                    cases.append(group[i])
    elif arity > 2:
        cases += [[0] * arity, [1] * arity,
                  list(range(arity)), [-1] * arity]
    else:  # arity 0: nullary solve takes no inputs
        return [[]]
    while len(cases) < count:
        if arity:
            cases.append([_gen_value(rng) for _ in range(arity)])
        else:
            cases.append([])
    seen = []
    seen_keys = set()
    for case in cases:
        key = json.dumps(case, sort_keys=True)
        if key not in seen_keys:
            seen_keys.add(key)
            seen.append(case)
        if len(seen) >= count:
            break
    return seen[:count]


def canon(value):
    """Normalize one side's output so equivalent values compare equal across
    runtimes: tuples->lists, integral floats->int, dict keys sorted."""
    if isinstance(value, bool):
        return value
    if isinstance(value, float):
        if value.is_integer() and abs(value) < 2 ** 53:
            return int(value)
        return value
    if isinstance(value, (list, tuple)):
        return [canon(item) for item in value]
    if isinstance(value, dict):
        return {str(key): canon(value[key]) for key in sorted(value, key=str)}
    return value


def equal(first, second):
    return canon(first) == canon(second)


def _err_line(stderr_bytes, tmpdir):
    """Last stderr line, sanitized for reasons: no tmp paths, capped length."""
    try:
        text = (stderr_bytes or b"").decode("utf-8", errors="replace")
    except Exception:
        return None
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    if not lines:
        return None
    errs = [line[4:] for line in lines if line.startswith("ERR:")]
    line = errs[-1] if errs else lines[-1]
    line = line.replace(tmpdir, "<workdir>")
    return line[:200] if len(line) > 200 else line


def run_one(language, prog, args, timeout, cwd):
    """Run one case. Returns (status, value, err); value is set only for "ok".

    Statuses: ok | crash | timeout | truncated | bad_output. Tracebacks and
    program output never leave this function except one sanitized stderr line —
    the caller only reports counts, failing inputs and that line, so reference
    text and expected outputs cannot leak into reasons (spec section 4).
    """
    cmd = INTERPS[language]
    if cmd is None:  # runtime missing: every case fails, caller reviews
        return ("crash", None, "runtime missing")
    cmd = cmd + [prog, json.dumps(args)]
    try:
        proc = subprocess.run(cmd, stdin=subprocess.DEVNULL,
                              capture_output=True,
                              timeout=timeout, cwd=cwd, env=SPAWN_ENV)
    except subprocess.TimeoutExpired:
        return ("timeout", None, None)
    except Exception:
        return ("crash", None, None)
    out = proc.stdout or b""
    if len(out) > STDOUT_CAP:
        return ("truncated", None, None)
    if proc.returncode != 0:
        return ("crash", None, _err_line(proc.stderr, cwd))
    try:
        text = out.decode("utf-8", errors="strict")
    except Exception:
        return ("bad_output", None, None)
    for line in text.splitlines():
        if line.startswith("OUT:"):
            try:
                return ("ok", json.loads(line[4:]), None)
            except Exception:
                return ("bad_output", None, None)
    return ("bad_output", None, None)
