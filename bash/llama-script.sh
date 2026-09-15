#!/usr/bin/env bash


usage() {
    cat << EOF
Start llama.cpp server
Usage: $(basename "${BASH_SOURCE[0]}") [options] parameter

Options:
    -h, --help                  Print help and exit
    --llama-help                Print llama.cpp help and exit
    -v, --verbose               Enable verbose output
    -a, --all                   Run all supporting tools
    -s, --source <repository>   Binary source. Default github
                                    github          - Run downloaded GitHub Vulkan release
                                    huggingface     - Run HugginFace realease installed from llama.app
    -m, --model <model>         Large language model. Default qwen-27-r
                                    gemma-26b       - Gemma 4 26B A4B
                                    qwen-27b-g-fast - ISTA-DASLab Qwen3.8 27B GSQ RCO GGUF IQ3_XXS 
                                    qwen-27b-g-long - ISTA-DASLab Qwen3.8 27B GSQ RCO GGUF IQ3_S
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
    all_flag=false
    command_source="huggingface"
    model="qwen-27b-g-fast"
    
    # Parse flags and named parameters
    while :; do
        case "${1-}" in
            -h | --help) usage;;
            --llama-help) llama_help_flag=true;;
            -v | --verbose) verbose_flag=true;;
            -a | --all) all_flag=true;;
            -s | --source)
                command_source="${2-}"
                shift
                ;;
            -m | --model)
                model="${2-}"
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


kill_processes(){
    pkill llama
    pkill qdrant
    pkill -f ctxpact
    sleep 1
}


tools() {
    # Context compaction proxy
    nohup ptyxis -- bash -c "cd $HOME/Documents/github/ctxpact \
        && source .venv/bin/activate \
        && python -m ctxpact.server --config config-${model}.yaml" > /dev/null 2>&1 &
    # Embedding model
    nohup ptyxis -- bash -c "${command} \
        -a nomic-embed-text-v1 \
        -m $HOME/applications/llama-cpp/models/nomic/nomic-embed-text-v1.f16.gguf \
        --rope-scaling yarn \
        --rope-freq-scale .75 \
        -c 2048 \
        -b 2048 \
        -ub 2048 \
        -ngl all \
        --embedding \
        --host 0.0.0.0 \
        --port 8081" > /dev/null 2>&1 &
    # Vector database
    nohup ptyxis -- bash -c "cd $HOME/applications/qdrant \
        && ./qdrant" > /dev/null 2>&1 &
}


autoload() {
    # command
    case ${command_source} in
        "huggingface") command="llama serve";;
        "github") command="$HOME/applications/llama-cpp/binary/vulkan/llama-server";;
    esac

    # Model
    model_dir="$HOME/applications/llama-cpp/models/"
    gemma_args=(
        -c 131027
        -ncmoe 7
        -ctk q8_0
        -ctv q8_0
        -ngld all
        --temp 1.0
        --top-k 64
        --top-p 0.95
    )
    qwen_args=(
        -ctk q5_0
        -ctv q5_0
        -lm none
        -ctkd q5_0
        -ctvd q5_0
        -ngld all
        --temp 1.0
        --top-k 20
        --top-p 0.95
        --min-p 0.0
        --presence-penalty 0.0
        --repeat-penalty 1.0
        --spec-draft-n-max 2
        --reasoning-preserve
    )
    case "${model}" in
        "gemma-26b") command_args+=(
            ${gemma_args[@]}
            -a "gemma-4-26B-A4B-it-qat-UD-Q4_K_XL"
            -m "${model_dir}/gemma/unsloth/gemma-4-26B-A4B-it-qat-UD-Q4_K_XL.gguf"
            -md "${model_dir}/gemma/unsloth/mtp-gemma-4-26B-A4B-it-qat-Q8_0.gguf"
            -mm "${model_dir}/gemma/unsloth/mmproj-gemma-4-26B-A4B-it-qat-F16.gguf"
            --spec-type "draft-mtp"
        );;  
        "qwen-27b-g-fast") command_args+=(
            ${qwen_args[@]}
            -a "Qwen3.8-27B-GSQ-RCO-IQ3_XXS"
            -m "${model_dir}/qwen/ista-daslab/Qwen3.8-27B-GSQ-RCO-IQ3_XXS-mtp.gguf"
            --spec-type "draft-mtp"
            -c 106496
        );;
        "qwen-27b-g-long") command_args+=(
            ${qwen_args[@]}
            -a "Qwen3.8-27B-GSQ-RCO-IQ3_S"
            -m "${model_dir}/qwen/ista-daslab/Qwen3.8-27B-GSQ-RCO-IQ3_S.gguf"
            -md "${model_dir}/qwen/hermihg/Qwen3.8-27B-DFlash2-Q2_K_S-MIX.gguf"
            -mm "${model_dir}/qwen/empero-ai/mmproj-Qwen3.8-27B-BF16.gguf"
            --spec-type "draft-dflash"
            -c 163840
        );;
        *) die "Incorrect model name: ${model}";;
    esac
}


main() {
    # Setup comomon parameters
    # Min. batch size for full gpu utilisation
    #   -b 256
    #   -ub 128
    # Min. batch size for parsing large pdfs as images
    #   -b 1024
    #   -ub 512
    # Max. batch size for parsing large pdfs as images 
    #   -b 2048
    #   -ub 1024
    # Max. batch size for parsing large pfds as text
    #   -b 8192
    #   -ub 4096
    command_args=(
        -t 8
        -b 1024
        -ub 512
        -fa on
        -ngl all
        -fit off
        -td 8
        -ctxcp 2
        -cram 4096
        --context-shift
        --jinja
        --host 0.0.0.0
        --port 8080
    )

    # Load model preferences
    autoload
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
