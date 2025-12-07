
#!/usr/bin/env bash

usage() {
    cat << EOF
Log vnstat daily data within specified hours.
Usage: $(basename "${BASH_SOURCE[0]}") [options]

Options:
    -h, --help                  Print help and exit
    -i, --interface <interface> Network interface. Defalut 1
                                    0 - eno1 (ethernet)
                                    1 - wlp5s0 (wifi)
                                    <empty> - all interfaces
    -y, --year <year>           Filter by year. Default current year
    -m, --month <month>         Filter by month. Default current month
    -s, --start-hour <hour>     Filter by starting hour. Default 7
    -e, --end-hour <hour>       Filter by ending hour. Default 23
    --json-raw                  Path to vnstat output. Default ~/temp/vnstat_raw.json
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
    interface=1
    year=$(date +%Y)
    month=$(date +%-m)
    start_hour=7
    end_hour=23
    json_raw=~/"temp/vnstat_raw.json"
    
    # Parse flags and named parameters
    while :; do
        case "${1-}" in
            -h | --help) usage;;
            -i | --interface)
                interface="${2-}"
                shift
                ;;
            -y | --year)
                year="${2-}"
                shift
                ;;
            -m | --month)
                month="${2-}"
                shift
                ;;
            -s | --start-hour)
                start_hour="${2-}"
                shift
                ;;
            -e | --end-hour)
                end_hour="${2-}"
                shift
                ;;
            --json-raw)
                json_raw="${2-}"
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
    #[[ -z "${interface-}" ]] && die "Missing required parameter: --interface"    # Leave empty for all interfaces
    [[ -z "${year-}" ]] && die "Missing required parameter: --year"
    [[ -z "${month-}" ]] && die "Missing required parameter: --month"
    [[ -z "${start_hour-}" ]] && die "Missing required parameter: --start-hour"
    [[ -z "${end_hour-}" ]] && die "Missing required parameter: --end-hour"
    [[ -z "${json_raw-}" ]] && die "Missing required parameter: --json-raw"
    # Check for no. of positional parameters
    [[ ${#args[@]} -lt 0 ]] && die "Missing positional parameters. Given "${#args[@]}", expected 0"
    [[ ${#args[@]} -gt 0 ]] && die "Too many positional parameters. Given "${#args[@]}", expected 0"

}


main() {
    # Export vnstat hourly data
    vnstat --json h > "${json_raw}"

    # Process hourly data
    jq -r '
        def to_human:
            if . >= 1073741824 then {value: ((. / 1073741824 * 100 | floor) / 100), unit: "GB"}
            elif . >= 1048576 then {value: ((. / 1048576 * 100 | floor) / 100), unit: "MB"}
            else {value: ((. / 1024 * 100 | floor) / 100), unit: "KB"}
            end;
        def pad_left(width): 
            tostring
            | (width - length) as $diff
            | if $diff > 0 then ((" " * $diff) + .) else . end;
        def format_value(v):
            (v | to_human) as $h
            | "\(($h.value | tostring | split(".")[0] | pad_left(3))).\($h.value | tostring | split(".")[1] // "0" | .[0:1]) \($h.unit)";
        .interfaces['${interface}'] | {
            name: .name,
            daily: (
                .traffic.hour
                | map(select(.date.year == '${year}' and .date.month == '${month}'))
                | group_by(.date)
                | map({
                    date: .[0].date,
                    rx: (map(select(.time.hour >= '${start_hour}' and .time.hour <= '${end_hour}') | .rx) | add),
                    tx: (map(select(.time.hour >= '${start_hour}' and .time.hour <= '${end_hour}') | .tx) | add),
                    total: (map(select(.time.hour >= '${start_hour}' and .time.hour <= '${end_hour}') | (.rx + .tx)) | add) 
                })
            ),
            monthly: (
                .traffic.hour
                | map(select(.date.year == '${year}' and .date.month == '${month}' and .time.hour >= '${start_hour}' and .time.hour <= '${end_hour}'))
                | {
                    rx: (map(.rx) | add),
                    tx: (map(.tx) | add),
                    total: (map(.rx + .tx) | add)
                }
            )
        }
        | "Interface:     \(.name)",
        "",
        (
            .daily[]
            | "\(.date.year)-\(.date.month | tostring | if length == 1 then "0" + . else . end)-\(.date.day | tostring | if length == 1 then "0" + . else . end):    RX: \(format_value(.rx)) | TX: \(format_value(.tx)) | Total: \(format_value(.total))"
        ),
        "",
        "Monthly Total: RX: \(format_value(.monthly.rx)) | TX: \(format_value(.monthly.tx)) | Total: \(format_value(.monthly.total))"
    ' ~/temp/vnstat_raw.json
}


parse_arguments "$@"
main
