#!/bin/bash
# Verifying an Android image: the boot header, the appended DTB, AVB.
#
# docs/devices.md D12. This asserts the things only this artifact shape can be
# asked about; everything that is really about the rootfs stays in
# image/verify.sh, so a second backend inherits it.
#
# The artifact is a DIRECTORY, not a file (D10): boot.img, vbmeta.img,
# rootfs.simg and flash.sh. So "decompress" has no counterpart here -- but the
# rootfs is an Android SPARSE image and has to be expanded with simg2img before
# image/verify.sh can mount it, because fastboot cannot flash a raw image over
# 4 GiB and ours is 6.06.

# Assert the boot artifacts, then hand image/verify.sh a $WORK/root.img.
verify_artifact() {
sec "artifact"
# A directory, and saying so plainly beats "cannot open file" three checks later.
[ -d "$IMG_XZ" ] || { no "$IMG_XZ is not a directory -- an Android artifact is a directory of images (D10)"; return 1; }
# vbmeta.img is NOT in this list, because whether one exists is a device fact
# (android-bootimg.sh's NEEDS_VBMETA) rather than a property of the artifact
# shape. The Fairphone takes none, and demanding one here reported a correct
# image as broken. The "verified boot" section below is where it is asked
# about, in both directions: present-and-wrong on a device that takes one,
# present-at-all on a device that does not.
for f in boot.img rootfs.simg flash.sh; do
  [ -e "$IMG_XZ/$f" ] && ok "$f present" || no "$f missing from the artifact"
done
[ -x "$IMG_XZ/flash.sh" ] && ok "flash.sh is executable" || no "flash.sh is not executable"

# The retry counter (D26). Without a --set-active the bootloader may refuse the
# image that was just flashed, with nothing on screen to say why -- so the one
# line that clears it is asserted rather than assumed to have survived an edit.
grep -q -- '--set-active' "$IMG_XZ/flash.sh" \
  && ok "flash.sh resets the slot retry counter" \
  || no "flash.sh never runs --set-active; a spent retry counter refuses the new image (D26)"

sec "boot image"
# The v0 header, at the offsets image/boot/android-image.py writes and that
# were measured off an image which demonstrably boots this device.
hdr=$(dd if="$IMG_XZ/boot.img" bs=8 count=1 status=none 2>/dev/null)
[ "$hdr" = "ANDROID!" ] && ok "ANDROID! magic" || no "boot.img does not start with ANDROID! (got '$hdr')"

# page_size is at byte 36, header_version at 40, both little-endian u32.
psize=$(od -An -tu4 -j36 -N4 "$IMG_XZ/boot.img" 2>/dev/null | tr -d ' ')
hver=$(od -An -tu4 -j40 -N4 "$IMG_XZ/boot.img" 2>/dev/null | tr -d ' ')
[ "$psize" = 4096 ] && ok "page size 4096" || no "page size is $psize, not 4096"
[ "$hver" = 0 ] && ok "header version 0" || no "header version is $hver, not 0"

# ramdisk_size, a little-endian u32 at byte 16. This backend ships no initramfs
# (D24) -- the kernel mounts root itself -- and a non-zero value here means one
# crept back in, which on this device is 18 MB of code that cannot print.
rdsz=$(od -An -tu4 -j16 -N4 "$IMG_XZ/boot.img" 2>/dev/null | tr -d ' ')
[ "$rdsz" = 0 ] && ok "no ramdisk (the kernel mounts root itself)" \
                || no "boot.img carries a ${rdsz:-?}-byte ramdisk; this backend ships none (D24)"

# kernel_size, a little-endian u32 at byte 8. Read here because the size check
# below needs it and so does the DTB extraction further down.
ksize=$(od -An -tu4 -j8 -N4 "$IMG_XZ/boot.img" 2>/dev/null | tr -d ' ')

# The whole file should then be the header page plus the padded kernel, with
# nothing after it. Catches a stray page or a truncated kernel, both of which
# boot into silence.
want=$(( 4096 + (ksize + 4095) / 4096 * 4096 ))
have=$(stat -c%s "$IMG_XZ/boot.img")
[ "$have" = "$want" ] && ok "boot.img is header + kernel, $have bytes" \
                      || no "boot.img is $have bytes, not the $want a header plus a padded kernel makes"

sec "boot cmdline"
# Read back out of the artifact rather than trusted from the script that wrote
# it. Every line of this is a thing that, if wrong, gives two penguins and
# silence -- there is no console on this device to say which (D23).
#
# The v0 header splits the cmdline: 512 bytes at offset 64, the rest at 608.
cmdline=$(dd if="$IMG_XZ/boot.img" bs=1 skip=64 count=512 status=none 2>/dev/null | tr -d '\0')
cmdline="$cmdline$(dd if="$IMG_XZ/boot.img" bs=1 skip=608 count=1024 status=none 2>/dev/null | tr -d '\0')"
printf '  cmdline: %s\n' "$cmdline"

case "$cmdline" in
  *root=PARTLABEL=*) ok "root=PARTLABEL= (the kernel resolves this without udev)" ;;
  *root=LABEL=*) no "root=LABEL= needs an initramfs to resolve a filesystem label; this image has none" ;;
  *) no "no root= in the cmdline -- the kernel would use whatever the bootloader passes" ;;
