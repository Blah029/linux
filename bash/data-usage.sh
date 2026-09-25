#!/usr/bin/env bash


usage() {
    cat << EOF
Filter vnstat daily usage data within the billing period and specified hours.
Usage: $(basename "${BASH_SOURCE[0]}") [options]

Options:
    -h, --help                  Print help and exit
    -i, --interface [interface] Network interface. Default 1
                                    0 - eno1 (ethernet)
                                    1 - wlan0 (wifi)
                                    empty - all interfaces
    -y, --year <year>           Filter by year. Default start year of the billing period
    -m, --month <month>         Filter by month. Default start month of the billing period
    -d, --day <day>             Starting date of billing period. Default 24
                                The billing period starts on this day, of the
                                current month if today is past it, otherwise
                                of the previous month
    -s, --start-hour <hour>     Filter by starting hour. Default 7
    -e, --end-hour <hour>       Filter by ending hour. Default 23
    -j, --json-raw <path>       Path to vnstat output. Default ~/temp/vnstat_raw.json
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
    day=24
    start_hour=7
    end_hour=23
    json_raw="$HOME/temp/vnstat_raw.json"

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
            -d | --day)
                day="${2-}"
                shift
                ;;
            -r | --renew)
                day="${2-}"
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
            -j | --json-raw)
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
    [[ -z "${day-}" ]] && die "Missing required parameter: --day"
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

    # Determine billing period
    # Start
    if [[ $(date +%-d) -lt "${day}" ]]; then
        if [[ "${month}" == 1 ]]; then
            year=$(( year - 1 ))
            month=12
        else
            month=$(( month - 1))
        fi
    fi
    start_date=$(( year * 10000 + month * 100 + day ))
    # End
    if [[ "${month}" == 12 ]]; then
        end_year=$(( year + 1))
        end_month=1
    else
        end_year="${year}"
        end_month=$(( month + 1))
    fi
    end_date=$(( end_year * 10000 + end_month * 100 + day ))

    # Process hourly data
    jq -r \
        --arg interface "${interface}" \
        --argjson start_date "${start_date}" \
        --argjson end_date "${end_date}" \
        --argjson start_hour "${start_hour}" \
        --argjson end_hour "${end_hour}" '
        def to_human:
            if . == null then {value: 0, unit: "KB"}
            elif . >= 1073741824 then {value: ((. / 1073741824 * 100 | floor) / 100), unit: "GB"}
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
        (if $interface == "" then .interfaces else [.interfaces[$interface | tonumber]] end)[]
        | (.traffic.hour
            | map(select(
                (.date.year * 10000 + .date.month * 100 + .date.day) >= $start_date
                and (.date.year * 10000 + .date.month * 100 + .date.day) < $end_date
              ))
            | group_by(.date)
            | map(
                . as $g
                | ($g | map(select(.time.hour >= $start_hour and .time.hour <= $end_hour))) as $sel
                | {
                    date: $g[0].date,
                    rx: ($sel | map(.rx) | add),
                    tx: ($sel | map(.tx) | add),
                    total: ($sel | map(.rx + .tx) | add)
                  }
              )
          ) as $daily
        | {
            name: .name,
            daily: $daily,
            period: ($daily | {
                rx: (map(.rx) | add),
                tx: (map(.tx) | add),
                total: (map(.total) | add)
              })
          }
        | "Interface:     \(.name)",
        "",
        (
            .daily[]
            | "\(.date.year)-\(.date.month | tostring | if length == 1 then "0" + . else . end)-\(.date.day | tostring | if length == 1 then "0" + . else . end):    RX: \(format_value(.rx)) | TX: \(format_value(.tx)) | Total: \(format_value(.total))"
        ),
        "",
        "Period Total: RX: \(format_value(.period.rx)) | TX: \(format_value(.period.tx)) | Total: \(format_value(.period.total))"
    ' "${json_raw}"
}


parse_arguments "$@"
main
