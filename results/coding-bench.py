#!/usr/bin/env python3
"""Realistic pi-style coding benchmark (thinking-heavy workload), 3 unique repeats."""
import json
import statistics
import sys
import time
import urllib.request

BASE = "http://10.0.0.1:8080/v1"
MODEL = "Qwen3.8-27B-GSQ-RCO-IQ3_XXS"

TEMPLATE = """You are a senior Python engineer. Task {seed}: fix the bug and reply with only the corrected function.

def chunked(items, size):
    out = []
    i = 0
    while i < len(items):
        out.append(items[i:i + size])
        i += 1
    return out

Bug: the last chunk is dropped when len(items) is not a multiple of size. Provide only the fixed code."""


def one(seed):
    body = {
        "model": MODEL,
        "messages": [
            {"role": "system", "content": "You are an expert coding assistant. Be concise."},
            {"role": "user", "content": TEMPLATE.format(seed=seed)},
        ],
        "max_tokens": 512,
        "stream": True,
        "temperature": 0.7,
        "top_p": 0.8,
    }
    req = urllib.request.Request(BASE + "/chat/completions",
                                 data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    t0 = time.perf_counter()
    ttft = None
    timings = None
    with urllib.request.urlopen(req, timeout=1800) as resp:
        for raw in resp:
            line = raw.decode().strip()
            if not line.startswith("data:"):
                continue
            payload = line[5:].strip()
            if payload == "[DONE]":
                break
            try:
                chunk = json.loads(payload)
            except json.JSONDecodeError:
                continue
            if chunk.get("timings"):
                timings = chunk["timings"]
            choices = chunk.get("choices") or []
            if choices:
                delta = choices[0].get("delta") or {}
                if delta.get("reasoning_content") or delta.get("content"):
                    if ttft is None:
                        ttft = time.perf_counter() - t0
    wall = time.perf_counter() - t0
    t = timings or {}
    return {
        "seed": seed,
        "ttft_s": round(ttft, 3) if ttft else None,
        "wall_s": round(wall, 3),
        "prompt_n": t.get("prompt_n"),
        "gen_tps": t.get("predicted_per_second"),
        "predicted_n": t.get("predicted_n"),
        "draft_n": t.get("draft_n"),
        "draft_accepted": t.get("draft_n_accepted"),
    }


def main():
    tag = sys.argv[1] if len(sys.argv) > 1 else "coding"
    rows = [one(i) for i in range(3)]
    for r in rows:
        r["tag"] = tag
        print(json.dumps(r))
    gens = [r["gen_tps"] for r in rows if r.get("gen_tps")]
    if gens:
        acc = [ (r["draft_accepted"] / r["draft_n"]) if (r.get("draft_n") and r.get("draft_accepted") is not None) else 0.0
                for r in rows ]
        print("AGG " + json.dumps({
            "gen_tps": round(statistics.median(gens), 2),
            "draft_accept_rate": round(statistics.median(acc), 3),
            "avg_ttft_s": round(statistics.median([r["ttft_s"] for r in rows if r.get("ttft_s")]), 2),
        }))


if __name__ == "__main__":
    main()
