# llama.cpp Runtime Optimization — Final Report

Date: 2026-09-10
Scope: `Qwen3.8-27B-GSQ-RCO` (dense) — fast (`IQ3_XXS`, 106,496 ctx) default + long (`IQ3_S`, 176,403 ctx). Ridge ignored per instruction. Flag tuning only — no source build; running `~/.local/bin/llama` (0.3.0-dev, build 10679) used for bench/perplexity.

## Hardware
- CPU: Intel i5-11400, 6C/12T, AVX-512
- RAM: 16 GiB
- GPU: AMD Radeon RX 9060 XT, 16 GB VRAM (radv Vulkan), up to 8 GB GTT shared sys-RAM

## Final tuned serve flags (fast model)
```
-t 8 -td 8 -b 1024 -ub 512 -fa on -ngl all -fit off -ctxcp 2 -cram 4096
--context-shift --jinja -ctk q5_0 -ctv q5_0 -lm none -ctkd q5_0 -ctvd q5_0
-ngld all --spec-type draft-mtp --spec-draft-n-max 2
-a Qwen3.8-27B-GSQ-RCO-IQ3_XXS -c 106496
```
Long model: same flags with `-a Qwen3.8-27B-GSQ-RCO-IQ3_S -c 176403`.

## Performance (baseline F0 → tuned)
| Metric | Baseline (F0) | After tuning | Note |
|---|---|---|---|
| pp512 | 623.7 t/s | — | unchanged by flag sweeps |
| pp1024 | 622.6 t/s | — | unchanged |
| pp8192 (fast) | 565.7 t/s | — | unchanged |
| tg128 (fast) | 23.26 t/s | **24.12 t/s (+3.6%)** | `-t 8 -td 8` |
| pp8192 (long) | 551.7 t/s | — | |
| tg128 (long) | 20.50 t/s | **21.50 t/s (+5.0%)** | `-t 8 -td 8` |
| tg @ 30.6k ctx, spec n-max 2 | — | **33.9 t/s**, accept 0.90 | vs nmax3 11.7 t/s (0.71), nmax4 12.3 t/s (0.64) |

Sweep decisions: batch `-b 1024 -ub 512` (no gain beyond), threads `-t 8 -td 8`, speculative `n-max 2` (draft-MTP), KV `q5_0/q5_0` for both models, long context cap kept at 176,403.

## Accuracy
- Perplexity (fast): q5_0 KV **4.8384±0.045** vs q8_K KV **4.8341±0.045** → Δ0.0043, within noise. q5 KV is safe.
- Final flags change no quantization/KV precision → Step 6 numbers remain valid.

## Memory
- Baseline: VRAM 14.95/15.92 GiB (~94%); RAM ~10 GiB used, 5.2 GiB free; swap 1.9 GiB.
- Post-restore: RAM free ~8.6 GiB; VRAM ~15.97 GB with both servers + ctxpact.
- KV estimate: ~25.8 KiB/token → fast full 106,496 ≈ 2.8 GiB; long full 176,403 ≈ 4.6 GiB.
- GTT set from measured need: `-cram 4096` (4 GB). Long-model full KV fits VRAM + 4 GB cram headroom; ~8.6 GiB sys-RAM free left for prompt cache/checkpoints.

## Ctxpact compaction — root cause and fix
Failure chain (observed 503s in pi/AnythingLLM sessions):
1. `token_ratio 0.70` → threshold 74,547 tokens; `max_summary_tokens 16,384` → post-compaction size could re-exceed n_ctx → summarization overflow → raw request > 106,496 → llama HTTP 400 → ctxpact 503 "All providers failed".
2. Provider `timeout_seconds 180` < stage-2 summarization wall time under load (measured +300–400 s on trigger turns) → timeouts → circuit breaker opens → further 503s.
3. KV contention: active assistant session holding a ~70k-token idle slot (~1.8 GiB) could starve summarization requests.

Fixes (both fast + long configs):
- `token_ratio 0.70 → 0.60` (threshold 63,897)
- `max_summary_tokens 16,384 → 8192`
- `timeout_seconds 180 → 600`

Validation (clean run, session idle): **all turns succeeded, zero 503s, 3 `dcp_and_summarize` compactions**:
- 77,103 → 62,357 (trigger `token_count=77103 >= threshold=63897`)
- 92,723 → 62,891
- 92,752 → 62,892
Post-compaction sanity answer correct. Trigger turns cost +300–400 s wall time (stage-2 summarization).

## Bench suite accuracy (ctxpact, `Qwen3.8-27B-GSQ-RCO-IQ3_XXS`)
| Bench | Run 1 (broken) | Run 2 | Final |
|---|---|---|---|
| ReadAgent (Frankenstein, 8 Qs, direct :8080) | 4/8 (0.50) — empty answers, `max_tokens 1024` | 7/8 (0.88) — `max_tokens 4096` | **8/8 (1.00)** — token budget 12,000 → 16,384 |
| LoCoMo-MC10 (20 Qs, via ctxpact readagent) | 0/20 — 503s (hardcoded `config.yaml` = remote Dyson provider → circuit breaker) | 5/20 (25%) — local config, `max_tokens 256` | **18/20 (90%)** — `max_tokens 4096`; random baseline 10% |
| LongMemEval | skipped — dataset `longmemeval_oracle.json` not available locally | — | — |

