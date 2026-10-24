# JBL Tune 780NC control protocol (Stage 3 spec)

Single source of truth. Evidence: `notes/stage1-findings.md` (capture), `notes/stage2-findings.md` (code), raw data in `analysis/gatt.tsv`.

**Confidence tags:** **both** = seen in code and in the capture. **capture** = seen in the capture only. **code** = seen in code only. Single source = unverified, do not send from a Mac app until a second source agrees.

All multi-byte numbers are **little-endian** unless stated.

## 1. Transport (both)
- BLE GATT service `65786365-6c70-6f69-6e74-2e636f6d0000` (ASCII "excelpoint.com").
- Characteristic `...6d0002`: phone **writes** here (handle `0xb003` in the capture, properties write + write-without-response). Code name `BLE_CMD_TX_CHAR_UUID_02`.
- Characteristic `...6d0001`: device **notifies** here (handle `0xb005`, properties read + notify). Code name `BLE_CMD_RX_CHAR_UUID_01`.
- Characteristic `...6d0003` ("raw") exists in code (`Constants.java:46`), not seen on this device.
- The phone enabled notifications once per connection (a write to handle `0xb006`, right after discovery; value not captured in my extract, so **capture, probable**).
- The app used ATT Write Request (opcode 0x12) and got notifications (opcode 0x1b).
- The headphones are also a classic Bluetooth device (audio, calls). A separate RFCOMM exchange on channel 23 happens at connect. It carries none of the settings. Purpose unknown.

## 2. Framing (both)
Builder: `AssembleCmd4.generateCmdList` (`com/harman/protocol4/AssembleCmd4.java`).

| Offset | Size | Field | Value |
|---|---|---|---|
| 0 | 2 | identifier | bytes `00 dd` in normal frames. `01 dd` on the clock-sync frames. Meaning of the first byte not understood. |
| 2 | 2 | command ID | see section 4 |
| 4 | 1 | packet count | 1 for normal messages |
| 5 | 1 | packet index | 0-based |
| 6 | 2 | payload size | bytes |
| 8 | n | payload | per chunk. Chunk size = negotiated MTU - 15 |

- **Checksum / CRC / signature:** none in the builder, none visible in the capture (frames are repeatable byte for byte). **Both.**
- **Encryption:** none seen. **Both.**
- Large messages (EQ) are split into several frames by packet count/index. Handling beyond count = 1 is not needed for the verified features.
- **TLV** (inside SET payloads, GET replies and notifications): `tag u16 | length u16 | value[length]`.
- GET payload: just a list of `tag u16`.
- Replies and notifications start their payload with a **status u16**. `0000` = OK (the only value seen).

## 3. Value encodings (code; the first two also confirmed in capture)
- **StatusLevel1** (1 byte): `(status << 7) | (level & 0x7f)`. Parse: bit 7 = status, bits 0-6 = level. (both)
- **StatusLevel2** (2 bytes, little-endian): `(status << 15) | (level & 0x7fff)`. (both)
- **Gesture** (1 byte function ID, section 6). (both)
- **Ints** (`Occupy1Byte/2Bytes/4BytesEachInt`): array of ints, 1/2/4 bytes each.
- Strings: ASCII or UTF-8. MAC: 6 bytes.

## 4. Command IDs
| ID | Name | Direction | Confidence | Use |
|---|---|---|---|---|
| 0x0001 | GET_DEVICE_INFO | phone to device | both | payload = tag list; reply is command 0x0001 from device |
| 0x0002 | SET_DEVICE_INFO | phone to device | both | payload = TLVs |
| 0x0003 | NOTIFICATION_TO_APP | device to phone | both | state push |
| 0x0004 | NOTIFICATION_TO_DEVICE | phone to device | code | not seen |
| 0x0201 | GET_DEVICE_ANALYTICS_DATA | phone to device | both | sent at connect with empty payload. Not needed. |
| 0x02FF | CLEAN_DEVICE_ANALYTICS_DATA | | code | **Off limits** |
| 0x00FF | RESET_TO_FACTORY | | code | **Off limits** |
| 0x0101-0x0104 | OTA start/data/stop/notify | | code | **Off limits** |

