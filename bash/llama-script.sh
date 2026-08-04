#!/usr/bin/env bash


usage() {
    cat << EOF
Start llama.cpp server
Usage: $(basename "${BASH_SOURCE[0]}") [options] parameter

Options:
    -h, --help                  Print help and exit
    -f, --flag                  Example flag
    -p, --parameter <parameter> Example named parameter
EOF
    exit
}


die() {
    echo >&2 -e "${1-}\n"
    usage
    exit
}


parse_arguments() {
    verbose=false
    model="12B"
    quantisation="4"
    gpu_offload="all"
    
    # Parse flags and named parameters
    while :; do
        case "${1-}" in
            -h | --help) usage;;
            -v | --verbose) verbose=true;;
            -m | --model)
                model="${2-}"
                shift
                ;;
            -q | --quant)
                quantisation="${2-}"
                shift
                ;;
            -o | --offload)
                offload="${2-}"
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
    [[ -z "${model-}" ]] && die "Missing required parameter: --parameter"
    [[ -z "${quantisation-}" ]] && die "Missing required parameter: --parameter"
    [[ -z "${gpu_offload-}" ]] && die "Missing required parameter: --parameter"
    # Check for no. of positional parameters
    [[ ${#args[@]} -lt 0 ]] && die "Missing positional parameters. Given "${#args[@]}", expected 1"
    [[ ${#args[@]} -gt 0 ]] && die "Too many positional parameters. Given "${#args[@]}", expected 1"

}


main() {
    llama serve \
        -m "applications/llama-cpp/gemma-4-${model}-it-Q${quantisation}_0.gguf" \
        -md "applications/llama-cpp/mtp-gemma-4-${model}-it-Q${quantisation}_0.gguf" \
        --spec-type draft-mtp \
        --spec-draft-n-max 3 \
        --spec-draft-ngl all \
        -ngl all \
        --fit on \
        --fit-target 1024 \
        -fa auto \
        -ctk q8_0 \
        -ctv q8_0 \
        --ctx-size 8219 \
        --context-shift \
        --parallel 1 \
        --jinja \
        --host 0.0.0.0 \
        --port 8080 \
        --props \
        --metrics
}


parse_arguments "$@"
main
