# Arbeidsnotat: SATS Mentra Rflex-speil på macOS

Egne notater fra vår egen økt, startet 2026-11-05. Skrevet 2026-11-06.
Ikke en del av det opprinnelige repoet (som er en erfaringsrapport fra en annen person og et annet speil).

Maskin: MacBook (Apple Silicon), macOS 27.0.1. Speilet er samme modell som i rapporten:
RK3399, Samsung eMMC 59000 MB, serienummer MIRROR_SERIAL.

---

## 1. Verktøy på macOS (RKDevTool finnes ikke for Mac)

| Verktøy | Hvordan |
|---|---|
| `rkdeveloptool` 1.32 | Bygget fra kilde (`rockchip-linux/rkdeveloptool`, commit 304f073). Krevde `make CXXFLAGS="-g -O2 -Wno-vla-cxx-extension"` fordi Apples clang gjør en advarsel om til feil. Ligger i `/opt/homebrew/bin/`. Kilde: `/path/to/workspace/tools-src/rkdeveloptool/` |
| `rk3399_loader_v1.30.130.bin` | Fantes ikke ferdig i `rockchip-linux/rkbin`. Satt sammen med Rockchips `boot_merger` fra `RKBOOT/RK3399MINIALL.ini`, kjørt i Docker (`debian:bookworm-slim`, `--platform linux/amd64`) fordi `boot_merger` er et Linux-program. Resultat: 454 990 byte, starter med `BOOT`, sha256 `5555479f6df3aba516a6aefb4beb86322f81dcec9db5e0bcae26d436286a847a`. Ligger i `/path/to/workspace/tools-src/rkbin/` |
| `adb` / `fastboot` | `brew install --cask android-platform-tools` (v37) |
| `e2fsprogs` | `brew install e2fsprogs`. Keg-only, så verktøyene ligger i `/opt/homebrew/opt/e2fsprogs/sbin/` (`debugfs`, `dumpe2fs`, `resize2fs`, `mke2fs`) |
| `lsusb`, `gtimeout` | `brew install lsusb coreutils` |

### Erfaringer med rkdeveloptool på Mac

- **USB-C til USB-C rett i Macen fungerte.** Ingen USB-2.0-hub var nødvendig, i motsetning til rapportens Windows-oppsett. Tilkoblingen kjørte på 480 Mb/s (USB 2.0-hastighet).
- **Ingen drivere trengs.** `rkdeveloptool` snakker direkte med USB gjennom libusb.
- **`ld` viser `Maskrom` også etter at loaderen er lastet.** På Mac bytter den ikke til `Loader`, slik rapporten beskriver fra Windows. Den eneste måten å sjekke om loaderen kjører, er å gjøre noe som krever den, for eksempel `rfi`.
- **`db` to ganger på rad henger.** Skjer loaderen å ikke starte, må speilet strømmes helt av og settes i maskrom på nytt før nytt forsøk.
- **Pakk kommandoene i `gtimeout`.** `rkdeveloptool` henger uten tidsgrense hvis speilet er i en halvveis tilstand.

---

## 2. Lest fra speilet (ingen skriving)

`rkdeveloptool rfi`: Samsung, 59000 MB, **120 832 000 sektorer** = 61 865 984 000 byte. Identisk med rapportens speil.

`rkdeveloptool ppt`: 15 partisjoner, samme navn og samme start-LBA som `docs/partition-map.txt`.

**Feil funnet i `docs/partition-map.txt`:** `frp` har desimal start 1370112, men riktig er **1378304** (hex `0x150800` stemmer; desimaltallet i dokumentet er feil). Oppdaget av en gap-sjekk i vårt eget backupskript.

---

## 3. Full backup (ferdig og verifisert)

Ligger i `/path/to/backups/original/` (NAS). Macen hadde ikke nok ledig plass.

- Tatt med `/path/to/workspace/backup-emmc.sh`, som bare bruker lesekommandoen `rl`. Store partisjoner leses i biter på 2 GiB, og ferdige biter hoppes over hvis skriptet startes på nytt.
- **61 865 984 000 byte**, nøyaktig hele eMMC-en. Ingen feil, ingen nye forsøk.
- `sha256` for hele: `1ce310f1bc57b30e88d735421e8d9bf27c733a7f6ac0f18d674812ad82086773` (konkatenering av filene i `ORDER.txt`).
- Per fil: `SHA256SUMS` (44 filer). Oppsummering: `VERIFISERING.txt`.
- **Uavhengig andre lesing** med `/path/to/workspace/verify-emmc.sh`: alt unntatt `cache` og `userdata` ble lest en gang til fra speilet og hashet. **16 av 16 like.** Backupen representerer altså speilet, ikke bare en lesbar fil.
- GPT er hel: både primær header (sektor 1) og backup-header (siste sektor) har signaturen `EFI PART`.
- Tidsbruk: lesing rundt 1 time 8 minutter (farten varierte mellom 4 og 23 MB/s), hashing rundt 3,5 timer. macOS sin `shasum` er skrevet i Perl og er treg; `openssl dgst -sha256` ville gått mye raskere.

