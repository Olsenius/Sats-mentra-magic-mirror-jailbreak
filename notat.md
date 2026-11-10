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

## 4. Første skriving til speilet: `misc` (nullstilling)

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

## 6. Andre skriving: `boot-recovery` uten wipe (forsøk på root-adb)

Mål: starte i speilets egen recovery, der kiosk-appen ikke kjører og derfor ikke
kan sperre adb. Bygget er `userdebug`, så recovery bør kunne gi root-adb.

Skrevet samme 4 sektorer (32768–32771) på nytt, denne gangen bare
`boot-recovery` på offset 0 og **ingen** `recovery\n...`-argumenter. Bekreftet
null før skriving, tilbakelest identisk etter. Deretter `rkdeveloptool rd`.

**Resultat (det viktigste funnet i denne økta):**

```
Reset Device OK.
[3s] usb=1   [6s] usb=0   [9s] usb=0
[12s] ADB: MIRROR_SERIAL	recovery
```

adb **nådde** speilet i recovery-modus rundt 12 sekunder etter omstart, men
enheten var borte før neste kommando rakk å kjøre. 120 sekunder med polling
etterpå fant ingenting: `adb=''`, `usb=0`, `maskrom=0`.

Da recovery-**menyen** sto på skjermen, var det fortsatt **ingen USB-enhet i det
hele tatt** på Macen — ingen `0x2207` i `system_profiler`, ingenting i
`adb devices`, og `rkdeveloptool ld` svarte «not found any devices!».

**Tolkning:** recovery slår på adbd tidlig i oppstarten, men USB forsvinner når
menyen tar over skjermen. Recovery i ro, med menyen framme, eksponerer altså
ingenting. Vinduet er reelt, men bare noen sekunder langt, og det er helt i
starten — før menyen.

---

## 7. Der vi står nå (2026-11-06)

- Speilet står i **recovery-menyen**. Ingen USB.
- `misc` er tømt av recovery igjen (den rydder BCB-en etter seg).
- Kiosk-låsen er **ikke** fjernet. En nullstilling er kjørt, og kiosk-appen kom
  tilbake fra `/odm`, nøyaktig som rapportens kapittel 5 forutsier.
- Full verifisert backup finnes (kapittel 3), **men bare på NAS-en**.
- Macens USB-tillatelse må stå på **Alltid**, ellers ser man ingenting uansett.

---

## 8. Neste steg

### A. Beste neste forsøk: send recovery rett i sideload

I stedet for å jage et vindu på noen sekunder, be recovery om å gå **direkte til
sideload**. Da blir adbd stående og venter i ubestemt tid, uten at menyen tar
over USB. Dette krever maskrom for å skrive `misc`.

```sh
# Bygg BCB: command="boot-recovery", recovery="recovery\n--sideload\n"
printf 'boot-recovery' > /tmp/bcb.bin
truncate -s 64 /tmp/bcb.bin
printf 'recovery\n--sideload\n' >> /tmp/bcb.bin
truncate -s 2048 /tmp/bcb.bin
xxd /tmp/bcb.bin | head -6          # kontroller før skriving

# Speilet i maskrom, loader lastet:
gtimeout 60 rkdeveloptool db /path/to/workspace/tools-src/rkbin/rk3399_loader_v1.30.130.bin
gtimeout 30 rkdeveloptool rfi                       # eneste måte å bekrefte at loaderen kjører
gtimeout 30 rkdeveloptool rl 32768 4 /tmp/misc_before.bin && xxd /tmp/misc_before.bin | head -4
gtimeout 60 rkdeveloptool wl 32768 /tmp/bcb.bin
gtimeout 30 rkdeveloptool rl 32768 4 /tmp/misc_after.bin && cmp /tmp/bcb.bin /tmp/misc_after.bin
gtimeout 30 rkdeveloptool rl 32772 60 /tmp/misc_rest.bin   # skal være identisk med backupen
gtimeout 30 rkdeveloptool rd
```

Så, **før** omstarten er ferdig, ha denne armet og ventende:

```sh
adb kill-server; adb start-server
adb wait-for-recovery-device && adb shell 'id; echo ---; getprop ro.build.type; echo ---; ls /dev/block/mapper/; echo ---; mount'
```

`adb wait-for-recovery-device` fyrer av i samme øyeblikk recovery er oppe, i
stedet for å polle etterpå. **Første kommando skal bare lese**, ikke endre noe,
så vi vet hva som er mulig før vi rører data.