esac

# The one that cost a night. ABL appends init=/init, which is right for an
# Android ramdisk and wrong for an Arch rootfs, and a failed init= is a panic
# with no fallback. Ours must come after it, so it must be here.
case " $cmdline " in
  *" init=/sbin/init "*) ok "init=/sbin/init overrides the bootloader's init=/init (D25)" ;;
  *" init="*) no "init= is set to something other than /sbin/init -- check it exists in the rootfs" ;;
  *) no "no init= -- ABL appends init=/init, an Arch root has no /init, and the kernel panics (D25)" ;;
esac

case " $cmdline " in
  *" ro "*) ok "root starts read-only, so systemd-fsck-root can check it" ;;
  *) no "root is not mounted ro; systemd-fsck-root has ConditionPathIsReadWrite=!/ and will never run" ;;
esac
case " $cmdline " in
  *" rootwait "*) ok "rootwait (the eMMC is not probed when init runs)" ;;
  *) no "no rootwait -- the root device is not necessarily there yet" ;;
esac

# One fact, one spelling: the partition the kernel is told to boot from is the
# partition flash.sh writes the rootfs to.
cmdpart=${cmdline##*root=PARTLABEL=}; cmdpart=${cmdpart%% *}
flashpart=$(sed -n 's/^ROOTPART=//p' "$IMG_XZ/flash.sh" | head -1)
[ -n "$cmdpart" ] && [ "$cmdpart" = "$flashpart" ] \
  && ok "boot cmdline and flash.sh agree on '$cmdpart'" \
  || no "cmdline boots from '${cmdpart:-?}' but flash.sh writes the rootfs to '${flashpart:-?}'"

# The kernel payload must carry an appended DTB: sargo's deviceinfo sets
# append_dtb=true, and a boot image without one is a black screen with nothing
# to read. FDT magic is d00dfeed, big-endian, and it should appear AFTER the
# gzip magic that starts the kernel.
dd if="$IMG_XZ/boot.img" of="$WORK/kernel.bin" bs=1 skip=4096 count="${ksize:-0}" status=none 2>/dev/null
kmagic=$(dd if="$WORK/kernel.bin" bs=2 count=1 status=none 2>/dev/null | od -An -tx1 | tr -d ' \n')
[ "$kmagic" = "1f8b" ] && ok "kernel payload is gzip (Image.gz)" || no "kernel payload is not gzip (magic $kmagic)"
if od -An -tx1 -v "$WORK/kernel.bin" 2>/dev/null | tr -d ' \n' | grep -q 'd00dfeed'; then
  ok "a device tree is appended to the kernel"
else
  no "no FDT magic in the kernel payload -- the DTB was not appended"
fi

sec "verified boot"
# Whether there is a vbmeta at all is a device fact (android-bootimg.sh's
# NEEDS_VBMETA), so this section asks the image rather than assuming one.
#
# The two cases are checked in OPPOSITE directions on purpose. On a device that
# takes one, a missing or wrong vbmeta is a phone that refuses the kernel. On a
# device that does not -- the Fairphone 4, whose vbmeta partition is critical
# and stays locked under a plain bootloader unlock -- a vbmeta.img sitting in
# the output directory IS the hazard, because the obvious thing to do with one
# is flash it, and that fails the transaction. So its absence is the assertion.
if [ -f "$IMG_XZ/vbmeta.img" ]; then
  case "$DEVICE" in
    fp4)
      no "this image carries a vbmeta.img and $DEVICE does not take one -- flashing it would fail against a locked critical partition" ;;
    *)
      # Flag 2 is AVB_VBMETA_IMAGE_FLAGS_VERIFICATION_DISABLED. Without it an
      # Android 12 bootloader refuses an unsigned kernel, and the error it
      # gives does not mention verification -- hence asserted, not assumed.
      vmagic=$(dd if="$IMG_XZ/vbmeta.img" bs=4 count=1 status=none 2>/dev/null)
      [ "$vmagic" = "AVB0" ] && ok "vbmeta magic AVB0" || no "vbmeta.img is not an AVB image (got '$vmagic')"
      # Flags are a big-endian u32 at byte 120 of the header.
      vflags=$(od -An -tu4 --endian=big -j120 -N4 "$IMG_XZ/vbmeta.img" 2>/dev/null | tr -d ' ')
      [ "$vflags" = 2 ] && ok "vbmeta flags = 2 (verification disabled)" \
                        || no "vbmeta flags = ${vflags:-?}, not 2 -- the bootloader will refuse this kernel"
      ;;
  esac
