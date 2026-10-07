#!/usr/bin/env python3
"""Contract + security tests for coderunner (Task 2).

Starts coderunner/server.py over loopback HTTP and POSTs run_check pairs:
- 15 same-behavior pairs (loop-vs-builtin, iter-vs-recursion, rename,
  for-vs-while, cross-language py/js + py/ruby) must FULLY pass;
- 15 different-behavior pairs (off-by-one, plus-vs-minus, max-vs-min, ...)
  must MISMATCH (passed < total);
- security asserts: reasons/failed samples carry no reference text or
  expected outputs; unknown language is refused pre-execution; oversized
  stdout is truncated and fails the case; nondeterministic reference and
  slow attempt are caught.

References carry narrow type guards (int-only / list-only) so the valid set
is exactly the task domain; attempts run only on valid inputs. Loop/recursion
variants always sit on the reference side (or on both sides with equal cost):
a slow reference drops the input, a slow attempt would mismatch.

Usage: python3 coderunner/test_security.py
"""
import http.client
import importlib.util
import json
import os
import sys
import threading
import time
from http.server import ThreadingHTTPServer

ROOT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, ROOT)
spec = importlib.util.spec_from_file_location(
    "coderunner_server", os.path.join(ROOT, "server.py"))
assert spec is not None and spec.loader is not None
server = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server)

httpd = ThreadingHTTPServer(("127.0.0.1", 0), server.Handler)
port = httpd.server_address[1]
threading.Thread(target=httpd.serve_forever, daemon=True).start()


def post(path, obj=None, timeout=180):
    body = json.dumps(obj or {}).encode()
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=timeout)
    conn.request("POST", path, body=body,
                 headers={"Content-Type": "application/json"})
    resp = conn.getresponse()
    payload = resp.read()
    conn.close()
    return resp.status, json.loads(payload)


def get(path):
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=15)
    conn.request("GET", path)
    resp = conn.getresponse()
    payload = json.loads(resp.read())
    conn.close()
    return resp.status, payload


INT1 = ("    if not isinstance(x, int):\n"
        "        raise TypeError('int only')\n")
INT2 = ("    if not isinstance(a, int) or not isinstance(b, int):\n"
        "        raise TypeError('int only')\n")
LIST = ("    if not isinstance(xs, list):\n"
        "        raise TypeError('list only')\n")


def py1(body):
    return "def solve(x):\n" + INT1 + body


def py2(body):
    return "def solve(a, b):\n" + INT2 + body


def pyl(body):
    return "def solve(xs):\n" + LIST + body


