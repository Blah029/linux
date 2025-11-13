#!/usr/bin/env bash


usage() {
    cat << EOF
Download and install latest version of Proton-GE from https://github.com/GloriousEggroll/proton-ge-custom
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
    # make temp working directory
    echo "Creating temporary working directory..."
    rm -rf /tmp/proton-ge-custom
    mkdir /tmp/proton-ge-custom
    cd /tmp/proton-ge-custom

    # download tarball
    echo "Fetching tarball URL..."
    tarball_url=$(curl -s https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest | grep browser_download_url | cut -d\" -f4 | grep .tar.gz)
    tarball_name=$(basename $tarball_url)
    echo "Downloading tarball: $tarball_name..."
    curl -# -L $tarball_url -o $tarball_name --no-progress-meter

    # download checksum
    echo "Fetching checksum URL..."
    checksum_url=$(curl -s https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest | grep browser_download_url | cut -d\" -f4 | grep .sha512sum)
    checksum_name=$(basename $checksum_url)
    echo "Downloading checksum: $checksum_name..."
    curl -# -L $checksum_url -o $checksum_name --no-progress-meter

    # check tarball with checksum
    echo "Verifying tarball $tarball_name with checksum $checksum_name..."
    sha512sum -c $checksum_name
    # if result is ok, continue

    # make steam directory if it does not exist
    echo "Creating Steam directory if it does not exist..."
    mkdir -p ~/.steam/steam/compatibilitytools.d

    # extract proton tarball to steam directory
    echo "Extracting $tarball_name to Steam directory..."
    tar -xf $tarball_name -C ~/.steam/steam/compatibilitytools.d/
    echo "All done :)"
}


parse_arguments "$@"
main
