#!/usr/bin/env bash


usage() {
    cat << EOF
Trim video files with ffmpeg
Usage: $(basename "${BASH_SOURCE[0]}") [options] filename start end

Options:
    -h, --help                          Print help and exit
    -p, --parent-dir <path>             Path of the parent directory. Default ~/"Videos/OBS/AMD - Games"
    -i, --in-extension <extension>      Input file extension. Default mkv
    -o, --out-extension <extension>     Output file extension. Default mp4
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
    in_extension=mkv
    out_extension=mp4

    # Parse flags and named parameters
    while :; do
        case "${1-}" in
            -h | --help) usage;;
            -p | --parent-dir)
                parent_dir="${2-}"
                shift
                ;;
            -i | --in-extension)
                in_extension="${2-}"
                shift
                ;;
            -o | out-extension)
                out_extension="${2-}"
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
    [[ -z "${in_extension-}" ]] && die "Missing required parameter: --in-extension"
    [[ -z "${out_extension-}" ]] && die "Missing required parameter: --out-extension"
    # Check for no. of positional parameters
    [[ ${#args[@]} -lt 3 ]] && die "Missing positional parameters. Given "${#args[@]}", expected 3"
    [[ ${#args[@]} -gt 3 ]] && die "Too many positional parameters. Given "${#args[@]}", Expected 3"
}


main() {
    ffmpeg -ss "${args[1]}" -to "${args[2]}" -i "$parent_dir/${args[0]}.$in_extension" -c copy "$parent_dir/Trimmed - ${args[0]%.*}.$out_extension"
}


parse_arguments "$@"
main

