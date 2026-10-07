#!/usr/bin/env python3
"""Diff-fuzz coderunner: deterministic inputs, reference-vs-attempt execution.

Contract: POST /v1/run_check {key, language, reference, attempt, seed, cases}
  -> {passed, total, deterministic, needs_review, reasons[], failed_sample[]}
GET /up -> {runtimes: {python, node, ruby}}.

`language` is the attempt language; `reference_language` optionally overrides
it for the reference (cross-language tasks compare normalized outputs).
Shape mirrors sidecar/server.py: stdlib http.server, threading + semaphore
(extras get 503 busy), request cap, transport trouble as non-200.
"""
import importlib.util as __importlib_util  # noqa: E402
import json
import os
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

_HERE = os.path.dirname(os.path.abspath(__file__))
_spec = __importlib_util.spec_from_file_location(
    "coderunner_runners", os.path.join(_HERE, "runners.py"))
if _spec is None or _spec.loader is None:
    raise SystemExit("coderunner: cannot load runners.py")
runners = __importlib_util.module_from_spec(_spec)
_spec.loader.exec_module(runners)

PER_CASE_TIMEOUT = 2.0  # spec section 1: slow case fails the case, not the check
OVERALL_BUDGET = 100.0  # worst-case guard so one check never outruns the client read timeout
MAX_BODY = 262144
MAX_CASES = 100  # spec section 0: N=100 starter constant
MIN_VALID_ABSOLUTE = 20  # spec section 4: fewer valid inputs -> needs_review
FAILED_SAMPLE_MAX = 5
# At most two concurrent checks, the rest get 503 busy (mirrors GRADE_SEM).
RUN_SEM = threading.Semaphore(2)


