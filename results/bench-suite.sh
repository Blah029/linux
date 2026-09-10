#!/bin/bash
# Bench suite: readagent (8 Frankenstein Qs, direct :8080) + LoCoMo (20 Qs, via ctxpact).
# Pattern per bench: sleep (buffer for live pi response) -> full-stack restart
# (llama-script.sh -a: kill_processes waits for ports to free before the new
# serve binds; pkill uses self-safe 'ctxpact[.]server' pattern) -> wait health
# -> run benchmark.
R=/home/ransika/Documents/github/linux/results
B=/home/ransika/Documents/github/ctxpact/bench
PY=/home/ransika/Documents/github/ctxpact/.venv/bin/python3
export BENCH_MODEL=Qwen3.8-27B-GSQ-RCO-IQ3_XXS

wait_health() {
  for i in $(seq 1 150); do
    h1=$(curl -s --max-time 3 -o /dev/null -w "%{http_code}" http://10.0.0.1:8080/health)
    h2=$(curl -s --max-time 3 -o /dev/null -w "%{http_code}" http://10.0.0.1:8000/health)
    [ "$h1" = "200" ] && [ "$h2" = "200" ] && break
    sleep 5
  done
  echo "health: 8080=$h1 8000=$h2 at $(date +%T)"
}

echo "bench-suite start $(date +%T)"
sleep 90

echo "--- restart #1 ---"
setsid nohup bash /usr/local/bin/llama-script.sh -a > "$R/bench-suite-restart1.log" 2>&1 &
wait_health

echo "--- readagent ---"
cd "$B"
$PY benchmark_readagent_direct.py readagent-final > "$R/readagent-final.log" 2>&1
echo "readagent done $(date +%T)"

echo "--- restart #2 ---"
setsid nohup bash /usr/local/bin/llama-script.sh -a > "$R/bench-suite-restart2.log" 2>&1 &
wait_health

echo "--- locomo (20 Qs) ---"
$PY benchmark_locomo.py --n 20 > "$R/locomo-final.log" 2>&1
echo "locomo done $(date +%T)"

echo "longmemeval SKIPPED (dataset longmemeval_oracle.json not available locally)"
touch "$R/bench-suite-DONE"
echo "bench-suite finished $(date +%T)"