SAME = [
    ("sum-loop-vs-builtin", 1,
     pyl("    total = 0\n    for v in xs:\n        total += v\n    return total\n"),
     "def solve(xs):\n    return sum(xs)\n", "python", "python", {}),
    ("sum-recursion-vs-loop", 2,
     "def rec(xs):\n    return 0 if not xs else xs[0] + rec(xs[1:])\n"
     + pyl("    return rec(xs)\n"),
     pyl("    total = 0\n    for v in xs:\n        total += v\n    return total\n"),
     "python", "python", {}),
    ("fact-loop-vs-prod", 3,
     py1("    n = 1\n    for i in range(1, x + 1):\n        n *= i\n    return n\n"),
     "import math\n" + py1("    return math.prod(range(1, x + 1))\n"),
     "python", "python", {"cases": 25}),
    ("double-loop-vs-mul", 4,
     py1("    t = 0\n    n = x if x > 0 else -x\n    for _ in range(n):\n        t += 2\n    return t if x > 0 else -t\n"),
     py1("    return x * 2\n"), "python", "python", {"cases": 25}),
    ("square-mul-vs-pow", 5,
     py1("    return x * x\n"), py1("    return x ** 2\n"),
     "python", "python", {"cases": 25}),
    ("add-commuted", 6,
     py2("    return a + b\n"), "def solve(a, b):\n    return b + a\n",
     "python", "python", {"cases": 25}),
    ("max-builtin-vs-manual", 7,
     pyl("    return max(xs)\n"),
     pyl("    m = xs[0]\n    for v in xs:\n        m = v if v > m else m\n    return m\n"),
     "python", "python", {}),
    ("min-builtin-vs-manual", 8,
     pyl("    return min(xs)\n"),
     pyl("    m = xs[0]\n    for v in xs:\n        m = v if v < m else m\n    return m\n"),
     "python", "python", {}),
    ("gcd-math-vs-euclid", 9,
     "import math\n" + py2("    return math.gcd(a, b)\n"),
     py2("    a, b = abs(a), abs(b)\n    while b:\n"
         "        a, b = b, a % b\n    return a\n"),
     "python", "python", {"cases": 25}),
    ("abs-py-vs-ruby", 10,
     py1("    return abs(x)\n"),
     "def solve(x)\n  raise TypeError unless x.is_a?(Integer)\n"
     "  x < 0 ? -x : x\nend\n", "python", "ruby", {"cases": 25}),
    ("iseven-mod-vs-bit", 11,
     py1("    return x % 2 == 0\n"), py1("    return (x & 1) == 0\n"),
     "python", "python", {"cases": 25}),
    ("triangular-formula-variants", 12,
     py1("    return x * (x + 1) // 2\n"),
     py1("    return (x * x + x) // 2\n"), "python", "python", {"cases": 25}),
    ("sum-renamed-with-comments", 13,
     pyl("    total = 0\n    for v in xs:\n        total += v\n    return total\n"),
     "# add everything up\ndef solve(xs):\n"
     "    acc = 0  # running total\n"
     "    for item in xs:\n        acc = acc + item\n    return acc\n",
     "python", "python", {}),
    ("accumulate-for-vs-while", 14,
     "def solve(x):\n    t = 0\n    for i in range(x):\n        t += i\n    return t\n",
     "def solve(x):\n    t = 0\n    i = 0\n    while i < x:\n"
     "        t += i\n        i += 1\n    return t\n",
     "python", "python", {"cases": 25}),
    ("double-py-ref-js-att", 1,
     py1("    return x * 2\n"),
     "function solve(x) { return x * 2; }\n",
     "python", "javascript", {}),
    ("indented-paste", 15,
     py1("    return x * 2\n"),
     "   def solve(x):\n       return x * 2\n",
     "python", "python", {}),
]

DIFF = [
    ("off-by-one-range", 101,
     "def solve(x):\n    return sum(range(x))\n",
     "def solve(x):\n    return sum(range(x + 1))\n", "python", {"cases": 25}),
    ("plus-vs-minus", 102,
     py2("    return a + b\n"), "def solve(a, b):\n    return a - b\n",
     "python", {"cases": 25}),
    ("max-vs-min", 103,
     pyl("    return max(xs)\n"), "def solve(xs):\n    return min(xs)\n",
     "python", {}),
    ("double-vs-triple", 104,
     py1("    return x * 2\n"), py1("    return x * 3\n"),
     "python", {"cases": 25}),
    ("square-vs-cube", 105,
     py1("    return x * x\n"), py1("    return x * x * x\n"),
     "python", {"cases": 25}),
    ("add-vs-mul", 106,
     py2("    return a + b\n"), "def solve(a, b):\n    return a * b\n",
     "python", {"cases": 25}),
    ("abs-vs-negate", 107,
     py1("    return abs(x)\n"), py1("    return -x\n"),
     "python", {"cases": 25}),
    ("even-vs-odd", 108,
     py1("    return x % 2 == 0\n"), py1("    return x % 2 == 1\n"),
     "python", {"cases": 25}),
    ("sum-vs-prod", 109,
     pyl("    t = 0\n    for v in xs:\n        t += v\n    return t\n"),
     "import math\ndef solve(xs):\n    return math.prod(xs)\n",
     "python", {}),
    ("sum-vs-len", 110,
     pyl("    return sum(xs)\n"), "def solve(xs):\n    return len(xs)\n",
     "python", {"cases": 25}),
    ("sqdiff-vs-diff-of-squares", 111,
     py2("    return (a - b) * (a - b)\n"),
     "def solve(a, b):\n    return (a - b) * (a + b)\n",
     "python", {"cases": 25}),
    ("sum-vs-const-zero", 112,
     pyl("    return sum(xs)\n"), "def solve(xs):\n    return 0\n",
     "python", {"cases": 25}),
    ("sum-vs-raise", 113,
     pyl("    return sum(xs)\n"),
     "def solve(xs):\n    raise ValueError('wrong')\n",
     "python", {"cases": 25}),
    ("sum-vs-syntax-error", 114,
     pyl("    return sum(xs)\n"), "def solve(xs)\n    return 1\n",
     "python", {"cases": 25}),
    ("sum-vs-wrong-arity", 115,
     pyl("    return sum(xs)\n"), "def solve(a, b):\n    return a\n",
     "python", {"cases": 25}),
]