else
  case "$DEVICE" in
    fp4) ok "no vbmeta.img, which is correct for $DEVICE (pmOS flashes none either)" ;;
    *)   no "no vbmeta.img -- an Android 12 bootloader will refuse this unsigned kernel" ;;
  esac
fi

sec "rootfs"
# Sparse, and checked for it. A raw image here would flash fine while it is
# small and fail the day the rootfs crosses 4 GiB, with fastboot reporting
# "Failed reading from userdata" -- a message about a partition that is really
# about a size. Catching it here costs one dd.
smagic=$(dd if="$IMG_XZ/rootfs.simg" bs=4 count=1 status=none 2>/dev/null | od -An -tx1 | tr -d " \n")
[ "$smagic" = "3aff26ed" ] && ok "rootfs.simg is an Android sparse image" \
  || no "rootfs.simg has magic $smagic, not 3aff26ed -- fastboot cannot flash a raw image over 4 GiB"

# Expanded rather than mounted in place: the shared checks below mount it
# read-write and run the first-boot scripts inside it.
simg2img "$IMG_XZ/rootfs.simg" "$WORK/root.img" 2>/dev/null || {
  no "simg2img could not expand rootfs.simg"; return 1; }
printf '  rootfs %s sparse -> %s raw\n' \
  "$(du -h "$IMG_XZ/rootfs.simg" | cut -f1)" "$(du -h "$WORK/root.img" | cut -f1)"
}

# ---------------------------------------------------------------------------
# The Fairphone 4's hardware chains.
#
# Kept as a separate function rather than as more branches inside sargo's
# checks, because almost nothing lines up: a different firmware directory, no
# mba.mbn, no ACDB blob, a different UCM vendor path, and no camera profile at
# all. Interleaving them would produce a block of conditionals in which
# neither device's chain could be read end to end, and reading a chain end to
# end is the entire value of these sections (D27's lesson: every link fails
# quietly, so each is asserted separately).
#
# UNBOOTED. Every path below was derived from postmarketOS's own packages for
# this device and from what pkgbuilds/firmware-moarchy-fp4 installs, not from
# a phone. See docs/fairphone-4.md.
_verify_hw_fp4() {

sec "the Wi-Fi chain (D27, fp4)"
# Same shape as sargo's and for the same reason: Wi-Fi here is not one
# component failing loudly, it is a chain going quiet. The WCN3990 firmware
# executes on the MODEM DSP, so a phone with no modem firmware has no Wi-Fi --
# which is why modem.mbn is in this section and not in a telephony one.
#
# No mba.mbn in this list, and that is a real difference rather than an
# oversight: sargo needs the modem boot authenticator as a separate image,
# and FairBlobs/FP4-firmware ships none -- pmaports' firmware-fairphone-fp4
# installs no mba.mbn either.
_fwd=$R/usr/lib/firmware/qcom/sm7225/fairphone4
for _f in modem.mbn wlanmdsp.mbn adsp.mbn cdsp.mbn; do
  if [ -s "$_fwd/$_f" ]; then ok "firmware $_f present"
  else no "no $_fwd/$_f -- the DSP never boots, so what runs on it never runs"; fi
done

# The protection-domain mapper, which is the KERNEL's on this SoC too --
# CONFIG_QCOM_PD_MAPPER=m in the vendored config. A missing module here is
# silent: the WLAN domain lookup simply never resolves.
_kver=$(ls "$R/usr/lib/modules" 2>/dev/null | head -1)
if [ -n "$_kver" ] && \
   find "$R/usr/lib/modules/$_kver" -name 'qcom_pd_mapper.ko*' | grep -q .; then
  ok "the in-kernel protection-domain mapper is present ($_kver)"
else
  no "no qcom_pd_mapper module in the image -- nothing answers the WLAN domain lookup"
fi

# The userspace half: rmtfs is what actually starts the modem DSP, because
# nothing in the kernel does (qcom_q6v5_mss sets rproc->auto_boot = false).
[ -x "$R/usr/bin/rmtfs" ] \
  && ok "rmtfs is installed (it is what starts the modem DSP)" \
  || no "no /usr/bin/rmtfs -- the modem remoteproc is never told to start, so there is no Wi-Fi"

sec "the audio chain (fp4)"
# Shorter than sargo's, and the omissions are the finding rather than gaps in
# the checking.
#
# No Global_cal.acdb: that is an SDM670 q6core requirement. This SoC's
# calibration lives in the hexagonfs tree instead, which is served over
# FastRPC by hexagonrpcd -- a daemon that is not packaged for Arch. So the
# tree is checked for, and the thing that would read it is known to be absent.
[ -d "$R/usr/share/qcom/sm7225/Fairphone/fp4" ] \
  && ok "the hexagonfs tree is installed" \
  || no "no /usr/share/qcom/sm7225/Fairphone/fp4 -- the DSPs have no filesystem to read"

# The use-case profile. Without it the card exists and PipeWire shows no sink,
# because WirePlumber will not expose a card it cannot route. The conf.d name
# has to be the card's long name exactly -- "Fairphone 4", space included.
[ -s "$R/usr/share/alsa/ucm2/Fairphone/fp4/HiFi.conf" ] \
  && ok "the fp4 ALSA use-case profile is installed" \
  || no "no ucm2/Fairphone/fp4/HiFi.conf -- the card would expose no sink"
# -L, not -e. This is a symlink whose target is ABSOLUTE
# (/usr/share/alsa/ucm2/Fairphone/fp4/fp4.conf), which is correct on the phone
# and unresolvable here: -e follows it and lands on the CONTAINER's /usr,
# where it does not exist, so a perfectly good package reads as missing. The
# target is checked as a string instead, which is the thing that has to be
# right anyway.
_ucmlink="$R/usr/share/alsa/ucm2/conf.d/sm7225/Fairphone 4.conf"
if [ -L "$_ucmlink" ] || [ -e "$_ucmlink" ]; then
  ok "ALSA can find it by card name (conf.d/sm7225)"
  _t=$(readlink "$_ucmlink" 2>/dev/null)
  case "$_t" in
    /usr/share/alsa/ucm2/Fairphone/fp4/fp4.conf|"")
      [ -n "$_t" ] && ok "the lookup points at the profile this package ships" ;;
    *) no "conf.d link points at '$_t', not the fp4 profile" ;;
  esac
