#!/usr/bin/env bash
# Read-only connection monitor. Stop with Ctrl-C before using rkdeveloptool elsewhere.
set -u

for tool in gtimeout rkdeveloptool adb; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Missing required tool: $tool" >&2
        exit 1
    fi
done

trap 'printf "\nMonitor stopped.\n"; exit 0' INT TERM
previous_status=''
last_heartbeat=$SECONDS
echo 'Watching Rockchip USB and ADB every 2 seconds. No device writes.'
echo 'Stop this monitor before running other rkdeveloptool commands.'

while true; do
    rockchip_output=$(gtimeout 3 rkdeveloptool ld 2>&1)
    if [[ "$rockchip_output" == *'DevNo='* ]]; then
        rockchip_status="$rockchip_output"
    elif [[ "$rockchip_output" == *'not found any devices'* ]]; then
        rockchip_status='No Rockchip device'
    else
        rockchip_status="Rockchip check failed: $rockchip_output"
    fi

    adb_output=$(gtimeout 3 adb devices -l 2>&1)
    status=$(printf '%s\n%s' "$rockchip_status" "$adb_output")
    if [[ "$status" != "$previous_status" ]]; then
        printf '\n[%s] Connection changed:\n%s\n' "$(date '+%H:%M:%S')" "$status"
        previous_status="$status"
        last_heartbeat=$SECONDS
    elif (( SECONDS - last_heartbeat >= 30 )); then
        printf '[%s] Still watching; connection unchanged.\n' "$(date '+%H:%M:%S')"
        last_heartbeat=$SECONDS
    fi
    sleep 2
done
