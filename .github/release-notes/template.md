**JBL Protocol4 {{VERSION}}**, a small macOS menu bar app for recent JBL headphones. Built and tested on the **JBL Tune 780NC**.

> [!IMPORTANT]
> **Unofficial.** This app is not made, affiliated with, authorized or endorsed by JBL, Harman International Industries or Samsung Electronics. It is not the official JBL Headphones app. No warranty: use at your own risk.

## What's new in {{VERSION}}
{{WHATS_NEW}}

## What it does
Click the headphones icon in the menu bar to get:
- Battery level, also shown next to the menu bar icon (can be turned off)
- Noise control: ANC, Ambient Aware, TalkThru, Off
- Voice Aware (Low, Mid, High) and Spatial Sound (Music, Movie, Game)
- Under **More settings**: left/right balance, auto power off, voice prompts, undo for changes made since the app opened, and the app's own settings
- Power off (click twice)

It connects to any model that uses the same "Protocol4" (about 34 recent JBL models), and greys out controls the connected model does not have. **Only the Tune 780NC has been tested.** EQ, button mapping, firmware update and factory reset are left out on purpose.

## Install
**Needs:** macOS 14 or later, Apple Silicon or Intel. Pair the headphones with your Mac first (System Settings > Bluetooth).

1. Download **`JBLProtocol4-{{VERSION}}.dmg`** below.
2. Open it and drag **JBLProtocol4** into **Applications**.
3. Open the app and allow Bluetooth access. There is no window: it lives in the menu bar.

**Updating from {{PREV_VERSION}}:** quit the app (More settings > Quit), then install the new DMG and choose Replace.

**If macOS says it "cannot verify" the app:** the app is not notarized by Apple (that needs a paid developer account), so this is expected. Go to System Settings > Privacy & Security and click **Open Anyway**, or run:

```
xattr -dr com.apple.quarantine /Applications/JBLProtocol4.app
```

Full steps in the [README](https://github.com/NeoHBz/JBLProtocol4#if-macos-blocks-jblprotocol4).

**Phone app will not connect?** The headphones accept one controller at a time. By default this app lets go 10 seconds after you close its panel. If **Keep always connected** is on, turn it off or quit the app.

## Downloads
| File | What it is |
|---|---|
| `JBLProtocol4-{{VERSION}}.dmg` | Installer (recommended) |
| `JBLProtocol4-{{VERSION}}.zip` | The same app as a zip |
| `SHA256SUMS.txt` | Checksums to verify your download |

Built by GitHub Actions from tag `{{TAG}}`. The app has no network code and needs no account. Verify with `shasum -a 256 JBLProtocol4-{{VERSION}}.dmg`:

```
{{CHECKSUMS}}
```

## Known limits
- Tested on the Tune 780NC only. Other Protocol4 models should work, but are unverified.
- Live Beam 4 and Live Flex 4 have no photo in the JBL app, so they show a headphones symbol.

**Full Changelog**: https://github.com/NeoHBz/JBLProtocol4/compare/{{PREV_TAG}}...{{TAG}}
