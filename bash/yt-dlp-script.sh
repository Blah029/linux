
#!/usr/bin/env bash


usage() {
    cat << EOF
Custom wrapper for yt-dlp
Usage: $(basename "${BASH_SOURCE[0]}") [options] url

Options:
    -h, --help                  Print help and exit
    -m, --mode <mode>           Mode. Default list
                                    list        - list formats
                                    manual      - download specified format code
                                    audio       - download highest quality audio
                                    playlist    - download mp3 playlist with metadata
    -f, --format                Format code (when used in manual mode)
    -o, --out-path              Change output path. Default "~/Downloads/yt-dlp-downloads"
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
    out_path="~/Downloads/yt-dlp-downloads"
    mode=list
    
    # Parse flags and named parameters
    while :; do
        case "${1-}" in
            -h | --help) usage;;
            -m | --mode)
                mode="${2-}"
                shift
                ;;
            -f | --format)
                format="${2-}"
                shift
                ;;
            -o | --out-path)
                out_path="${2-}"
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
    [[ -z "${out_path-}" ]] && die "Missing required parameter: --out-path"
    [[ -z "${mode-}" ]] && die "Missing required parameter: --mode"
    # Check for no. of positional parameters
    [[ ${#args[@]} -lt 1 ]] && die "Missing positional parameters. Given "${#args[@]}", expected 1"
    [[ ${#args[@]} -gt 1 ]] && die "Too many positional parameters. Given "${#args[@]}", Expected 1"

}


main() {
    url="${args[0]}"
        case "${mode}" in
        list)
            yt-dlp -F "${url}"
            ;;
        manual)
            yt-dlp "${url}" -f "${format}" -o "${out_path}/%(title)s.%(ext)s"
            ;;
        audio)
            yt-dlp "${url}" -f bestaudio -x --audio-format mp3 --audio-quality 0 -o "${out_path}/%(title)s.%(ext)s"
            ;;
        playlist)
            yt-dlp "${url}" -f bestaudio -x --audio-format mp3 --audio-quality 0 --embed-thumbnail --ppa "EmbedThumbnail+ffmpeg_o:-c:v mjpeg -vf crop=\"'if(gt(ih,iw),iw,ih)':'if(gt(iw,ih),ih,iw)'\"" --embed-metadata --embed-chapters --break-on-existing -o "${out_path}/%(playlist_index)s %(title)s.%(ext)s"
            ;;
        # Exit if an unexpected option is passed
        -?*) die "Unexpected option: $1";;
        # If no matches, break while loop to parse positional parameters
        *) break;;
    esac
}


parse_arguments "$@"
main