else
  no "no conf.d/sm7225/'Fairphone 4'.conf -- the profile exists and nothing looks it up"
fi

# The speaker amplifier's firmware, in both of the two places
# firmware-moarchy-fp4 installs it. Which one the aw88264 driver asks for is
# not settled off the config alone, so the package ships both and this checks
# both are really there rather than that one of them is.
for _f in aw882xx_spk_reg_l.bin aw882xx_spk_reg_r.bin; do
  if [ -s "$R/usr/lib/firmware/postmarketos/$_f" ] && [ -e "$R/usr/lib/firmware/$_f" ]; then
    ok "amplifier firmware $_f is reachable by both names"
  else
    no "$_f is not present under both /usr/lib/firmware and .../postmarketos -- the speaker may stay silent"
  fi
done

# The WirePlumber format override. Upstream carries it because the amplifier's
# I2S link does not accept what WirePlumber negotiates by default, and the
# symptom is silence rather than an error anyone can read.
[ -s "$R/usr/share/wireplumber/wireplumber.conf.d/52-fairphone-fp4.conf" ] \
  && ok "the S32LE format override for this card is installed" \
  || no "no 52-fairphone-fp4.conf -- WirePlumber may negotiate a format the amplifier refuses"

# --- and what is KNOWN not to work, asserted so it cannot be forgotten -----
#
# These are not failures of this image. They are upstream limits, recorded
# here as notes so that a passing run does not read as "audio works".
grep -q 'SectionDevice."Mic' "$R/usr/share/alsa/ucm2/Fairphone/fp4/HiFi.conf" 2>/dev/null \
  && ok "the UCM profile defines a capture device" \
  || note "the UCM profile defines playback only -- the built-in microphone does not work upstream either"

sec "the camera (fp4)"
# Nothing to check, and saying so is the point. sargo ships two DCP colour
# profiles; this device ships none, because its sensors do not stream yet --
# the imx576 driver was still on the mailing list in May 2026 and nothing
# configures the media graph. A colour profile here would be a correction
# applied to no image.
note "no camera profiles on $DEVICE -- the sensors do not stream on mainline yet"
}