Er tilstanden `sideload` og ikke `recovery`, bruk
`adb wait-for-sideload-device`. Et userdebug-bygg gir ofte `adb shell` også i
sideload; gir det bare `adb sideload`, er vei A stengt.

### B. Hvis vi får skall i recovery

Følg rapportens kapittel 5:

```sh
mount /data || mount -t ext4 /dev/block/by-name/userdata /data
rm -f /data/system/device_owner_2.xml /data/system/device_policies.xml
# og merk com.mentra.launcher avinstallert for bruker 0 i
# /data/system/users/0/package-restrictions.xml
```

**Dette alene holder ikke.** Rapporten er tydelig: APK-en ligger på
skrivebeskyttet `/odm/bundled_uninstall_back-app/` og setter seg som device
owner på nytt ved hver oppstart. APK-en må også skjules permanent, med
`adb remount` (overlayfs) og en whiteout over `/odm`. Sjekk derfor i recovery om
`/dev/block/mapper/odm` finnes og kan monteres, og om APK-en ligger der
rapporten sier.

### C. Hvis recovery-adb er stengt: nullstill og kapre første oppstart

Skriv BCB med `recovery\n--wipe_data\n--locale=en_US\n` (som i kapittel 4),
og ha `adb wait-for-device` armet. Rapporten sier root-adb var tilgjengelig rett
etter nullstillingen, før kiosk-appen var ferdig provisjonert. Vi fikk aldri
prøvd dette, fordi macOS blokkerte USB den gangen.

### D. Siste utvei: endre `odm` offline over maskrom

Les `super` (sektor 1379328, lengde 6373376), finn `odm`-ekstentene i
LP-metadataen, fjern APK-en i ext4-bildet med `debugfs`, skriv tilbake bare de
berørte sektorene.

**Ikke gjort, og ikke verifisert.** Kjernens kommandolinje har
`androidboot.veritymode=enforcing`, samtidig som `vbmeta` rapporterer
verifisering avslått. Det er uavklart om `/odm` er dm-verity-beskyttet. Er den
det, vil en endring gi en enhet som ikke starter. **Avklar dette før noe skrives:
les `vbmeta` og se etter en hashtree-deskriptor for `odm`.** Backupen finnes, så
det er reparerbart, men dette er den dyreste veien.

### E. Rydd opp uansett

Kopier backupen fra `/path/to/backups/original/` til et annet
sted. Den finnes nå bare på ett sted.

### Nyttige lesekommandoer

```sh
# misc: er BCB-en vår konsumert?
rkdeveloptool rl 32768 8 misc_now.bin && xxd -a -l 128 misc_now.bin
# userdata: når ble filsystemet laget? (les 1 MiB, dumpe2fs trenger mer enn superblokken)
rkdeveloptool rl 7752704 2048 ud.bin && dumpe2fs -h ud.bin | grep -E 'created|Mount count'
# vbmeta: finnes det en hashtree-deskriptor for odm?
rkdeveloptool rl 57344 2048 vbmeta.bin && strings vbmeta.bin | head -20
```

## 9. Regler vi holder oss til

- Ingen generisk RK3399-firmware. Panelinnstillingene ligger i speilets egen programvare.
- Ingen `EraseAll`, og ikke skriving til hele flashen.
- Rør ikke `uboot`, `trust`, `parameter` eller `boot`.
- Alt som skrives: les tilbake og sammenlign, og sjekk at nabområdene er urørt.
- Usikker på en offset? Stopp.

## 10. Oppfølging 2026-11-10: offline deaktivering av installasjonskilden

- Factory reset med ADB ventende ga fortsatt ingen USB/ADB; Mentra kom tilbake.
- Viktig: `db` kan få timeout selv når loaderen har startet. Direkte `rfi` bekreftet Samsung 120832000 sektorer etter timeout. Ikke last loader på nytt uten å sjekke `rfi`.
- Backupens vbmeta: Algorithm NONE, Flags 2, ingen deskriptorer. Live vbmeta ble sammenlignet byte for byte med backupen.
- Live LP-metadata (første MiB av super) og hele odm ble sammenlignet med backupen: identiske.
- odm: 40408 sektorer fra absolutt LBA 4267008 (super 1379328 + extent 2887680).
- Endret bare katalogoppføringen i odm-blokk 15: `com.mentra.launcher.apk` → `com.mentra.launcher.off`. Filinnhold og inode beholdes. Én sektor skrevet: absolutt LBA **4267128**.
- Hele odm lest tilbake etter skriving: identisk med forberedt bilde, alle øvrige byte uendret. `e2fsck -fn` består.
- Original og patch ligger foreløpig i `/tmp/mirror-analysis/odm-original-sector.bin` og `odm-patch-sector.bin`; full original finnes i NAS-backupen. For rollback: gjenopprett den opprinnelige sektoren fra verifisert backup etter kontroll av live data.
- Deretter skrevet verifisert wipe_data-BCB i de første fire misc-sektorene; resten av de første 64 sektorene uendret. Reset sendt, ADB venter.
- **Eier bekreftet etter omstart: speilet er inne i stock Android.** Deaktivering av installasjonskilden i `/odm` etterfulgt av nullstilling ga vanlig Android i stedet for Mentra-oppsettet. Device-owner-status og varighet gjennom en ny kaldoppstart er ennå ikke kontrollert.

