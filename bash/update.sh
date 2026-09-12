#!/usr/bin/env bash


usage() {
    cat << EOF
Update DNF packages, flatpaks, docker containers etc.
Usage: $(basename "${BASH_SOURCE[0]}") [options]

Options:
    -h, --help                  Print help and exit
EOF
    exit
}


die() {
    echo >&2 -e "${1-}\n"
    usage
    exit
}


parse_arguments() {
    # Parse flags and named parameters
    while :; do
        case "${1-}" in
            -h | --help) usage;;
            # Exit if an unexpected option is passed
            -?*) die "Unexpected option: $1";;
            # If no matches, break while loop to parse positional parameters
            *) break;;
        esac
        shift
    done
    
    # Check for no. of positional parameters
    [[ ${#args[@]} -gt 0 ]] && die "Too many positional parameters. Given "${#args[@]}", expected 0"

}

docker_containers=(
    anythingllm
    searxng
)


main() {
    # DNF
    echo -e "\n[DNF]"
    sudo dnf update --refresh -y
    # Flatpak
    echo -e "\n[Flatpak]"
    sudo flatpak update -y
    # Docker
    for container in ${docker_containers[@]}; do(
        echo -e "\n[Docker - $container]"
        cd $HOME/applications/$container && \
        docker compose down && \
        docker compose pull && \
        docker compose up -d
    ); done
    cd $HOME
    # Other
    echo -e "\n[Llama.cpp]"
    llama update
    echo -e "\n[Pi Coding Agent]"
    sudo npm --prefix /usr/local install -g --ignore-scripts --min-release-age=0 @earendil-works/pi-coding-agent
}


parse_arguments "$@"
main
