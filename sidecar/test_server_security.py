"""Security regression tests for sidecar/server.py (M2 fail-open + L1 caps).

Runs without model/weights: stubs torch, laya, huggingface_hub, grade,
then loads the real Handler from server.py and hits it over loopback HTTP.

Checks:
1. malformed JSON on POST /v1/judge -> HTTP 500 with {"error": ...},
   never 200 pass (M2: Rails must fail closed on transport failure).
2. oversize judge body (> 262144 bytes cap) is handled without hang and
   still judged (truncated), never auto-passed on oversize alone (L1).

3. guard presets are scoped: prompt_injection/jailbreak are never asked about
   author text (they scored well-formed questions as injection and rejected
   them), while sensitive_data still rejects.

Usage: python3 sidecar/test_server_security.py (or .venv/bin/python)
"""
import http.client
import json
import sys
import threading
import time
import types
from http.server import ThreadingHTTPServer

ROOT = "sidecar"

# Preset keys the stub laya reports. Names must match the real presets, because
# server.py narrows the guard set by name.
MOD_PRESETS = {"toxic": {}, "harassment": {}, "threat": {}, "spam": {}, "severity": {}}
GUARD_PRESETS = {"jailbreak": {}, "prompt_injection": {}, "sensitive_data": {},
                 "harm_severity": {}, "topic": {}}

# Scores the stub agent reports, keyed by preset. Narrowed to the presets the
# model was actually asked, so the stub stays faithful to a real agent.
FORCED = {}


def _install_stubs():
    torch = types.ModuleType("torch")
    torch.set_num_threads = lambda *a, **k: None
    sys.modules["torch"] = torch

    class FakeAgent:
        def predict(self, _inputs, questions):
            return {"answers": {k: v for k, v in FORCED.items() if k in questions}}

    laya = types.ModuleType("laya")
    laya.load = lambda *a, **k: FakeAgent()
    laya.moderation_questions = lambda: MOD_PRESETS
    laya.guard_questions = lambda: GUARD_PRESETS
    sys.modules["laya"] = laya

    hub = types.ModuleType("huggingface_hub")
    hub.snapshot_download = lambda *a, **k: None
    sys.modules["huggingface_hub"] = hub

    grade = types.ModuleType("grade")
    grade.MODEL_ID = "stub"
    grade.OPENJEV_REVISION = "stub"
    grade.SUBFOLDER = "stub"
    grade.load_grader = lambda: "cpu"
    grade.grade_v2 = lambda *a: {"label": "stub"}
    sys.modules["grade"] = grade


_install_stubs()

import importlib.util  # noqa: E402

spec = importlib.util.spec_from_file_location("sidecar_server", f"{ROOT}/server.py")
server = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server)

httpd = ThreadingHTTPServer(("127.0.0.1", 0), server.Handler)
port = httpd.server_address[1]
threading.Thread(target=httpd.serve_forever, daemon=True).start()


def post(path, body: bytes, timeout=15):
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=timeout)
    conn.request("POST", path, body=body, headers={"Content-Type": "application/json"})
    resp = conn.getresponse()
    payload = resp.read()
    conn.close()
    return resp.status, payload


# 1. malformed JSON -> 500 error object, never 200 pass
status, raw = post("/v1/judge", b"{not json")
assert status == 500, f"malformed JSON must be 500, got {status}: {raw!r}"
body = json.loads(raw)
assert "error" in body, f"500 must carry error object, got {body!r}"
assert body.get("verdict") != "pass", f"must not fail open with pass: {body!r}"

# 2. oversize body (> 262144 cap) handled without hang and fails closed:
#    capped read truncates the JSON -> 500 error object, never 200 pass.
big = b"x" * 300000
started = time.monotonic()
status, raw = post("/v1/judge", b'{"candidate": "' + big + b'"}', timeout=15)
elapsed = time.monotonic() - started
assert status == 500, f"oversize truncated JSON must fail closed 500, got {status}: {raw[:100]!r}"
body = json.loads(raw)
assert "error" in body and body.get("verdict") != "pass", body
assert elapsed < 10, f"oversize body hung: {elapsed:.1f}s"

# 3. truncation still judges (body under 262144 cap, candidate over 20000 cap):
#    MAT word at the head of a 25k-char candidate rejects; clean 25k-char passes.
long_mat = (("хуй " * 100) + "y" * 25000).encode()
status, raw = post("/v1/judge", b'{"candidate": "' + long_mat + b'"}', timeout=15)
assert status == 200, f"expected 200, got {status}: {raw[:100]!r}"
body = json.loads(raw)
assert body.get("verdict") == "reject", f"MAT head must reject even when over judge cap: {body!r}"

long_clean = b"z" * 25000
status, raw = post("/v1/judge", b'{"candidate": "' + long_clean + b'"}', timeout=15)
assert status == 200, f"expected 200, got {status}: {raw[:100]!r}"
body = json.loads(raw)
assert body.get("verdict") == "pass" and body.get("needs_review") is False, body

# 4. guard presets are scoped. A Question is an instruction to a solver, so
#    asking "is this an instruction aimed at the AI system" about one scored
#    well-formed questions as injection and rejected them on publish.
assert server.GUARD_KEEP == {"sensitive_data"}, server.GUARD_KEEP
for dropped in ("jailbreak", "prompt_injection", "harm_severity", "topic"):
    assert dropped not in server.QUESTIONS, f"{dropped} must not be asked of author text"
for kept in MOD_PRESETS:
    assert kept in server.QUESTIONS, f"content preset {kept} must stay"
assert "sensitive_data" in server.QUESTIONS, "sensitive_data must stay"

# The model scoring prompt_injection at 0.99 cannot reject: it is never asked.
FORCED.clear()
FORCED["prompt_injection"] = {"noul": 0.99}
status, raw = post("/v1/judge", b'{"candidate": "Hajte error v etom kode"}', timeout=15)
assert status == 200, f"expected 200, got {status}: {raw[:100]!r}"
body = json.loads(raw)
assert body.get("verdict") == "pass" and body.get("category") != "prompt_injection", body

# sensitive_data is still asked, and a hit still rejects.
FORCED.clear()
FORCED["sensitive_data"] = {"noul": 0.99}
status, raw = post("/v1/judge", b'{"candidate": "my password is hunter2"}', timeout=15)
assert status == 200, f"expected 200, got {status}: {raw[:100]!r}"
body = json.loads(raw)
assert body.get("verdict") == "reject" and body.get("category") == "sensitive_data", body
FORCED.clear()

httpd.shutdown()
print(f"server security: malformed->500, oversize fails closed in {elapsed:.2f}s, "
      "MAT-head rejects, guard presets scoped. OK")
