# Stage 2 Findings: static analysis vs capture

Sources: decompiled app (`decompiled/jadx/sources`), capture analysis (`notes/stage1-findings.md`).
Confidence: **both** = seen in code and in capture. **code** / **capture** = single source.

## Where the protocol lives
- Package `com/harman/protocol4/` ("protocol4"). The older `AA <cmd> <len>` code in `com/harman/commands/` and `HandleParse.java` is a different, older protocol. My Stage 0 note about `AA 25` does not describe this headphone.
- Feature table: `com/harman/sdk/message/DeviceInfoFeature5.java` (tag ID, name, read/write, value codec). Machine copy: `analysis/feature5_table.json`.
- Value codecs: `com/harman/protocol4/features/*.java`.
- Gesture function IDs: `com/harman/sdk/cst/GestureFunType.java`.
- Framing builder: `com/harman/protocol4/AssembleCmd4.java`. Command IDs: `HeaderCommandID.java`.
- Per-model control classes: `com/harman/cmdctrl/imp/control/u3/{protocol4,airoha,lea,bes}/`. Which one the Tune 780NC uses is **not determined** (the factory class is a stub). The Tune 770NC has both an `airoha` and an `lea` class, which fits the Airoha chip.
- Native libs: not examined this stage (`libnativelib`, `libcounterfeit`). Open.

## Transport (both)
- GATT service `65786365-6c70-6f69-6e74-2e636f6d0000` (ASCII "excelpoint.com"). Characteristics `...0001` (RX char in code), `...0002` (TX char), `...0003` (raw). `com/harman/bluetooth/constantsimp/Constants.java:43-46`.
- Capture: writes to handle `0xb003`, notifications on `0xb005`. Mapping of handles to characteristic UUIDs not yet checked in the capture.
- A separate throughput/OTA service exists in code (`BesSdkConstants.java:58-60`, `...2e636f820000`). Not seen in capture. Off limits.

## Frame format (both)
Little-endian fields. Builder: `AssembleCmd4.generateCmdList`.
| Bytes | Field | Notes |
|---|---|---|
| 2 | identifier | captured as `00 dd` (and `01 dd` on a few frames, meaning unknown) |
| 2 | command ID | `HeaderCommandID` |
| 1 | packet count | 1 for normal messages |
| 1 | packet index | 0-based |
| 2 | payload size | |
| n | payload | chunk size = MTU - 15 |
- **No checksum, no encryption, no signing** in the builder (code). Captured frames are plain and repeatable (capture). **Both.**
- Large payloads (EQ) are split into several frames by count/index.
- Earlier I read bytes 4-5 as "seq 0001". Correct reading: packet count 1, index 0.

## Command IDs (code; first four seen in capture)
| ID | Name | Seen in capture |
|---|---|---|
| 0x0001 | GET_DEVICE_INFO | yes (payload = list of u16 tag IDs) |
| 0x0002 | SET_DEVICE_INFO | yes (payload = TLVs) |
| 0x0003 | NOTIFICATION_TO_APP | yes (device pushes) |
| 0x0004 | NOTIFICATION_TO_DEVICE | no |
| 0x0201 | GET_DEVICE_ANALYTICS_DATA | yes, at connect (I mislabelled it "type 0102" earlier) |
| 0x02FF | CLEAN_DEVICE_ANALYTICS_DATA | no. **Avoid.** |
| 0x00FF | RESET_TO_FACTORY | no. **Off limits.** |
| 0x0101 / 0x0102 / 0x0103 / 0x0104 | START_OTA / SEND_OTA_DATA / STOP_OTA / OTA_NOTIFICATION | no. **Off limits.** |

TLV (inside SET/GET replies/notifications): `tag u16, length u16, value`. A GET reply and a notification start the payload with a u16 status (`0000` = OK).

## Value codecs (code)
- `StatusLevelSize1Feature`: 1 byte = `(status << 7) | (level & 0x7f)`. Reply parse: bit 7 = status, low 7 bits = level. **Both.**
  - ANC `ff` = on level 127; `7f` = off level 127. Voice Aware `81`/`82`/`83` = on, level 1/2/3; `03` = off.
- `StatusLevelSize2Feature` (Auto Power Off): 2 bytes, layout not read yet.
- `GestureFeature`: payload = list of 1-byte function IDs.
- `Occupy1ByteEachIntFeature` / `Occupy2BytesEachIntFeature`: arrays of ints (1 or 2 bytes each).

