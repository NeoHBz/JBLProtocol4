# jbl-protocol4

Unofficial, independent research into the "Protocol4" control protocol the JBL Headphones app uses over Bluetooth Low Energy for recent JBL headphones and earbuds, with the aim of a macOS menu bar alternative. Reverse engineered and tested on the **JBL Tune 780NC**; see [Device family](#device-family) for the other models that share it.
Not affiliated with or endorsed by JBL or Harman. JBL and Harman are trademarks of their respective owners. This is independent interoperability research on the author's own device, and it comes with no warranty: use at your own risk, you are responsible for your own device.

## Device family
The 780NC speaks the protocol the JBL app calls "Protocol4". According to the app's bundled product list, about 34 recent JBL models use the same protocol, on Bestechnic and Realtek chips alike. **Only the Tune 780NC has been tested.** Each model supports its own subset of settings, so other models need checking before use. Full table with controller classes and product IDs: `notes/protocol.md` section 11.

| Group | Models |
|---|---|
| Same controller as the 780NC (closest) | Tune 680NC, **Tune 780NC** (tested), Tune 785NC |
| Live over-ear | Live 680NC, Live 780NC |
| Tune on-ear/over-ear (Realtek) | Tune 520BT2, 530BT, 535BT, 730BT, 735BT |
| Tour / Tune / Sense / Endurance | Tour One M3, Tune 135BT, Tune 235BT, Sense Lite, Endurance Zone |
| Live earbuds | Live Beam 4, Live Buds 4, Live Flex 4 |
| Tune earbuds | Tune Flex 3, Tune Buds 3, Tune Beam 3 |
| Vibe / Wave earbuds | Vibe Beam 3, Vibe Buds 3, Vibe Flex 3, Wave Beam 3, Wave Buds 3, Wave Flex 3 |
| Other | Endurance Pace, Endurance Peak 4, Endurance Run 3 Wireless, Junior Free, Sense Pro, Soundgear Clips, Smart Tx |

Older models (for example Tune 770NC, Live 770NC) use different protocols and are not covered.

## What is here
- `notes/protocol.md`: the protocol spec (framing, tags, value encodings, what is off limits). Every claim carries a confidence level (observed in capture, seen in code, or both).
- `notes/stage*-findings.md`, `notes/recon.md`, `notes/capture-script.md`: working notes per stage.
- `proto/jbl_proto.py`: encoder/parser. It only builds and parses bytes. `build_set` refuses factory reset, firmware update and any tag not verified as writable; `build_frame` refuses off-limits commands and off-limits tags in SET payloads.
- `proto/tests/test_replay.py`: replays a real capture byte for byte.
- `mac/`: small `bleak` scripts used on a Mac (scan, read-only probes, single-setting writes).
- `analysis/`: helper scripts for turning a Bluetooth HCI capture into a table.
- `Dockerfile`, `docker-compose.yml`: tooling container (jadx, apktool, tshark, python).

## What is deliberately not here
- The app (APK) and anything decompiled from it. Some notes cite paths such as `decompiled/...`, `captures/...`, `analysis/feature5_table.json` and a private brief: those files exist only on the author's machine.
- Raw captures and the full table derived from them: they contain device serials, addresses and phone identifiers.
- `proto/fixtures/gatt.public.tsv` is a redacted command-channel-only fixture (serial, address, clock-sync and host-name hash zeroed, timestamps replaced). It is built by `analysis/redact_fixture.py` from a private table, which you can produce for your own device with `analysis/dump_gatt.sh` and your own HCI snoop log. `proto/tests` use `gatt.tsv` if present, else the public fixture.

## Safety
Do not send firmware-update, factory-reset or unverified commands. The spec lists the off-limits tags. Every write in `mac/` replays a frame that was first seen in a real capture.

## Status
Stages 0 to 6 done (recon, capture, static cross-check, spec, offline validation, read-only Mac prototype, low-risk writes). Stage 7 (menu bar app) not started. Licensed under the MIT License (see `LICENSE`). Local, private values live in a gitignored `local.config.json` (template: `local.config.example.json`).
