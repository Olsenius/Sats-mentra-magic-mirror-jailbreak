# Minimal media fixes and network keep-alive

`device/data-local/mirror_media_local.sh` is an alternative boot hook for installations
that need the camera/audio fixes and connectivity without CPU frequency changes,
Companion assistant settings or microphone watchdogs from the full `mirror_local.sh`.

Install it as `/data/local/mirror_local.sh` only after checking any existing hook.
The system image must already contain the hook in `device/etc/mirror_setup.sh`.
Keep a copy of an existing local hook before replacing it.

Required adjacent files:

- `/data/local/net_keepalive.sh`, from `device/data-local/net_keepalive.sh`.
- `/data/local/ext-impl-patched.so`, generated with `tools/patch_external_camera_hal.py`
  from the device's original camera library. Never publish the vendor binary.
- `/data/local/usb_audio_policy_configuration.xml`, generated with
  `tools/make_usb_audio_policy.py` from the device's original USB audio policy.

The media hook verifies exact source and patched hashes before mounting anything.
Different vendor files require review; do not remove the hash checks to force a patch.
It bind-mounts copies over vendor paths without modifying the vendor partition.
It defers audio changes while a recorder is running and camera changes unless the
camera service reports no active clients. Existing mounts are left alone on reruns.
The hook starts the network watchdog before media setup.

The network watchdog checks the local supplicant state instead of pinging a router.
Every 20 seconds it disables Wi-Fi driver suspend/radio power saving and checks for
an ADB listener on port 5555. It asks the supplicant to reconnect after three checks
in a disconnected state, with at most three requests per 30 minutes. It does not
switch Wi-Fi off, probe other network hosts or wake the screen. Missing ADB listeners
are restored after two checks. It uses a PID guard and a bounded log at
`/data/local/net_keepalive.log`.

Verified on one unit: all five apps in `device/dexopt_speed.sh` compiled with status
`speed`; patched camera/audio hashes matched; both services returned to running;
re-running the hook left one watchdog and did not restart the media services;
ADB remained reachable with the screen asleep and radio power management off.
Full reboot persistence, recovery from an actual Wi-Fi drop, high-resolution image
capture and microphone recording are not yet verified by these checks.

This does not secure network ADB. The bring-up image still exposes root ADB without
authentication and must be restricted to a controlled network.