## 11. Bekreftet nettverks-ADB og gjennomgang av Android 13

- `adb connect 192.0.2.10:5555` lyktes. Android 10, `sys.boot_completed=1`, ADB som uid 2000 (shell).
- `pm list packages com.mentra` ga ingen pakker; `dumpsys device_policy` viste ingen aktive administratorer/device owner. Mentra-låsen er dermed fjernet i nåværende oppstart. Kaldoppstart er ennå ikke testet.
- Repoets Android 13-løp: kapittel 7 (modifisert offisiell arm64 A/B GSI, DSU-test først), deretter kapittel 11 (permanent system i to extents i super, LP-metadata sist, tilbakelesing og rollback-slice).
- Bygg krever Linux med loop-mount og SELinux-xattrs; build-skriptene har hardkodede `/root/a13` og placeholder-stier. Flash-skriptene har forfatterens image-/metadata-hasher og skal ikke kjøres uendret på vårt speil.
- GSI og ferdig system-image følger ikke repoet. Nytt bilde må anskaffes fra offisiell kilde, tilpasses og verifiseres før DSU-test. Ingen Android 13-image er lastet ned eller skrevet i denne gjennomgangen.
- Vår odm er nå endret med én sektor. Fremtidige hash-sjekker må sammenligne mot den verifiserte patchen, ikke kreve original odm-hash fra forfatterens speil.

## 12. Android 13 DSU-bygg i Docker (2026-11-10, pågår)

- Root bekreftet med `su 0 id` (denne su-varianten støtter ikke `su -c`).
- Docker Desktop Linux; container `mirror-a13-builder` (privileged for loop-mount), volum `mirror-a13-work` montert på `/root/a13`. Repo montert read-only på `/repo`.
- Offisiell AOSP ARM64 GSI TQ3A.230805.001.A3, arkiv `aosp_arm64-exp-TQ3A.230805.001.A3-10454027-66e107ed.zip`, fra Googles GSI-utgivelsesside.
- Arkivets SHA256 kontrollert mot Google: `66e107edaf84b74ba1572be9a4216bf7ae45b3b7f0b516ba2b7aa365ba763905`.
- Kjørte `build/a13-build1.sh` i container; vendor CIL hentet fra vår verifiserte vendor-backup. Tilpasset `build/a13-mod.sh` med denne filstien. 1820 typer gjort permissive som repoets kompatibilitetsmetode; SELinux-xattrs kontrollert bevart.
- Brukte dagens `device/etc/{dbg_log.sh,mirror_setup.sh,tw_daemon.sh,init/zz_dbg.rc}` fremfor eldre innebygde kopier i byggeskriptene. Kamera beholder VPU-tilgang som i oppdatert repo.
- Lagt til `persist.adb.tcp.port=5555` og `service.adb.tcp.port=5555` for nettverks-ADB under DSU-test. Repoets bring-up-oppsett bruker root-ADB uten autentisering og permissive SELinux-domener.
- `e2fsck -fy`, krymping, 64 MiB slakk og avsluttende `e2fsck -fn` består. Ferdig image: 2493153280 byte, SHA256 `e1634afb6493499ce5d6d4affc6cea788de53deb814c2670561b764c3b918568`.
- Docker-image: `/root/a13/system_new.img`; vertskopi `/tmp/mirror-analysis/android13-dsu.img`, gzip-kopi ved siden av. Tilpasset byggesekvens foreløpig `/tmp/mirror-analysis/prepare-dsu.sh` (siste fsck/shrink kjørt separat etter at resize2fs krevde skrivende fsck).
- Overføring av gzip-image til `/data/local/tmp/android13-dsu.img.gz` pågår. DSU ikke installert eller startet ennå; permanent system i super urørt av Android 13-arbeidet.

### DSU installert og testoppstart sendt

