#!/usr/bin/env python3
"""Diagnose the ctxpact 503: replay the multi-turn pattern, capture 503 body,
and test the same payload directly against :8080."""
import json
import time
import urllib.request
import urllib.error
import uuid

CTX = "http://10.0.0.1:8000/v1"
DIRECT = "http://10.0.0.1:8080/v1"
MODEL = "Qwen3.8-27B-GSQ-RCO-IQ3_XXS"
SENTENCES = 600


def prose(start, count):
    return " ".join(
        f"Sentence {start + k}: subsystem {(start + k) % 97} processes batch "
        f"{(start + k) * 7919 % 100000} with coefficient {((start + k) * 31) % 500} "
        f"and emits report code R-{start + k:06d}."
        for k in range(count)
    )


def call(base, body, session_id=None):
    headers = {"Content-Type": "application/json"}
    if session_id:
        headers["X-Session-ID"] = session_id
    req = urllib.request.Request(base + "/chat/completions",
                                 data=json.dumps(body).encode(), headers=headers)
    t0 = time.perf_counter()
    try:
        with urllib.request.urlopen(req, timeout=1800) as resp:
            return json.loads(resp.read().decode()), time.perf_counter() - t0, None
    except urllib.error.HTTPError as e:
        return None, time.perf_counter() - t0, e.read().decode()[:600]


def main():
    sid = "diag-" + uuid.uuid4().hex[:12]
    msgs = [{"role": "system", "content": "Reply in one short sentence."}]
    n = 0
    for i in range(5):
        user = f"Read this record and acknowledge briefly: {prose(n, SENTENCES)}"
        n += SENTENCES
        msgs.append({"role": "user", "content": user})
        body = {"model": MODEL, "messages": msgs, "max_tokens": 64,
                "temperature": 0.7, "top_p": 0.8}
        data, wall, err = call(CTX, body, sid)
        if err:
            print(f"TURN {i+1} FAIL ({wall:.1f}s): {err}")
            # same payload direct to 8080
            data2, wall2, err2 = call(DIRECT, body)
            if err2:
                print(f"  DIRECT also FAIL: {err2}")
            else:
                t = (data2 or {}).get("timings", {}) if isinstance(data2, dict) else {}
                print(f"  DIRECT OK ({wall2:.1f}s) prompt_n={t.get('prompt_n')}")
            break
        t = (data or {}).get("timings", {})
        print(f"TURN {i+1} OK ({wall:.1f}s) prompt_n={t.get('prompt_n')} cache_n={t.get('cache_n')}")
        ch = (data or {}).get("choices") or [{}]
        msgs.append({"role": "assistant",
                     "content": (ch[0].get("message") or {}).get("content", "")})
        time.sleep(1)


if __name__ == "__main__":
    main()