**SET exchange (both):** phone sends SET (0x0002) with one TLV. Device replies with a notification (0x0003) containing the resulting state (status `0000` + TLVs), then an ack: command 0x0002, payload `0000`. Observed order: notification first, ack about 1 ms later.

## 5. Tag table
`rw` and type from `DeviceInfoFeature5.java`. "Samples" counts captured SETs/states.

### Device info (read)
| Tag | Name | Type | Capture value | Confidence |
|---|---|---|---|---|
| 0x0004 | ProductID | 2 B | `5f21` = 0x215f | both |
| 0x0005 | ColorID | 1 B | `09` | both |
| 0x0008 | LeftDeviceSerialNumber | ASCII | device serial (not recorded here) | both |
| 0x000a | MACAddress | 6 B | | both |
| 0x000c | FirmwareVersion | 3 B | `19 2b 0a` read as bytes; version formatting not decoded | both (tag), capture (meaning of bytes) |
| 0x000d | LeftDeviceBatteryStatus | StatusLevel1 | `30` (= 48, app showed 48%) | tag: both. **Percent meaning: verified, 2 samples (0x30=48 with app 48%; 0x2f=47 with app 47%, Mac read 19:46). Capture + Mac.** The standard BLE battery (0x180F/0x2A19) reads differently (50% at the same time as app 47%). |
| 0x002e | PairingStatus | 1 B | `01` | both |
| 0x002f | HostType | 1 B | `01` (phone SET this at connect) | both |

### Noise control (all both)
The three tags behave as one exclusive group. Device replies to any SET with all three states.
| Action | Tag | SET value | Reply states (0x18, 0x19, 0x1a) |
|---|---|---|---|
| ANC on | 0x0018 | `ff` | ff, 7f, 7f |
| Everything off | 0x0018 | `7f` | 7f, 7f, 7f |
| Ambient Aware on | 0x0019 | `ff` | 7f, ff, 7f |
| TalkThru on | 0x001a | `ff` | 7f, 7f, ff |
Samples: ANC on 5, off 4, Ambient Aware 2, TalkThru 2. "Off" is expressed by writing `7f` to tag 0x18.

### Other settings
| Feature | Tag | Type | SET payload value | Confidence |
|---|---|---|---|---|
| Voice Aware (code name Sidetone) | 0x0023 | StatusLevel1 | `03` off, `81` Low, `82` Mid, `83` High | both (3-5 samples each) |
| Balance | 0x0015 | StatusLevel1 | on: `0x80 \| (50 + b)`, b in -16..+16; off: `50 + b` (center off = `32`) | both (1-2 samples per point: -16, 0, +16) |
| Spatial Sound | 0x0022 | StatusLevel1 | on: `82` Music, `81` Movie, `83` Game; off: `03` (keeps mode bits) | both for tag; mode numbers: capture, 1 sample each |
| Auto Power Off | 0x0012 | StatusLevel2 | on: `0x8000 \| seconds`; off: `seconds`. 30 min `0887`, 1 h `108e`, 2 h `209c`, off at 2 h `201c` | both (1 sample each; seconds decoding from code) |
| Voice Prompts | 0x0c40 | StatusLevel1 | `ff` on, `7f` off | both (1 each) |
| Voice Prompt language | 0x0c41 | 1 B | `01` English. The app sends 0x0c40 and 0x0c41 together in one SET (two TLVs) when toggling prompts | both for tag, other languages unverified |
| Smart Audio & Video | 0x100f | 4 x u16 | e.g. `0001 3500 9600 ffff` | tag both. **Value layout unknown. Drops the connection.** |
| Heartbeat | 0x0002 | no payload | SET with empty value | both |
| Power off (code name ManualPowerOff) | 0x0011 | 2 B int | SET value `0000`: full frame `00dd020001000600110002000000` | **both.** Capture (`captures/bugreport2.zip`, 18:46:14.301, 1 sample): device pushed the tag back, acked, then dropped the link ~150 ms later. Code: `General4Control.shutDown()` sends ManualPowerOff = 0 (`DeviceInfoFeature5` id 17). **Sent from the Mac 21:08 (probe8.py): headphones switched off, button press brought them back.** Needs a button press to return. |
| Sync time | 0x0031 | ints | sent in frames starting `01 dd` at connect | both (tag), layout unknown |

