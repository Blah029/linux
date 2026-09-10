#!/usr/bin/env python3
"""Multi-turn natural-growth compaction test via ctxpact (v2).

Uses UNIQUE prose (one unique numbered sentence per ~25 tokens) so DCP/
SequenceDetector cannot dedupe it; the session's outgoing tokens grow
linearly until the token_ratio trigger (0.70 x 106496 = 74,547) fires
stage-2 summarization.
"""
import json
import time
import urllib.request
import uuid

CTX = "http://10.0.0.1:8000/v1"
MODEL = "Qwen3.8-27B-GSQ-RCO-IQ3_XXS"
TURNS = 6
SENTENCES_PER_TURN = 600  # ~15k tokens per turn (~25 tok/sentence)


def unique_prose(start: int, count: int) -> str:
    parts = []
    for k in range(count):
        n = start + k
        parts.append(
            f"Sentence {n}: subsystem {n % 97} processes batch {n * 7919 % 100000} "
            f"with coefficient {(n * 31) % 500} and emits report code R-{n:06d}."
        )
    return " ".join(parts)


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
    sid = "compact-v2-" + uuid.uuid4().hex[:12]
    msgs = [{"role": "system", "content": "You are a helpful assistant. Reply in one short sentence."}]
    print(json.dumps({"event": "start", "session_id": sid}))
    n = 0
    for i in range(TURNS):
        prose = unique_prose(n, SENTENCES_PER_TURN)
        n += SENTENCES_PER_TURN
        user = f"Read this technical record and acknowledge it briefly: {prose}"
        msgs.append({"role": "user", "content": user})
        try:
            data, wall = post(msgs, 256, sid)
        except Exception as e:
            print(json.dumps({"event": "turn", "turn": i + 1, "error": str(e)}))
            break
        ch = (data.get("choices") or [{}])[0]
        t = data.get("timings") or {}
        print(json.dumps({
            "event": "turn", "turn": i + 1,
            "wall_s": round(wall, 1),
            "prompt_n": t.get("prompt_n"),
            "prefill_tps": round(t.get("prompt_per_second") or 0, 1),
            "gen_tps": round(t.get("predicted_per_second") or 0, 1),
            "predicted_n": t.get("predicted_n"),
            "cache_n": t.get("cache_n"),
        }))
        msgs.append({"role": "assistant", "content": (ch.get("message") or {}).get("content", "")})
        time.sleep(1)
        sess = get_session(sid)
        evs = sess.get("compaction_events") or []
        last = {
            "trigger": evs[-1].get("trigger"),
            "tokens_before": evs[-1].get("tokens_before"),
            "tokens_after": evs[-1].get("tokens_after"),
            "stage": evs[-1].get("stage"),
        } if evs else None
        print(json.dumps({
            "event": "session_state", "turn": i + 1,
            "total_input_tokens": sess.get("total_input_tokens"),
            "total_output_tokens": sess.get("total_output_tokens"),
            "user_turn_count": sess.get("user_turn_count"),
            "compaction_count": len(evs),
            "last_event": last,
            "error": sess.get("error"),
        }))
    # post-compaction sanity turn
    try:
        data, wall = post(msgs + [{"role": "user", "content": "In one sentence, summarize the most recent record you read."}], 256, sid)
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
        "total_input_tokens": sess.get("total_input_tokens"),
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
