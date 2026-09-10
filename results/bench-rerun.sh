#!/bin/bash
# Bench re-run (fixed): full-stack restart -> readagent (max_tokens=4096)
# -> locomo 20 Qs (local config via CTXPACT_CONFIG) -> restore stack ctxpact.
R=/home/ransika/Documents/github/linux/results
B=/home/ransika/Documents/github/ctxpact/bench
PY=/home/ransika/Documents/github/ctxpact/.venv/bin/python3
export BENCH_MODEL=Qwen3.8-27B-GSQ-RCO-IQ3_XXS
export CTXPACT_CONFIG=config-qwen-27b-g-fast.yaml

wait_health() {
  for i in $(seq 1 150); do
    h1=$(curl -s --max-time 3 -o /dev/null -w "%{http_code}" http://10.0.0.1:8080/health)
    h2=$(curl -s --max-time 3 -o /dev/null -w "%{http_code}" http://10.0.0.1:8000/health)
    [ "$h1" = "200" ] && [ "$h2" = "200" ] && break
    sleep 5
  done
  echo "health: 8080=$h1 8000=$h2 at $(date +%T)"
}

echo "bench-rerun start $(date +%T)"
sleep 90

echo "--- full-stack restart ---"
setsid nohup bash /usr/local/bin/llama-script.sh -a > "$R/bench-rerun-restart.log" 2>&1 &
wait_health

echo "--- readagent (max_tokens=4096) ---"
cd "$B"
$PY benchmark_readagent_direct.py readagent-final2 > "$R/readagent-final2.log" 2>&1
echo "readagent done $(date +%T)"

echo "--- locomo 20 (local config) ---"
$PY benchmark_locomo.py --n 20 > "$R/locomo-final2.log" 2>&1
echo "locomo done $(date +%T)"

echo "--- restore stack ctxpact ---"
PAT='ctxpact[.]server'; pkill -f "$PAT"
sleep 2
setsid nohup ptyxis -- bash -c "cd $HOME/Documents/github/ctxpact && source .venv/bin/activate && python -m ctxpact.server --config config-qwen-27b-g-fast.yaml" > "$HOME/.ctxpact/server.log" 2>&1 &
for i in $(seq 1 60); do
  h=$(curl -s --max-time 3 -o /dev/null -w "%{http_code}" http://10.0.0.1:8000/health)
  [ "$h" = "200" ] && break
  sleep 2
done
echo "ctxpact health: $h"
touch "$R/bench-rerun-DONE"
echo "bench-rerun finished $(date +%T)"
