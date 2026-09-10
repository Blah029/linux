#!/usr/bin/env bash
# Window A2: llama-bench matrix (fixed: -ngl 9999). Self-healing: stops servers,
# benchmarks, restores the full stack. Detached-safe: setsid nohup bash window-a2.sh
set -u

L="$HOME/.local/bin/llama"
M="$HOME/applications/llama-cpp/models"
FAST="$M/qwen/ista-daslab/Qwen3.8-27B-GSQ-RCO-IQ3_XXS-mtp.gguf"
LONG="$M/qwen/ista-daslab/Qwen3.8-27B-GSQ-RCO-IQ3_S.gguf"
RESTORE_LOG="$HOME/Documents/github/linux/results/window-a2-restore.log"

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

bench() { # model tag extra-args...
    local model="$1"; local tag="$2"; shift 2
    log "BENCH $tag: model=$(basename "$model") args=$*"
    "$L" bench -m "$model" -fa on -ngl 9999 \
        -p 512  -n 0   -r 3 "$@" 2>&1 | grep -vE "WARNING: radv|ggml_vulkan" | sed "s/^/[$tag] /"
    "$L" bench -m "$model" -fa on -ngl 9999 \
        -p 1024 -n 0   -r 3 "$@" 2>&1 | grep -vE "WARNING: radv|ggml_vulkan" | sed "s/^/[$tag] /"
    "$L" bench -m "$model" -fa on -ngl 9999 \
        -p 8192 -n 0   -r 3 "$@" 2>&1 | grep -vE "WARNING: radv|ggml_vulkan" | sed "s/^/[$tag] /"
    "$L" bench -m "$model" -fa on -ngl 9999 \
        -p 0    -n 128 -r 3 "$@" 2>&1 | grep -vE "WARNING: radv|ggml_vulkan" | sed "s/^/[$tag] /"
}

log "=== WINDOW A2 START $(date) ==="
pkill -x llama 2>/dev/null && log "stopped llama servers" || log "no llama processes"
wait_vram_free

bench "$FAST" F0  -t 12 -b 1024 -ub 512 -ctk q5_0 -ctv q5_0
bench "$FAST" F-t6 -t 6  -b 1024 -ub 512 -ctk q5_0 -ctv q5_0
bench "$FAST" F-t8 -t 8  -b 1024 -ub 512 -ctk q5_0 -ctv q5_0
bench "$FAST" F-b2 -t 12 -b 2048 -ub 1024 -ctk q5_0 -ctv q5_0
bench "$FAST" F-b4 -t 12 -b 4096 -ub 2048 -ctk q5_0 -ctv q5_0
bench "$FAST" F-b8 -t 12 -b 8192 -ub 4096 -ctk q5_0 -ctv q5_0
bench "$FAST" F-q8 -t 12 -b 1024 -ub 512 -ctk q8_0 -ctv q5_0

bench "$LONG" L0  -t 12 -b 1024 -ub 512 -ctk q5_0 -ctv q5_0
bench "$LONG" L-t6 -t 6  -b 1024 -ub 512 -ctk q5_0 -ctv q5_0
bench "$LONG" L-t8 -t 8  -b 1024 -ub 512 -ctk q5_0 -ctv q5_0
bench "$LONG" L-b2 -t 12 -b 2048 -ub 1024 -ctk q5_0 -ctv q5_0
bench "$LONG" L-b4 -t 12 -b 4096 -ub 2048 -ctk q5_0 -ctv q5_0
bench "$LONG" L-b8 -t 12 -b 8192 -ub 4096 -ctk q5_0 -ctv q5_0

log "RESTORE: starting llama-script.sh -a"
nohup bash /usr/local/bin/llama-script.sh -a > "$RESTORE_LOG" 2>&1 &
wait_healthy 8080
wait_healthy 8081
log "free: $(free -h | grep Mem)"
log "VRAM used: $(cat /sys/class/drm/card1/device/mem_info_vram_used)"
log "=== WINDOW A2 DONE $(date) ==="
touch "$HOME/Documents/github/linux/results/window-a2-DONE"
