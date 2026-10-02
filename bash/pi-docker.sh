#!/usr/bin/env bash


usage() {
    cat << EOF
Run Pi Coding Agent in a Docker container
Usage: $(basename "${BASH_SOURCE[0]}") [options]

Options:
    -h, --help                  Print help and exit
    -b, --build                 Build the pi-sandbox image before running
    -w, --write                 Mount the working directory with write permissions
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
    write_flag=false
    
    # Parse flags and named parameters
    while :; do
        case "${1-}" in
            -h | --help) usage;;
            -b | --build) build_flag=true;;
            -w | --write) write_flag=true;;
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


main() {
    image="pi-sandbox"
    docker_directory="$HOME/applications/pi-coding-agent"
    docker_file="$HOME/Documents/github/linux/docker/pi-coding-agent/Dockerfile.pi"
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
    if [[ $write_flag == true ]]; then
        core_mounts+=(-v "$PWD:/workspace")
    else
        core_mounts+=(-v "$PWD:/workspace:ro")
    fi
    # Rebuild image on flag
    if [[ $build_flag == true ]]; then
        echo -e "Updating build context"
        for build_file in ${build_context[@]}; do(
            cp "${build_file}" "${docker_directory}/"
        ); done
        echo -e "Building image $image\n"
        docker build -t "$image" -f "$docker_directory/Dockerfile.pi" "$docker_directory"
    fi

    # Run pi
    docker run "${docker_args[@]}" \
        "${core_mounts[@]}" \
        "${supplementary_mounts[@]}" \
        "${situational_mounts[@]}" \
        "$image"
}


parse_arguments "$@"
main
