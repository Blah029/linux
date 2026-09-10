#!/usr/bin/env bash
# Window B: speculative-depth sweep (n-max 2/3/4) with -t 8 -td 8, measured via HTTP API.
# Ends by restoring the full stack via the tuned llama-script.sh (current flags in script).
# Detached-safe: setsid nohup bash window-b.sh
set -u

L="$HOME/.local/bin/llama"
M="$HOME/applications/llama-cpp/models"
FAST="$M/qwen/ista-daslab/Qwen3.8-27B-GSQ-RCO-IQ3_XXS-mtp.gguf"
ALIAS="Qwen3.8-27B-GSQ-RCO-IQ3_XXS"
R="$HOME/Documents/github/linux/results"
SERVE_LOG="$R/window-b-serve.log"

log() { echo "[$(date +%H:%M:%S)] $*"; }

wait_vram_free() {
    for i in $(seq 1 60); do
        local v=$(cat /sys/class/drm/card1/device/mem_info_vram_used)
        if [ "$v" -lt 2000000000 ]; then log "VRAM free: $v B"; return 0; fi
        sleep 2
    done
    log "WARNING: VRAM still in use after 120s"
    return 1
}

wait_healthy() { # port
    for i in $(seq 1 90); do
        if curl -s --max-time 3 "http://127.0.0.1:$1/v1/models" | grep -q '"data"'; then
            log "port $1 healthy"; return 0
        fi
        sleep 2
    done
    log "WARNING: port $1 not healthy after 180s"
    return 1
}

start_variant() { # nmax
    pkill -x llama 2>/dev/null || true
    wait_vram_free
    local args=(serve -t 8 -td 8 -b 1024 -ub 512 -fa on -ngl all -fit off \
        -ctxcp 2 -cram 4096 --context-shift --jinja --host 0.0.0.0 --port 8080 \
        -ctk q5_0 -ctv q5_0 -lm none -ctkd q5_0 -ctvd q5_0 -ngld all \
        --temp 1.0 --top-k 20 --top-p 0.95 --min-p 0.0 --presence-penalty 0.0 --repeat-penalty 1.0 \
        --spec-type draft-mtp --spec-draft-n-max "$1" -a "$ALIAS" -c 106496 -m "$FAST")
    nohup "$L" "${args[@]}" > "$SERVE_LOG" 2>&1 &
    wait_healthy 8080
}

log "=== WINDOW B START $(date) ==="

for N in 2 3 4; do
    log "VARIANT n-max=$N"
    start_variant "$N"
    python3 "$R/apibench.py" --model "$ALIAS" --sizes 1024,4096,15872 --gen 512 --repeat 3 --tag "nmax$N" \
        | tee "$R/window-b-nmax$N-apibench.json"
    python3 "$R/coding-bench.py" "nmax$N" | tee "$R/window-b-nmax$N-coding.json"
done

# Pick best n-max by median gen_tps across apibench sizes
BEST=$(python3 - "$R" <<'EOF'
import json, statistics, sys
R = sys.argv[1]
best = (2, 0.0)
for n in (2, 3, 4):
    try:
        lines = open(f"{R}/window-b-nmax{n}-apibench.json").read().strip().splitlines()
        agg = json.loads(lines[-1][4:])
        g = statistics.median([v["gen_tps"] for v in agg.values()])
        if g > best[1]:
            best = (n, g)
    except Exception:
        pass
print(best[0])
EOF
)
log "BEST n-max = $BEST"

# Final validation with the chosen variant
start_variant "$BEST"
python3 "$R/apibench.py" --model "$ALIAS" --sizes 1024,4096,15872,65536 --gen 128 --repeat 1 --tag final-longctx \
    | tee "$R/window-b-final-longctx.json"
python3 "$R/coding-bench.py" "final" | tee "$R/window-b-final-coding.json"
python3 "$R/e2e-baseline2.py" | tee "$R/window-b-final-e2e.json"

# Restore the full tuned stack
pkill -x llama 2>/dev/null || true
wait_vram_free
log "RESTORE: starting tuned llama-script.sh -a"
nohup bash /usr/local/bin/llama-script.sh -a > "$R/window-b-restore.log" 2>&1 &
wait_healthy 8080
wait_healthy 8081
log "free: $(free -h | grep Mem)"
log "VRAM used: $(cat /sys/class/drm/card1/device/mem_info_vram_used)"
log "=== WINDOW B DONE $(date) ==="
touch "$R/window-b-DONE"
