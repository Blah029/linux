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
    -u, --update                Download latest GitHub Vulkan release
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
    update_flag=false
    command_source="github"
    model="qwen-image"

    # Parse flags and named parameters
    while :; do
        case "${1-}" in
            -h | --help) usage;;
            --diffusion-help) diffusion_help_flag=true;;
            -v | --verbose) verbose_flag=true;;
            -r | --restart) restart_flag=true;;
            -u | --update) update_flag=true;;
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


autoload() {
    # Command
    case ${command_source} in
        "github") command="$HOME/applications/stable-diffusion-cpp/binary/vulkan/sd-server";;
    esac

    # Model
    model_dir="$HOME/applications/stable-diffusion-cpp/models/"
    qwen_args=(
        --steps 8
        --cfg-scale 1.0
        --sampling-method euler
        --sigmas 1.0,0.978453,0.95418,0.926626,0.89508,0.845148,0.704534,0.414568,0.0
    )
    case "${model}" in
        "qwen-image") command_args+=(
            ${qwen_args[@]}
            --diffusion-model "${model_dir}/qwen/atomicchat/Qwen-Image-2.1-Turbo-Q8_0.gguf"
            --llm "${model_dir}/qwen/atomicchat/Qwen-Image-2.1-Turbo-Abliterated-Uncensored-Q8_0.gguf"
            --llm_vision "${model_dir}/qwen/atomicchat/mmproj-Qwen-Image-2.1-Turbo-Abliterated-Uncensored-BF16.gguf"
            --vae "${model_dir}/qwen/comfy-org/qwen_image_2.1_vae_bf16.safetensors"
        );;
        "qwen-image-std") command_args+=(
            ${qwen_args[@]}
            --diffusion-model "${model_dir}/qwen/atomicchat/Qwen-Image-2.1-Turbo-Q8_0.gguf"
            --llm "${model_dir}/qwen/qwen/Qwen3VL-8B-Instruct-Q8_0.gguf"
            --llm_vision "${model_dir}/qwen/qwen/mmproj-Qwen3VL-8B-Instruct-F16.gguf"
            --vae "${model_dir}/qwen/comfy-org/qwen_image_2.1_vae_bf16.safetensors"
        );;
        *) die "Incorrect model name: ${model}";;
    esac
}


update() {
    mkdir -p "/tmp/stable-diffusion-cpp"
    latest_url="$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/leejet/stable-diffusion.cpp/releases/latest")"
    tag="${latest_url##*/}"
    latest_version="${tag##*-}"
    download_url="https://github.com/leejet/stable-diffusion.cpp/releases/download/${tag}/sd-master-${latest_version}-bin-Linux-Ubuntu-26.04-x86_64-vulkan.zip"
    download_path="/tmp/stable-diffusion-cpp/sd-master-${latest_version}-bin-Linux-Ubuntu-26.04-x86_64-vulkan.zip"
    install_path="$HOME/applications/stable-diffusion-cpp/binary/vulkan"
    echo "Downloading stable-diffusion.cpp ${tag}"
    curl -fsSL -o "${download_path}" "${download_url}"
    echo "Removing old files at ${install_path}"
    rm "${install_path}/"*
    echo "Unzipping"
    unzip "${download_path}" -d "${install_path}"
    echo "Done":
}


main() {
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
    if [[ $update_flag == true ]]; then
        update
    else
        # Launch stable-diffusion.cpp
        ${command} ${command_args[@]}
    fi
}


parse_arguments "$@"
main
