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
    model_path="applications/llama-cpp/models/gemma-4-${model}-it-Q${quantisation}_0.gguf"
    mtp_path="applications/llama-cpp/models/mtp-gemma-4-${model}-it-Q${quantisation}_0.gguf"
    llama serve \
        -m ${model_path} \
        -md ${mtp_path} \
        --spec-type draft-mtp \
        -t 12 \
        -c 0 \
        -b 8192 \
        -ub 4096 \
        -fa on \
        -ctk q8_0 \
        -ctv q8_0 \
        -ngl all \
        -mg 0 \
        -fit on \
        -fitt 1024 \
        -ctkd q8_0 \
        -ctvd q8_0 \
        --temp 0.5 \
        -ngld all \
        --host 0.0.0.0 \
        --port 8080
}


parse_arguments "$@"
main