def _min_valid(total):
    return min(MIN_VALID_ABSOLUTE, max(1, total // 5))


def _review(passed, total, reasons, failed_sample=None):
    return {"passed": passed, "total": total, "deterministic": True,
            "needs_review": True, "reasons": list(reasons),
            "failed_sample": list(failed_sample or [])}


def run_check(ref_code, ref_lang, att_code, att_lang, seed, cases):
    try:
        cases = max(1, min(MAX_CASES, int(cases or MAX_CASES)))
    except (TypeError, ValueError):
        cases = MAX_CASES
    try:
        seed = int(seed or 0)
    except (TypeError, ValueError):
        seed = 0
    arity = runners.get_arity(ref_lang, ref_code)
    if arity is None:
        return _review(0, 0, ["reference has no usable solve() entrypoint"])
    for lang in (ref_lang, att_lang):
        if runners.INTERPS.get(lang) is None:
            return _review(0, 0, [f"runtime {lang} unavailable"])
    inputs = runners.gen_inputs(seed, cases, arity)
    threshold = _min_valid(len(inputs))
    deadline = time.monotonic() + OVERALL_BUDGET

    def budget():
        return min(PER_CASE_TIMEOUT, max(0.05, deadline - time.monotonic()))

    def exhausted():
        return time.monotonic() >= deadline

    # Separate directories per side: the attempt must never see the reference
    # program file (no sibling import, no cross-reads). Outputs are compared;
    # file contents never leave the runner.
    with tempfile.TemporaryDirectory(prefix="runcheck-ref-") as ref_tmp, \
            tempfile.TemporaryDirectory(prefix="runcheck-att-") as att_tmp:
        ref_prog = runners.write_program(ref_tmp, "ref", ref_lang, ref_code)
        att_prog = runners.write_program(att_tmp, "att", att_lang, att_code)
        # Pass 1: reference-first. Inputs the reference crashes/times out on
        # are dropped (spec section 4); too few valid ones -> needs_review.
        valid = []  # (input_index, reference_output)
        for index, args in enumerate(inputs):
            status, value = runners.run_one(ref_lang, ref_prog, args, budget(), ref_tmp)
            if status == "ok":
                valid.append((index, value))
            if exhausted():
                return _review(0, len(valid), ["runner time budget exhausted"])
        if len(valid) < threshold:
            return _review(0, len(valid), [
                f"reference answered {len(valid)} of {len(inputs)} inputs (minimum {threshold})"])
        # Pass 2: reference determinism (double run over valid inputs).
        for index, first in valid:
            status, value = runners.run_one(ref_lang, ref_prog, inputs[index],
                                            budget(), ref_tmp)
            if exhausted():
                return _review(0, len(valid), ["runner time budget exhausted"])
            if status != "ok" or not runners.equal(value, first):
                return {"passed": 0, "total": len(valid),
                        "deterministic": False, "needs_review": True,
                        "reasons": ["reference is nondeterministic: "
                                    "repeated run differs"],
                        "failed_sample": [inputs[index]]}
        # Pass 3: attempt on valid inputs only; normalized-output compare.
        passed = 0
        differ = timed_out = crashed = capped = no_output = 0
        failed = []
        for index, want in valid:
            status, value = runners.run_one(att_lang, att_prog, inputs[index],
                                            budget(), att_tmp)
            if exhausted():
                return _review(passed, len(valid),
                               ["runner time budget exhausted"] +
                               _summary(passed, len(valid)), failed)
            if status == "ok" and runners.equal(value, want):
                passed += 1
                continue
            if status == "ok":
                differ += 1
            elif status == "timeout":
                timed_out += 1
            elif status == "truncated":
                capped += 1
            elif status == "bad_output":
                no_output += 1
            else:
                crashed += 1
            if len(failed) < FAILED_SAMPLE_MAX:
                failed.append(inputs[index])
        reasons = _summary(passed, len(valid))
        if differ:
            reasons.append(f"{differ} outputs differ")
        if timed_out:
            reasons.append(f"{timed_out} timed out")
        if crashed:
            reasons.append(f"{crashed} crashed")
        if capped:
            reasons.append(f"{capped} exceeded stdout cap")
        if no_output:
            reasons.append(f"{no_output} produced no output")
        return {"passed": passed, "total": len(valid),
                "deterministic": True, "needs_review": False,
                "reasons": reasons, "failed_sample": failed}


def _summary(passed, total):
    return [f"passed {passed} of {total} cases"]


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):  # keep logs to our single run_check line
        pass

    def _json(self, payload, status=200):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/up":
            return self._json({"runtimes": runners.RUNTIMES})
        self.send_error(404)

    def do_POST(self):
        if self.path != "/v1/run_check":
            return self.send_error(404)
        if not RUN_SEM.acquire(blocking=False):
            return self._json({"error": "busy"}, status=503)
        try:
            length = min(int(self.headers.get("Content-Length", 0)), MAX_BODY)
            try:
                payload = json.loads(self.rfile.read(length) or b"{}")
            except Exception as exc:
                return self._json(
                    {"error": f"bad json: {exc}"}, status=500)
            att_lang = payload.get("language") or ""
            ref_lang = payload.get("reference_language") or att_lang
            for lang in (att_lang, ref_lang):
                if lang not in runners.LANGUAGES:
                    # Refused pre-execution: no subprocess is ever spawned.
                    return self._json(
                        {"error": f"unknown language {lang!r}"},
                        status=400)
            ref = payload.get("reference") or ""
            att = payload.get("attempt") or ""
            if not ref or not att:
                return self._json(
                    {"error": "reference and attempt are required"}, status=400)
            try:
                result = run_check(ref, ref_lang, att, att_lang,
                                   payload.get("seed"), payload.get("cases"))
            except Exception as exc:  # Rails treats non-200 as pending + retry
                return self._json(
                    {"error": f"runner failed: {exc}"}, status=500)
            # Log key/count/languages only — never code (spec section 4).
            print(f"run_check key={payload.get('key')} lang={ref_lang}/{att_lang} "
              f"passed={result['passed']}/{result['total']} "
              f"needs_review={result['needs_review']}", flush=True)
            return self._json(result)
        finally:
            RUN_SEM.release()


def build_server(host, port):
    return ThreadingHTTPServer((host, port), Handler)


if __name__ == "__main__":
    _host = os.environ.get("CODERUNNER_HOST", "127.0.0.1")
    try:
        _port = int(os.environ.get("CODERUNNER_PORT", "8001"))
        if len(sys.argv) > 1:
            _port = int(sys.argv[1])
    except ValueError as err:
        raise SystemExit(f"bad port: {sys.argv[1]!r}") from err
    print(f"coderunner on {_host}:{_port} (runtimes={runners.RUNTIMES})", flush=True)
    build_server(_host, _port).serve_forever()