Final LoCoMo by type: adversarial 4/4, multi_hop 3/4, open_domain 4/4, single_hop 4/4, temporal_reasoning 3/4. Avg latency 79.6 s, avg prompt 19,315 tokens.

Bench infra fixes:
- Launcher `kill_processes`: wait for ports 8080/8081/8000/6333 to free before new serve binds (escalate `pkill -9`); self-safe pattern `pkill -f 'ctxpact[.]server'` (no more SIGTERM of the benchmark's venv python or the calling shell).
- `benchmark_locomo.py`: honor `CTXPACT_CONFIG` env (was hardcoded `config.yaml` pointing at unreachable `169.254.241.219:8080` + dummy OpenRouter key); `max_tokens 256 → 4096`.
- `benchmark_readagent_direct.py`: `max_tokens 1024 → 4096`; `TOKEN_BUDGET` env-overridable (16,384 used).
- Ctxpact server logging: `llama-script.sh tools()` now logs to `~/.ctxpact/server.log` (was `/dev/null`).

## Functional verification
- **pi coding agent**: live (this session) against `http://10.0.0.1:8080/v1`; `~/.pi/agent/models.json` long contextWindow 163,840 → 176,403; stale `qwen-27b-r` entry removed from `settings.json`.
- **AnythingLLM RAG**: `rag` tool verified (API key works, 7 workspaces incl. `pi-coding-agent`); `.env` fixed: `EMBEDDING_MODEL_PREF=nomic-embed-text-v1.f16.gguf`, `LOCAL_AI_MODEL_TOKEN_LIMIT=106496`; container recreated, API verified.
- **Compaction**: validated above.
- **Full stack healthy at handoff**: llama `:8080` + `:8081`, ctxpact `:8000` (health 200), qdrant `:6333`, searxng `:8082`.

## Files modified
- `/home/ransika/Documents/github/linux/bash/llama-script.sh` (also hard-linked at `/usr/local/bin/llama-script.sh`) — threads, kill/port-wait hardening, self-safe pkill pattern, ctxpact log file
- `/home/ransika/Documents/github/ctxpact/config-qwen-27b-g-fast.yaml`, `config-qwen-27b-g-long.yaml` — compaction + timeout
- `/home/ransika/Documents/github/ctxpact/bench/benchmark_readagent_direct.py`, `benchmark_locomo.py` — bench config fixes
- `/home/ransika/.pi/agent/models.json`, `settings.json`
- `/home/ransika/applications/anythingllm/.env`
- `/home/ransika/Documents/github/linux/results/*` — apibench, coding-bench, compaction tests, window scripts, bench launchers, logs, memory baseline

## CPU tuned-profile A/B (Step 21)
| test | balanced | throughput-performance | Δ |
|---|---|---|---|
| pp512 | 624.96 ± 2.63 | 629.14 ± 0.37 | +0.7% |
| pp1024 | 623.74 ± 0.16 | 624.34 ± 0.58 | +0.1% |
| pp8192 | 565.59 ± 0.08 | 566.46 ± 0.21 | +0.2% |
| tg128 | 24.26 ± 0.11 | 24.62 ± 0.06 | +1.5% |

Deltas within run-to-run noise (GPU-offloaded workload; CPU handles tokenization, server plumbing, KV spillover). **Decision: keep `throughput-performance`** (current active profile; slightly better, zero downside). Bench command: `llama bench` with `-ngl 9999 -t 8 -b 1024 -ub 512 -ctk q5_0 -ctv q5_0`, 3 reps, stack stopped/restored around the run.

## Manual follow-ups
- **[Optional]** LongMemEval accuracy: obtain `longmemeval_oracle.json`, then `benchmark_longmemeval.py` (script ready).
- Monitor `~/.ctxpact/server.log` for future 503 diagnostics.

## [DONE] tags
- [DONE:1] memory baseline
- [DONE:2] bench binary match
- [DONE:3] bench baseline F0
- [DONE:4] fast sweeps
- [DONE:5] long sweeps
- [DONE:6] perplexity
- [DONE:7] end-to-end baselines
- [DONE:8] batch sweep
- [DONE:9] thread sweep
- [DONE:10] speculative depth sweep (n-max 2)
- [DONE:11] fast KV precision
- [DONE:12] long KV precision
- [DONE:13] long context cap
- [DONE:14] llama-script.sh flags + hard-link
- [DONE:15] ctxpact config edits
- [DONE:16] compaction tuning validated (clean run, 3 compactions, 0 503s)
- [DONE:17] ctxpact bench suite validated (ReadAgent 8/8; LoCoMo 18/20; LongMemEval skipped)
- [DONE:18] AnythingLLM .env fixes
- [DONE:19] pi models.json contextWindow
- [DONE:20] pi settings.json cleanup
- [DONE:22] memory monitor (stopped at handoff)
- [DONE:23] full benchmark re-run under final flags
- [DONE:24] perplexity delta valid
- [DONE:25] final functional verification (pi, AnythingLLM RAG, compaction)
- [DONE:21] CPU tuned A/B (balanced vs throughput-performance; kept throughput-performance)
- [DONE:26] this report
