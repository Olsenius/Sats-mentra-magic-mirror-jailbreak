#!/system/bin/sh
# Keep Wi-Fi/ADB reachable with the display asleep. No router probes or scans.
WPA=/vendor/bin/wpa_cli
SOCKET=/data/vendor/wifi/wpa/sockets
PIDFILE=/data/local/tmp/net_keepalive.pid
LOG=/data/local/net_keepalive.log
oldpid=$(cat "$PIDFILE" 2>/dev/null)
if [ -n "$oldpid" ] && [ "$oldpid" != "$$" ] &&
   grep -q net_keepalive.sh "/proc/$oldpid/cmdline" 2>/dev/null; then
    exit 0
fi
echo $$ > "$PIDFILE"
log_message() {
    echo "$(date '+%m-%d %H:%M:%S') $*" >> "$LOG"
    if [ "$(wc -c < "$LOG")" -gt 100000 ]; then
        tail -n 200 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
    fi
}
wpa() { "$WPA" -p "$SOCKET" -i wlan0 "$@"; }
log_message 'Started: local Wi-Fi checks only; no network probes'
misses=0
repairs=0
window=$(date +%s)
adb_misses=0
while true; do
    # Android may restore power saving whenever the screen goes off.
    wpa driver SETSUSPENDMODE 0 >/dev/null 2>&1
    /vendor/bin/iwconfig wlan0 power off >/dev/null 2>&1
    state=$(wpa status 2>/dev/null | sed -n 's/^wpa_state=//p')
    case "$state" in
        DISCONNECTED|INACTIVE|SCANNING) misses=$((misses + 1)) ;;
        *) misses=0 ;;
    esac
    now=$(date +%s)
    if [ $((now - window)) -ge 1800 ]; then repairs=0; window=$now; fi
    if [ "$misses" -ge 3 ] && [ "$repairs" -lt 3 ]; then
        # Ask the existing supplicant to reconnect; never turn Wi-Fi off.
        wpa reconnect >/dev/null 2>&1
        repairs=$((repairs + 1))
        misses=0
        log_message "Requested reconnect (attempt $repairs in this 30-minute window)"
    fi
    if grep -Eiq ':15B3 [0-9A-F:]+ 0A ' /proc/net/tcp6 /proc/net/tcp; then
        adb_misses=0
    else
        adb_misses=$((adb_misses + 1))
        if [ "$adb_misses" -ge 2 ]; then
            setprop persist.adb.tcp.port 5555
            setprop service.adb.tcp.port 5555
            setprop ctl.restart adbd
            adb_misses=0
            log_message 'Restored ADB listener on port 5555'
        fi
    fi
    sleep 20
done