# What has to be true of THIS device's rootfs (the optional hook in verify.sh).
verify_rootfs() {
sec "the boot slot is marked successful (D26)"
# The check that is invisible in every other section, because an image missing
# this is otherwise perfect. An A/B bootloader counts a slot down on every
# handoff and marks it unbootable at zero unless the OS calls back; a phone
# without qbootctl gets about three reboots and then needs a host with fastboot.
[ -x "$R/usr/bin/qbootctl" ] \
  && ok "qbootctl is installed" \
  || no "no /usr/bin/qbootctl -- nothing will mark the boot slot, and the phone stops booting after a few reboots (D26)"

# Enabled by the PACKAGE's own symlink, not by moarchy-firstboot: a first-boot
# script can fail, and this has to be true from the moment the image exists.
# Same two-tree rule as verify.sh's unit(): /usr/lib is how a package enables
# a unit, /etc is what `systemctl enable` writes.
_u=qbootctl-mark-successful.service
if [ -L "$R/usr/lib/systemd/system/multi-user.target.wants/$_u" ] ||
   [ -L "$R/etc/systemd/system/multi-user.target.wants/$_u" ]; then
  ok "$_u is enabled"
else
  no "$_u is not enabled in either tree -- qbootctl is installed but nothing runs it"
fi

# And that it actually runs qbootctl, rather than being a unit that was renamed
# out from under its ExecStart.
if grep -q '^ExecStart=/usr/bin/qbootctl -m' "$R/usr/lib/systemd/system/$_u" 2>/dev/null; then
  ok "the unit execs qbootctl -m"
else
  no "the unit's ExecStart is not /usr/bin/qbootctl -m"
fi

# The hardware chains below are per device, and are guarded rather than
# generalised. sargo and the Fairphone share a boot backend and almost no
# hardware: different SoC, different firmware layout, different UCM vendor
# path, different storage. What they do share is already above this line.
case "$DEVICE" in
  fp4) _verify_hw_fp4 ;;
  *)
sec "the Wi-Fi chain (D27)"
# Every link, because on this SoC Wi-Fi is not one component failing loudly but
# a chain going quiet: ath10k_snoc binds, the interface never appears, and
# nothing in dmesg says the word modem. Each of these is separately capable of
# producing that exact picture, so each is asserted separately.
#
# 1. The firmware the modem DSP boots from, and the WLAN image that runs on it.
_fwd=$R/usr/lib/firmware/qcom/sdm670/sargo
for _f in mba.mbn modem.mbn wlanmdsp.mbn; do
  if [ -s "$_fwd/$_f" ]; then ok "firmware $_f present"
  else no "no $_fwd/$_f -- the modem DSP never boots, so the WLAN firmware never runs"; fi
done

# 2. The protection-domain mapper, which is the KERNEL's on this SoC: the
# sdm670 table in qcom_pd_mapper.c names the WLAN domain ath10k looks up, and
# an auxiliary device created when a DSP starts autoloads it. A missing module
# here is silent -- the lookup simply never finds mpss_wlan_pd.
_kver=$(ls "$R/usr/lib/modules" 2>/dev/null | head -1)
if [ -n "$_kver" ] && \
   find "$R/usr/lib/modules/$_kver" -name 'qcom_pd_mapper.ko*' | grep -q .; then
  ok "the in-kernel protection-domain mapper is present ($_kver)"
else
  no "no qcom_pd_mapper module in the image -- nothing answers the WLAN domain lookup"
fi

# 3. The board file, from linux-firmware-atheros. Named here because it comes
# from a package nothing names explicitly (`linux-firmware` pulls it in), which
# is exactly how the Adreno lost its microcode twice.
[ -s "$R/usr/lib/firmware/ath10k/WCN3990/hw1.0/board-2.bin" ] \
  && ok "ath10k WCN3990 board file present" \
  || no "no ath10k/WCN3990/hw1.0/board-2.bin -- install linux-firmware-atheros"

# 4. The daemons. rmtfs is the one that is not optional and does not look
# load-bearing: its -s flag is what writes "start" to the modem remoteproc,
# because the kernel sets rproc->auto_boot = false and starts nothing itself.
# pd-mapper is NOT in this list on purpose -- check 2 is what replaced it.
for _b in rmtfs tqftpserv; do
  [ -x "$R/usr/bin/$_b" ] && ok "$_b is installed" \
    || no "no /usr/bin/$_b -- moarchy-qcom-modem is missing from the image"
done

# 5. And that something runs them. Same two-tree rule as qbootctl above.
for _u in rmtfs.service tqftpserv.service; do
  if [ -L "$R/usr/lib/systemd/system/multi-user.target.wants/$_u" ] ||
     [ -L "$R/etc/systemd/system/multi-user.target.wants/$_u" ]; then
    ok "$_u is enabled"
  else
    no "$_u is not enabled in either tree -- installed and never started"
  fi
