#!/usr/bin/env bash


usage() {
    cat << EOF 
Download and install latest version of custom proton
Usage: $(basename "${BASH_SOURCE[0]}") [options] repo

Options:
    -h, --help                  Print help and exit
Repos:
    -g, --protonge              Updtae Proton-GE (https://github.com/GloriousEggroll/proton-ge-custom)
    -d, --dwproton <version>    Update DW-Proton. Example dwproton-10.0-14 (https://dawn.wine/dawn-winery/dwproton)
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
    repo=0
    version=0

    # Parse flags and named parameters
    while :; do
        case "${1-}" in
            -h | --help) usage;;
            -g | --protonge) repo="ge";;
            -d | --dwproton)
                repo="dw"
                version="${2-}"
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
}


update_proton_ge() {
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
    curl -# -L $tarball_url -o $tarball_name

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


update_dwproton() {
    # Check for valid version
    case "${version}" in
        dwproton) ;;
        # Exit if an unexpected version is passed
        -?*) die "Unexpected DW-Proton version: ${version}";;
    esac

    # make temp working directory
    echo "Creating temporary working directory..."
    rm -rf /tmp/dw-proton
    mkdir /tmp/dw-proton
    cd /tmp/dw-proton

    # download tarball
    echo "Fetching tarball URL..."
    tarball_url="https://dawn.wine/dawn-winery/dwproton/releases/download/${version}/${version}-x86_64.tar.xz"
    tarball_name=$(basename $tarball_url)
    echo "Downloading tarball: $tarball_name..."
    curl -# -L $tarball_url -o $tarball_name

    # download checksum
    echo "Fetching checksum URL..."
    checksum_url="https://dawn.wine/dawn-winery/dwproton/releases/download/${version}/${version}-x86_64.sha512sum"
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


main() {
    case $repo in
        "ge")
            echo "Updating Proton-GE"
            update_proton_ge
            ;;
        "dw")
            echo "Updating DW-Proton"
            update_dwproton
            ;;
        0) die "Specify a repo"
    esac
}


parse_arguments "$@"
main
