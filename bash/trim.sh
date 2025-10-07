#!/bin/bash

# Track which commands to run
trim_video=true
print_help=false

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        --help) trim_video=false print_help=true ;;
    esac
done

$trim_video && ffmpeg -ss $2 -to $3 -i "$PWD/$1" -c copy "$PWD/Trimmed - ${1%.*}.mp4"
$print_help && echo -e  "trim.sh [file] [start] [end]"
