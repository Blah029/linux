#!/usr/bin/env bash


usage() {
    cat << EOF
Run Pi Coding Agent in a Docker container
Usage: $(basename "${BASH_SOURCE[0]}") [options]

Options:
    -h, --help                      Print help and exit
    -b, --build                     Rebuild the pi-sandbox image
    -f, --force                     Force rebuild without build cache
    -w, --write                     Mount the working directory with write permissions
    -c, --checkpoint <checkpoint>   Run pi-sandbox:<checkpoint> image created from commit. Default none
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
    build_flag=false
    force_flag=false
    write_flag=false
    checkpoint=false
    
    # Parse flags and named parameters
    while :; do
        case "${1-}" in
            -h | --help) usage;;
            -b | --build) build_flag=true;;
            -f | --force) force_flag=true;;
            -w | --write) write_flag=true;;
            -c | --checkpoint)
                checkpoint="${2-}"
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

    # Check for no. of positional parameters
    [[ ${#args[@]} -gt 0 ]] && die "Too many positional parameters. Given "${#args[@]}", expected 0"
}


rebuild() {
    build_args=(
        -t "${image}"
        -f "${docker_directory}/Dockerfile.pi"
    )
    if [[ ${force_flag} == true ]]; then
        build_args+=(
            --no-cache
        )
    else
        pi_version="$(curl -fsSL 'https://registry.npmjs.org/@earendil-works%2Fpi-coding-agent' \
            | grep -o '"latest"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 | cut -d'"' -f4)"
        [[ -n "${pi_version}" ]] || die "Could not determine latest pi-coding-agent version"
        build_args+=(
            --pull
            --build-arg "PI_VERSION=${pi_version}"
        )
    fi
    echo "Updating build context"
    for build_file in "${build_context[@]}"; do(
        cp "${build_file}" "${docker_directory}/"
    ); done
    echo -e "Building image ${image} ${pi_version}\n"
    docker build "${build_args[@]}" "${docker_directory}"
    echo "Build complete"
    exit
}


main() {
    image="pi-sandbox"
    docker_directory="$HOME/applications/pi-coding-agent"
    build_context=(
        "$HOME/Documents/github/linux/docker/pi-coding-agent/Dockerfile.pi"
    )
    docker_args=(
        --rm
        -it
    )
    core_mounts=(
        -v "$HOME/.pi/agent:/root/.pi/agent"
        -v "$HOME/.vimrc:/root/.vimrc:ro"
    )
    supplementary_mounts=(
        -v "$HOME/applications:/mnt/applications:ro"
        -v "$HOME/Documents/github:/mnt/github:ro"
    )
    situational_mounts=(
        -v "/mnt/games/SteamLibrary/steamapps/common/No Man's Sky:/mnt/no-mans-sky:ro"
        -v "/mnt/games/SteamLibrary:/mnt/steamlibrary:ro"
    )
    
    # Set read/write permissions
    if [[ ${write_flag} == true ]]; then
        core_mounts+=(-v "$PWD:/workspace")
    else
        core_mounts+=(-v "$PWD:/workspace:ro")
    fi
    # Rebuild image on flag
    if [[ ${build_flag} == true ]]; then
        rebuild
    fi
    # Check checkpoint
    if [[ "${checkpoint}" != false ]]; then
        if docker image inspect "pi-sandbox:${checkpoint}" >/dev/null 2>&1; then
            image="pi-sandbox:${checkpoint}"
        else
            die "Docker image pi-sandbox has no ${checkpoint} checkpoint"
        fi
    fi
            
    # Run pi
    docker run "${docker_args[@]}" \
        "${core_mounts[@]}" \
        "${supplementary_mounts[@]}" \
        "${situational_mounts[@]}" \
        "${image}"
}


parse_arguments "$@"
main