done

# 6. The condition rmtfs.service will be judged by at boot. The kernel names
# the node after the device tree's qcom,client-id, and sdm670-google-common.dtsi
# says 1 -- so a unit asking for mem0 would be enabled, correct-looking, and
# skipped at every boot with nothing but a "condition failed" in the journal.
if grep -q '^ConditionPathExists=/dev/qcom_rmtfs_mem1' \
     "$R/usr/lib/systemd/system/rmtfs.service" 2>/dev/null; then
  ok "rmtfs.service waits on /dev/qcom_rmtfs_mem1 (DT client-id 1)"
else
  no "rmtfs.service's ConditionPathExists is not /dev/qcom_rmtfs_mem1 -- it would never start"
fi

# 7. Bluetooth is a different radio and shares none of the above: WCN3990's BT
# is a UART controller on &uart6 driven by hci_qca, wanting only these two.
# Cheap to check and it costs a rebuild to discover on the device.
for _f in crbtfw21.tlv crnv21.bin; do
  [ -s "$R/usr/lib/firmware/qca/$_f" ] && ok "Bluetooth firmware $_f present" \
    || no "no qca/$_f -- hci_qca has no patch/NVM to download"
done

# 8. And the address, without which all of the above is true and bluez still
# lists no adapter at all (D28).
[ -x "$R/usr/bin/bootmac" ] && ok "bootmac is installed" \
  || no "no /usr/bin/bootmac -- hci0 comes up unconfigured and bluez shows nothing"
[ -s "$R/usr/lib/udev/rules.d/90-bootmac-bluetooth.rules" ] \
  && ok "bootmac's Bluetooth rule is installed" \
  || no "no 90-bootmac-bluetooth.rules -- nothing sets the BD address"

sec "the audio chain (D29, D32)"
# The same shape as the Wi-Fi chain above and for the same reason: every link
# fails quietly, and the symptom of the first one is four errors downstream.
#
# 1. The calibration blob. qcom-q6core will not probe without it, q6afe sits on
# q6core, and the end of that is /proc/asound/cards reading "no soundcards".
[ -s "$R/usr/lib/firmware/qcom/sdm670/sargo/Global_cal.acdb" ] \
  && ok "Global_cal.acdb present (q6core probes, so there is a sound card)" \
  || no "no Global_cal.acdb -- qcom-q6core will not probe and the phone is silent"

# 2. The use-case profile. Without it the card exists and PipeWire shows no
# sink and no source, because WirePlumber will not expose a card it cannot
# route. The conf.d name has to be the card's name exactly.
[ -s "$R/usr/share/alsa/ucm2/Google/sargo/sargo.conf" ] \
  && ok "the sargo ALSA use-case profile is installed" \
  || no "no ucm2/Google/sargo/sargo.conf -- the card would expose no sink or source"
if [ -e "$R/usr/share/alsa/ucm2/conf.d/sdm660/Google Pixel 3a.conf" ]; then
  ok "ALSA can find it by card name (conf.d/sdm660)"
else
  no "no conf.d/sdm660/'Google Pixel 3a'.conf -- the profile exists and nothing looks it up"
fi

# 2b. Loudness. Every one of these is a file that exists or does not, and the
# failure of each is the same symptom -- a phone at full volume that nobody can
# hear (D34). None of it is inferable from the profile being present.
if grep -q "BOOST Enable Switch" "$R/usr/share/alsa/ucm2/Google/sargo/VoiceCall.conf" 2>/dev/null; then
  ok "the Speakers verb enables both CS35L36 boost converters"
else
  no "VoiceCall.conf has no BOOST cset -- the amps run off VBAT, not the 10 V rail (D34)"
fi

# The graph and the unit that runs it are shipped by two different packages, so
# check them apart: either one alone is silent in a way the other explains.
[ -s "$R/usr/share/pipewire/filter-chain.conf.d/99-moarchy-loudness.conf" ] \
  && ok "the speaker loudness filter graph is installed" \
  || no "no filter-chain.conf.d/99-moarchy-loudness.conf -- nothing to compress (D34)"

[ -s "$R/usr/lib/systemd/user/moarchy-loudness.service" ] \
  && ok "moarchy-loudness.service is installed" \
  || no "no moarchy-loudness.service -- the graph would ship and never run (D34)"

if [ -L "$R/usr/lib/systemd/user/pipewire.service.wants/moarchy-loudness.service" ]; then
  ok "moarchy-loudness.service is enabled"
else
  no "moarchy-loudness.service is not enabled -- installed, correct, and never started (D34)"
fi

