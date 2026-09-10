#!/usr/bin/env python3
"""End-to-end baseline: realistic prompts through ctxpact proxy and direct llama-server."""
import json
import time
import urllib.request

CTX = "http://10.0.0.1:8000/v1"
LLAMA = "http://10.0.0.1:8080/v1"

CODING_PROMPT = """You are a senior Python engineer. Fix the bug in this function and reply with only the corrected function:

def merge_sorted(a, b):
    out = []
    i = j = 0
    while i < len(a) and j < len(b):
        if a[i] <= b[j]:
            out.append(a[i])
            i += 1
        else:
            out.append(b[j])
            i += 1
    out.extend(a[i:])
    out.extend(b[j:])
    return out

The bug: when b[j] is smaller, the code increments i instead of j. Provide only the fixed code."""


def post(base, model, messages, max_tokens):
    body = {
        "model": model,
        "messages": messages,
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
    session_id = None
    with urllib.request.urlopen(req, timeout=3600) as resp:
        session_id = resp.headers.get("X-Session-ID")
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
    return {"ttft_s": ttft, "wall_s": wall, "timings": timings, "session_id": session_id}


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
        "session_id": r.get("session_id"),
    }))


def main():
    # (a) small chat via ctxpact
    r = post(CTX, "Qwen3.8-27B-GSQ-RCO-IQ3_XXS",
             [{"role": "user", "content": "In one sentence: what is the time complexity of mergesort?"}], 128)
    show("e2e-ctxpact-small", r)

    # (b) pi-style coding prompt, direct llama
    r = post(LLAMA, "Qwen3.8-27B-GSQ-RCO-IQ3_XXS",
             [{"role": "system", "content": "You are an expert coding assistant. Be concise."},
              {"role": "user", "content": CODING_PROMPT}], 512)
    show("e2e-coding-direct", r)

    # (c) compaction trigger via ctxpact (~80k tokens)
    filler = ("The quick brown fox jumps over the lazy dog near the old mill. "
              "A sample sentence with some technical content about systems design. ")
    big = f"Context dump {12345}. " + filler * 4000 + "\n\nSummarise the above in one sentence."
    r = post(CTX, "Qwen3.8-27B-GSQ-RCO-IQ3_XXS",
             [{"role": "user", "content": big}], 256)
    show("e2e-compaction-trigger", r)
    if r.get("session_id"):
        time.sleep(2)
        try:
            with urllib.request.urlopen(CTX + f"/v1/sessions/{r['session_id']}", timeout=30) as resp:
                print("SESSION " + json.dumps(json.loads(resp.read().decode())))
        except Exception as e:  # noqa: BLE001
            print("SESSION FAIL", e)


if __name__ == "__main__":
    main()
