# JBL Protocol4

A small macOS menu bar app for recent JBL headphones, plus the reverse-engineered spec of "Protocol4", the Bluetooth Low Energy control protocol the JBL Headphones app uses. Reverse engineered and tested on the **JBL Tune 780NC**; see [Device family](#device-family) for the other models that share it.

> [!IMPORTANT]
> **Unofficial.** JBL Protocol4 is an independent project. It is not made, affiliated with, authorized, sponsored or endorsed by JBL, Harman International Industries, Incorporated, or Samsung Electronics. It is not the official JBL Headphones app and gets no support from them.
>
> JBL, Harman, Tune and the product names are trademarks of their respective owners. They are used here only to say which devices the app works with. The product photos the app shows belong to Harman International and are not covered by this project's license ([details](mac/JBLProtocol4/ProductImages/README.md)).
>
> This is interoperability research on the author's own device. It comes with no warranty (see [LICENSE](LICENSE)): use it at your own risk, you are responsible for your own device. Using it may affect your warranty or support from the manufacturer.

## What the app does
Click the headphones icon in the menu bar to get:
- Battery level
- Noise control: ANC, Ambient Aware, TalkThru, Off
- Voice Aware (Low, Mid, High) and Spatial Sound (Music, Movie, Game)
- Under **More settings**: left/right balance, auto power off, voice prompts
- Power off (click twice)

It connects to any model in the [Device family](#device-family) and greys out controls the connected model does not have. EQ, button mapping, firmware update and factory reset are left out on purpose.

## Installation
**Requirements:** macOS 14 or later, Apple Silicon or Intel. The headphones must already be paired with your Mac in System Settings > Bluetooth.

### Install in 3 steps
1. Download `JBLProtocol4-<version>.dmg` from the [latest release](https://github.com/NeoHBz/JBLProtocol4/releases/latest).
2. Open it and drag **JBLProtocol4** into **Applications**.
3. Open the app and allow Bluetooth access when macOS asks. There is no window: the app lives in the menu bar.

If it stays on "Not connected", close the JBL Headphones app on your phone and try again. If it still does not connect, remove the headphones in System Settings > Bluetooth and pair them again (see `notes/protocol.md`, open questions).

**Update:** quit the app (More settings > Quit), install the new DMG and choose Replace.
**Uninstall:** move `/Applications/JBLProtocol4.app` to the Trash, and remove its entry in System Settings > Privacy & Security > Bluetooth.

### If macOS blocks JBLProtocol4
The first time you open it, macOS may say it "cannot verify" the app or that it "could not verify JBLProtocol4 is free of malware". That is because the app is not notarized by Apple, which needs a paid Apple Developer membership. It does not mean anything was found in it. What you can check yourself:
- All the code is in this repository, and every release is built from a tag by GitHub Actions (`.github/workflows/release.yml`), not on someone's laptop.
- The app needs no account and has no network code: it only talks to your headphones over Bluetooth.
- Each release lists SHA-256 checksums in `SHA256SUMS.txt`. Check your download with `shasum -a 256 JBLProtocol4-*.dmg`.

Then pick one of these:

#### Option A: System Settings
1. Try to open JBLProtocol4 once and close the warning.
2. Open System Settings > Privacy & Security and scroll down to Security.
3. Next to "JBLProtocol4 was blocked", click **Open Anyway** and confirm with your password.

#### Option B: Terminal
Remove the download quarantine flag from this one app:

    xattr -dr com.apple.quarantine /Applications/JBLProtocol4.app

Please do not turn Gatekeeper off for the whole Mac (`spctl --master-disable`) to run this app. Options A and B only affect this one app.

### Build from source
Needs the Xcode command line tools (Swift 5.9 or later). No Xcode project, just `make`:

    git clone https://github.com/NeoHBz/JBLProtocol4.git
    cd JBLProtocol4/mac/JBLProtocol4
    make cert      # once: a self-signed signing certificate, so macOS remembers the Bluetooth permission across builds
    make install   # signed Release build into /Applications

Details, every `make` target and the CI signing setup: `mac/JBLProtocol4/README.md`.

### Making a release
Push a version tag: `git tag v0.1.0 && git push origin v0.1.0`. The `release` workflow runs the tests, builds a universal (Apple Silicon and Intel) app, and publishes the DMG, zip and checksums as a GitHub release. Tags with a dash (`v0.2.0-beta.1`) become pre-releases.

### Product photos
The panel shows a photo of the connected model in its colour. The photos are in `mac/JBLProtocol4/ProductImages/`. They belong to Harman International (JBL) and are **not** covered by this project's license: see `mac/JBLProtocol4/ProductImages/README.md` for ownership and the disclaimer.

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
- `mac/JBLProtocol4/`: the menu bar app (Swift package).
- `mac/*.py`: small `bleak` scripts used on a Mac (scan, read-only probes, single-setting writes).
- `analysis/`: helper scripts for turning a Bluetooth HCI capture into a table.
- `Dockerfile`, `docker-compose.yml`: tooling container (jadx, apktool, tshark, python).

## What is deliberately not here
- The app (APK) and anything decompiled from it. Some notes cite paths such as `decompiled/...`, `captures/...`, `analysis/feature5_table.json` and a private brief: those files exist only on the author's machine.
- Raw captures and the full table derived from them: they contain device serials, addresses and phone identifiers.
- `proto/fixtures/gatt.public.tsv` is a redacted command-channel-only fixture (serial, address, clock-sync and host-name hash zeroed, timestamps replaced). It is built by `analysis/redact_fixture.py` from a private table, which you can produce for your own device with `analysis/dump_gatt.sh` and your own HCI snoop log. `proto/tests` use `gatt.tsv` if present, else the public fixture.

## Safety
Do not send firmware-update, factory-reset or unverified commands. The spec lists the off-limits tags. Every write in `mac/` replays a frame that was first seen in a real capture.

## Status
Stages 0 to 7 done (recon, capture, static cross-check, spec, offline validation, read-only Mac prototype, low-risk writes, menu bar app). The app is only tested on the Tune 780NC. Licensed under the MIT License (see `LICENSE`). Local, private values live in a gitignored `local.config.json` (template: `local.config.example.json`).