# The graph names two LADSPA plugins by absolute path. A missing swh-plugins is
# a filter-chain that fails to build its nodes at startup, which is a line in a
# user journal and silence everywhere else.
for _p in sc4_1882 fast_lookahead_limiter_1913; do
  [ -s "$R/usr/lib/ladspa/$_p.so" ] \
    && ok "LADSPA $_p is present" \
    || no "no /usr/lib/ladspa/$_p.so -- the loudness graph cannot load (D34)"
done

# 3. Call audio specifically. A call is not carried by the modem alone: q6voiced
# holds VoiceMMode1 open for its duration, and without it a dial is torn down
# the moment it is made -- which looks like a network problem and is not.
[ -x "$R/usr/bin/q6voiced" ] && ok "q6voiced is installed" \
  || no "no /usr/bin/q6voiced -- calls terminate the moment they are dialled (D32)"
_u=q6voiced.service
if [ -L "$R/usr/lib/systemd/system/multi-user.target.wants/$_u" ] ||
   [ -L "$R/etc/systemd/system/multi-user.target.wants/$_u" ]; then
  ok "$_u is enabled"
else
  no "$_u is not enabled in either tree -- installed and never started"
fi

# 4. And the numbers it needs. Its unit ConditionPathExists on this file, so a
# missing one is not an error anywhere: the unit is simply skipped, for ever.
sec "the camera's colour (D30)"
# Two halves, each useless alone. The profile without a patched megapixels is
# never read; the patched megapixels without a profile falls back to identity
# colour matrices, which is the green preview this pair exists to fix.
for _c in Rear Front; do
  if [ -s "$R/usr/share/megapixels/config/google,b4s4-sdm670,$_c.dcp" ]; then
    ok "camera profile for $_c present"
  else
    no "no google,b4s4-sdm670,$_c.dcp -- that camera renders green"
  fi
done

# The patched lookup, asserted against the shipped binary rather than against
# the package version: Arch's 2.1.0 and ours are both "2.1.0", and the only
# difference that matters is this string.
#
# `grep -a` on the binary, NOT `strings`: binutils is not in this container,
# and a missing `strings` makes every pattern fail -- which reads as "the bad
# string is absent" and passes the second check. That false pass was caught by
# the first check failing beside it, which is luck rather than design.
if [ -x "$R/usr/bin/megapixels" ]; then
  if grep -aq '/megapixels/config/%s,%s\.dcp' "$R/usr/bin/megapixels"; then
    ok "megapixels looks up profiles by <model>,<camera>.dcp"
  else
    no "megapixels is the unpatched build -- it cannot find a profile at all (D30)"
  fi
  if grep -aq '/megapixels/config/%s\.conf' "$R/usr/bin/megapixels"; then
    no "megapixels still has the .conf lookup that shadows libmegapixels' device config"
  else
    ok "the .conf lookup that breaks the camera is gone"
  fi
else
  no "no /usr/bin/megapixels in the image"
fi

if [ -s "$R/usr/share/q6voiced/q6voiced.conf" ]; then
  if grep -q '^q6voice_device=' "$R/usr/share/q6voiced/q6voiced.conf"; then
    ok "q6voiced.conf names a voice PCM ($(sed -n 's/^q6voice_device=/device /p' "$R/usr/share/q6voiced/q6voiced.conf"))"
  else
    no "q6voiced.conf has no q6voice_device -- the unit would start with no PCM"
  fi
else
  no "no /usr/share/q6voiced/q6voiced.conf -- q6voiced's unit is condition-skipped silently"
fi
    ;;
esac
}

