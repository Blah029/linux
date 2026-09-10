#!/usr/bin/env bash
# Lightweight memory monitor: VRAM used + RAM available + swap used every 30s.
LOG="$HOME/Documents/github/linux/results/mem-monitor.log"
echo "# ts vram_used_bytes ram_available_kib swap_used_kib" >> "$LOG"
while true; do
    v=$(cat /sys/class/drm/card1/device/mem_info_vram_used)
    r=$(awk '/Mem:/{print $7}' /proc/meminfo)
    s=$(awk '/Swap:/{print $4}' /proc/meminfo)
    echo "$(date '+%H:%M:%S') $v $r $s" >> "$LOG"
    sleep 30
done
