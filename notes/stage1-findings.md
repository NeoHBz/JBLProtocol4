# Stage 1 Findings (JBL Tune 780NC)

Source: `captures/bugreport.zip` -> `btsnoop_hci.log` (18:06 to 18:44 phone time, 23,488 packets), matched to `captures/action-log.csv`.
Derived files: `analysis/gatt.tsv` (all GATT writes/notifications), `analysis/tlv.py`, `analysis/writes_by_payload.py`.

**Confidence rule:** everything below is **observed in capture only** (single source). Nothing is confirmed in code yet. That happens in Stage 2.

**Timing:** packets arrive 1 to 3 seconds before your log marks (tap, then log). A few marks are up to 8 seconds late. Phone and btsnoop clocks agree (btsnoop stores phone-local time).

> **Stage 2 corrections (2026-10-24):** (1) Header bytes 4-5 ("seq 0001") are packet count and index. (2) Frames I called "type 0102" are command 0x0201, the analytics GET, not OTA. (3) Tag names now confirmed in code, see `stage2-findings.md`: 0x0d = LeftDeviceBatteryStatus, 0x18 = ANC, 0x23 = Sidetone (Voice Aware), 0x100f = SmartSwitch, 0x0b86 = LEAudioAuraCastStatus. (4) Every tag that matched is now "both"; see that file for the confidence per row. (5) The ANC button option codes are confirmed (`09` ANC+AA+Off, `0b` ANC+AA, `0c` ANC+Off, `0d` AA+Off), and the unlogged 18:37:52 write of `09` fits re-enabling Off.

## Transport
- Commands use **BLE GATT**, in a vendor service whose 128-bit UUID bytes spell ASCII `excelpoint.com`.
  - Write requests (opcode 0x12) from the phone go to handle `0xb003`.
  - Notifications (opcode 0x1b) from the headphones come back on handle `0xb005`.
  - Handle `0xb006`: 10 writes, not decoded.
- Classic RFCOMM (channel 23) also carries a short exchange (model ID `42ad54`, firmware string `IoT_SDK_for_BT_Audio_V5.4.0.AB157x`, an "in-use" challenge). It appears only at connect/reconnect moments (18:08, 18:21 to 18:22, 18:25 to 18:29, 18:39). It carries none of your setting changes. Purpose unknown. Treat as unverified.
- Other GATT services present: Fast Pair (0xFE2C), Battery (0x180F), LE Audio (0x1844, 0x184D, 0x184E, 0x1850), Generic. The standard Battery service was not obviously used by the app. Not checked.
- Chipset hint: firmware string says Airoha AB157x. The app bundles Airoha libs (RACE protocol: flash/RAM read/write). **No RACE traffic identified in this capture. Treat any RACE-style command as Off Limits.**

## Frame format (observed)
`[00 dd] [type u16 LE] [seq u16 LE, always 0001 seen] [len u16 LE] [payload]`
- Type `0001` GET: payload = list of tag IDs (u16 LE each).
- Type `0002` SET: payload = one or more TLVs. TLV = `tag u16 LE, length u16 LE, value`.
- Reply to GET: type `0001`, payload = status `0000` then TLVs.
- Ack to SET: type `0002`, payload `0000` (status OK).
- State push after a SET: type `0003`, payload = status then the new TLVs.
- Type `0003` from the phone with `f101`-style long payloads = EQ data blobs (see EQ).
- Frames starting `01 dd` (tag 0x31, 9 bytes) appear at connect. Unknown, possibly clock sync. Not decoded.
- No checksum or encryption seen so far (frames are plain, repeat byte for byte). A checksum field has not been identified. Confirm in code.

