#!/usr/bin/env bash


usage() {
    cat << EOF
Run Pi Coding Agent in a Docker container
Usage: $(basename "${BASH_SOURCE[0]}") [options]

Options:
    -h, --help                      Print help and exit
    -w, --write                     Mount the working directory with write permissions
    -b, --build                     Rebuild the pi-sandbox image
    -f, --force                     Force rebuild without build cache
    -t, --tag <tag>                 Run pi-sandbox:<tag> image. Default ""
    -d, --dockerfile <name>         Name of docker file. Default Dockerfile.pi
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
    write_flag=false
    build_flag=false
    force_flag=false
    tag=""
    dockerfile="Dockerfile.pi"
    
    # Parse flags and named parameters
    while :; do
        case "${1-}" in
            -h | --help) usage;;
            -w | --write) write_flag=true;;
            -b | --build) build_flag=true;;
            -f | --force) force_flag=true;;
            -t | --tag)
                tag=":${2-}"
                shift
                ;;
            -d | --dockerfile)
                dockerfile="${2-}"
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
        -t "${image}${tag}"
        -f "${docker_directory}/${dockerfile}"
    )
    if [[ ${force_flag} == true ]]; then
        build_args+=( --no-cache)
    else
        pi_version="$(curl -fsSL 'https://registry.npmjs.org/@earendil-works%2Fpi-coding-agent' \
            | grep -o '"latest"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 | cut -d'"' -f4)"
        [[ -n "${pi_version}" ]] || die "Could not determine latest pi-coding-agent version"
        build_args+=(--build-arg "PI_VERSION=${pi_version}")
        if [[ "${tag}" == "" ]]; then
            build_args+=(--pull)
        fi
    fi
    echo "Updating build context"
    rm "${docker_directory}"/*
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
        "$HOME/Documents/github/linux/docker/pi-coding-agent/${dockerfile}"
    )
    docker_args=(
        --rm
        -it
    )
    core_mounts=(
        -v "$HOME/Documents/github/linux/docker/pi-coding-agent/AGENTS.md:/root/.pi/agent/AGENTS.md"
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
    
    # Mount Pi configuration
    for item in "$HOME/.pi/agent"/*; do 
        core_mounts+=(-v "$HOME/.pi/agent/${item##*/}:/root/.pi/agent/${item##*/}")
    done
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
    # Check tag
    if [[ "${tag}" != "" ]]; then
        if docker image inspect "pi-sandbox${tag}" >/dev/null 2>&1; then
            image="pi-sandbox${tag}"
        else
            die "Docker image pi-sandbox has no ${tag} checkpoint"
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