passed = 0


def run_pair(name, seed, ref, att, ref_lang, att_lang="python", extra=None):
    global passed
    req = {"key": name, "language": att_lang, "reference_language": ref_lang,
           "reference": ref, "attempt": att, "seed": seed}
    req.update(extra or {})
    status, body = post("/v1/run_check", req)
    return status, body


for name, seed, ref, att, ref_lang, att_lang, extra in SAME:
    status, body = run_pair(name, seed, ref, att, ref_lang, att_lang, extra)
    assert status == 200, f"{name}: status {status}: {body!r}"
    assert body["total"] > 0, f"{name}: no valid inputs: {body!r}"
    assert body["passed"] == body["total"], \
        f"{name}: {body['passed']}/{body['total']}: {body!r}"
    assert body["deterministic"] is True, f"{name}: {body!r}"
    assert body["needs_review"] is False, f"{name}: {body!r}"
    passed += 1
    print(f"same {name}: {body['passed']}/{body['total']}", flush=True)

for name, seed, ref, att, ref_lang, extra in DIFF:
    status, body = run_pair(name, seed, ref, att, ref_lang, "python", extra)
    assert status == 200, f"{name}: status {status}: {body!r}"
    assert body["total"] > 0, f"{name}: no valid inputs: {body!r}"
    assert body["passed"] < body["total"], \
        f"{name}: unexpectedly fully passing: {body!r}"
    assert body["needs_review"] is False, f"{name}: {body!r}"
    assert body["failed_sample"], f"{name}: no failing inputs: {body!r}"
    passed += 1
    print(f"diff {name}: {body['passed']}/{body['total']}", flush=True)

assert passed == 31, f"matrix incomplete: {passed}/31"

# --- security asserts ---
# 1. GET /up reports real runtimes, nothing missing.
status, up = get("/up")
assert status == 200, up
for rt in ("python", "node", "ruby"):
    assert up["runtimes"].get(rt) not in (None, "", "missing"), up
assert isinstance(up.get("runners_mtime"), int) and up["runners_mtime"] > 0, up

# 9. Orphan predicate: reparented-to-init exits, init itself and supervised never do.
assert server.is_orphaned(12345, 1) is True
assert server.is_orphaned(1, 0) is False
assert server.is_orphaned(12345, 6789) is False
print("orphan predicate: stale processes self-terminate", flush=True)
print(f"runtimes: {up['runtimes']}", flush=True)

# 2. Reasons and failing inputs carry no reference text or expected outputs.
marked_ref = ("# REFSECRET-987\n"
              + pyl("    t = 0\n    for v in xs:\n        t += v\n    return t\n"))
status, body = run_pair("leak-probe", 201, marked_ref,
                        "def solve(xs):\n    return len(xs)\n", "python",
                        "python", {"cases": 25})
