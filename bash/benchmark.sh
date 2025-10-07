#!/bin/bash

# Track which commands to run
test_cpu=false
test_gpu=false
print_help=false

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        --cpu|-c) test_cpu=true ;;
        --gpu|-g) test_gpu=true ;;
	--help) print_help=true ;;
    esac
done

# Launch commands in background
pids=()  # array to store PIDs

$test_cpu && stress-ng --matrix 0 -t 5m --tz & pids+=($!)
$test_gpu && mangohud "/usr/local/bin/FurMark_2.9.0.0_linux64/FurMark_linux64/FurMark_GUI" & pids+=($!)
$print_help && echo -e  "benchmark.sh [arguments]\n    --cpu       Run CPU  benchmark\n    --gpu       Run GPU benchmark\n    --help      Print help"

# Wait for all launched processes
if [ ${#pids[@]} -gt 0 ]; then
    wait "${pids[@]}"
fi

