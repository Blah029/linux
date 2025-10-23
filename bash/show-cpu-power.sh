#!/usr/bin/env bash


usage() {
    cat << EOF
Expose CPU power draw to MangoHud
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
    
    # Parse positional parameters
    args=("$@")
}


main() {
    sudo chmod o+r /sys/class/powercap/intel-rapl\:0/energy_uj
}


parse_arguments "$@"
main