- Gzip-overføring fullført, 1085612675 byte. Pakket ut på speilet; SHA256 identisk med Docker-bygget.
- Installert med root `gsi_tool install --gsi-size 2493153280 --userdata-size 8589934592 --no-reboot`. Android 10-verktøyet bruker fd 1 som bildestrøm; fd 0 og 1 ble åpnet read-only mot image-filen.
- `/data/gsi/dsu/system_gsi.img.0000` kontrollert med SHA256: identisk med bildet. Feilloggen var tom.
- `gsi_tool status` viste installed/disabled. AOSP Android 10-koden forklarer dette før første oppstart: install_status inneholdt `0`, one_shot_boot `1`; setGsiBootable hadde allerede klargjort engangsoppstarten. Et ekstra enable-forsøk svarte «not currently disabled» og endret ikke dette.
- `adb reboot` sendt for første DSU-test. Android 13-oppstart, skjerm og nettverks-ADB er ennå ikke bekreftet. DSU-data er separate; Wi-Fi kan måtte settes opp manuelt. Permanent Android 13-flashing er ikke utført.

### Android 13 DSU-test bekreftet

- Eier bekreftet Android 13 på skjermen og koblet til samme Wi-Fi, samme IP.
- Nettverks-ADB på `192.0.2.10:5555` fungerer; `id` viser uid 0 (root).
- Android 13, build `TQ3A.230805.001.A3`, `sys.boot_completed=1`.
- `gsi_tool status`: running, installed, disabled. Running bekrefter DSU-gjesten; disabled er forenlig med engangsoppstart og betyr at testen ikke er gjort permanent.
- Ingen com.mentra-pakker og ingen aktive device-adminer/device owner i dumpsys.
- Skjerm 1080x1920, density 240.
- Permanent Android 13 i super er fortsatt ikke installert. Vanlig ny omstart kan returnere til Android 10; videre permanent installasjon må følge egne kontroller og rollback-oppsett i kapittel 11 i rapporten.

## 13. Permanent Android 13: skrivefasen fullført (2026-11-10)

- Brukeren ba uttrykkelig om permanent installasjon etter vellykket DSU-test.
- Live super-head identisk med backup, SHA256 `7a551ebb5fad13105315003705a7f31a368c812dbd0607ef91cdd417c7a4ef9d`. DSU-kilden `/dev/block/mapper/system_gsi` er read-only og har SHA256 `e1634afb6493499ce5d6d4affc6cea788de53deb814c2670561b764c3b918568`.
- Rollback-slice: 940544000 byte (super-sektor 0–1836999), SHA256 `56b6f425da724552fc7451f82268f41a601d4808df88aada6c0764a37ef8fdef`, matcher live original systemregion + metadata før skriving.
- System: 4869440 sektorer, extent A 1834952 @ 2048, extent B 3034488 @ 2930688, relativt til super. Ny metadata godkjent av enhetens lpdump før skriving.
- Tilpasset stage1 brukte read-only DSU-blokken direkte, i stedet for ny stor nettverksoverføring. Extent B skrevet og tilbakelest først: `d638e51f406c4025c236220f1a23d94bae8113aaf9ec2f77d107cdd4ccb63b22`; A deretter: `a3a24173c436c98199e7a0f353720dceed165c48ab50298e4dbfd8cd4d880cc8`.
- Ny dm-linear mapping hash stemmer med hele Android 13-bildet; read-only mount viste Android 13. Sammenhengende område fra super-sektor 1837056 til 2930687 (vendor/product/odm + mellomrom) hashet før og etter: uendret. Stage1 OK.
- Stage2 skrev første MiB av super, hash `ef43d6fb000dd59455447c419325ec25c1ea045ece56f40682d9597661775eb0`; tilbakelesing stemmer og lpdump viser riktig layout.
- Recovery wipe-BCB skrevet til første fire misc-sektorer etter kontroll av tom BCB; tilbakelest lik og nabosektorene uendret. `adb reboot recovery` sendt for nullstilling av data/DSU og første permanente oppstart.
- Rollback-slice, metadata før/etter, lokale flash-skript, stage1-logg og BCB-filer lagret i `/path/to/backups/android13-migration/`.
- **Permanent oppstart uten DSU er bekreftet.** Etter at eier koblet til Wi-Fi igjen: Android 13 `TQ3A.230805.001.A3`, `sys.boot_completed=1`, `gsi_tool status=normal`, `/dev/block/dm-0` montert read-only på `/`, og permanent systempartisjon på 2493153280 byte. Root-ADB virker på samme IP. Ingen com.mentra-pakker eller aktive device-adminer/device owner. En ekstra kaldoppstart er ikke testet.
