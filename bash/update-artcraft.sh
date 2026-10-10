#!/usr/bin/env bash


usage() {
    cat << EOF
Download and install ArtCraft package updates from  https://github.com/storytold
Usage: $(basename "${BASH_SOURCE[0]}") [options] parameter

Options:
    -h, --help                  Print help and exit
    -y, --yes                   Update without confirming
    -p, --package <format>      Packagxing format. Default rpm
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
    y_flag=false
    packaging_format="rpm"
    
    # Parse flags and named parameters
    while :; do
        case "${1-}" in
            -h | --help) usage;;
            -y | --yes) y_flag=true;;
            -p | --package)
                packaging_format="${2-}"
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
    [[ -z "${packaging_format-}" ]] && die "Missing required parameter: --package"
    # Check for no. of positional parameters
    [[ ${#args[@]} -lt 0 ]] && die "Missing positional parameters. Given "${#args[@]}", expected 1"
    [[ ${#args[@]} -gt 0 ]] && die "Too many positional parameters. Given "${#args[@]}", expected 1"

}


main() {
    apps=(
        photocraft
        filmcraft
        designcraft
        pdfcraft
    )
    dnf_args=()
    mkdir -p "$HOME/temp/artcraft"
    for app in ${apps[@]}; do
        # Check versions
        installed_version=$(rpm -q "${app}")
        installed_version="${installed_version#*-}"
        installed_version="${installed_version%-*}"
        latest_url="$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/storytold/${app}/releases/latest")"
        tag="${latest_url##*/}"
        latest_version="${tag#v}"
        # Skip / download
        if [[ "${installed_version}" == "${latest_version}" ]]; then
            echo "Latest ${app} version ${installed_version} already installed"
        else
            download_url="https://github.com/storytold/${app}/releases/download/${tag}/${app}-${latest_version}-linux-x86_64.${packaging_format}"
            file_path="$HOME/temp/artcraft/${app}-${latest_version}-linux-x86_64.${packaging_format}"
            echo "Downloading ${app} v${latest_version} ${packaging_format}"
            curl -fsSL -o "${file_path}" "${download_url}"
            if [[ "${y_flag}" == true ]]; then
                dnf_args+=(-y)
            fi
            sudo dnf install "${dnf_args[@]}" "${file_path}"
        fi
    done
}


parse_arguments "$@"
main