assert status == 200, body
blob = json.dumps(body)
assert "REFSECRET-987" not in blob, f"reference text leaked: {blob[:300]!r}"
assert "def solve" not in " ".join(body["reasons"]), body["reasons"]
for sample in body["failed_sample"]:
    assert isinstance(sample, list), f"sample must be inputs: {sample!r}"
print("no-leak: reasons/samples carry no reference text", flush=True)

# 3. Unknown language is refused pre-execution (fast 400, nothing spawned).
started = time.monotonic()
status, body = post("/v1/run_check", {
    "key": "go-probe", "language": "go", "reference": "x", "attempt": "y",
    "seed": 1})
elapsed = time.monotonic() - started
assert status == 400, f"unknown language must be 400, got {status}: {body!r}"
assert "go" in body.get("error", ""), body
assert elapsed < 10, f"refusal must be instant (no execution): {elapsed:.1f}s"
print(f"unknown-language refused in {elapsed:.2f}s", flush=True)

# 4. Oversized stdout is truncated and fails the case (correct value aside).
loud = ("def solve(x):\n    print('Z' * 200000)\n    return x * 2\n")
status, body = run_pair("loud-attempt", 202, py1("    return x * 2\n"),
                        loud, "python", "python", {"cases": 25})
assert status == 200, body
assert body["total"] > 0, body
assert body["passed"] < body["total"], f"loud output must fail: {body!r}"
assert any("stdout cap" in r for r in body["reasons"]), body["reasons"]
print("stdout-cap: oversized output truncated and failed", flush=True)

# 5. Nondeterministic reference -> needs_review + deterministic false.
noisy = "import random\ndef solve(x):\n    return random.randint(0, 999999)\n"
status, body = run_pair("noisy-ref", 203, noisy,
                        "def solve(x):\n    return 0\n", "python",
                        "python", {"cases": 20})
assert status == 200, body
assert body["needs_review"] is True, body
assert body["deterministic"] is False, body
print("nondeterminism caught: needs_review + deterministic=false", flush=True)

# 6. Slow attempt (5s sleep vs ~2s case timeout) mismatches, server survives.
sleeper = "import time\ndef solve(x):\n    time.sleep(5)\n    return x * 2\n"
status, body = run_pair("slow-attempt", 204, py1("    return x * 2\n"),
                        sleeper, "python", "python", {"cases": 8})
assert status == 200, body
assert body["total"] > 0, body
assert body["passed"] < body["total"], f"slow attempt must fail: {body!r}"
assert any("timed out" in r for r in body["reasons"]), body["reasons"]
print("slow-attempt: per-case timeout fails the case, server alive", flush=True)

# 7. Attempt importing the sibling reference program must fail: each side
# runs in its own directory, so there is no sibling to import.
cheat = "import ref\ndef solve(x):\n    return ref.solve(x)\n"
status, body = run_pair("sibling-import", 205, py1("    return x * 2\n"),
                        cheat, "python", "python", {"cases": 8})
assert status == 200, body
assert body["total"] > 0, body
assert body["passed"] < body["total"], \
    f"sibling import must not pass: {body!r}"
print("sibling-import: no cross-side visibility", flush=True)

# 8. Crashing attempts report the first error line (sanitized, no paths).
status, body = run_pair("error-line", 206,
                        py1("    return x\n"),
                        "def solve(x):\n    raise ValueError('wrong')\n",
                        "python", "python", {"cases": 8})
assert status == 200, body
assert body["passed"] == 0, body
assert any("ValueError" in r for r in body["reasons"]), body["reasons"]
assert not any("tmp" in r and "/" in r for r in body["reasons"]), body["reasons"]
print("error-line: first stderr line reported, paths scrubbed", flush=True)

httpd.shutdown()
print(f"coderunner: {passed}/31 pairs + 8 security asserts OK")
