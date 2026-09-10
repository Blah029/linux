# Memory baseline (step 1)

Captured while fast model (qwen-27b-g-fast) server + embedding server are running.

| Metric | Value |
|---|---|
| VRAM used | 15,998,885,888 B ≈ 14.95 GiB |
| VRAM total | 17,095,983,104 B ≈ 15.92 GiB |
| VRAM utilization | ~94% |
| RAM total | 15 GiB |
| RAM used | 10 GiB |
| RAM available | 5.2 GiB |
| Swap used | 1.9 GiB (pressure indicator) |

CSV expectations for comparison:
- Avg idle VRAM ~0.86 GiB; idle RAM ~5 GiB; prompt cache 4 GiB; 2 checkpoints/slot × 4 slots; 1 GiB headroom.
- Fast model heavy (131072 ctx): VRAM 15.4–15.7 GiB, GTT 1.2 GiB, RAM 6.0–6.1 GiB — consistent with observed VRAM 14.95 GiB (context in use < max).

Notes:
- Swap already 1.9 GiB used → keep RAM headroom conservative; long model (176403 ctx) will add ~3.5 GiB GTT + ~9 GiB RAM under heavy load per CSV, which risks OOM with current desktop footprint. Fallback cap for long: -c 163840.
- Idle state (no llama servers) not captured without stopping services; CSV idle values used as reference.
