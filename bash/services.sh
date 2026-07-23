#!/usr/bin/env bash


usage() {
    cat << EOF
Description
Usage: $(basename "${BASH_SOURCE[0]}") [options] parameter

Options:
    -h, --help                  Print help and exit
    -f, --flag                  Example flag
    -p, --parameter <parameter> Example named parameter
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
    action=0
    
    # Parse flags and named parameters
    while :; do
        case "${1-}" in
            -h | --help) usage;;
            -s | --start) action="start";;
            -e | --stop) action="stop";;
            -r | --restart) action="restart";;
            # Exit if an unexpected option is passed
            -?*) die "Unexpected option: $1";;
            # If no matches, break while loop to parse positional parameters
            *) break;;
        esac
        shift
    done
    
    # Parse positional parameters
    args=("$@")
}


start_services() {
    # Jellyfin
    echo -e  "\nStarting jellyfin service..."
    sudo systemctl start jellyfin
    # Wireguard
    echo -e "\nStarting wireguard service..."
    sudo systemctl start wg-quick@wg0
    # ssh
    echo -e "\nStarting ssh service..."
    sudo systemctl start sshd
}


stop_services() {
    # Jellyfin
    echo -e "\nStopping jellyfin service..."
    sudo systemctl stop jellyfin
    # Wireguard
    echo -e "\nBringing wireguard interface down..."
    sudo wg-quick down wg0
    echo -e "\nStopping wireguard service..."
    sudo systemctl stop wg-quick@wg0
    # ssh
    echo -e "\nStopping ssh service...\n"
    sudo systemctl stop sshd
}


restart_services() {
    stop_services
    start_services
}


main() {
    case "$action" in
        "start") start_services;;
        "stop") stop_services;;
        "restart") restart_services;;
        # Exit if an unexpected option is passed
        0) die "Unexpected option: $1";;
    esac
}


parse_arguments "$@"
main