# The rootfs growing to fill its partition.
verify_grow() {
sec "behaviour: the rootfs grows to fill userdata"

# Half of I7 on this device, and the other half must NOT happen. The partition
# is `userdata`, sized by the vendor and sitting in a GPT beside xbl, abl, tz
# and the A/B slots, so only the filesystem grows -- never the partition.
# docs/devices.md D22.
#
# The first check is the one that matters: sfdisk running on this device would
# rewrite a vendor partition table on a phone with no removable storage and no
# recovery image.
grow=$(grep -h '^DEVICE_GROW=' "$R/usr/share/moarchy/device/device.conf" 2>/dev/null | cut -d= -f2)
[ "$grow" = filesystem ] \
  && ok "device.conf says DEVICE_GROW=filesystem (the vendor GPT is never rewritten)" \
  || no "DEVICE_GROW is '${grow:-unset}', not filesystem -- this device would run sfdisk on a vendor partition table"

# And the half that does happen, exercised ONLINE -- on the mounted filesystem,
# through the loop device backing it.
#
# That is not a workaround for the rootfs being mounted here; it is the more
# faithful test. moarchy-grow-rootfs runs from a systemd unit during boot and
# calls `resize2fs "$root_src"` against the device / is already mounted from,
# so an online grow is exactly what happens on the phone. The first version of
# this check ran resize2fs against $WORK/root.img while verify.sh had it
# mounted, which simply fails.
#
# losetup -c is the part that is easy to miss: truncating the backing file does
# not change the size the loop device reports, so resize2fs would find no new
# room and report success having done nothing.
loop=$(findmnt -no SOURCE "$R" 2>/dev/null)
case "$loop" in
  /dev/loop*)
    before=$(dumpe2fs -h "$loop" 2>/dev/null | awk -F: '/Block count/{gsub(/ /,"",$2); print $2}')
    truncate -s +64M "$WORK/root.img"
    losetup -c "$loop" 2>/dev/null
    if resize2fs "$loop" >/dev/null 2>&1; then
      after=$(dumpe2fs -h "$loop" 2>/dev/null | awk -F: '/Block count/{gsub(/ /,"",$2); print $2}')
      if [ -n "${before:-}" ] && [ -n "${after:-}" ] && [ "$after" -gt "$before" ]; then
        ok "resize2fs grew the mounted rootfs $(( before * 4096 / 1048576 ))M -> $(( after * 4096 / 1048576 ))M"
      else
        no "resize2fs did not grow the filesystem (${before:-?} -> ${after:-?} blocks)"
      fi
    else
      no "resize2fs failed on $loop -- the growth half of I7 is NOT tested"
    fi ;;
  *)
    # No loop device. That is expected under rootless podman, where the rootfs
    # is mounted through fuse2fs -- and it means the ONLINE grow above cannot
    # be run, because there is no block device for resize2fs to act on.
    #
    # Rather than skip the half of I7 that reclaims 100 GB of this phone, do
    # the OFFLINE equivalent on a COPY: grow the backing file and resize the
    # unmounted filesystem in it. That still proves this filesystem can be
    # grown -- the geometry, the feature flags and resize2fs's willingness are
    # all the same. What it does not prove is the online path, which is the one
    # moarchy-grow-rootfs actually takes on the phone.
    #
    # Said out loud, because "grew" and "grew while mounted" are not the same
    # claim and a run that made the weaker one silently would be the worst
    # outcome here.
    if [ "${ROOT_MOUNT_KIND:-}" = fuse ]; then
      note "no loop device (fuse2fs mount) -- testing the OFFLINE grow instead"
      cp "$WORK/root.img" "$WORK/grow.img"
      # fuse2fs does not replay or clear the journal, so the copy looks
      # unclean and resize2fs refuses it with "Please run e2fsck -f first".
      # -f forces, -y answers; both are safe on a throwaway copy and neither
      # touches the image that gets flashed.
      e2fsck -fy "$WORK/grow.img" >/dev/null 2>&1 || true
      before=$(dumpe2fs -h "$WORK/grow.img" 2>/dev/null | awk -F: '/Block count/{gsub(/ /,"",$2); print $2}')
      # The block size is READ, not assumed to be 4096. mke2fs picks it from
      # the filesystem's size -- 1024 for a small one -- so a hardcoded 4096
      # reports a 32M image as 128M, which was measured on a test image before
      # this line said so. The rootfs this normally runs against is large
      # enough to get 4096 either way; the point is that the number printed is
      # the filesystem's rather than this script's guess about it.
      bs=$(dumpe2fs -h "$WORK/grow.img" 2>/dev/null | awk -F: '/Block size/{gsub(/ /,"",$2); print $2}')
      bs=${bs:-4096}
      truncate -s +64M "$WORK/grow.img"
      if resize2fs "$WORK/grow.img" >/dev/null 2>&1; then
        after=$(dumpe2fs -h "$WORK/grow.img" 2>/dev/null | awk -F: '/Block count/{gsub(/ /,"",$2); print $2}')
        if [ -n "${before:-}" ] && [ -n "${after:-}" ] && [ "$after" -gt "$before" ]; then
          ok "resize2fs grew the rootfs offline $(( before * bs / 1048576 ))M -> $(( after * bs / 1048576 ))M"
          note "the ONLINE grow -- what the phone actually does -- was not exercised"
        else
          no "resize2fs did not grow the filesystem (${before:-?} -> ${after:-?} blocks)"
        fi
      else
        no "resize2fs failed on $WORK/grow.img -- the growth half of I7 is NOT tested"
      fi
      rm -f "$WORK/grow.img"
    else
      # Never silently skip: this is the half that reclaims 50 GB of a phone.
      no "rootfs is not on a loop device (got '${loop:-none}') -- growth NOT tested"
    fi ;;
esac
}
