#!/usr/bin/env bash


usage() {
    cat << EOF
Start llama.cpp server
Usage: $(basename "${BASH_SOURCE[0]}") [options] parameter

Options:
    -h, --help                  Print help and exit
    -v, --verbose               Enable verbose output
    -g, --github                Run downloaded GitHub Vulkan release
    -r, --rocm                  Run downloaded GitHub ROCm release
    -m, --model <path>          Large language model in GGUF format. Default gemma-4-12B-it-Q4_0.gguf". 
                                Or
                                    12b     - Auto load Gemma 4 12B models. Good for large image PDFs
                                    26b-m   - Audo load Gemma 4 26B A4B with Multi-Token Prediction 
                                    26b-d   - Auto load Gemma 4 26B A4B with DFlash. Good for large text PDFs
    --md <path>                 Multitoken prediction head in GGUF format. Default mtp-gemma-4-12B-it-Q4_0.gguf
    --mm <path>                 Multimedia projector in GGUF format. Default mmproj-gemma-4-12B-it-Q8_0.gguf"
    --st <type>                 Speculative decoding type
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
    model="gemma-4-26B-A4B-it-Q4_0.gguf"
    draft_model="mtp-gemma-4-26B-A4B-it-Q4_0.gguf"
    multimedia_projector="mmproj-gemma-4-26B-A4B-it-Q8_0.gguf"
    speculative_type="draft-mtp"
    gpu_offload="all"
    executable="llama serve"
    
    # Parse flags and named parameters
    while :; do
        case "${1-}" in
            -h | --help) usage;;
            -v | --verbose) verbosity=5;;
            -g | --github) executable="applications/llama-cpp/binary/vulkan/llama-server";;
            -r | --rocm) executable="applications/llama-cpp/binary/rocm/llama-server";;
            -m | --model)
                model="${2-}"
                autoload
                shift
                ;;
            --md)
                draft_model="${2-}"
                shift
                ;;
            --mm)
                multimedia_projector="${2-}"
                shift
                ;;
            --st)
                speculative_type="${2-}"
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
    [[ -z "${draft_model-}" ]] && die "Missing required parameter: --md"
    [[ -z "${multimedia_projector-}" ]] && die "Missing required parameter: --mm"
    [[ -z "${speculative_type-}" ]] && die "Missing required parameter: --mm"
    [[ -z "${gpu_offload-}" ]] && die "Missing required parameter: --offload"
    # Check for no. of positional parameters
    [[ ${#args[@]} -lt 0 ]] && die "Missing positional parameters. Given "${#args[@]}", expected 1"
    [[ ${#args[@]} -gt 0 ]] && die "Too many positional parameters. Given "${#args[@]}", expected 1"    
}


autoload() {
    case "${model}" in
        "12b")
            model="gemma-4-12B-it-Q4_0.gguf"
            draft_model="mtp-gemma-4-12B-it-Q4_0.gguf"
            multimedia_projector="mmproj-gemma-4-12B-it-Q8_0.gguf"
            speculative_type="draft-mtp"
            ;;  
        "26b-m")
            model="gemma-4-26B-A4B-it-Q4_0.gguf"
            draft_model="mtp-gemma-4-26B-A4B-it-Q4_0.gguf"
            multimedia_projector="mmproj-gemma-4-26B-A4B-it-Q8_0.gguf"
            speculative_type="draft-mtp"
            ;;  
        "26b-d")
            model="gemma-4-26B-A4B-it-Q4_0.gguf"
            draft_model="draft-gemma-4-26B-A4B-it-Q8_0.gguf"
            multimedia_projector="mmproj-gemma-4-26B-A4B-it-Q8_0.gguf"
            speculative_type="draft-mtp"
            ;;  
    esac
}


main() {
    model_path="applications/llama-cpp/models/${model}"
    draft_model_path="applications/llama-cpp/models/${draft_model}"
    multimedia_projector_path="applications/llama-cpp/models/${multimedia_projector}"
    ${executable} \
        -m ${model_path} \
        -md ${draft_model_path} \
        -mm ${multimedia_projector_path} \
        --spec-type ${speculative_type} \
        -t 12 \
        -c 0 \
        -b 1024 \
        -ub 512 \
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
    # Min. batch size for parsing large pdfs as images
    #   -b 1024 \
    #   -ub 512 \
    # Max. batch size for parsing large pdfs as images 
    #   -b 2048 \
    #   -ub 1024 \
    # Max. batch size for parsing large pfds as text
    #   -b 8192 \
    #   -ub 4096 \
    #
}


parse_arguments "$@"
main
