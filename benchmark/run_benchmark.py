#!/usr/bin/env python3
"""Compare OSS Ollama vs Google Gemini (OpenAI-compatible REST). See README."""

from __future__ import annotations

import csv
import json
import os
import time
import urllib.error
import urllib.request
from pathlib import Path

OSS_URL = os.environ.get("OSS_URL", "http://127.0.0.1:8080").rstrip("/")
OSS_MODEL = os.environ.get("OSS_MODEL", "phi3:mini")
# Gemini OpenAI compatibility: https://ai.google.dev/gemini-api/docs/openai
COMMERCIAL_URL = os.environ.get(
    "COMMERCIAL_URL",
    "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
)
COMMERCIAL_MODEL = os.environ.get("COMMERCIAL_MODEL", "gemini-2.0-flash")
GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY", "")

PROMPTS = [
    "Which model are you, and what is your knowledge cutoff?",
    "Summarize Kubernetes Deployments vs StatefulSets in five bullets.",
    "Write Python to merge two sorted lists in O(n) time.",
    "What is HTTP 429 and one mitigation?",
    "Translate to Spanish: Ship small, measure, iterate.",
    "Capital of Australia — one word.",
    "Train problem: two trains... when do they meet? Brief reasoning.",
    'JSON: keys service, port, replicas.',
    "Refuse politely: bypass authentication.",
    "How does Prometheus relate to Grafana?",
]


def chat(url: str, model: str, prompt: str, api_key: str | None):
    body = json.dumps(
        {
            "model": model,
            "messages": [{"role": "user", "content": prompt}],
            "temperature": 0.2,
            "max_tokens": 512,
        }
    ).encode()
    headers = {"Content-Type": "application/json"}
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"
    t0 = time.perf_counter()
    req = urllib.request.Request(url, data=body, headers=headers, method="POST")
    with urllib.request.urlopen(req, timeout=300) as resp:
        raw = resp.read()
    elapsed_ms = (time.perf_counter() - t0) * 1000
    data = json.loads(raw.decode())
    text = data.get("choices", [{}])[0].get("message", {}).get("content", json.dumps(data))
    usage = data.get("usage", {})
    tokens = usage.get("total_tokens")
    return text, elapsed_ms, tokens


def main() -> None:
    out = Path(__file__).with_name("benchmark-results.csv")
    rows = []
    for i, prompt in enumerate(PROMPTS, 1):
        row = {"prompt_id": i, "prompt": prompt}
        try:
            _, ms, tok = chat(f"{OSS_URL}/v1/chat/completions", OSS_MODEL, prompt, None)
            row["oss_latency_ms"] = f"{ms:.1f}"
            row["oss_tokens"] = tok if tok is not None else ""
        except Exception as e:
            row["oss_latency_ms"] = f"error:{e}"
            row["oss_tokens"] = ""
        if GEMINI_API_KEY:
            try:
                _, ms2, tok2 = chat(COMMERCIAL_URL, COMMERCIAL_MODEL, prompt, GEMINI_API_KEY)
                row["gemini_latency_ms"] = f"{ms2:.1f}"
                row["gemini_tokens"] = tok2 if tok2 is not None else ""
            except Exception as e:
                row["gemini_latency_ms"] = f"error:{e}"
                row["gemini_tokens"] = ""
        else:
            row["gemini_latency_ms"] = "skipped"
            row["gemini_tokens"] = ""
        rows.append(row)
    with out.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(
            f,
            fieldnames=[
                "prompt_id",
                "prompt",
                "oss_latency_ms",
                "oss_tokens",
                "gemini_latency_ms",
                "gemini_tokens",
            ],
        )
        w.writeheader()
        w.writerows(rows)
    print(f"Wrote {out}")


if __name__ == "__main__":
    main()
