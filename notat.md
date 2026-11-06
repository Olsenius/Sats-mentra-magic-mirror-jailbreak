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

- **macOS må få lov til å koble til tilbehøret. Dette kostet oss flere timer.**
  macOS spør «Tillat at tilbehøret kobles til?» første gang en USB-enhet dukker opp.
  Varselet kom på Macen, ikke på speilet, og det forsvant av seg selv før det ble
  besvart. Da ble speilet avvist, og etter det var det **helt usynlig** for Macen:
  ingenting i `system_profiler SPUSBHostDataType`, ingenting i `ioreg -p IOUSB`,
  og `rkdeveloptool ld` svarte «not found any devices!». Det ser identisk ut med
  en død kabel eller et speil som ikke er i maskrom, og vi lette lenge på feil sted.
  **Fiks:** Systeminnstillinger → Personvern og sikkerhet → «Tillat at tilbehør
  kobles til» → **Alltid**. Sett den før du begynner, for speilet dukker opp som
  nytt tilbehør ved hver omstart (maskrom, loader, recovery, Android), og hvert
  varsel du mister ser ut som maskinvarefeil.
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

## 5. Hva som skjedde etter omstart

Rett etter omstart: **ingen USB-enhet på Macen**, ingen `adb`. På skjermen kom et
språkvalg (English / Norwegian / Swedish), og etter det startet speilet i kiosk.
Vi trodde først at kiosk-appen hadde sperret adb, og deretter at kabelen var død.
**Begge var feil.** Macen hadde avvist speilet som tilbehør (se kapittel 1), så
ingenting kunne ses uansett hvilken modus speilet var i.

### Bekreftet i ettertid (lest i maskrom etter at USB-tillatelsen var fikset)

- **Nullstillingen kjørte.** De 4 sektorene vi skrev i `misc` er **nullet ut**
  igjen; recovery rydder BCB-en etter seg når den har kjørt.
- **`userdata` er laget på nytt 2026-11-06 07:03:28** (var 2021-11-08), ny UUID,
  rundt 1,2 GB brukt. Altså et rent filsystem.
- **Kiosk-appen kom likevel tilbake**, nøyaktig som rapportens kapittel 5 sier:
  den installerer seg fra skrivebeskyttet `/odm` og blir device owner på nytt.
  En nullstilling alene er ikke nok.
- Vi fikk aldri brukt adb-vinduet etter nullstillingen, men det var fordi macOS
  blokkerte USB, ikke nødvendigvis fordi vinduet var lukket. Rapporten sier at
  adb (med root) var tilgjengelig her.

### Der vi står nå

`boot-recovery` er skrevet til de samme 4 sektorene i `misc`, **uten**
`--wipe_data`, og tilbakelest som identisk. Målet er å starte i speilets egen
recovery, der kiosk-appen ikke kjører og derfor ikke kan sperre adb. Bygget er
`userdebug`, så recovery bør gi root-adb. Ikke prøvd ennå.

---

## 6. Neste steg

1. **Start speilet** (vanlig oppstart, ikke maskrom). BCB-en i `misc` sender det
   til recovery. Se etter `recovery` i `adb devices`.
2. **Virker ikke recovery-adb:** start normalt i stedet og se om adb dukker opp nå
   som macOS slipper USB gjennom. Vinduet er sannsynligvis rett etter en
   nullstilling, før kiosk-appen er ferdig provisjonert.
3. **Med adb:** følg rapportens kapittel 5, altså slett
   `/data/system/device_owner_2.xml` og `device_policies.xml`, merk
   `com.mentra.launcher` avinstallert for bruker 0 i `package-restrictions.xml`,
   og skjul APK-en på `/odm` med en overlay (`adb remount` + whiteout).

### Nyttige lesekommandoer

```sh
# misc: er BCB-en vår konsumert?
rkdeveloptool rl 32768 8 misc_now.bin && xxd -a -l 128 misc_now.bin
# userdata: når ble filsystemet laget? (les 1 MiB, dumpe2fs trenger mer enn superblokken)
rkdeveloptool rl 7752704 2048 ud.bin && dumpe2fs -h ud.bin | grep -E 'created|Mount count'
```

## 7. Regler vi holder oss til

- Ingen generisk RK3399-firmware. Panelinnstillingene ligger i speilets egen programvare.
- Ingen `EraseAll`, og ikke skriving til hele flashen.
- Rør ikke `uboot`, `trust`, `parameter` eller `boot`.
- Alt som skrives: les tilbake og sammenlign, og sjekk at nabområdene er urørt.
- Usikker på en offset? Stopp.
