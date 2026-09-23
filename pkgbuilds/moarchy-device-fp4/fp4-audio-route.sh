#!/bin/bash
# Keep the Fairphone 4's capture and playback routes connected.
#
# WHY THIS EXISTS
#
# The capture path is a DPCM front-end/back-end link, and the mixer that
# carries it -- "MultiMedia2 Mixer TX_CODEC_DMA_TX_3" -- is cleared when a
# capture stream *ends*. Measured on hardware 2026-09-23:
#
#   * asserted and left completely idle, it stays on indefinitely (60s+);
#   * run one capture and it is off again the moment that capture finishes;
#   * with the route off when a stream starts, the stream opens, reports
#     RUNNING, and delivers zero frames -- no error to the client.
#
# That last point is why this cannot be fixed by reacting to a stream
# starting: by then it is already too late. The route has to be up *before*
# the device is opened. So this asserts it once and then re-asserts after
# every stream teardown, leaving it armed for whatever opens the microphone
# next.
#
# Upstream this belongs in the UCM profile's EnableSequence, which ALSA runs
# on device open. That needs PipeWire's ACP layer to offer this card a
# profile, and it offers only "off" and "pro-audio" -- see
# docs/fp4-defects.md D13. When that is solved, delete this.
#
#   fp4-audio-route            assert once and exit
#   fp4-audio-route --watch    assert, then keep re-asserting (the service)
set -u

CARD=0

ROUTES=(
    "MultiMedia2 Mixer TX_CODEC_DMA_TX_3|1"   # capture:  mic -> MultiMedia2
    "QUIN_MI2S_RX Audio Mixer MultiMedia1|1"  # playback: MultiMedia1 -> amps
    "ADC1 Switch|1"                           # the codec's AMIC1 input

    # Call audio. These connect the DSP's voice session to the same backends
    # the media path uses: the microphone on TX_CODEC_DMA_TX_3 for uplink, the
    # amplifiers on QUIN_MI2S_RX for downlink.
    #
    # They have to be up BEFORE a call arrives, not after. q6voiced opens the
    # voice PCM the moment ModemManager reports an active call, and a DPCM
    # front end with no routed back end fails at open() with -EINVAL -- which
    # presents as a call that connects with no audio in either direction,
    # because the session never starts at all.
    "VoiceMMode1 Capture Mixer TX_CODEC_DMA_TX_3|1"
    "QUIN_MI2S_RX Voice Mixer VoiceMMode1|1"
    "CS-Voice Capture Mixer TX_CODEC_DMA_TX_3|1"
    "QUIN_MI2S_RX Voice Mixer CS-Voice|1"

    # Uplink vocproc topology. The driver defaults TX to SM_ECNS (0x10F71),
    # single-mic echo cancellation and noise suppression, which is driven by
    # ACDB calibration data this device does not have -- `find /usr/lib/firmware
    # -iname '*acdb*'` returns nothing. 0x10F70 is TOPOLOGY_ID_NONE, no
    # processing and no calibration needed.
    #
    # Not a local workaround: sc7280-mainline/linux 8bdb8de44a makes exactly
    # this the driver default for the Fairphone 5, with the commit message
    # "only this topology seems to work so far for the mic". Once that default
    # is carried here, this line can go.
    "VoiceMMode1 TX Topology|69488"
)

get() { amixer -c "$CARD" cget name="$1" 2>/dev/null | sed -n 's/^  : values=//p' | head -1; }

assert_routes() {
    local r name want cur
    for r in "${ROUTES[@]}"; do
        name=${r%|*}; want=${r#*|}
        cur=$(get "$name")
        [ -z "$cur" ] && return 1                    # card not up yet
        case "$cur" in
            on|"$want") ;;
            *) amixer -c "$CARD" cset name="$name" "$want" >/dev/null 2>&1 ;;
        esac
    done
    return 0
}

# Wait for the card, then arm the routes.
deadline=$((SECONDS + 30))
until assert_routes; do
    [ "$SECONDS" -ge "$deadline" ] && { echo "sound card did not appear" >&2; exit 0; }
    sleep 1
done

if [ "${1:-}" != "--watch" ]; then
    for r in "${ROUTES[@]}"; do printf '%s = %s\n' "${r%|*}" "$(get "${r%|*}")"; done
    exit 0
fi

# Re-arm after every stream teardown. pactl subscribe emits a line per event;
# filtering is deliberately loose because re-asserting is idempotent and
# cheap, and missing an event costs a silent recording.
pactl subscribe 2>/dev/null | while read -r _; do
    assert_routes
done
