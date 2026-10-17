#!/bin/sh
# Make the modem's GNSS engine emit standard NMEA ($GPGGA, $GPRMC, $GPGSV,
# $GPGSA, $GPVTG), which is what ModemManager hands to geoclue (D8).
#
# ModemManager does this itself when location is enabled: QMI-LOC "Get NMEA
# Types", and if the mask is not what it wants, "Set NMEA Types". On this
# modem the Set's indication never reaches it ("couldn't setup required NMEA
# traces: Operation timed out", 2026-10-16), so the mask stays `none` and only
# Qualcomm's proprietary $PQ... sentences flow -- receiver running, nothing an
# application can read. The same Set from qmicli succeeds and reads back, and
# once the mask is right MM's Get sees it and skips the Set. So this sets it,
# once per boot, before anything asks for a position.
#
# Idempotent: does nothing when the mask already has GGA. Never fatal: a phone
# with no GPS still boots and calls.
types='gga|rmc|gsv|gsa|vtg'

i=0
while [ $i -lt 30 ]; do
  cur=$(qmicli -d qrtr://0 --loc-get-nmea-types 2>/dev/null) && break
  i=$((i + 1))
  sleep 2
done
if [ -z "$cur" ]; then
  echo "QMI-LOC not reachable after 60 s; leaving NMEA types alone"
  exit 0
fi

case "$cur" in
  *gga*) echo "NMEA types already set: ${cur##*: }"; exit 0 ;;
esac

if qmicli -d qrtr://0 --loc-set-nmea-types="$types" >/dev/null 2>&1; then
  echo "NMEA types were '${cur##*: }', set to $types"
else
  echo "setting NMEA types failed (were '${cur##*: }')"
fi
exit 0
