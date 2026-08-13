#!/usr/bin/env bash


usage() {
    cat << EOF
Run stress-ng and FurMark GUI benchmarks
Usage: $(basename "${BASH_SOURCE[0]}") [options]

Options:
    -h, --help              Print help and exit
    -c, --cpu               Run cpu benchmark
    -g, --gpu               Run gpu benchmark
    -t, --time <time>       Specify cpu benchmark time. Default 5m
EOF
    exit
}


die() {
    echo >&2 -e "${1-}\n"
    usage
    exit
}


parse_arguments() {
    # Flags
    test_cpu=false
    test_gpu=false
    cpu_time=5m

    # Parse flags and named parameters
    while :; do
        case "${1-}" in
            -h | --help) usage;;
            -c | --cpu) test_cpu=true;;
            -g | --gpu) test_gpu=true;;
            -t | --time)
                cpu_time="${2-}"
                shift
                ;;
            # Exit if an unexpected option is passed
            -?*) die "Unexpected option: $1";;
            # If no matches, break while loop to parse positional parameters
            *) break;;
        esac
        shift
    done

    # Parse positional parameters
    args=("$@")

    # Check for required named parameters
    [[ -z "${cpu_time-}" ]] && die "Missing required parameter: --time"
}


main() {
    # Launch commands in background
    pids=()  # array to store PIDs

    $test_cpu && stress-ng --matrix 0 -t "$cpu_time" --tz & pids+=($!)
    $test_gpu && mangohud "$HOME/applications/furmark/FurMark_GUI" & pids+=($!)

    # Wait for all launched processes
    if [ ${#pids[@]} -gt 0 ]; then
        wait "${pids[@]}"
    fi

}

parse_arguments "$@"
main

