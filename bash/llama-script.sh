#!/usr/bin/env bash


usage() {
    cat << EOF
Start llama.cpp server
Usage: $(basename "${BASH_SOURCE[0]}") [options] parameter

Options:
    -h, --help                  Print help and exit
    -v, --verbose               Enable verbose output
    -a, --all                   Run all tools for AnythingLLM
    --vulkan                    Run downloaded GitHub Vulkan release
    --rocm                      Run downloaded GitHub ROCm release
    -m, --model <model>         Large language model. Default qwen-27b 
                                    gemma-12b       - Gemma 4 12B. Good for large image PDFs
                                    gemma-26b       - Gemma 4 26B A4B with Multi-Token Prediction 
                                    gemma-26b-df    - Gemma 4 26B A4B with DFlash. Good for large text PDFs
                                    qwen-27b        - Qwen 3.8 27B
    --em <file>                 Vector embedding model in GGUF format. Default nomic/nomic-embed-text-v1.f16.gguf
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
    verbose_flag=false
    tools_flag=false
    executable="llama serve"
    model="qwen-27b"
    embedding_model="nomic/nomic-embed-text-v1.f16.gguf"
    
    # Parse flags and named parameters
    while :; do
        case "${1-}" in
            -h | --help) usage;;
            -v | --verbose) verbose_flag=true;;
            -a | --all) tools_flag=true;;
            --vulkan) executable="$HOME/applications/llama-cpp/binary/vulkan/llama-server";;
            --rocm) executable="$HOME/applications/llama-cpp/binary/rocm/llama-server";;
            -m | --model)
                model="${2-}"
                shift
                ;;
            --em)
                embedding_model="${2-}"
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
    [[ -z "${embedding_model-}" ]] && die "Missing required parameter: --em"
}


autoload() {
    gemma_args=(
        -c 262144
        --temp 1.0
        --top-k 64
        --top-p 0.95
    )
    qwen_args=(
        -c 131072
        --temp 1.0
        --top-k 20
        --top-p 0.95
        --presence-penalty 0.0
        --spec-draft-n-max 3
    )
    case "${model}" in
        "gemma-26b")
            llm="gemma/unsloth/gemma-4-26B-A4B-it-qat-UD-Q4_K_XL.gguf"
            draft_model="gemma/unsloth/mtp-gemma-4-26B-A4B-it-Q8_0.gguf"
            multimedia_projector="gemma/unsloth/mmproj-gemma-4-26B-A4B-it-F16.gguf"
            speculative_type="draft-mtp"
            common_args+=(${gemma_args[@]})
            ;;  
        "qwen-27b")
            llm="qwen/empero-ai/Qwen3.8-27B-Ridge-3.7bpw.gguf"
            multimedia_projector="qwen/empero-ai/mmproj-Qwen3.8-27B-BF16.gguf"
            speculative_type="draft-mtp"
            common_args+=(${qwen_args[@]})
            ;;
    esac
}


tools() {
    # Embedding model
    embedding_model_path="$HOME/applications/llama-cpp/models/${embedding_model}"
    nohup ptyxis -- bash -c "${executable} \
        -m ${embedding_model_path} \
        --rope-scaling yarn \
        --rope-freq-scale .75 \
        -c 2048 \
        -b 2048 \
        -ub 2048 \
        -ngl all \
        --embedding \
        --host 0.0.0.0 \
        --port 8081" > "$HOME/temp/nohup-nomic.txt" 2>&1 &
    # Vector database
    nohup ptyxis -- bash -c "cd $HOME/applications/qdrant \
        && ./qdrant" > "$HOME/temp/nohup-qdrant.txt" 2>&1 &
}


main() {
    # Setup comomon parameters
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
    common_args=(
        -t 12
        -b 1024
        -ub 512
        -fa on
        -ctk q8_0
        -ctv q8_0
        -ngl all
        -mg 0
        -ctkd q8_0
        -ctvd q8_0
        -td 12
        -ngld all
        --jinja
        --host 0.0.0.0
        --port 8080
    )

    # Load model preferences
    autoload
    common_args+=(-m "$HOME/applications/llama-cpp/models/${llm}")
    if [[ -n $draft_model ]]; then
        common_args+=(-md "$HOME/applications/llama-cpp/models/${draft_model}")
    fi
    if [[ -n $multimedia_projector ]]; then
        common_args+=(-mm "$HOME/applications/llama-cpp/models/${multimedia_projector}")
    fi
    if [[ -n $speculative_type ]]; then
        common_args+=(--spec-type ${speculative_type})
    fi
    
    # Act on flags
    if [ $verbose_flag == true ]; then
        common_args+=(-v)
    fi
    if [ $tools_flag == true ]; then
        tools
    fi

    # Launch llama.cpp
    ${executable} ${common_args[@]}
}


parse_arguments "$@"
main