### Buttons (Gesture type)
| Gesture | Tag | Confidence |
|---|---|---|
| Multi-function single press | 0x0f82 | both |
| Multi-function double press | 0x0f84 | both |
| Multi-function triple press | 0x0f88 | both |
| Multi-function press and hold | 0x0f83 | both |
| ANC button single press | 0x0f85 | both |
| ANC button long / double / triple | 0x0f86 / 0x0f87 / 0x0f89 | code only, not exercised |

Gesture function IDs (both): `08` Play/Pause, `c8` EQ On/Off, `c2` Spatial Sound (code name SpatialSoundHeadTrackingOff; app label "Spatial Sound On/Off"), `a1` Native Voice Assistant (TalkToDefaultAssistant).
ANC button option sets (both): `09` ANC + Ambient Aware + Off, `0b` ANC + Ambient Aware, `0c` ANC + Off, `0d` Ambient Aware + Off.
Factory defaults written by the app's Control Reset: 0x0f85=`0b`, 0x0f82=`08`, 0x0f84=`c8`, 0x0f88=`c2`, 0x0f83=`a1`.

### Equalizer
Tags 0x0e01 (EQInfoQuery) and 0x0e02 (EQInfo), multi-frame blobs of float filter coefficients computed in the app (native `libnative-peq`). **Not decoded. Not in scope for the first Mac version.**

## 6. Connect sequence (capture; first connect at 18:11:26)
1. Phone enables notifications on `...0001`.
2. Device notifies PairingStatus (0x2e) = 1.
3. Phone SETs HostType (0x2f) = 1. Device echoes it and acks.
4. Phone GETs a block of tags (ProductID, ColorID, MAC, serial, FirmwareVersion, battery 0x0d, 0x0e, ANC/AA/TT 0x18-0x1a, 0x23, 0x15, 0x22, 0x0b86, 0x0ba0, 0x0c40-0x0c42, 0x100f, and more). Device returns every value in one reply.
5. Phone GETs the gesture tags (0x0f82, 0x0f84, 0x0f88, 0x0f83, ...).
6. Phone SETs 0x0e01 (`ff`, then `c9`) and reads EQ data.
7. Phone sends 0x0201 (analytics GET), SETs 0x07 (HostNameCRC, 2 bytes), SyncTime (`01 dd` frames), reads voice prompt tags.
8. Heartbeat SETs about every 3 s appear during long waits.
- No authentication tags (0x3e, 0x4a, 0x4b, 0x53, 0x54) were sent. (capture)
- Whether a second central (a Mac) can connect at the same time as the phone: **unknown.**
- Whether bonding is needed for GATT access: **unknown** (the phone was bonded).

## 7. Test vectors (byte for byte from the capture, `analysis/gatt.tsv`)
Each case: phone request, then device replies in order (state notification, then ack). Stage 4 replays these.

