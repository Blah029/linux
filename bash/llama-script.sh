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
    -m, --model <model>         Large language model. Default gemma-26b" 
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
    model="gemma-26b"
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


autoload() {
    case "${model}" in
        "gemma-12b")
            llm="gemma/gemma-4-12B-it-Q4_0.gguf"
            draft_model="gemma/mtp-gemma-4-12B-it-Q4_0.gguf"
            multimedia_projector="gemma/gemma/mmproj-gemma-4-12B-it-Q8_0.gguf"
            speculative_type="draft-mtp"
            ;;  
        "gemma-26b")
            llm="gemma/gemma-4-26B-A4B-it-Q4_0.gguf"
            draft_model="gemma/mtp-gemma-4-26B-A4B-it-Q4_0.gguf"
            multimedia_projector="gemma/mmproj-gemma-4-26B-A4B-it-Q8_0.gguf"
            speculative_type="draft-mtp"
            ;;  
        "gemma-26b-df")
            llm="gemma/gemma-4-26B-A4B-it-Q4_0.gguf"
            draft_model="gemma/dflash-gemma-4-26B-A4B-it-Q8_0.gguf"
            multimedia_projector="gemma/mmproj-gemma-4-26B-A4B-it-Q8_0.gguf"
            speculative_type="draft-dflash"
            ;;  
        "qwen-27b")
            die "Qwen 3.8 27B not implemented"
            ;;  
    esac
}


main() {
    # Set common llama.cpp parameters
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
    executable_args=(
        -t 12
        -c 0
        -b 1024
        -ub 512
        -fa on
        -ctk q8_0
        -ctv q8_0
        -ngl all
        -mg 0
        -fit on
        -fitt 1024
        -ctkd q8_0
        -ctvd q8_0
        --temp 0.5
        -td 12
        -ngld all
        --host 0.0.0.0
        --port 8080
    )

    # Set model preferences
    autoload
    executable_args+=(-m "$HOME/applications/llama-cpp/models/${llm}")
    if [[ -n $draft_model ]]; then
        executable_args+=(-md "$HOME/applications/llama-cpp/models/${draft_model}")
    fi
    if [[ -n $multimedia_projector ]]; then
        executable_args+=(-mm "$HOME/applications/llama-cpp/models/${multimedia_projector}")
    fi
    if [[ -n $speculative_type ]]; then
        executable_args+=(--spec-type ${speculative_type})
    fi
    
    # Act on flags
    if [ $verbose_flag == true ]; then
        executable_args+=(-v)
    fi
    if [ $tools_flag == true ]; then
        tools
    fi

    # Launch llama.cpp
    ${executable} ${executable_args[@]}
}


parse_arguments "$@"
main
