# jbl780nc-re

Unofficial, independent research into how the JBL Headphones app talks to the **JBL Tune 780NC** over Bluetooth Low Energy, with the aim of a macOS menu bar alternative.
Not affiliated with or endorsed by JBL or Harman. Use at your own risk; you are responsible for your own device.

## What is here
- `notes/protocol.md`: the protocol spec (framing, tags, value encodings, what is off limits). Every claim carries a confidence level (observed in capture, seen in code, or both).
- `notes/stage*-findings.md`, `notes/recon.md`, `notes/capture-script.md`: working notes per stage.
- `proto/jbl_proto.py`: encoder/parser. It only builds and parses bytes. It refuses factory reset, firmware update and any tag not verified as writable.
- `proto/tests/test_replay.py`: replays a real capture byte for byte.
- `mac/`: small `bleak` scripts used on a Mac (scan, read-only probes, single-setting writes).
- `analysis/`: helper scripts for turning a Bluetooth HCI capture into a table.
- `Dockerfile`, `docker-compose.yml`: tooling container (jadx, apktool, tshark, python).

## What is deliberately not here
- The app (APK) and anything decompiled from it.
- Raw captures and the full table derived from them: they contain device serials, addresses and phone identifiers.
- `proto/fixtures/gatt.public.tsv` is a redacted command-channel-only fixture (serial, address, clock-sync and host-name hash zeroed, timestamps replaced). It is built by `analysis/redact_fixture.py` from a private table, which you can produce for your own device with `analysis/dump_gatt.sh` and your own HCI snoop log. `proto/tests` use `gatt.tsv` if present, else the public fixture.

## Safety
Do not send firmware-update, factory-reset or unverified commands. The spec lists the off-limits tags. Every write in `mac/` replays a frame that was first seen in a real capture.

## Status
Stages 0 to 6 done (recon, capture, static cross-check, spec, offline validation, read-only Mac prototype, low-risk writes). Stage 7 (menu bar app) not started. No license has been chosen yet.
