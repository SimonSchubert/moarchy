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
# docs/fp4-fixes.md D13. When that is solved, delete this.
#
#   fp4-audio-route            assert once and exit
#   fp4-audio-route --watch    assert, then keep re-asserting (the service)
set -u

CARD=0

ROUTES=(
    # Codec-side capture routing: AMIC1 -> ADC1 -> SoundWire TX -> decimators.
    # This is the UCM Mic EnableSequence, and it has to live here too because
    # that sequence never runs on this card (ACP offers no UCM profile, see the
    # header). Both decimators take ADC0 (= the codec's ADC1 = AMIC1) because
    # the backend is forced to two channels; ADC1_MIXER Switch is what puts the
    # ADC on the SoundWire TX port -- without it, on a clean mixer state, every
    # capture fails with EIO. Enum values are item indices (SWR_MIC = 1,
    # ADC0 = 1) so the comparison in assert_routes() matches what cget prints.
    # Gains are the calibrated ones from ucm-HiFi.conf.
    #
    # Until 2026-10-08 nothing in the image set these at all; development
    # phones only worked because alsa-restore replayed mixer state saved from
    # manual test sessions (docs/fp4-fixes.md D32).
    "TX DEC0 MUX|1"                           # SWR_MIC
    "TX DEC1 MUX|1"                           # SWR_MIC
    "TX SMIC MUX0|1"                          # ADC0
    "TX SMIC MUX1|1"                          # ADC0
    "TX_AIF1_CAP Mixer DEC0|1"
    "TX_AIF1_CAP Mixer DEC1|1"
    "ADC1_MIXER Switch|1"
    "ADC1 Volume|20"
    "TX_DEC0 Volume|88"
    "TX_DEC1 Volume|88"

    "MultiMedia2 Mixer TX_CODEC_DMA_TX_3|1"   # capture:  mic -> MultiMedia2
    "QUIN_MI2S_RX Audio Mixer MultiMedia1|1"  # playback: MultiMedia1 -> amps
    "ADC1 Switch|1"                           # the codec's AMIC1 input
)

# Call audio, kept OUT of ROUTES on purpose. These controls belong to the
# DSP's voice services, which register separately from the media ones and can
# be later or absent (seen 2026-10-08: after an ADSP restart the media
# controls returned but these five did not). While they were in ROUTES, one
# missing voice control made assert_routes() report "card not up", so the mic
# and speaker routes were not armed for 30 s -- long enough for WirePlumber to
# fail its node creation for the whole session. Now they are armed best-effort:
# a missing one is skipped and retried on every later event.
VOICE_ROUTES=(
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

# set_route NAME|VALUE -- arm one route; returns 1 if the control is absent.
set_route() {
    local name=${1%|*} want=${1#*|} cur
    cur=$(get "$name")
    [ -z "$cur" ] && return 1
    case "$cur" in
        on|"$want") ;;
        *) amixer -c "$CARD" cset name="$name" "$want" >/dev/null 2>&1 ;;
    esac
}

# Media routes gate ("card not up yet" until every one of them is readable);
# voice routes are best-effort and never hold the media path back.
assert_routes() {
    local r ok=0
    for r in "${ROUTES[@]}"; do set_route "$r" || ok=1; done
    for r in "${VOICE_ROUTES[@]}"; do set_route "$r" || true; done
    return $ok
}

# Wait for the card, then arm the routes.
deadline=$((SECONDS + 30))
until assert_routes; do
    [ "$SECONDS" -ge "$deadline" ] && { echo "sound card did not appear" >&2; exit 0; }
    sleep 1
done

if [ "${1:-}" != "--watch" ]; then
    for r in "${ROUTES[@]}" "${VOICE_ROUTES[@]}"; do printf '%s = %s\n' "${r%|*}" "$(get "${r%|*}")"; done
    exit 0
fi

# WirePlumber never retries a node it failed to create. If it got to the card
# before the routes above were armed (a slow boot, 2026-10-08: "Failed to
# create ALSA node ... Object activation aborted"), the card has no sink and no
# source for the whole session. The routes are armed now, so one WirePlumber
# restart creates the nodes. Once per session only: this unit is PartOf
# wireplumber, so that restart restarts this script as well, and the marker in
# the (per-boot) runtime dir stops it from doing it again.
mark="${XDG_RUNTIME_DIR:-/tmp}/fp4-audio-route.wp-restarted"
sleep 3   # let WirePlumber finish creating nodes on a normal boot first
if ! pactl list short sources 2>/dev/null | grep -q 'alsa_input\.platform-sound' \
   && [ ! -e "$mark" ]; then
    : > "$mark"
    echo "card has no PipeWire nodes; restarting wireplumber once" >&2
    systemctl --user restart wireplumber
    exit 0
fi

# Re-arm after every stream teardown. pactl subscribe emits a line per event;
# filtering is deliberately loose because re-asserting is idempotent and
# cheap, and missing an event costs a silent recording.
pactl subscribe 2>/dev/null | while read -r _; do
    assert_routes
done