| Case | Request | Device replies |
|---|---|---|
| ANC on | `00dd02000100050018000100ff` | `00dd030001001100000018000100ff190001007f1a0001007f` ; `00dd0200010002000000` |
| ANC off (all off) | `00dd020001000500180001007f` | `00dd0300010011000000180001007f190001007f1a0001007f` ; `00dd0200010002000000` |
| Ambient Aware on | `00dd02000100050019000100ff` | `00dd0300010011000000180001007f19000100ff1a0001007f` ; `00dd0200010002000000` |
| TalkThru on | `00dd0200010005001a000100ff` | `00dd0300010011000000180001007f190001007f1a000100ff` ; `00dd0200010002000000` |
| Voice Aware High | `00dd0200010005002300010083` | `00dd03000100070000002300010083` ; `00dd0200010002000000` |
| Voice Aware Low | `00dd0200010005002300010081` | `00dd03000100070000002300010081` ; `00dd0200010002000000` |
| Voice Aware Mid | `00dd0200010005002300010082` | `00dd03000100070000002300010082` ; `00dd0200010002000000` |
| Voice Aware off | `00dd0200010005002300010003` | `00dd03000100070000002300010003` ; `00dd0200010002000000` |
| Balance on, 0 | `00dd02000100050015000100b2` | `00dd030001000700000015000100b2` ; `00dd0200010002000000` |
| Balance on, -16 | `00dd02000100050015000100a2` | `00dd030001000700000015000100a2` ; `00dd0200010002000000` |
| Balance on, +16 | `00dd02000100050015000100c2` | `00dd030001000700000015000100c2` ; `00dd0200010002000000` |
| Balance off | `00dd0200010005001500010032` | `00dd03000100070000001500010032` ; `00dd0200010002000000` |
| Spatial Music | `00dd0200010005002200010082` | `00dd03000100070000002200010082` ; `00dd0200010002000000` |
| Spatial Movie | `00dd0200010005002200010081` | `00dd03000100070000002200010081` ; `00dd0200010002000000` |
| Spatial Game | `00dd0200010005002200010083` | `00dd03000100070000002200010083` ; `00dd0200010002000000` |
| Auto Power Off 30 min | `00dd020001000600120002000887` | `00dd0300010008000000120002000887` ; `00dd0200010002000000` |
| Auto Power Off 1 h | `00dd02000100060012000200108e` | `00dd030001000800000012000200108e` ; `00dd0200010002000000` |
| Auto Power Off 2 h | `00dd02000100060012000200209c` | `00dd030001000800000012000200209c` ; `00dd0200010002000000` |
| Auto Power Off off | `00dd02000100060012000200201c` | `00dd030001000800000012000200201c` ; `00dd0200010002000000` |
| Voice Prompts on | `00dd020001000a00400c0100ff410c010001` | `00dd0300010007000000400c0100ff` ; `00dd0300010007000000410c010001` ; `00dd0200010002000000` |
| MFB single = EQ On/Off | `00dd020001000500820f0100c8` | `00dd0300010007000000820f0100c8` ; `00dd0200010002000000` |

Other frames (capture):
- Single-tag GET, tag 0x0c: `00dd0100010002000c00`
- Heartbeat (SET tag 0x0002, length 0): `00dd02000100040002000000`
- Connect GET block: first captured at 18:11:26.971, starts `00dd010001003200040005000a00...`

