#!/usr/bin/env bash


usage() {
    cat << EOF
Start stable-diffusion.cpp server
Usage: $(basename "${BASH_SOURCE[0]}") [options] parameter

Options:
    -h, --help                  Print help and exit
    --diffusion-help            Print stable-diffusion.cpp help and exit
    -v, --verbose               Enable verbose output
    -r, --restart               Kill existing stable-diffusion.cpp processes, llama.cpp processes, and tools
    -s, --source <repository>   Binary source. Default github
                                    github          - Run downloaded GitHub Vulkan release
    -m, --model <model>         Image model. Default qwen-image
                                    qwen-image      - AtomicChat Qwen Image 2.1 Turbo, abliterated uncensored encoder
                                    qwen-image-std  - Qwen Image 2.1 Turbo, stock Qwen3-VL-8B encoder
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
    diffusion_help_flag=false
    verbose_flag=false
    restart_flag=false
    command_source="github"
    model="qwen-image"

    # Parse flags and named parameters
    while :; do
        case "${1-}" in
            -h | --help) usage;;
            --diffusion-help) diffusion_help_flag=true;;
            -v | --verbose) verbose_flag=true;;
            -r | --restart) restart_flag=true;;
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
    pkill -f sd-server
    pkill llama
    pkill qdrant
    pkill -f ctxpact
    sleep 1
}


check_files() {
    # Exit if any of the given files is missing
    local missing=()
    local f
    for f in "$@"; do
        [[ -f "${f}" ]] || missing+=("${f}")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Missing model files:" >&2
        printf '    %s\n' "${missing[@]}" >&2
        exit 1
    fi
}


autoload() {
    # command
    case ${command_source} in
        "github") command="$HOME/applications/stable-diffusion-cpp/binary/vulkan/sd-server";;
    esac

    # Model
    model_dir="$HOME/applications/stable-diffusion-cpp/models/"
    case "${model}" in
        "qwen-image")
            diffusion_model="${model_dir}/qwen/atomicchat/Qwen-Image-2.1-Turbo-Q8_0.gguf"
            llm_model="${model_dir}/qwen/atomicchat/Qwen-Image-2.1-Turbo-Abliterated-Uncensored-Q8_0.gguf"
            llm_vision_model="${model_dir}/qwen/atomicchat/mmproj-Qwen-Image-2.1-Turbo-Abliterated-Uncensored-BF16.gguf"
            ;;
        "qwen-image-std")
            diffusion_model="${model_dir}/qwen/atomicchat/Qwen-Image-2.1-Turbo-Q8_0.gguf"
            llm_model="${model_dir}/qwen/qwen/Qwen3VL-8B-Instruct-Q8_0.gguf"
            llm_vision_model="${model_dir}/qwen/qwen/mmproj-Qwen3VL-8B-Instruct-F16.gguf"
            ;;
        *) die "Incorrect model name: ${model}";;
    esac
    vae_model="${model_dir}/qwen/comfy-org/qwen_image_2.1_vae_bf16.safetensors"
    check_files "${diffusion_model}" "${llm_model}" "${llm_vision_model}" "${vae_model}"

    # Turbo 8-step schedule from the checkpoint (CFG 1, euler)
    command_args+=(
        --diffusion-model "${diffusion_model}"
        --llm "${llm_model}"
        --llm_vision "${llm_vision_model}"
        --vae "${vae_model}"
        --steps 8
        --cfg-scale 1.0
        --sampling-method euler
        --sigmas 1.0,0.978453,0.95418,0.926626,0.89508,0.845148,0.704534,0.414568,0.0
    )
}


main() {
    # Setup common parameters
    # Denoiser + VAE in VRAM (~8.1 GB), encoder in system RAM via --offload-to-cpu (~8.7 GB)
    # 1024x1024 keeps the prefix KV cache (~7 GiB) inside the 16 GB VRAM budget
    command_args=(
        -t 8
        -W 1024
        -H 1024
        --diffusion-fa
        --listen-ip 0.0.0.0
        --listen-port 8083
    )

    # Load model preferences
    autoload
    # Act on flags
    if [[ $diffusion_help_flag == true ]]; then
        command_args=(--help)
        restart_flag=false
    fi
    if [[ $verbose_flag == true ]]; then
        command_args+=("--log-level" "verbose")
    fi
    if [[ $restart_flag == true ]]; then
        kill_processes
    fi
    # Launch stable-diffusion.cpp
    ${command} ${command_args[@]}
}


parse_arguments "$@"
main
