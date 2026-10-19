#!/bin/bash
# Bring up a USB gadget with a serial console on it, so a phone that boots
# badly can still be read from the other end of the cable.
#
# --- Why this exists --------------------------------------------------------
#
# This device has no console anyone can reach. The bootloader appends
# `console=null` and strips whatever the boot image asked for (devices.md D23,
# D25, measured on sargo), and the only real UART is three test points inside
# the case -- TP1102, TP1104 and TP4810 on the Fairphone 4, per Fairphone's own
# repair documentation. So a phone that mounts root and then fails has, by
# default, no way to say why: no console, no log, and a screen that may never
# light up.
#
# The image's other answer is a debug build -- preseeded wifi plus an
# authorised ssh key. That is the right tool when the phone works. It is the
# wrong one here, twice over: it needs the phone to reach the network, which is
# most of what might be broken, and on THIS handset Wi-Fi is upstream-unstable
# even when everything else is right (pmaports#2841).
#
# A USB gadget needs none of that. The cable is already attached -- it is how
# the thing was flashed -- and the kernel drives the controller directly.
#
# --- What it makes ----------------------------------------------------------
#
#   acm.usb0   a serial port. On the host this is /dev/ttyACM0, and a getty
#              runs on the phone's end, so `screen /dev/ttyACM0` is a shell.
#              This is the one that matters: it needs no addresses, no DHCP
#              and no keys.
#   ncm.usb0   a network interface, for scp'ing something large off or for
#              ssh once there is a key. Configured but not depended on.
#
# --- Why it is safe to run unconditionally ----------------------------------
#
# It cannot affect flashing: fastboot is the bootloader, and nothing here runs
# until systemd does. Every step tolerates failure and the unit is a oneshot
# that is allowed to fail, so a phone that cannot build a gadget boots exactly
# as it would have.
#
# It grants no access the device does not already give: the account's password
# is locked and tty1 autologins, so anyone holding the phone has a shell
# already. This adds the same shell over a cable they would also be holding.
#
# --- Scope ------------------------------------------------------------------
#
# Shipped by moarchy-device-fp4 rather than by the common layer, deliberately:
# it is wanted on a handset that has never booted, and the Pixel -- which has,
# and is shipping -- should not gain a new boot-time service for it. If this
# proves itself here, promoting it is a move, not a rewrite.
set -u

G=/sys/kernel/config/usb_gadget/moarchy

say() { printf 'moarchy-usb-debug: %s\n' "$*"; }

# configfs is where a composite gadget is described. USB_CONFIGFS is a module
# in this kernel, so libcomposite has to be asked for by name -- nothing
# autoloads it, because nothing else references it.
modprobe libcomposite 2>/dev/null || { say "no libcomposite; nothing to do"; exit 0; }

if [ ! -d /sys/kernel/config/usb_gadget ]; then
  mountpoint -q /sys/kernel/config || mount -t configfs none /sys/kernel/config 2>/dev/null
fi
[ -d /sys/kernel/config/usb_gadget ] || { say "configfs has no usb_gadget; giving up"; exit 0; }

# A UDC is the USB device controller the gadget binds to. Without one the
# phone is not in peripheral mode -- cable out, or the port is in host mode --
# and there is nothing to attach to.
udc=$(ls /sys/class/udc 2>/dev/null | head -1)
[ -n "$udc" ] || { say "no UDC (cable out, or not in peripheral mode)"; exit 0; }

# Already built and bound: leave it alone. This runs again on resume and on a
# manual restart, and tearing down a working console to rebuild it is how you
# lose the log you were reading.
# Test the CONTENT, not the size. configfs's UDC file is a newline when the
# gadget is unbound, so `[ -s ]` is true either way -- and the script would
# then report "gadget already bound to " (to nothing) and exit, refusing to
# repair exactly the half-built gadget it exists to repair. Measured on an FP4
# 2026-09-22, where a previous run had created the gadget but failed to bind.
_bound=$(cat "$G/UDC" 2>/dev/null | tr -d '[:space:]')
if [ -n "${_bound:-}" ]; then
  say "gadget already bound to $_bound"
  exit 0
fi

mkdir -p "$G" || { say "cannot create the gadget"; exit 0; }
cd "$G" || exit 0

# 1d6b:0104 is the Linux Foundation's "Multifunction Composite Gadget", which
# is what this is. Using it rather than inventing ids means the host's generic
# drivers bind without a udev rule.
echo 0x1d6b > idVendor  2>/dev/null
echo 0x0104 > idProduct 2>/dev/null
echo 0x0200 > bcdUSB    2>/dev/null

