#!/usr/bin/env bash


usage() {
    cat << EOF
Start llama.cpp server
Usage: $(basename "${BASH_SOURCE[0]}") [options] parameter

Options:
    -h, --help                  Print help and exit
    -v, --verbose               Enable verbose output
    -m, --model <path>          Large language model in GGUF format
    --mtp <path>                Multitoken prediction head in GGUF format
    --mmproj <path>             Multimedia projector in GGUF format
    -o, --offload <layers>      Numebr of layers to offload to gpu. Default all
EOF
    exit
}


die() {
    echo >&2 -e "${1-}\n"
    usage
    exit
}


parse_arguments() {
    # Defaults
    verbosity=3
    model="gemma-4-12B-it-Q4_0.gguf"
    mtp="mtp-gemma-4-12B-it-Q4_0.gguf"
    mmproj="mmproj-gemma-4-12B-it-Q8_0.gguf"
    gpu_offload="all"
    
    # Parse flags and named parameters
    while :; do
        case "${1-}" in
            -h | --help) usage;;
            -v | --verbose) verbosity=5;;
            -m | --model)
                model="${2-}"
                shift
                ;;
            --mtp)
                mtp="${2-}"
                shift
                ;;
            -mmproj)
                mmproj="${2-}"
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
    [[ -z "${model-}" ]] && die "Missing required parameter: --model"
    [[ -z "${mtp-}" ]] && die "Missing required parameter: --mtp"
    [[ -z "${mmproj-}" ]] && die "Missing required parameter: --mmproj"
    [[ -z "${gpu_offload-}" ]] && die "Missing required parameter: --offload"
    # Check for no. of positional parameters
    [[ ${#args[@]} -lt 0 ]] && die "Missing positional parameters. Given "${#args[@]}", expected 1"
    [[ ${#args[@]} -gt 0 ]] && die "Too many positional parameters. Given "${#args[@]}", expected 1"

}


main() {
    model_path="applications/llama-cpp/models/${model}"
    mtp_path="applications/llama-cpp/models/${mtp}"
    mmproj_path="applications/llama-cpp/models/${mmproj}"
    llama serve \
        -m ${model_path} \
        -md ${mtp_path} \
        -mm ${mmproj_path} \
        --spec-type draft-mtp \
        -t 12 \
        -c 0 \
        -b 256 \
        -ub 128 \
        -fa on \
        -ctk q8_0 \
        -ctv q8_0 \
        -ngl all \
        -mg 0 \
        -fit on \
        -fitt 1024 \
        -lv ${verbosity} \
        -ctkd q8_0 \
        -ctvd q8_0 \
        --temp 0.5 \
        -td 12 \
        -ngld all \
        --host 0.0.0.0 \
        --port 8080
    # Min. batch size for full gpu utilisation
    #   -b 256 \
    #   -ub 128 \
    # Max. batch size for parsing large pdfs as images 
    #   -b 2048 \
    #   -ub 1024 \
    # Max. batch size for parsing large pfds as text
    #   -b 8192 \
    #   -ub 4096 \
}


parse_arguments "$@"
main