## 8. Off limits (never generate or send)
- Command 0x00FF RESET_TO_FACTORY and feature 0x000F FactoryReset
- OTA and firmware: commands 0x0101-0x0104, feature 0x1F00 LaunchOTAMode, the throughput/OTA service (`...2e636f820000`), `com/harman/bluetooth/ota`
- Command 0x02FF CLEAN_DEVICE_ANALYTICS_DATA
- LE Audio 0x0BA0 (reboots and needs re-pairing) and BT pairing mode 0x0BA5
- Auracast tags 0x0B81, 0x0B86 (table says 0x0B86 is read-only yet the app wrote it; unexplained)
- Authentication tags 0x3E, 0x4A, 0x4B, 0x53, 0x54
- Anything Airoha RACE style (flash/RAM read/write). The app bundles it, no traffic seen.
- Any write to a tag the code marks read-only
- Smart Audio & Video 0x100F (drops the connection, value layout unknown)
- Control Reset burst (overwrites the user's button settings)
- EQ writes (not decoded)

## 9. What a Mac app can use (verified or nearly)
Read: battery (0x0d, percent meaning unverified), current ANC / Ambient Aware / TalkThru, Voice Aware, balance, Spatial, Auto Power Off, voice prompts, firmware, product ID.
Write (candidates for Stage 6, low risk first): noise modes, Voice Aware, balance, button mapping, Spatial Sound, Auto Power Off. Each needs a second source or a live test with restore.
Drop: LE Audio, Auracast, Smart Audio & Video, EQ (for now).

## 10. Open questions
- [x] (done 19:46, see stage5-findings.md) Battery percent meaning: second reading at a different level, and what bit 7 does while charging. **Deferred by user: headphone has ~70 h battery, will take a short capture once the app shows a lower %.**
- [ ] Mac control link at the same time as the phone: user reports the headphones already hold audio connections to an iPhone and a Mac at once (multipoint), so two hosts are possible. Whether the **control channel** (GATT) accepts a second host is untested, Stage 5 will test it.
- [ ] Bond needed for GATT control: partial answer. An unbonded Mac got no replies (19:37). After forgetting the Mac and connecting while the headphones were in pairing mode, replies worked (19:46). Retest 19:53 outside pairing mode (bond present, audio re-paired): replies work, so pairing mode itself is not required. Bond test 19:56: after forgetting the LE-only 'Bluetooth Device' entry (audio entry kept), replies STILL work, so that separate entry is not what the channel depends on. What changed between the failing runs (19:31, 19:37) and all later runs is only that the Mac was re-paired for audio (fresh keys), so the cause is a fresh pairing / stale old pairing, not proven which.
- [ ] What `0xb006` writes contain (expected: notification enable)
- [x] (answered 2026-10-24, code: `product_list.json` maps the 780NC to `protocol4.Tune680Control`, a subclass of `General4Control`; see section 11) Which control class (protocol4 General4Control / airoha / lea) the 780NC uses
- [ ] The 780NC's supported-feature list (per-model config `assets/config/dash4/jbl_tune_780nc.json`, not yet read)
- [ ] Smart Audio & Video value layout (0x100f)
- [ ] Spatial Sound mode numbers (1 sample each)
- [ ] Auto Power Off non-standard durations
- [ ] Auracast tag discrepancy (0x0B86 vs 0x0B81)
- [ ] EQ payload layout
- [ ] First byte of the identifier (`00` vs `01`) and the SyncTime frames
- [ ] RFCOMM channel 23 exchange
- [ ] `libnativelib` and `libcounterfeit` (check for hidden auth or device checks)
- [ ] Other-language voice prompt IDs
- [x] (answered 19:46: HostType SET was accepted, echoed and acked; replies followed; SyncTime/HostNameCRC not needed for reads) Does the device require the phone-style connect steps (SET HostType 0x2f = 01, SyncTime 0x31, HostNameCRC 0x07) before it accepts commands from a second host? The encoder does not build these yet. Stage 5 starts read-only and will tell us.
- [ ] Tag 0x0e81 (4 phone writes, `810e 0200 0800`-style) is not in the app's feature table lookup I used. EQ related, not needed.

- Device normalises on-off values (observed 2026-10-24, Mac): voice prompt level bits are not kept (SET `ff`/`7f` reads back `80`/`00`); Auto Power Off "off" reads back with the default 30 min (`0807`) whatever duration was written. Compare status bits, not whole bytes.

## 11. Device family (code)
Source: `decompiled/apktool/assets/product_list.json` (`cmdCtrlList`, `platform`, `pidS`). Every model below uses a controller in `com/harman/cmdctrl/imp/control/u3/protocol4/`. Each controller is a thin subclass of `General4Control` (`Tune680Control.java` is 53 lines, `General4Control.java` 1777), so the framing in section 2 applies to all of them. Only the Tune 780NC is verified on hardware. The tags each model supports differ (earbuds, no ANC, etc.), so a client must identify the model by PID (tag 0x0004 ProductID, section 5; the 780NC returns `5f21` = 0x215f) and gate features per model.

The family follows the protocol, not the chip: the list tags the 780NC `Bes` although its firmware string says Airoha `AB157x` (stage1-findings.md), and the Tune 5xx/7xxBT entries are `Rtk` (Realtek).

| Controller | Model | Platform | PID |
|---|---|---|---|
| Tune680Control | JBL Tune 680NC | Bes | 215E |
| Tune680Control | **JBL Tune 780NC** | Bes | 215F |
| Tune680Control | JBL Tune 785NC | Bes | 21A4 |
| Live680NCControl | JBL Live 680NC | Bes | 2160 |
| Live680NCControl | JBL Live 780NC | Bes | 2161 |
| Tune530Control | JBL Tune 520BT2 | Rtk | 2188 |
| Tune530Control | JBL Tune 530BT | Rtk | 2162 |
| Tune530Control | JBL Tune 535BT | Rtk | 2194 |
| Tune530Control | JBL Tune 730BT | Rtk | 2163 |
| Tune530Control | JBL Tune 735BT | Rtk | 2195 |
| TourOneM3Control | JBL Tour One M3 | Bes | 2101 |
| TourOneM3Control | JBL Sense Lite | Bes | 2133 |
| TourOneM3Control | JBL Endurance Zone | Bes | 2134 |
| TourOneM3Control | JBL Tune 135BT | Bes | 2135 |
| TourOneM3Control | JBL Tune 235BT | Bes | 2136 |
| LiveTws4Control | JBL Live Beam 4 | Bes | 2179 |
| LiveTws4Control | JBL Live Buds 4 | Bes | 217b |
| LiveTws4Control | JBL Live Flex 4 | Bes | 217d |
| TuneFlex3Control | JBL Tune Flex 3 | Bes | 21B6 |
| TuneFlex3Control | JBL Tune Buds 3 | Bes | 21B7 |
| TuneBeam3Control | JBL Tune Beam 3 | Bes | 21B8 |
| WaveFlex3Control | JBL Vibe Flex 3 | Bes | 21B2 |
| WaveFlex3Control | JBL Vibe Buds 3 | Bes | 21B3 |
| WaveFlex3Control | JBL Vibe Beam 3 | Bes | 21B4 |
| WaveFlex3Control | JBL Wave Buds 3 | Bes | 21AB |
| WaveFlex3Control | JBL Wave Beam 3 | Bes | 21AC |
| WaveFlex3Control | JBL Wave Flex 3 | Bes | 21AD |
| EndurancePaceControl | JBL Endurance Pace | Bes | 2150 |
| EndurancePeak4Control | JBL Endurance Peak 4 | Rtk | 2151 |
| EnduranceRun3Control | JBL Endurance Run 3 Wireless | Bes | 214F |
| JuniorFreeControl | JBL Junior Free | Bes | 2154 |
| SenseProControl | JBL Sense Pro | Bes | 2153 |
| SoundgearClipControl | JBL Soundgear Clips | Bes | 2152 |
| SmartTxControl | JBL Smart Tx | Bes | 214B |

- Closest siblings: Tune 680NC and 785NC (same controller class as the 780NC). Best next candidates.
- `TourOneM4Control` and `TourPro4Control` exist in the protocol4 folder but no entry in the bundled list points at them (the list may be updated from a server).
- Not in this family: older models on the `airoha`, `bes`, `lea`, `protocol3` controllers (e.g. Tune 770NC, Live 770NC).
- [ ] Confirm the family on a second model (Tune 680NC or 785NC): same framing, GET ProductID returns its PID.
