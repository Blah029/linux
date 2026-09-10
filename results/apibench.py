#!/usr/bin/env python3
"""Benchmark client for the local llama-server (OpenAI-compatible).

Uses the server's timings object in the final SSE chunk:
  prompt_n / prompt_ms / prompt_per_second   -> prefill speed (cold if cache_n=0)
  predicted_n / predicted_ms / predicted_per_second -> effective gen speed (incl. spec)
  draft_n / draft_n_accepted                  -> speculative acceptance
  cache_n                                     -> prompt-cache hits

Each repetition uses a unique prompt prefix to avoid prompt-cache hits.

Usage:
  python3 apibench.py --model Qwen3.8-27B-GSQ-RCO-IQ3_XXS --sizes 512,2048,8192 --gen 512 --repeat 3 --tag baseline-fast
"""
import argparse
import json
import statistics
import sys
import time
import urllib.request

FILLER = (
    "The quick brown fox jumps over the lazy dog near the old mill. "
    "A sample sentence with some technical content about systems design. "
)


def build_prompt(seed: int, target_tokens: int) -> str:
    # unique prefix defeats the server prompt cache
    prompt = f"Probe {seed:06d}. " + FILLER * max(1, target_tokens // 13)
    return prompt


def one_request(base: str, model: str, prompt: str, max_tokens: int) -> dict:
    body = {
        "model": model,
        "messages": [{"role": "user", "content": prompt + "\n\nReply with exactly: OK"}],
        "max_tokens": max_tokens,
        "stream": True,
        "temperature": 0.7,
        "top_p": 0.8,
    }
    req = urllib.request.Request(
        base + "/chat/completions",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
    )
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
    t_end = time.perf_counter() - t0
    return {"ttft_s": ttft, "wall_s": t_end, "timings": timings}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://10.0.0.1:8080/v1")
    ap.add_argument("--model", required=True)
    ap.add_argument("--repeat", type=int, default=3)
    ap.add_argument("--sizes", default="512,2048,8192")
    ap.add_argument("--gen", type=int, default=512)
    ap.add_argument("--tag", default="")
    args = ap.parse_args()

    rows = []
    for size in [int(x) for x in args.sizes.split(",")]:
        for i in range(args.repeat):
            try:
                r = one_request(args.base, args.model, build_prompt(i + size, size), args.gen)
            except Exception as e:  # noqa: BLE001
                print(f"FAIL size={size} rep={i}: {e}", file=sys.stderr)
                continue
            t = r["timings"] or {}
            row = {
                "tag": args.tag,
                "size": size,
                "rep": i,
                "ttft_s": round(r["ttft_s"], 3) if r["ttft_s"] else None,
                "wall_s": round(r["wall_s"], 3),
                "prompt_n": t.get("prompt_n"),
                "prompt_ms": t.get("prompt_ms"),
                "prefill_tps": t.get("prompt_per_second"),
                "cache_n": t.get("cache_n"),
                "predicted_n": t.get("predicted_n"),
                "predicted_ms": t.get("predicted_ms"),
                "gen_tps": t.get("predicted_per_second"),
                "draft_n": t.get("draft_n"),
                "draft_accepted": t.get("draft_n_accepted"),
            }
            rows.append(row)
            print(json.dumps(row))

    if rows:
        agg = {}
        for size in sorted({r["size"] for r in rows}):
            rs = [r for r in rows if r["size"] == size and r.get("prefill_tps")]
            if not rs:
                continue
            agg[str(size)] = {
                "prefill_tps": round(statistics.median(r["prefill_tps"] for r in rs), 1),
                "gen_tps": round(statistics.median(r["gen_tps"] or 0 for r in rs), 1),
                "draft_accept_rate": round(
                    statistics.median(
                        (r["draft_accepted"] / r["draft_n"]) if (r.get("draft_n") and r.get("draft_accepted") is not None) else 0.0
                        for r in rs
                    ),
                    3,
                ),
            }
        print("AGG " + json.dumps(agg))


if __name__ == "__main__":
    main()
