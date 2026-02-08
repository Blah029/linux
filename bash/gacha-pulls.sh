#!/usr/bin/env bash


usage() {
    cat << EOF
Copy gacha pull history token to use with pull trackers
Usage: $(basename "${BASH_SOURCE[0]}") [options]

Options:
    -h, --help                  Print help and exit
    -e, --endfield              Copy Arknights Endfield pull token
    -w, --wuwa                  Copy Wuthering Waves pull token
    -p, --path <path>           Default path: /mnt/games
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
    game=0
    game_path="/mnt/games"
    
    # Parse flags and named parameters
    while :; do
        case "${1-}" in
            -h | --help) usage;;
            -e | --endfiled) game="arknights-endfield";;
            -w | --wuwa) game="wuthering-waves";;
            -p | --path)
                game_path="${2-}"
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
    [[ -z "${game_path-}" ]] && die "Missing required parameter: --parameter"
}


copy_endfield() {
    log_path="$game_path/$game/drive_c/users/$USER/AppData/LocalLow/Gryphline/Endfield/sdklogs/HGWebview.log"
    if [ -f "$log_path" ]; then
        token=$(grep -oP 'https://[^\s"]+?\.gryphline\.com/[^\s"]+?token[^\s"]+?server[^\s"]+' "$log_path" | head -n1)
        if [ -n "$token" ]; then
            if command -v xclip >/dev/null 2>&1; then
                echo -n "$token" | xclip -selection clipboard
            else
                echo "Clipboard tool not found. Token: $token"
            fi
            echo "Token copied"
        else
            echo "No matching token found"
        fi
    else
        echo "Log file not found at $log_path"
    fi
}


copy_wuwa(){
    curl -sSL https://raw.githubusercontent.com/wuwatracker/wuwatracker/refs/heads/main/import.sh | bash
}


main() {
    case $game in
        "arknights-endfield")
            echo "Attempting to copy Arknights Endfield token..."
            copy_endfield
            ;;
        "wuthering-waves")
            echo "Attempting to copy Wuthering Waves token..."
            copy_wuwa
            ;;
        0) die "Specify a game"
    esac
}


parse_arguments "$@"
main