mkdir -p strings/0x409
echo "moarchy"        > strings/0x409/manufacturer 2>/dev/null
echo "moarchy debug"  > strings/0x409/product      2>/dev/null
# A serial number the host can tell two phones apart by, when there are two.
echo "$(cat /etc/machine-id 2>/dev/null | cut -c1-16)" > strings/0x409/serialnumber 2>/dev/null

mkdir -p configs/c.1/strings/0x409
echo "debug" > configs/c.1/strings/0x409/configuration 2>/dev/null
echo 250     > configs/c.1/MaxPower                    2>/dev/null

# The serial port first, because it is the one worth having.
# The symlink target must be ABSOLUTE. configfs resolves it with kern_path(),
# which is relative to this process's CWD -- not, as every other symlink in
# Unix, to the directory the link is created in. `cd "$G"` above therefore
# makes "../../functions/acm.usb0" resolve to /sys/kernel/functions/acm.usb0,
# which does not exist, and the link silently fails. A config with no functions
# in it then fails to bind with -EINVAL, and the only symptom is
#
#   udc a600000.usb: failed to start moarchy: -22
#
# which names neither the config nor the missing function. Measured on an FP4
# 2026-09-22; this cost a boot's worth of debugging to find.
if mkdir -p functions/acm.usb0 2>/dev/null; then
  if err=$(ln -sf "$G/functions/acm.usb0" "$G/configs/c.1/acm.usb0" 2>&1); then
    say "acm.usb0 -> /dev/ttyGS0"
  else
    say "could not add acm.usb0 to the config: $err"
  fi
fi

# NCM rather than RNDIS: Linux and macOS hosts bind NCM without help, and the
# host that flashed this phone is the one that will debug it. Addresses are
# fixed rather than served, because a DHCP client is one more thing that can
# be the reason nothing works.
if mkdir -p functions/ncm.usb0 2>/dev/null; then
  echo "02:42:ac:10:2a:01" > functions/ncm.usb0/host_addr 2>/dev/null
  echo "02:42:ac:10:2a:02" > functions/ncm.usb0/dev_addr  2>/dev/null
  if err=$(ln -sf "$G/functions/ncm.usb0" "$G/configs/c.1/ncm.usb0" 2>&1); then
    say "ncm.usb0 -> usb0"
  else
    say "could not add ncm.usb0 to the config: $err"
  fi
fi

# Bind. This is the moment the host sees a new device.
if err=$(echo "$udc" > UDC 2>&1); then
  say "bound to $udc"
else
  # -EINVAL here almost always means the config has no functions linked into
  # it; the messages above say whether the links were made.
  say "could not bind to $udc: ${err:-unknown error}"
  say "functions in configs/c.1: $(ls "$G/configs/c.1" 2>/dev/null | tr '\n' ' ')"
  exit 0
fi

# The phone's end of the network link. 172.16.42.0/24 is what postmarketOS
# uses for exactly this, so a host that already knows that convention needs no
# telling.
for _ in 1 2 3 4 5; do
  if ip link show usb0 >/dev/null 2>&1; then
    ip addr add 172.16.42.1/24 dev usb0 2>/dev/null
    ip link set usb0 up 2>/dev/null
    say "usb0 is 172.16.42.1/24"
    break
  fi
  sleep 1
done

# --- the getty ---------------------------------------------------------------
#
# The account's password is LOCKED (that is the image's design -- README says
# so), which means a login prompt on this port would be unusable: there is no
# password to type. So the serial getty has to autologin, exactly as tty1 does.
#
# Who to log in as is read from the tty1 drop-in that image/configure.sh
# already wrote, rather than hardcoded here. That file is the one place the
# image records the account's name, and copying from it means this cannot
# disagree with the console the phone shows on its own screen.
_u=$(sed -n 's/.*--autologin \([a-z_][a-z0-9_-]*\).*/\1/p' \
       /etc/systemd/system/getty@tty1.service.d/autologin.conf 2>/dev/null | head -1)
if [ -n "${_u:-}" ] && [ -e /dev/ttyGS0 ]; then
  d=/run/systemd/system/serial-getty@ttyGS0.service.d
  mkdir -p "$d"
  cat > "$d/autologin.conf" <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\\\u' --noclear --autologin $_u %I \$TERM
EOF
  systemctl daemon-reload 2>/dev/null
  systemctl start serial-getty@ttyGS0.service 2>/dev/null &&
    say "shell on /dev/ttyGS0 as $_u (host: screen /dev/ttyACM0 115200)"
else
  say "no tty1 autologin to copy, or no /dev/ttyGS0 -- serial shell not started"
fi

exit 0
