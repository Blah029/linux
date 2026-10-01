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

    # Set read/write permissions
    if [[ $write_flag == true ]]; then
        workspace_mount="$PWD:/workspace"
    else
        workspace_mount="$PWD:/workspace:ro"
    fi
    # Rebuild image on flag
    if [[ $build_flag == true ]]; then
        echo -e "Building image $image\n"
        docker build -t "$image" -f "$docker_directory/Dockerfile.pi" "$docker_directory"
    fi

    # Run pi
    docker run --rm -it \
        -v "$workspace_mount" \
        -v "$HOME/.pi/agent:/root/.pi/agent" \
        "$image"
}


parse_arguments "$@"
main
