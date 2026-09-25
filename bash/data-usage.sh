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
    -r, --renew <date>          Renewal day of the month. Default 24
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
    renew_date=24
    start_hour=7
    end_hour=23
    json_raw="$HOME/temp/vnstat_raw.json"
    year=""
    month=""

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
            -r | --renew)
                renew_date="${2-}"
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

    # Validate renewal day
    [[ "${renew_date}" =~ ^[0-9]+$ ]] || die "Invalid renewal day: ${renew_date}"
    (( renew_date >= 1 && renew_date <= 31 )) || die "Invalid renewal day: ${renew_date}"

    # Determine the start of the billing period (renewal day of the current or
    # previous month, unless year/month are given explicitly)
    if [[ -z "${year}" || -z "${month}" ]]; then
        cur_year=$(date +%Y)
        cur_month=$(date +%-m)
        cur_day=$(date +%-d)
        if (( cur_day >= renew_date )); then
            period_year=$cur_year
            period_month=$cur_month
        else
            period_year=$cur_year
            period_month=$(( cur_month - 1 ))
            (( period_month == 0 )) && { period_month=12; ((period_year--)); }
        fi
        [[ -z "${year}" ]] && year=$period_year
        [[ -z "${month}" ]] && month=$period_month
    fi

    # Billing period: from the renewal day of the start month, up to (not
    # including) the renewal day of the following month
    start_serial=$(( year * 10000 + month * 100 + renew_date ))
    end_month=$(( month + 1 ))
    end_year=$year
    (( end_month > 12 )) && { end_month=1; ((end_year++)); }
    end_serial=$(( end_year * 10000 + end_month * 100 + renew_date ))

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
    jq -r \
        --arg interface "${interface}" \
        --argjson start_serial "${start_serial}" \
        --argjson end_serial "${end_serial}" \
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
                (.date.year * 10000 + .date.month * 100 + .date.day) >= $start_serial
                and (.date.year * 10000 + .date.month * 100 + .date.day) < $end_serial
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