## Tag table: capture matched to code
| Tag | Code name | Type | Capture meaning | Status |
|---|---|---|---|---|
| 0x0004 | ProductID | r, 2B | `5f21` = 0x215f | both (0x215f appears in the app's 780NC image names) |
| 0x0005 | ColorID | r, 1B | `09` | both |
| 0x0008 | LeftDeviceSerialNumber | r, ASCII | serial string | both |
| 0x000a | MACAddress | r | 6 bytes | both |
| 0x000c | FirmwareVersion | r | 3 bytes | both |
| 0x000d | LeftDeviceBatteryStatus | r, StatusLevel1 | `30` = 48 | **tag identity: both. Value as percent: one matching sample (see below)** |
| 0x0012 | AutoPowerOff | rw, StatusLevel2 | `0887`,`108e`,`209c`,`201c` | both for tag. value layout: capture only |
| 0x0015 | LRBalance | rw, StatusLevel1 | bit7 on, level = 50 + balance | both |
| 0x0018 | ANC | rw, StatusLevel1 | `ff` on, `7f` off | both |
| 0x0019 | AA (Ambient Aware) | rw, StatusLevel1 | `ff` | both |
| 0x001a | TT (TalkThru) | rw, StatusLevel1 | `ff` | both |
| 0x0022 | SpatialSoundScene | rw, StatusLevel1 | `82` Music, `81` Movie, `83` Game | both for tag. mode mapping: capture only |
| 0x0023 | Sidetone (= "Voice Aware" in the app) | rw, StatusLevel1 | `03` off, `81`/`82`/`83` Low/Mid/High | both |
| 0x0031 | SyncTime | rw | at connect | both |
| 0x002e / 0x002f | PairingStatus / HostType | r | first notifications at connect | both |
| 0x0002 | Heartbeat | rw, no payload | `00dd 0200 0100 0000`-style keep-alive every ~3 s | both |
| 0x0c40 / 0x0c41 | VoicePromptStatus / VoicePromptLanguage | rw | `ff`/`7f`, `01` English | both |
| 0x0e01 / 0x0e02 | EQInfoQuery / EQInfo | rw | EQ presets (large multi-frame) | both. content not decoded |
| 0x0ba0 | LEAudioUniCastStatus | rw | `ff`/`7f`; **reboots + re-pairs** | both. **Off limits** |
| 0x0f82 | Button1ShortPress | rw, Gesture | multi-function single | both |
| 0x0f84 | Button1DoublePress | rw | multi-function double | both |
| 0x0f88 | Button1TriplePress | rw | multi-function triple | both |
| 0x0f83 | Button1LongPress | rw | multi-function hold | both |
| 0x0f85 | Button2ShortPress | rw | ANC button single press | both |
| 0x0f86 / 0x0f87 / 0x0f89 | Button2LongPress / DoublePress / TriplePress | rw | not exercised | code only |
| 0x100f | SmartSwitch | rw, 2B ints | Smart Audio & Video (8 bytes = 4 ints); drops connection | both for tag. values not decoded |
| 0x0b81 | LEAudioAuraCastScan | rw | written with `011e`/`001e` near the Auracast toggle | both for tag. meaning unclear |
| 0x0b86 | LEAudioAuraCastStatus | table says **read-only**, capture shows the app writing `ff`/`7f` | **discrepancy**, unexplained. Do not send. |

## Gesture function IDs (both)
`08` PlayPause, `c8` EQOnOff, `c2` (code name SpatialSoundHeadTrackingOff; app label "Spatial Sound On/Off"), `a1` TalkToDefaultAssistant (native voice assistant), `09` ANC+AmbientAware+Off, `0b` ANC+AmbientAware, `0c` ANC+Off, `0d` AmbientAware+Off. Others: `00` Off, `03` AmbientAware, `04` TalkThru, `07` ANC, `0f` TalkThruOff, `05`/`06` Next/Previous track, `01`/`02` Volume up/down.
- Control **Reset** (18:21:13) wrote only gesture tags (0x0f85=`0b`, 0x0f82=`08`, 0x0f84=`c8`, 0x0f88=`c2`, 0x0f83=`a1`), not FactoryReset (0x000f). **Both** (matches the earlier reading of the app text).
- Default for the ANC button (`0b`) excludes Off. The unlogged write of `09` at 18:37:52 is the likely moment you re-enabled Off (still unconfirmed).

## Handshake, auth
- No authentication tags appear in the capture: AuthenticateDevice (0x3e), AuthenticationAlgorithm (0x4a), AdvancedAuthenticateDevice (0x4b), AccessoryAuthentication* (0x53/0x54) all exist in code but were not sent in these sessions (**capture: absent**).
- Connect sequence seen (capture): device notifies PairingStatus/HostType, app sets HostType, GETs a list of tags (ProductID, ColorID, MAC, serial, firmware, battery, ANC/AA/TT, Sidetone, Balance, Spatial, etc.), SET SyncTime (frames starting `01 dd`), reads EQ, then Heartbeat.
- The classic RFCOMM exchange on channel 23 (model ID, firmware string, "in-use" challenge) is unexplained. Open.

## Battery
- Tag identity is now backed by code (LeftDeviceBatteryStatus). The value is `0x30` flat across 20 minutes, and the app showed 48% at 18:40:26. Format is probably a status+level byte, so bit 7 may be a charging flag and the low 7 bits the percent. **Still one sample.** Verify with a second battery reading (also check whether bit 7 flips on charge).
- The app also defines `RightDeviceBatteryStatus` (0x0e) and `CaseBatteryStatus`. Not relevant to this headband.

## Open items
- [ ] Which control class applies to the 780NC (likely protocol4 General4Control family or airoha), and which features it exposes
- [ ] `StatusLevelSize2Feature` layout for Auto Power Off
- [ ] Smart Audio & Video value layout (0x100f)
- [ ] Auracast tag discrepancy (0x0b86 vs 0x0b81)
- [ ] EQ payload layout (`EQInfoFeature`, `libnative-peq`), deferred
- [ ] `libnativelib` and `libcounterfeit` (Stage 0 caveat)
- [ ] The RFCOMM channel-23 exchange
- [ ] Meaning of `01 dd` identifier frames
- [ ] Battery value confirmation with a second reading
