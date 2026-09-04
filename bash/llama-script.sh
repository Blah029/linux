#!/usr/bin/env bash


usage() {
    cat << EOF
Start llama.cpp server
Usage: $(basename "${BASH_SOURCE[0]}") [options] parameter

Options:
    -h, --help                  Print help and exit
    --llama-help                Print llama.cpp help and exit
    -v, --verbose               Enable verbose output
    -r, --restart               Kill existing processes before running command
    -a, --all                   Run all tools for AnythingLLM
    -s, --source <repository>   Binary source. Default github
                                    github          - Run downloaded GitHub Vulkan release
                                    huggingface     - Run HugginFace realease installed from llama.app
    -m, --model <model>         Large language model. Default qwen-27-r
                                    gemma-26b       - Gemma 4 26B A4B
                                    qwen-27-r       - Empero-AI Qwen 3.8 27B Ridge
                                    qwen-27b-q3     - Unsloth Qwen 3.8 27B Q3_K_XL
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
    llama_help_flag=false
    verbose_flag=false
    restart_flag=false
    all_flag=false
    command_source="huggingface"
    model="qwen-27b-g-long"
    embedding_model="nomic/nomic-embed-text-v1.f16.gguf"
    
    # Parse flags and named parameters
    while :; do
        case "${1-}" in
            -h | --help) usage;;
            --llama-help) llama_help_flag=true;;
            -v | --verbose) verbose_flag=true;;
            -r | --restart) restart_flag=true;;
            -a | --all) all_flag=true;;
            -s | --source)
                command_source="${2-}"
                shift
                ;;
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
    [[ -z "${command_source-}" ]] && die "Missing required parameter: --source"
    [[ -z "${model-}" ]] && die "Missing required parameter: --model"
}


autoload() {
    # command
    case ${command_source} in
        "huggingface") command="llama serve";;
        "github") command="$HOME/applications/llama-cpp/binary/vulkan/llama-server";;
    esac

    # Model
    gemma_args=(
        -c 131027
        -ncmoe 7
        -ctk q8_0
        -ctv q8_0
        -fit off
        -ngld all
        --temp 1.0
        --top-k 64
        --top-p 0.95
    )
    qwen_args=(
        -ctk q5_0
        -ctv q4_1
        -lm none
        -fit off
        -ctkd q4_0
        -ctvd q4_0
        -ngld all
        --temp 1.0
        --top-k 20
        --top-p 0.95
        --min-p 0.0
        --presence-penalty 0.0
        --repeat-penalty 1.0
        --spec-draft-n-max 3
        --reasoning-preserve
    )
    case "${model}" in
        "gemma-26b")
            llm="gemma/unsloth/gemma-4-26B-A4B-it-qat-UD-Q4_K_XL.gguf"
            draft_model="gemma/unsloth/mtp-gemma-4-26B-A4B-it-qat-Q8_0.gguf"
            multimedia_projector="gemma/unsloth/mmproj-gemma-4-26B-A4B-it-qat-F16.gguf"
            speculative_type="draft-mtp"
            command_args+=(
                ${gemma_args[@]}
                -a "gemma-4-26B-A4B-it-qat-UD-Q4_K_XL"
            )
            ;;  
        "qwen-27b-r")
            llm="qwen/empero-ai/Qwen3.8-27B-Ridge-3.7bpw.gguf"
            multimedia_projector="qwen/empero-ai/mmproj-Qwen3.8-27B-BF16.gguf"
            speculative_type="draft-mtp,ngram-mod"
            command_args+=(
                ${qwen_args[@]}
                -a "Qwen3.8-27B-Ridge-3.7bpw"
                -c 131072
            )
            ;;
        "qwen-27b-g-fast")
            llm="qwen/ista-daslab/Qwen3.8-27B-GSQ-RCO-IQ3_XXS-mtp.gguf"
            speculative_type="draft-mtp"
            command_args+=(
                ${qwen_args[@]}
                -a "Qwen3.8-27B-GSQ-RCO-IQ3_XXS"
                -c 90112
            )
            ;;
        "qwen-27b-g-long")
            llm="qwen/ista-daslab/Qwen3.8-27B-GSQ-RCO-IQ3_S.gguf"
            draft_model="qwen/hermihg/Qwen3.8-27B-DFlash2-Q2_K_S-MIX.gguf"
            multimedia_projector="qwen/empero-ai/mmproj-Qwen3.8-27B-BF16.gguf"
            speculative_type="draft-dflash"
            command_args+=(
                ${qwen_args[@]}
                -a "Qwen3.8-27B-GSQ-RCO-IQ3_S"
                -c 163840
                
            )
            ;;
        -?*) die "Incorrect model name: ${model}";;
    esac
}


kill_processes(){
    pkill llama
    pkill qdrant
    pkill -f ctxpact
}


tools() {
    # Context compaction proxy
    nohup ptyxis -- bash -c "cd $HOME/Documents/github/ctxpact \
        && source .venv/bin/activate \
        && python -m ctxpact.server --config config-${model}.yaml --local" > "$HOME/temp/nohup-ctxpact.txt" 2>&1 &
    # Embedding model
    embedding_model_path="$HOME/applications/llama-cpp/models/${embedding_model}"
    nohup ptyxis -- bash -c "${command} \
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
    command_args=(
        -t 12
        -b 1024
        -ub 512
        -fa on
        -ngl all
        -td 12
        -ctxcp 2
        -cram 4096
        --context-shift
        --jinja
        --host 0.0.0.0
        --port 8080
    )
    # Kill running processes
    if [ $restart_flag == true ]; then
        kill_processes
    fi

    # Load model preferences
    autoload
    command_args+=(-m "$HOME/applications/llama-cpp/models/${llm}")
    if [[ -n $draft_model ]]; then
        command_args+=(-md "$HOME/applications/llama-cpp/models/${draft_model}")
    fi
    if [[ -n $multimedia_projector ]]; then
        command_args+=(-mm "$HOME/applications/llama-cpp/models/${multimedia_projector}")
    fi
    if [[ -n $speculative_type ]]; then
        command_args+=(--spec-type ${speculative_type})
    fi
    
    # Act on flags
    if [ $llama_help_flag == true ]; then
        command_args=(--help)
        all_flag=false
    fi
    if [ $verbose_flag == true ]; then
        command_args+=(-lv 4)
    fi
    if [ $all_flag == true ]; then
        kill_processes
        tools
    fi

    # Launch llama.cpp
    ${command} ${command_args[@]}
}


parse_arguments "$@"
main
