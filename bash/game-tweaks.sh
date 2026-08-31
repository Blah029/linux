#!/usr/bin/env bash


usage() {
    cat << EOF
Expose CPU power draw to MangoHud, fix Wine+PipeWire audio popping
Usage: $(basename "${BASH_SOURCE[0]}") [options]

Options:
    -h, --help                  Print help and exit
    -u, --undo                  Undo changes
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
    undo_flag=false

    # Parse flags and named parameters
    while :; do
        case "${1-}" in
            -h | --help) usage;;
            -u | --undo) undo_flag=true;;
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
    if [ $undo_flag == false ]; then
        echo -e "\nEnabling CPU power monitoring..."
        sudo chmod o+r /sys/class/powercap/intel-rapl\:0/energy_uj
        echo -e "\nSetting GPU performace level to high..."
        echo high | sudo tee /sys/class/drm/card1/device/power_dpm_force_performance_level
        #echo -e "\nFixing sample rate and buffer quantum..."
        #pw-metadata -n settings 0 clock.force-rate 48000
        #pw-metadata -n settings 0 clock.force-quantum 500
        #echo -e "\nDecreasing swappiness..."
        #sudo sysctl vm.swappiness=10
    else
        echo -e "\nSetting GPU performace level to auto..."
        echo auto | sudo tee /sys/class/drm/card1/device/power_dpm_force_performance_level
    fi
}


parse_arguments "$@"
main

