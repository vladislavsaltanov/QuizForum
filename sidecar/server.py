#!/usr/bin/env python3
"""Real Laya moderation sidecar: multilingual checkpoint, CPU, preloaded.

One batched forward pass (moderation + guard presets) per verdict.
Contract: POST /v1/judge {key, candidate, question, presets} ->
{"verdict": "reject"|"pass", "needs_review": bool, "category": str}.
GET /up -> {"model", "loaded"}.
"""
import json
import os
import re
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault("HF_HOME", os.path.join(ROOT, "weights", "hf-cache"))

import torch

torch.set_num_threads(1)

import laya  # noqa: E402

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


class Handler(BaseHTTPRequestHandler):
    def _json(self, payload):
        body = json.dumps(payload).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/up":
            return self._json({"model": "laya-multilingual", "loaded": True})
        self.send_error(404)

    def do_POST(self):
        if self.path != "/v1/judge":
            return self.send_error(404)
        try:
            length = int(self.headers.get("Content-Length", 0))
            payload = json.loads(self.rfile.read(length) or b"{}")
            self._json(judge(payload.get("candidate") or ""))
        except Exception as exc:  # fail open at transport; Rails fails closed
            self._json({"verdict": "pass", "needs_review": True, "category": f"error: {exc}"})


if __name__ == "__main__":
    try:
        port = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
    except ValueError:
        raise SystemExit(f"bad port: {sys.argv[1]}")
    print(f"laya sidecar on :{port} (multilingual, CPU)", flush=True)
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
