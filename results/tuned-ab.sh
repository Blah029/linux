#!/usr/bin/env bash
# Step 21: CPU tuned-profile A/B. Usage: bash tuned-ab.sh <balanced|throughput>
# Self-healing: stops llama servers, benches the fast model under the CURRENT
# tuned profile (verified), restores the full stack.
set -u

PROFILE="${1:?usage: tuned-ab.sh <balanced|throughput>}"
R="$HOME/Documents/github/linux/results"
L="$HOME/.local/bin/llama"
FAST="$HOME/applications/llama-cpp/models/qwen/ista-daslab/Qwen3.8-27B-GSQ-RCO-IQ3_XXS-mtp.gguf"
ACTIVE=$(cat /etc/tuned/active_profile 2>/dev/null)
log() { echo "[$(date +%H:%M:%S)] $*"; }

wait_vram_free() {
    for i in $(seq 1 60); do
        local v=$(cat /sys/class/drm/card1/device/mem_info_vram_used)
        if [ "$v" -lt 2000000000 ]; then log "VRAM free: $v B"; return 0; fi
        sleep 2
    done
    log "WARNING: VRAM still in use after 120s: $(cat /sys/class/drm/card1/device/mem_info_vram_used)"
    return 1
}

wait_healthy() {
    for i in $(seq 1 90); do
        if curl -s --max-time 3 "http://127.0.0.1:$1/v1/models" | grep -q '"data"'; then
            log "port $1 healthy"; return 0
        fi
        sleep 2
    done
    log "WARNING: port $1 not healthy after 180s"; return 1
}

log "TUNED-AB START profile-requested=$PROFILE active=$ACTIVE"
if [ "$ACTIVE" != "$PROFILE" ]; then
    log "ERROR: active tuned profile is '$ACTIVE', expected '$PROFILE'. Run: sudo tuned-adm profile $PROFILE"
    exit 1
fi

# buffer for any live pi response, then stop llama servers (keep ctxpact/qdrant/docker)
sleep 90
pkill -x llama 2>/dev/null && log "stopped llama servers" || log "no llama processes to stop"
wait_vram_free

bench() { # tag extra-args... (bench subcommand: no -td, no -fit, -ngl needs a number)
    local tag="$1"; shift
    log "BENCH $tag: args=$*"
    "$L" bench -m "$FAST" -fa on -ngl 9999 \
        -p 512  -n 0   -r 3 "$@" 2>&1 | sed "s/^/[$tag] /"
    "$L" bench -m "$FAST" -fa on -ngl 9999 \
        -p 1024 -n 0   -r 3 "$@" 2>&1 | sed "s/^/[$tag] /"
    "$L" bench -m "$FAST" -fa on -ngl 9999 \
        -p 8192 -n 0   -r 3 "$@" 2>&1 | sed "s/^/[$tag] /"
    "$L" bench -m "$FAST" -fa on -ngl 9999 \
        -p 0    -n 128 -r 3 "$@" 2>&1 | sed "s/^/[$tag] /"
}

bench "T-$PROFILE" -t 8 -b 1024 -ub 512 -ctk q5_0 -ctv q5_0

log "RESTORE: starting llama-script.sh -a"
nohup bash /usr/local/bin/llama-script.sh -a > "$R/tuned-ab-restore.log" 2>&1 &
wait_healthy 8080
wait_healthy 8081
wait_healthy 8000

log "VRAM used: $(cat /sys/class/drm/card1/device/mem_info_vram_used)"
log "TUNED-AB DONE $PROFILE $(date)"
touch "$R/tuned-ab-$PROFILE-DONE"
