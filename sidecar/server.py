#!/usr/bin/env python3
"""Real Laya moderation sidecar + OpenJev 0.8B jury grader: CPU, preloaded.

One batched forward pass (moderation + guard presets) per verdict.
Contract: POST /v1/judge {key, candidate, question, presets} ->
{"verdict": "reject"|"pass", "needs_review": bool, "category": str}.
Grading: POST /v1/grade {reference, answer, points_text} -> grade_v2 result
{label, score, needs_review, review_reasons, ...}.
GET /up -> {"model", "loaded", "grade": {"model", "dtype", "loaded"}}.
"""
import json
import os
import re
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault("HF_HOME", os.path.join(ROOT, "weights", "hf-cache"))

import torch

torch.set_num_threads(1)

import laya  # noqa: E402
from huggingface_hub import snapshot_download  # noqa: E402

import grade  # noqa: E402

REJECT_AT = 0.8
REVIEW_AT = 0.5

agent = laya.load("convaiinnovations/laya", subfolder="multilingual")
MOD_Q = laya.moderation_questions()
GUARD_Q = laya.guard_questions()
overlap = set(MOD_Q) & set(GUARD_Q)
if overlap:
    raise SystemExit(f"preset key collision: {overlap}")
QUESTIONS = {**MOD_Q, **GUARD_Q}


MAT = re.compile(r"\b(хуй|пизд|бля|еб|сук|пидор|мудак|залуп|дроч|гондон|шлюх|трах|сперм|сись|пись|наху|оху|поху|заеб)\w*", re.IGNORECASE)

# Coarse pre-filter: catches short mats the model misses.
def judge(candidate):
    if MAT.search(candidate or ""):
        return {"verdict": "reject", "needs_review": False, "category": "мат"}
    answers = agent.predict({"post": candidate, "prompt": candidate}, QUESTIONS)["answers"]
    worst_name, worst_p = "", 0.0
    for name, ans in answers.items():
        try:
            p = float((ans or {}).get("noul", 0.0))
        except (TypeError, ValueError):
            return {"verdict": "pass", "needs_review": True, "category": name}
        if p > worst_p:
            worst_name, worst_p = name, p
    if worst_p >= REJECT_AT:
        return {"verdict": "reject", "needs_review": False, "category": worst_name}
    if worst_p >= REVIEW_AT:
        return {"verdict": "pass", "needs_review": True, "category": worst_name}
    return {"verdict": "pass", "needs_review": False, "category": ""}

# Jury weights live in ./weights like Laya; first boot downloads the pinned revision.
snapshot_download(repo_id=grade.MODEL_ID, revision=grade.OPENJEV_REVISION,
                  allow_patterns=[grade.SUBFOLDER + "/*"])
GRADE_DTYPE = grade.load_grader()
# CPU inference is heavy: at most two concurrent grades, the rest get 503 busy.
GRADE_SEM = threading.Semaphore(2)


class Handler(BaseHTTPRequestHandler):
    def _json(self, payload, status=200):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/up":
            return self._json({"model": "laya-multilingual", "loaded": True,
                               "grade": {"model": "openjev-0.8b",
                                         "dtype": GRADE_DTYPE, "loaded": True}})
        self.send_error(404)

    def do_POST(self):
        if self.path == "/v1/judge":
            try:
                length = int(self.headers.get("Content-Length", 0))
                payload = json.loads(self.rfile.read(length) or b"{}")
                self._json(judge(payload.get("candidate") or ""))
            except Exception as exc:  # fail open at transport; Rails fails closed
                self._json({"verdict": "pass", "needs_review": True, "category": f"error: {exc}"})
            return
        if self.path != "/v1/grade":
            return self.send_error(404)
        if not GRADE_SEM.acquire(blocking=False):
            return self._json({"error": "busy"}, status=503)
        try:
            length = min(int(self.headers.get("Content-Length", 0)), 262144)
            payload = json.loads(self.rfile.read(length) or b"{}")
            self._json(grade.grade_v2(payload.get("reference") or "",
                                      payload.get("answer") or "",
                                      payload.get("points_text") or ""))
        except Exception as exc:  # Rails treats non-200 as transport failure: pending + retry
            self._json({"error": f"{exc}"}, status=500)
        finally:
            GRADE_SEM.release()


if __name__ == "__main__":
    try:
        port = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
    except ValueError as err:
        raise SystemExit(f"bad port: {sys.argv[1]}") from err
    print(f"laya sidecar on :{port} (multilingual + openjev-0.8b/{GRADE_DTYPE}, CPU)", flush=True)
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
