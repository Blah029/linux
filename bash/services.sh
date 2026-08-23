#!/usr/bin/env bash


usage() {
    cat << EOF
Manage background homelab services
Usage: $(basename "${BASH_SOURCE[0]}") [options]

Options:
    -h, --help      Print help and exit
    -s, --start     Start
    -e, --stop      Stop 
    -r, --restart   Restart
    -a, --all       Manage all including critical services
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
    all_flag=false
    
    # Parse flags and named parameters
    while :; do
        case "${1-}" in
            -h | --help) usage;;
            -s | --start) action="start";;
            -e | --stop) action="stop";;
            -r | --restart) action="restart";;
            -a | --all) all_flag=true;;
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
    # Batch start services
    echo -e "Starting services\n" 
    for service in ${services[@]}; do
        echo -e "${service}"
        sudo systemctl start ${service}
    done
    
    # Start other processes
    echo -e "\nRunning post start-up commands\n"
    # Docker - AythingLLM
    echo "Docker - Starting AnythingLLM provider processes"
    nohup ptyxis -- bash -c "llama-script.sh -a" > "$HOME/temp/nohup-gemma.txt" 2>&1 &
}


stop_services() {
    # Stop other processs
    echo -e "Preparing to stop services\n"
    # Docker - AnythingLLM
    echo "Docker - Killing AnythingLLM provider processes"
    pkill llama
    pkill qdrant
    pkill -f ctxpact
    if [[ $all_flag == true ]]; then
        # Wireguard
        echo "Wireguard - Bringing interface down"
        sudo wg-quick down wg0
    fi
    # Batch stop services
    echo -e "\nStopping services\n"
    for service in ${services[@]}; do
        echo "${service}"
        sudo systemctl stop ${service}
    done
}


restart_services() {
    stop_services
    echo ""
    start_services
}


main() {
    services=(
        "docker.socket"
        "docker"
        "jellyfin"
    )
    critical_services=(
        "playit"
        "sshd"
        "wg-quick@wg0"
    )
    if [[ $all_flag == true ]]; then
        services+=(${critical_services[@]})
    fi

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