## Tag table (write = phone SET, one value per tag)
| Feature | Tag | Value meaning | Samples | Notes |
|---|---|---|---|---|
| ANC on | 0x0018 | `ff` | 5 | sets ANC active |
| Off (all noise modes off) | 0x0018 | `7f` | 4 | device reply shows 0x18, 0x19, 0x1a all `7f` |
| Ambient Aware | 0x0019 | `ff` | 2 | |
| TalkThru | 0x001a | `ff` | 2 | |
| Voice Aware | 0x0023 | bit7 = on, low bits = level: `03` off, `81` Low, `82` Mid, `83` High | 3 to 5 each | off keeps last level bits |
| Left/Right balance | 0x0015 | bit7 = on, low 7 bits = 50 + balance: `b2` on/0, `a2` -16, `c2` +16, `32` off | 1 to 2 each | range -16..+16 |
| Spatial Sound | 0x0022 | bit7 = on, low bits mode: `82` Music, `81` Movie, `83` Game, `02`/`03` off | 1 each | mode bits unconfirmed mapping, one sample each |
| Auto Power Off | 0x0012 (2 bytes) | `0887` 30 min, `108e` 1 hr, `209c` 2 hr, `201c` off | 1 each | second byte high bit looks like on flag. Tentative |
| Voice Prompts | 0x0c40 | `ff` on, `7f` off | 1 each | 0x0c41 = language index (`01` English) |
| Auracast | 0x0b86 | `ff` on, `7f` off | 1 each | 0x0b81 also written (2 bytes `011e`/`001e`), meaning unknown |
| LE Audio | 0x0ba0 | `ff` on, `7f` off | 1 each | **reboots and re-pairs. Do not send.** |
| Smart Audio & Video | 0x100f (8 bytes) | e.g. `00013500 9600ffff`, `c5002e00 6400ffff`, `c5002e00 9600ffff` | 1 each | semantics unknown; drops connection |
| ANC button single press (option set) | 0x0f85 | `09` and `0b`, `0c`, `0d` | 1 to 5 | see below |
| Multi-function single press | 0x0f82 | `08` Play/Pause, `c8` EQ On/Off, `c2` Spatial On/Off, `a1` Voice Assistant | 1 each | |
| Multi-function double press | 0x0f84 | same values (default `c8`) | 1 | |
| Multi-function triple press | 0x0f88 | same values (default `c2`) | 1 | |
| Multi-function press and hold | 0x0f83 | same values (default `a1`) | 1 | |
| Equalizer | type `0003` long blobs, tag 0x0e02 | float biquad data | several | complex, deferred |
| Control "Reset" (at 18:21:13) | multi-TLV SET of 0x0f85, 0x0f82, 0x0f84, 0x0f88, 0x0f83 | writes defaults: 0f85=`0b`, 0f82=`08`, 0f84=`c8`, 0f88=`c2`, 0f83=`a1` | 1 | |

ANC button option set (0x0f85): `09` seen as the original and after each restore. Disabling Off gave `0b`, disabling Ambient Aware gave `0c`, disabling ANC gave `0d`. So the value looks like a preset code for the allowed set, not a bit mask. Mapping of codes to sets is inferred from your log order only.

**Unlogged change:** the app wrote 0x0f85 = `09` at 18:37:52 (after a GET at 18:37:51), right before your headset press test. The reset at 18:21:13 had set it to `0b`, which excludes Off. Likely you re-enabled Off in the app without logging it. Please confirm.

## Battery (not confirmed)
- Tag `0x000d`, 1 byte, value `0x30` (= 48) in every connect-time reply and state push from 18:11 to 18:30.
- You read 48% in the app at 18:40:26. This is consistent, but it is **one matching value** and could be a coincidence.
- To verify I need a second reading at a different battery level (see open items).
- No battery request occurred at 18:40:26, so battery is not polled on demand there. It arrives in the connect-time read and later pushes.
- Phone-side Bluetooth battery for the headset is not exposed (null).

## Other observations
- Tag `0x0005` = `09` constant (unknown). Tag `0x0008` = ASCII (a device serial; not recorded). Tag `0x000a` = 6 bytes, looks like a MAC-style ID. Not repeated here.
- Tag `0x0e01` is written alternately `ff` and `c9` during connect; purpose unknown.
- A keep-alive-like write `00dd 0200 0100 0400 0200 0000` appears every ~3 s during the LE Audio reboot period (18:27:40 onward).
- Headset physical button presses (18:36 to 18:40) were not analyzed yet. They may appear as device notifications on `0xb005`.
- Power-off at 18:46:15 is after the first pulled capture. A second pull (`captures/bugreport2.zip`, log 18:06 to 21:03) contains it: SET tag 0x0011 = `0000`. See `notes/protocol.md`.

## Gate (Stage 1)
- ANC on/off: **passed** (tag 0x18, `ff` vs `7f`, 5 and 4 samples, consistent with your marks).
- Battery: **not yet.** Candidate tag 0x0d = 48. Needs a second data point.
- Transport: **passed** (BLE GATT, vendor service, handles 0xb003 / 0xb005).

## Open items
- [ ] You confirm: was 0x0f85 changed back to include Off at about 18:37:52 (unlogged)?
- [ ] Confirm original state of: Smart Audio & Video, EQ, Auto Power Off, Voice Prompts, Spatial Sound, Auracast (all restored? unknown)
- [ ] Battery verification: take a short second capture at a different battery level (headphones on charger a few minutes, or the next day). Check tag 0x0d changes with the app %
- [ ] Analyze headset-button device notifications (18:36 to 18:40)
- [ ] Check handle 0xb006 writes and tag 0x0e01 values
- [ ] Decode Smart Audio & Video 0x100f values
- [ ] Custom EQ round (deferred)
- [ ] Stage 2: confirm every tag above against the decompiled code, find framing code for `00 dd`, check for any checksum
- [ ] Mark Off Limits in `notes/protocol.md`: firmware update, factory reset, Control "Reset" burst, LE Audio (0x0ba0), anything RACE-style, anything on `0xb006` until understood