**Backupen ligger foreløpig bare på NAS-en. Den bør kopieres til et annet sted.**

### Bevis fra backupen på at speilet aldri var nullstilt

- `userdata`: ext4 laget **2021-11-08 09:41**, sist montert **2026-11-05 20:39** (da vi startet speilet), `Mount count: 1`, rundt 1,8 GB brukt.
- `cache`: recovery-loggene (`last_log`, `last_kmsg`) er fra **2021-11-08**. Recovery hadde ikke kjørt siden fabrikken.
- `misc` hadde en gammel `boot-recovery` + `recovery\n--wipe_all\n` på offset **16 KiB** (`0x4000`), en rest fra fabrikkflashingen i 2021 som speilet har ignorert i fem år.
- Kjernens kommandolinje (fra `last_kmsg`): `androidboot.verifiedbootstate=orange`, `androidboot.selinux=permissive`, `buildvariant=userdebug`. Altså ulåst bootloader og userdebug-bygg, som rapporten sier.

---

## 4. Første og eneste skriving til speilet: `misc`

Mål: få recovery til å nullstille `userdata`, slik rapportens kapittel 5 beskriver, for å få root-adb.

- Skrevet **4 sektorer (2048 byte) på sektor 32768–32771**, altså helt i starten av `misc`:
  `boot-recovery` på offset 0, og `recovery\n--wipe_data\n--locale=en_US\n` på offset 64.
- Før skriving: bekreftet at de samme 4 sektorene var **bare nuller** på speilet, likt backupen.
- Etter skriving: tilbakelest og **identisk** med filen vi skrev.
- Kontrollert at resten av `misc` (sektor 4–63) er **byte-identisk med backupen**.
- `rkdeveloptool rd` (Reset Device) rundt 06:58.

**Angre dette:** skriv de samme 4 sektorene tilbake med nuller, fra backupen:
```sh
dd if=03_misc.img bs=512 count=4 of=misc_head_original.bin
rkdeveloptool wl 32768 misc_head_original.bin
```

---

## 5. Hva som skjedde etter omstart (uavklart)

- Macen så **ingen USB-enhet** på 6 minutter etter omstart. Ingen `adb`, ingenting i USB-treet.
- På skjermen kom et **språkvalg** (English / Norwegian / Swedish). Oppsettet ble ikke rørt.
- Mest sannsynlig tolkning, som stemmer med rapportens kapittel 5: nullstillingen kjørte, Android 10 startet rent, og **kiosk-appen installerte seg på nytt fra `/odm` og ble device owner igjen**. Den slår av adb via `DISALLOW_DEBUGGING_FEATURES`, så USB-porten viser seg ikke for Macen.
- **Dette er ikke bekreftet.** Vi fikk aldri adb, så vi vet ikke sikkert at nullstillingen faktisk kjørte. Rapporten sier at adb var tilgjengelig etter nullstillingen, men ikke hvordan de koblet til, så det er mulig de rakk det i et kort vindu før appen sperret.

### Der vi står nå

Speilet er satt i maskrom igjen, men **`rkdeveloptool ld` finner ingen enhet**. Macen ser heller ingenting i USB-treet. Dette er uløst.

Ting å prøve:
1. Strøm helt av, vent 10–15 sekunder, hold knappen inne mens strømmen settes på, og hold i 3–5 sekunder etter.
2. Prøv en annen kabel, en annen port på Macen, og en USB 2.0-hub mellom.
3. Sjekk i  → Om denne maskinen → Systemrapport → USB om noe som helst dukker opp.
4. Kjør `rkdeveloptool ld` flere ganger mens speilet kobles til, for å fange opp et kort vindu.

---

## 6. Neste steg når kontakten er tilbake

1. **Les `misc`.** Er de 4 sektorene vi skrev nullet ut, har recovery kjørt og ryddet etter seg. Det bekrefter nullstillingen.
2. **Les superblokken på `userdata`** (`rkdeveloptool rl 7752704 8`, så `dumpe2fs -h`). Nytt «Filesystem created»-tidspunkt betyr at filsystemet er laget på nytt.
3. **Start i recovery uten nullstilling:** skriv bare `boot-recovery` (uten `--wipe_data`) til de samme 4 sektorene, og start på nytt. Kiosk-appen kjører ikke i recovery, så den kan ikke sperre adb der. Siden bygget er `userdebug`, bør recovery gi root-adb. Dette er ikke prøvd ennå.
4. Med adb: følg rapportens kapittel 5, altså slett `/data/system/device_owner_2.xml` og `device_policies.xml`, merk `com.mentra.launcher` avinstallert for bruker 0 i `package-restrictions.xml`, og skjul APK-en på `/odm` med en overlay (`adb remount` + whiteout).

## 7. Regler vi holder oss til

- Ingen generisk RK3399-firmware. Panelinnstillingene ligger i speilets egen programvare.
- Ingen `EraseAll`, og ikke skriving til hele flashen.
- Rør ikke `uboot`, `trust`, `parameter` eller `boot`.
- Alt som skrives: les tilbake og sammenlign, og sjekk at nabområdene er urørt.
- Usikker på en offset? Stopp.
