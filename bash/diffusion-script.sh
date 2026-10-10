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
    -m, --model <model>         Large language model. Default qwen-image
                                    qwen-image  - AtomicChat Qwen Image 2.1 Turbo Uncensored
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
    pkill diffusion
    pkill llama
    pkill qdrant
    pkill -f ctxpact
    sleep 1
}


autoload() {
    # command
    case ${command_source} in
        "github") command="$HOME/applications/stable-diffusion-cpp/sd-server";;
    esac

    # Model
    model_dir="$HOME/applications/stable-diffusion-cpp/models/"
    qwen_args=(
    )
    case "${model}" in
        "qwen-image") command_args+=(
            ${qwen_args[@]}
        );;
        *) die "Incorrect model name: ${model}";;
    esac
}


main() {
    command_args=(
    )

    # Load model preferences
    autoload
    # Act on flags
    if [[ $diffusion_help_flag == true ]]; then
        command_args=(--help)
        restart_flag=false
    fi
    if [[ $verbose_flag == true ]]; then
        command_args+=(-lv 4)
    fi
    if [[ $restart_flag == true ]]; then
        kill_processes
    fi
    # Launch llama.cpp
    ${command} ${command_args[@]}
}


parse_arguments "$@"
main
