#!/system/bin/sh
# Minimal alternative to mirror_local.sh: install as /data/local/mirror_local.sh.
# Requires the patched camera library and generated USB audio policy beside it.
# Called by the existing system mirror_setup.sh hook after boot completes.

# Start connectivity first. The watchdog prevents duplicate instances itself.
if [ -f /data/local/net_keepalive.sh ]; then
    setsid sh /data/local/net_keepalive.sh >/dev/null 2>&1 &
fi

matches() {
    [ "$(sha256sum "$1" 2>/dev/null | cut -d ' ' -f 1)" = "$2" ]
}

audio_target=/vendor/etc/usb_audio_policy_configuration.xml
audio_patch=/data/local/usb_audio_policy_configuration.xml
if ! grep -q " $audio_target " /proc/mounts; then
    if matches "$audio_target" 13f6bfaa10b9e77974b0e250fb59e4f583ce0a623766c8cfce1451c96f37afde &&
       matches "$audio_patch" 7894964af07fe7463eb7976e1e34e56ba626d63812a7a95433b309c1008ec1df; then
        # Restarting audioserver during recording can cause a crash loop.
        if grep -q 'RUNNING' /proc/asound/card*/pcm*c/sub*/status 2>/dev/null; then
            log -t mirror_media 'Audio patch deferred: a recorder is active'
        else
            chmod 644 "$audio_patch"
            if mount -o bind "$audio_patch" "$audio_target"; then
                setprop ctl.restart audioserver
                log -t mirror_media 'USB audio policy applied'
            fi
        fi
    else
        log -t mirror_media 'Audio patch skipped: missing file or unexpected hash'
    fi
fi

camera_target=/vendor/lib/camera.device@3.4-external-impl.so
camera_patch=/data/local/ext-impl-patched.so
if ! grep -q " $camera_target " /proc/mounts; then
    if matches "$camera_target" 7f9709755376a60b64af35d41c96a361692919f5a0b47b4ce52f70b0d9c58efa &&
       matches "$camera_patch" 5faf6b7d4080e8787c3fcc7b47a07bcf1926da1753968ba6a146d70c1d63fc42; then
        # Do not interrupt an app using the camera.
        clients=$(dumpsys media.camera | sed -n '/Active Camera Clients:/,/Allowed user IDs:/p')
        if ! printf '%s\n' "$clients" | grep -q '^\[\]'; then
            log -t mirror_media 'Camera patch deferred: camera idle state not confirmed'
        else
            chmod 644 "$camera_patch"
            if mount -o bind "$camera_patch" "$camera_target"; then
                if [ "$(getprop init.svc.vendor.camera-provider-2-4-ext)" = running ]; then
                    setprop ctl.restart vendor.camera-provider-2-4-ext
                fi
                log -t mirror_media 'Camera allocation patch applied'
            fi
        fi
    else
        log -t mirror_media 'Camera patch skipped: missing file or unexpected hash'
    fi
fi
