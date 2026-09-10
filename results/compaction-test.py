#!/usr/bin/env python3
"""Multi-turn natural-growth compaction test via ctxpact.

Grows one session across 5 turns (~15k tokens each, ~75k total) to trigger the
natural compaction at token_ratio 0.70 (~74.5k of 106496). Measures per-turn
timings, compaction events, and post-compaction session state.
"""
import json
import time
import urllib.request
import uuid

CTX = "http://10.0.0.1:8000/v1"
MODEL = "Qwen3.8-27B-GSQ-RCO-IQ3_XXS"
TURNS = 5
TURNS_TOKENS = 15000

FILLER = (
    "The quick brown fox jumps over the lazy dog near the old mill. "
    "A sample sentence with some technical content about systems design. "
)
# measured: 1 filler copy ~= 25.4 tokens
COPIES = (TURNS_TOKENS - 20) // 25  # ~15k tokens per turn


def post(messages, max_tokens, session_id):
    body = {
        "model": MODEL,
        "messages": messages,
        "max_tokens": max_tokens,
        "stream": False,
        "temperature": 0.7,
        "top_p": 0.8,
    }
    req = urllib.request.Request(
        CTX + "/chat/completions",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "X-Session-ID": session_id},
    )
    t0 = time.perf_counter()
    with urllib.request.urlopen(req, timeout=3600) as resp:
        data = json.loads(resp.read().decode())
    wall = time.perf_counter() - t0
    return data, wall


def get_session(session_id):
    req = urllib.request.Request(
        f"{CTX}/sessions/{session_id}",
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode())
    except Exception as e:
        return {"error": str(e)}


def main():
    sid = "compact-test-" + uuid.uuid4().hex[:12]
    msgs = [{"role": "system", "content": "You are a helpful assistant. Keep replies short (<=200 tokens)."}]
    print(json.dumps({"event": "start", "session_id": sid}))
    for i in range(TURNS):
        seed = uuid.uuid4().hex
        user = (
            f"Turn {i + 1} (unique {seed[:12]}): read this passage and acknowledge it in one short sentence. "
            + FILLER * COPIES
        )
        msgs.append({"role": "user", "content": user})
        try:
            data, wall = post(msgs, 256, sid)
        except Exception as e:
            print(json.dumps({"event": "turn", "turn": i + 1, "error": str(e)}))
            break
        ch = (data.get("choices") or [{}])[0]
        t = data.get("timings") or {}
        row = {
            "event": "turn",
            "turn": i + 1,
            "wall_s": round(wall, 1),
            "prompt_n": t.get("prompt_n"),
            "prefill_tps": round(t.get("prompt_per_second") or 0, 1),
            "gen_tps": round(t.get("predicted_per_second") or 0, 1),
            "predicted_n": t.get("predicted_n"),
            "cache_n": t.get("cache_n"),
            "response_start": (ch.get("message") or {}).get("content", "")[:80],
        }
        print(json.dumps(row))
        msgs.append({"role": "assistant", "content": (ch.get("message") or {}).get("content", "")})
        time.sleep(1)
        sess = get_session(sid)
        evs = sess.get("compaction_events") or []
        print(json.dumps({
            "event": "session_state",
            "turn": i + 1,
            "session_tokens": sess.get("session_tokens"),
            "compaction_count": len(evs),
            "last_event": {
                "trigger": evs[-1].get("trigger"),
                "tokens_before": evs[-1].get("tokens_before"),
                "tokens_after": evs[-1].get("tokens_after"),
                "stage": evs[-1].get("stage"),
            } if evs else None,
            "error": sess.get("error"),
        }))
    # post-compaction sanity turn (small)
    try:
        data, wall = post(msgs + [{"role": "user", "content": "In one sentence, summarize the last passage you read."}], 256, sid)
        t = data.get("timings") or {}
        print(json.dumps({
            "event": "post-compaction-turn",
            "wall_s": round(wall, 1),
            "prompt_n": t.get("prompt_n"),
            "prefill_tps": round(t.get("prompt_per_second") or 0, 1),
            "gen_tps": round(t.get("predicted_per_second") or 0, 1),
            "predicted_n": t.get("predicted_n"),
            "response_start": ((data.get("choices") or [{}])[0].get("message") or {}).get("content", "")[:120],
        }))
    except Exception as e:
        print(json.dumps({"event": "post-compaction-turn", "error": str(e)}))
    sess = get_session(sid)
    evs = sess.get("compaction_events") or []
    print(json.dumps({
        "event": "final",
        "session_tokens": sess.get("session_tokens"),
        "compaction_events": [
            {"trigger": e.get("trigger"), "tokens_before": e.get("tokens_before"),
             "tokens_after": e.get("tokens_after"), "stage": e.get("stage")}
            for e in evs
        ],
        "error": sess.get("error"),
    }))
    print("DONE")


if __name__ == "__main__":
    main()
