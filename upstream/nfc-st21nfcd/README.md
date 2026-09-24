# ST21NFCD NFC driver — upstream RFC series

A Linux kernel driver for the ST21NFCD NFC controller, and the Fairphone 4
device-tree node that uses it. Prepared for submission; **not sent.**

## Status

Works on the handset. The controller completes NCI 2.0 init, RF discovery
runs, and a MIFARE Classic 4K card is detected and reported to userspace
(SENS_RES `0002`, SEL_RES `18`, UID). Detection is what the `moarchy.nfc` app
and `moarchy-nfc` helper use.

Passes `checkpatch.pl --strict` (only the generic "new file, does MAINTAINERS
need updating?" note, which is addressed — the driver adds its own entry),
`make W=1` clean on the driver, `dt_binding_check`, and `dtbs_check` on the
board.

## Why RFC

Two values in the driver were reverse-engineered from one Fairphone 4, not
read from a datasheet (ST publishes none for this part). They are commented as
observed rather than documented, and the cover letter flags them for review:

- `0x7e` — the byte returned on an I2C read when the controller is idle.
- `0x90` — the proprietary RF protocol number reported for MIFARE Classic,
  which the NCI core drops as unmappable without the `get_rfprotocol` hook.

Not yet exercised: card emulation, tag types beyond ISO 14443-A, suspend/
resume. The RFC asks reviewers what they would want covered before a non-RFC
posting.

## The series

| patch | subsystem | goes to |
| --- | --- | --- |
| 0001 binding | dt-bindings/net/nfc | NFC subsystem |
| 0002 driver + MAINTAINERS | drivers/nfc | NFC subsystem |
| 0003 FP4 device tree | arch/arm64 qcom | qcom/arm-soc, after the binding settles |

Patches 1–2 are the generic contribution and stand alone. Patch 3 depends on
the driver's `compatible` and is included for context; on the FP4 it would
also follow the mic (sm6350-mainline#11) and amp (#12) work, which is where
this device's other DT changes have gone.

## Recipients

From `scripts/get_maintainer.pl` on the driver patch:

- David Heidelberg <david@ixit.cz> — NFC subsystem maintainer
- oe-linux-nfc@lists.linux.dev — NFC list
- linux-kernel@vger.kernel.org

The DT patch (0003) additionally wants the qcom and devicetree lists; run
`get_maintainer.pl` on it at send time.

## To send (not done here)

```
git config sendemail.to "David Heidelberg <david@ixit.cz>"
git send-email --to=oe-linux-nfc@lists.linux.dev \
  --cc=linux-kernel@vger.kernel.org 00*.patch
```

Do a `--dry-run` first, and post from the personal identity
(`tadl-git@taufderl.de`), which is the Signed-off-by and MAINTAINERS entry.

## Where the code lives

The commits are on branch `fp4-nfc` in the sm6350 kernel tree used for FP4
work (not in this repo — only these generated patches and this note travel
here). The driver is board-agnostic; only patch 3 mentions the FP4.
