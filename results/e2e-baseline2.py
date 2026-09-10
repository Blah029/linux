#!/usr/bin/env python3
"""E2E baseline round 2: warm small chat + oversized trigger with fixed session id."""
import json
import time
import urllib.request

CTX = "http://10.0.0.1:8000/v1"


def post(base, model, messages, max_tokens, session_id=None):
    body = {
        "model": model,
        "messages": messages,
        "max_tokens": max_tokens,
        "stream": True,
        "temperature": 0.7,
        "top_p": 0.8,
    }
    headers = {"Content-Type": "application/json"}
    if session_id:
        headers["X-Session-ID"] = session_id
    req = urllib.request.Request(base + "/chat/completions",
                                 data=json.dumps(body).encode(), headers=headers)
    t0 = time.perf_counter()
    ttft = None
    timings = None
    with urllib.request.urlopen(req, timeout=3600) as resp:
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
    return {"ttft_s": ttft, "wall_s": wall, "timings": timings}


def show(tag, r):
    t = r.get("timings") or {}
    print(json.dumps({
        "tag": tag,
        "ttft_s": round(r["ttft_s"], 3) if r["ttft_s"] else None,
        "wall_s": round(r["wall_s"], 3),
        "prompt_n": t.get("prompt_n"),
        "prefill_tps": t.get("prompt_per_second"),
        "gen_tps": t.get("predicted_per_second"),
        "predicted_n": t.get("predicted_n"),
    }))


def main():
    r = post(CTX, "Qwen3.8-27B-GSQ-RCO-IQ3_XXS",
             [{"role": "user", "content": "In one sentence: what is the time complexity of mergesort?"}], 128)
    show("e2e-ctxpact-small-warm", r)

    filler = ("The quick brown fox jumps over the lazy dog near the old mill. "
              "A sample sentence with some technical content about systems design. ")
    big = f"Context dump {67890}. " + filler * 4000 + "\n\nSummarise the above in one sentence."
    sid = "e2e-baseline-oversized"
    r = post(CTX, "Qwen3.8-27B-GSQ-RCO-IQ3_XXS",
             [{"role": "user", "content": big}], 256, session_id=sid)
    show("e2e-compaction-trigger-2", r)
    for _ in range(20):
        time.sleep(2)
        try:
            with urllib.request.urlopen(CTX + f"/v1/sessions/{sid}", timeout=10) as resp:
                data = json.loads(resp.read().decode())
                print("SESSION " + json.dumps(data))
                return
        except Exception:
            continue
    print("SESSION not found after polling")


if __name__ == "__main__":
    main()
