# ST21NFCD NFC: superseded by the mainline st-nci series

**Status (2026-09-28): SUPERSEDED. Do not submit this.** The standalone driver
here duplicated in-flight mainline work and used the wrong shape. FP4 NFC now
converges on Kristian Brox's series, which extends the existing `st-nci` driver
rather than adding a new one:

> nfc: st-nci: Fairphone 5 NFC bring-up (ST21NFCD)
> https://lore.kernel.org/linux-arm-msm/20260902-fp5-st21nfcd-v4-v4-0-ded2f1c501be@proton.me/

sm6350-mainline PR #13 (this driver) was closed in favour of it.

## Why superseded

ST21NFCD is the same controller on the FP4 and the FP5. The earlier claim that
"no mainline driver spoke this protocol" was only true of *merged* mainline: a
series adding exactly it was already in review (v4 by 2026-09-02, with Luca
Weiss involved). It does the maintainer-preferred thing this staging did not:
it adds a raw-NCI path and a `st,st21nfcd` compatible to the existing
`drivers/nfc/st-nci/` driver, instead of a parallel `drivers/nfc/st21nfcd.c`.

That series also covers, more cleanly, both values this driver had
reverse-engineered:

- `0x90` (our MIFARE proprietary-protocol / `get_rfprotocol` remap): obviated.
  The st-nci series consumes the proprietary RF NTF `0xf02` (GID 0xf, OID 0x02)
  and lets the standard `RF_INTF_ACTIVATED_NTF` report the tag. Luca contributed
  that handling to v4.
- `0x7e` (our "idle read" byte): an artifact of this driver's read path. The
  st-nci path reads only on IRQ, so an idle read does not arise and there is
  nothing to detect.

So there is no review input to add to the st-nci series from here.

## What still needs doing for the FP4

Only the FP4 device-tree node, and only once `st,st21nfcd` lands upstream. It
must follow the st-nci binding's shape (interrupts-extended, pinctrl,
`vdd-io-supply`/clocks, `ese-present`/`uicc-present`), not the simpler `nfc@8`
node that was in patch 0003 here. Track the series above; when its binding
merges, add the sm7225 node the same way the mic (sm6350-mainline#11) and amp
(#12) DT work went.

## Historical record

The original standalone series (kept for reference only, not for submission)
was three patches: a new `st,st21nfcd` binding, a new `drivers/nfc/st21nfcd.c`
plain-NCI driver, and the FP4 `nfc@8` node. It worked on the handset (NCI 2.0
init, RF discovery, MIFARE Classic 4K detected: SENS_RES 0002, SEL_RES 18, UID)
and passed `checkpatch.pl --strict`, `make W=1`, `dt_binding_check` and
`dtbs_check`. It is superseded by the st-nci approach above.
