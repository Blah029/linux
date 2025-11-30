
#!/usr/bin/env bash


usage() {
    cat << EOF
Play multiple audio tracks simulateneously
Usage: $(basename "${BASH_SOURCE[0]}") [tracks] filename

Options:
    -h, --help                  Print help and exit
    -p, --parent-dir <path>     Path of the parent directory. Default ~/"Videos/OBS/AMD - Games"
    -t, --tracks <tracks>       Number of audio tracks. Default 0 (all)
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
    parent_dir=~/"Videos/OBS/AMD - Games"
    tracks=0

    # Parse flags and named parameters
    while :; do
        case "${1-}" in
            -h | --help) usage;;
            -t | --tracks)
                tracks="${2-}"
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

    # Check for required named parameters
    [[ -z "${parent_dir-}" ]] && die "Missing required parameter: --parent-directory"
    [[ -z "${tracks-}" ]] && die "Missing required parameter: --tracks"
    # Check for no. of positional parameters
    [[ ${#args[@]} -lt 1 ]] && die "Missing positional parameters. Given "${#args[@]}", expected 1"
    [[ ${#args[@]} -gt 1 ]] && die "Too many positional parameters. Given "${#args[@]}", Expected 1"

}


main() {
    # Check tracks
    if [ "${tracks}" -eq 0 ]; then
        tracks=$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "${args[0]}" | wc -l)
        if [ "${tracks}" -eq 0 ]; then
            die "No audio streams found in ${args[0]}"
        fi
    fi
    
    # Generate command strings
    aid_string=""
    for (( i=1; i<="${tracks}"; i++ )); do
        aid_string="${aid_string}[aid${i}]"
    done
    lavfi_string="${aid_string}amix=inputs=${tracks}[ao]"

    # Run command
    mpv --lavfi-complex="${lavfi_string}" "${parent_dir}/${args[0]}"
}


parse_arguments "$@"
main
