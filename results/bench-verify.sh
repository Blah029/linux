#!/bin/bash
# Final bench validation: full-stack restart -> readagent (budget=16384)
# -> locomo 20 Qs (max_tokens=4096, local config) -> restore stack ctxpact.
R=/home/ransika/Documents/github/linux/results
B=/home/ransika/Documents/github/ctxpact/bench
PY=/home/ransika/Documents/github/ctxpact/.venv/bin/python3
export BENCH_MODEL=Qwen3.8-27B-GSQ-RCO-IQ3_XXS
export CTXPACT_CONFIG=config-qwen-27b-g-fast.yaml
export READAGENT_TOKEN_BUDGET=16384

wait_health() {
  for i in $(seq 1 150); do
    h1=$(curl -s --max-time 3 -o /dev/null -w "%{http_code}" http://10.0.0.1:8080/health)
    h2=$(curl -s --max-time 3 -o /dev/null -w "%{http_code}" http://10.0.0.1:8000/health)
    [ "$h1" = "200" ] && [ "$h2" = "200" ] && break
    sleep 5
  done
  echo "health: 8080=$h1 8000=$h2 at $(date +%T)"
}

echo "bench-verify start $(date +%T)"
sleep 90

echo "--- full-stack restart ---"
setsid nohup bash /usr/local/bin/llama-script.sh -a > "$R/bench-verify-restart.log" 2>&1 &
wait_health

echo "--- readagent (budget=16384) ---"
cd "$B"
$PY benchmark_readagent_direct.py readagent-final3 > "$R/readagent-final3.log" 2>&1
echo "readagent done $(date +%T)"

echo "--- locomo 20 (max_tokens=4096) ---"
$PY benchmark_locomo.py --n 20 --label locomo-final3 > "$R/locomo-final3.log" 2>&1
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
touch "$R/bench-verify-DONE"
echo "bench-verify finished $(date +%T)"
