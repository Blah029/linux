#!/usr/bin/env bash


usage() {
    cat << EOF
Description
Usage: $(basename "${BASH_SOURCE[0]}") [options] parameter

Options:
    -h, --help                  Print help and exit
    --longhelp                  Show realcugan-ncnn-vulkan help
    -v                          verbose output
    -i input-path               Input image path (jpg/png/webp) or directory
                                    Default ~/Pictures/unprocessed/1-treated
    -o output-path              Output image path (jpg/png/webp) or directory
                                    Default ~/Pictures/unprocessed/2-upscaled
    -n noise-level              denoise level (-1/0/1/2/3). Default 2
    -s scale                    upscale ratio (1/2/3/4). Default 2
    -t tile-size                tile size (>=32/0=auto)
                                    Default 0 for single GPU
                                    Default 0,0,0 for multi-GPU
    -c syncgap-mode             Sync gap mode (0/1/2/3). Default 3
    -m model-path               realcugan model path. Default "models-se"
    -g gpu-id                   GPU device to use -1 for CPU, can be 0,1,2 for multi-GPU. Default "auto"
    -j load:proc:save           Thread count for load/proc/save. Can be 1:2,2,2:2 for multi-gpu. Default 1:2:2 
    -x                          Enable TTA mode
    -f format                   Output image format (jpg/png/webp). Default ext/png
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
    input_path="$HOME/Pictures/unprocessed/1-treated"
    output_path="$HOME//Pictures/unprocessed/2-upscaled"
    noise_level=2
    scale=2
    model="models-se"

    # Parse flags and named parameters
    while :; do
        case "${1-}" in
            -h | --help) usage;;
            -i | --input-path)
                input_path="${2-}"
                shift
                ;;
            -o | --output-path)
                output_path="${2-}"
                shift
                ;;
            -n | --noise-level)
                noise_level="${2-}"
                shift
                ;;
            -s | --scale)
                sclae="${2-}"
                shift
                ;;
            -m | --model-path)
                model="${2-}"
                shift
                ;;
            # If no matches, break while loop to parse positional parameters
            *) break;;
        esac
        shift
    done
    
    # Parse positional parameters
    args=("$@")

    # Check for required named parameters
    [[ -z "${input_path-}" ]] && die "Missing required parameter: --input-path"
    [[ -z "${output_path-}" ]] && die "Missing required parameter: --output-path"
    [[ -z "${noise_level-}" ]] && die "Missing required parameter: --noise-level"
    [[ -z "${scale-}" ]] && die "Missing required parameter: --scale"
    [[ -z "${model-}" ]] && die "Missing required parameter: --model-path"

}


main() {
    "$HOME/applications/realcugan-ncnn-vulkan/realcugan-ncnn-vulkan" \
        -i "${input_path}" \
        -o "${output_path}" \
        -n "${noise_level}" \
        -s "${scale}" \
        -m "${model}" \
        "${args[@]}"
}


parse_arguments "$@"
main
